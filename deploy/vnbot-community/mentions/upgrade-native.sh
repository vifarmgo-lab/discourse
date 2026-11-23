#!/usr/bin/env bash
# Install a pinned version on the existing AI-Server01 deployment.
# Mode is staged until enable-native.rb provisions the native API and webhook.
set -euo pipefail
[[ $(id -u) == 0 && $(hostname -s) == ai-server01 ]]
ref=${1:?supply the reviewed full commit SHA}
[[ $ref =~ ^[0-9a-f]{40}$ ]]
shared=/var/discourse/shared/standalone/vnbot-community
old=$(readlink "$shared/current")
[[ $old == releases/* ]]
rel="releases/$ref"
dest="$shared/$rel"
base="https://raw.githubusercontent.com/vifarmgo-lab/discourse/$ref/deploy/vnbot-community/mentions"
stage=$(mktemp -d "$shared/releases/.native-XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
for file in plugin.rb bridge.rb admin_connection.rb native.rb init.rb verify.rb verify-native.rb enable-native.rb replay-native.rb; do
  curl -fsS --retry 3 --max-time 45 "$base/$file" -o "$stage/$file"
  chmod 644 "$stage/$file"
  docker exec app ruby -c "/shared/vnbot-community/releases/${stage##*/}/$file" >/dev/null
done
chmod 755 "$stage"
if [[ -d $dest ]]; then diff -qr "$stage" "$dest" >/dev/null; else mv "$stage" "$dest"; fi
ln -sfnT "$rel" "$shared/current"
run=(docker exec -u discourse:www-data -w /var/www/discourse app bin/rails runner)
reload() {
  docker exec app sv restart unicorn || docker exec app sv status unicorn
  if docker exec app test -d /etc/service/sidekiq; then docker exec app sv restart sidekiq || docker exec app sv status sidekiq; fi
}
rollback() {
  ln -sfnT "$old" "$shared/current"
  reload
}
if ! "${run[@]}" "/shared/vnbot-community/$rel/verify-native.rb"; then ln -sfnT "$old" "$shared/current"; exit 1; fi
reload
for ((i=0;i<45;i++)); do
  if [[ $(curl -sS --max-time 3 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d '{}' https://community.vnbot.run/vnbot-community/result || true) =~ ^(503|403)$ ]] &&
     [[ $(curl -fsS --max-time 3 https://community.vnbot.run/srv/status || true) == ok ]]; then
    echo "Staged. Enable only after the signed workspace sender is ready."
    exit 0
  fi
  sleep 2
done
rollback
exit 1
