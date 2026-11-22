#!/usr/bin/env bash
# Verify this installation and restore one R2 archive into an offline PostgreSQL.
set -euo pipefail
umask 077
[[ $(hostname -s) == ai-server01 && $(id -u) == 0 ]]
forum=community.vnbot.run
[[ $(curl -fsS --max-time 15 "https://$forum/srv/status") == ok ]]
curl -sSI --max-time 15 "http://$forum/" | head -4
if [[ ${1:-} == brand ]]; then
  public=$(mktemp -d)
  guest_dir=$(docker exec app mktemp -d /tmp/vnbot-brand.XXXXXX)
  trap 'rm -rf -- "$public"; docker exec app rm -rf -- "$guest_dir"' EXIT
  for file in vnbot-wordmark-v4-light.svg vnbot-wordmark-v4-dark.svg vnbot-app-icon-128.png; do
    curl --fail --silent --show-error --location "https://vnbot.run/landing/img/$file" -o "$public/$file"
  done
  docker cp "$public/." "app:$guest_dir/"
  docker exec app chown -R discourse: "$guest_dir"
  docker exec -i -u discourse -e "VNBOT_BRAND=$guest_dir" -w /var/www/discourse app bundle exec rails runner - <<'BRAND'
require "vips"
dir = ENV.fetch("VNBOT_BRAND")
images = {}
%w[light dark].each do |variant|
  source = File.join(dir, "vnbot-wordmark-v4-#{variant}.svg")
  file = File.join(dir, "vnbot-wordmark-#{variant}.png")
  Vips::Image.svgload(source, scale: 2.0).pngsave(file)
  images[variant] = file
end
images["icon"] = File.join(dir, "vnbot-app-icon-128.png")
uploads = images.transform_values do |path|
  File.open(path, "rb") do |file|
    upload = UploadCreator.new(file, File.basename(path), type: "site_setting", for_site_setting: true).create_for(Discourse.system_user.id)
    raise upload.errors.full_messages.join(", ") unless upload.persisted?
    upload
  end
end
{ logo: "light", logo_dark: "dark", logo_small: "icon", logo_small_dark: "icon", favicon: "icon" }.each do |setting, image|
  SiteSetting.public_send("#{setting}=", uploads.fetch(image))
  raise "Logo setting failed: #{setting}" unless SiteSetting.public_send(setting)&.id == uploads.fetch(image).id
end
puts "PASS: official VNBot wordmark (light/dark), compact icon and favicon"
BRAND
fi
docker exec -i -u discourse -w /var/www/discourse app bundle exec rails runner - <<'RUBY'
slugs = %w[bat-dau-thong-bao hoi-dap-bao-loi da-lam-voi-vnbot kho-skill-workflow lop-thu-nghiem]
categories = slugs.map { |slug| Category.find_by!(slug: slug) }
room = categories.last
guest = Guardian.new
raise "Public category hidden" unless categories.first(4).all? { |cat| guest.can_see_category?(cat) }
raise "Private category exposed to guest" if guest.can_see_category?(room)
group = Group.find_by!(name: "vnbot_lop_thu_nghiem")
raise "Unexpected classroom grants" unless room.category_groups.pluck(:group_id).sort == [group.id, Group::AUTO_GROUPS[:staff]].sort
raise "Classroom self-enrollment possible" if group.public_admission || group.automatic_membership_email_domains.present?
raise "Answers disabled" unless categories[1].custom_fields["enable_accepted_answers"].to_s == "true"
raise "Signup open" unless SiteSetting.invite_only
raise "Locale or theme mismatch" unless SiteSetting.default_locale.to_s == "vi" && Theme.find(Theme::CORE_THEMES.fetch("horizon")).default?
raise "Image size incorrect" unless SiteSetting.max_image_size_kb == 4096
raise "Daily backup disabled" unless SiteSetting.backup_frequency == 1
ActiveRecord::Base.transaction do
  people = 2.times.map do
    name = "betaqa#{SecureRandom.hex(5)}"
    member = User.new(username: name, email: "#{name}@example.invalid", active: true, trust_level: 1)
    member.save!(validate: false)
    member
  end
  outsider, pupil = people
  GroupUser.create!(group: group, user: pupil)
  raise "Outsider can read class" if Guardian.new(outsider).can_see_category?(room)
  raise "Enrolled pupil cannot read class" unless Guardian.new(pupil).can_see_category?(room)
  raise "Member can post announcement" if Guardian.new(outsider).can_post_in_category?(categories.first)
  raise "Member cannot reply in Q&A" unless Guardian.new(outsider).can_post_in_category?(categories[1])
  raise ActiveRecord::Rollback
end
puts "PASS: four public categories, guest cannot see private classroom, classroom group ACL, solved, invite-only, vi, Horizon, 4 MiB, daily backup"
puts "Active human admins: #{User.real.where(admin: true, active: true).count}"
RUBY
[[ ${1:-} == restore ]] || exit 0
[[ -f /etc/vnbot-community/rclone.conf ]]
docker exec app discourse backup
systemctl start vnbot-community-storage.service
dir=/var/discourse/shared/standalone/backups/default
latest=$(find "$dir" -maxdepth 1 -type f -name '*.tar.gz' -printf '%T@ %f\n' | sort -nr | head -1 | cut -d' ' -f2-)
[[ -n $latest && $latest != */* ]]
work=$(mktemp -d)
audit_id=''
clean() {
  if [[ -n $audit_id ]]; then docker rm -fv "$audit_id" >/dev/null; fi
  rm -rf -- "$work"
}
trap clean EXIT
rclone --config /etc/vnbot-community/rclone.conf copyto "r2:vnbot-community-backup/default/$latest" "$work/archive"
cmp "$dir/$latest" "$work/archive"
tar -tzf "$work/archive" > "$work/manifest"
dump=$(awk '$0 ~ /^(\.\/)?dump\.sql(\.gz)?$/ {print; exit}' "$work/manifest")
[[ -n $dump ]]
image=$(docker inspect --format '{{.Image}}' app)
audit_id=$(docker run -d --network none --entrypoint /bin/sleep "$image" 1800)
docker exec -u postgres "$audit_id" bash -euc '
  bin=$(pg_config --bindir)
  "$bin/initdb" -D /tmp/vnbot-recovery --no-locale -E UTF8 >/dev/null
  "$bin/pg_ctl" -D /tmp/vnbot-recovery -o "-k /tmp -c listen_addresses=" -l /tmp/recovery.log -w start >/dev/null
'
psql_test=(docker exec -i -u postgres "$audit_id" psql -X -v ON_ERROR_STOP=1 -h /tmp -d postgres)
extract_dump() {
  if [[ $dump == *.gz ]]; then tar -xOzf "$work/archive" "$dump" | gzip -dc
  else tar -xOzf "$work/archive" "$dump"; fi
}
# Isolated container, no network and no production mounts.
docker exec -u postgres app psql -X -At -d discourse -c "select format('create extension if not exists %I with schema %I cascade;', e.extname, n.nspname) from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname <> 'plpgsql' and n.nspname='public'" | "${psql_test[@]}" >/dev/null
if [[ $(docker exec -u postgres app psql -X -At -d discourse -c "select count(*) from pg_namespace where nspname='discourse_functions'") == 1 ]]; then
  docker exec -u postgres app pg_dump --schema-only --no-owner --no-privileges -n discourse_functions discourse | "${psql_test[@]}" >/dev/null
fi
extract_dump | sed '/^CREATE SCHEMA public;$/d' | "${psql_test[@]}" > "$work/restore.log"
q="select count(*) from categories where slug in ('bat-dau-thong-bao','hoi-dap-bao-loi','da-lam-voi-vnbot','kho-skill-workflow','lop-thu-nghiem');"
[[ $("${psql_test[@]}" -Atc "$q") == 5 ]]
[[ $("${psql_test[@]}" -Atc "select read_restricted from categories where slug='lop-thu-nghiem'") == t ]]
[[ $("${psql_test[@]}" -Atc "select count(*) from topics where title='Bắt đầu với VNBot Community'") -ge 1 ]]
echo "PASS: R2 backup downloaded byte-for-byte, SQL restored offline, categories, privacy flag and welcome topic checked."
