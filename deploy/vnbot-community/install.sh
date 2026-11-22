#!/usr/bin/env bash
# First installation of the VNBot Community beta on its dedicated GDATA server.
set -euo pipefail
umask 077
forum=community.vnbot.run
install_dir=/var/discourse
seed_commit=0669aca77e40e93ce6435bcd0ca1932b63496d82
if [[ $(id -u) != 0 || $(hostname -s) != ai-server01 ]]; then
  echo "Run on the dedicated ai-server01 console as root." >&2
  exit 1
fi
if [[ ! -t 0 ]]; then
  echo "The initial owner must be entered at the server console." >&2
  exit 1
fi
read -r -p "Approved forum admin email: " owner
if [[ ! $owner =~ ^[A-Za-z0-9_.+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
  echo "Invalid email address." >&2
  exit 1
fi
docker info --format '{{.ServerVersion}}'
if [[ -n $(ss -ltnH '( sport = :80 or sport = :443 )') ]] || docker container inspect app >/dev/null 2>&1; then
  echo "Existing service detected. Inspect it before installing." >&2
  exit 1
fi
if [[ ! -e $install_dir ]]; then
  git clone --depth 1 https://github.com/discourse/discourse_docker.git "$install_dir"
fi
cd "$install_dir"
[[ $(git remote get-url origin) == https://github.com/discourse/discourse_docker.git ]]
exec 9>/run/vnbot-community-install.lock
flock -n 9 || { echo "An installation is already running."; exit 1; }
config=containers/app.yml
config_tmp=$(mktemp containers/vnbot-XXXXXX)
trap 'rm -f -- "$config_tmp"' EXIT
cat > "$config_tmp" <<YAML
templates:
  - templates/postgres.template.yml
  - templates/redis.template.yml
  - templates/web.template.yml
  - templates/web.ratelimited.template.yml
  - templates/web.ssl.template.yml
  - templates/web.letsencrypt.ssl.template.yml
expose:
  - "80:80"
  - "443:443"
params:
  db_default_text_search_config: pg_catalog.simple
env:
  LANG: en_US.UTF-8
  LC_ALL: en_US.UTF-8
  DISCOURSE_HOSTNAME: "$forum"
  DISCOURSE_DEVELOPER_EMAILS: "$owner"
  DISCOURSE_DEFAULT_LOCALE: vi
  DISCOURSE_INVITE_ONLY: "true"
  DISCOURSE_SKIP_EMAIL_SETUP: "1"
  LETSENCRYPT_ACCOUNT_EMAIL: "$owner"
volumes:
  - volume:
      host: /var/discourse/shared/standalone
      guest: /shared
  - volume:
      host: /var/discourse/shared/standalone/log/var-log
      guest: /var/log
hooks:
  after_code:
    - exec:
        cd: \$home/plugins
        cmd:
          - git clone https://github.com/discourse/docker_manager.git
YAML
if [[ -e $config ]]; then
  cmp -s "$config" "$config_tmp" || { echo "An existing app.yml differs. Leaving it in place."; exit 1; }
else
  install -m 0600 "$config_tmp" "$config"
fi
seed=/var/discourse/vnbot-community-bootstrap.rb
curl -fSsL --retry 2 "https://raw.githubusercontent.com/vifarmgo-lab/discourse/$seed_commit/deploy/vnbot-community/bootstrap.rb" -o "$seed"
git rev-parse HEAD > /var/discourse/vnbot-installer-revision
./launcher bootstrap app
./launcher start app
docker cp "$seed" app:/tmp/vnbot-community-bootstrap.rb
# docker cp preserves the root-owned host file mode. Grant read access inside the application container.
docker exec app chmod 0644 /tmp/vnbot-community-bootstrap.rb
docker exec -u discourse -w /var/www/discourse app bundle exec rails runner /tmp/vnbot-community-bootstrap.rb
echo "Forum started. Verify TLS, outbound email, private storage and a restore before inviting members."
