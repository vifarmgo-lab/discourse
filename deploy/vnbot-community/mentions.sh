#!/usr/bin/env bash
# Install the server-only plugin and verify application behavior before reloading web workers.
set -euo pipefail
[[ $(id -u) == 0 && $(hostname -s) == ai-server01 ]]
ref=802c34f40bfccbfb1ae246670c66577275458af2
base="https://raw.githubusercontent.com/vifarmgo-lab/discourse/$ref/deploy/vnbot-community/mentions"
shared=/var/discourse/shared/standalone/vnbot-community
root=/var/www/discourse/plugins/vnbot-community-mentions
config=/var/discourse/containers/app.yml
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
install -d -m 0755 "$shared" "$shared/releases"
release="$shared/releases/$ref"
install -d -m 0755 "$release"
for file in plugin.rb bridge.rb init.rb verify.rb; do
  curl -fsSL --retry 3 "$base/$file" -o "$scratch/$file"
  install -m 0644 "$scratch/$file" "$release/$file"
  docker exec app ruby -c "/shared/vnbot-community/releases/$ref/$file" >/dev/null
done
if docker exec app test -e "$root"; then
  [[ $(docker exec app readlink "$root") == /shared/vnbot-community/current ]]
fi
[[ ! -e "$shared/current" || -L "$shared/current" ]]
previous=$(readlink "$shared/current" || true)
restore_link() {
  if [[ -n $previous ]]; then ln -sfnT "$previous" "$shared/current"; else
    docker exec app rm -f "$root"
    rm -f "$shared/current"
  fi
}
ln -sfnT "releases/$ref" "$shared/current"
docker exec app ln -sfnT /shared/vnbot-community/current "$root"
runner=(docker exec -u discourse -w /var/www/discourse app bin/rails runner)
if ! "${runner[@]}" "/shared/vnbot-community/releases/$ref/init.rb" ||
   ! "${runner[@]}" "/shared/vnbot-community/releases/$ref/verify.rb"; then
  restore_link
  exit 1
fi
# Insert only the rebuild hook; keep the rest of the private app.yml byte-for-byte.
python3 - "$config" <<'PY'
from pathlib import Path
import os,sys,tempfile,shutil
p=Path(sys.argv[1])
before=p.read_bytes()
cmd=b"    - exec: ln -sfnT /shared/vnbot-community/current /var/www/discourse/plugins/vnbot-community-mentions\n"
if cmd not in before:
    marker=b"  after_code:\n"
    if before.count(marker)!=1: raise SystemExit("Review after_code hook before reloading")
    with tempfile.NamedTemporaryFile(dir=p.parent,delete=False) as f:
        f.write(before.replace(marker,marker+cmd,1))
        tmp=f.name
    shutil.copystat(p,tmp); os.chmod(tmp,0o600)
    keep=p.with_suffix(".yml.pre-community-mentions")
    if not keep.exists(): shutil.copy2(p,keep); os.chmod(keep,0o600)
    os.replace(tmp,p)
PY
docker exec app sv restart unicorn || true
if docker exec app test -d /etc/service/sidekiq; then docker exec app sv restart sidekiq || true; fi
for ((n=0;n<90;n++)); do
  if [[ $(curl -fsS --max-time 3 https://community.vnbot.run/srv/status 2>/dev/null || true) == ok ]]; then
    status=$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' --data '{"post_id":1,"answer":"probe"}' https://community.vnbot.run/vnbot-community/reply || true)
    if [[ $status == 403 ]]; then echo "PASS: Forum healthy; live callback rejects unsigned requests."; exit 0; fi
  fi
  sleep 2
done
echo 'Live health or endpoint check failed; restoring previous plugin and configuration.'
restore_link
if [[ -f $config.pre-community-mentions && -z $previous ]]; then
  # Remove only this hook to preserve any concurrent app.yml edits.
  sed -i '\|^    - exec: ln -sfnT /shared/vnbot-community/current /var/www/discourse/plugins/vnbot-community-mentions$|d' "$config"
fi
docker exec app sv restart unicorn || true
exit 1
