#!/usr/bin/env bash
# Activate a staged worker using the dedicated workspace's PUBLIC verification key.
# Optional second argument replays one existing eligible mention using the native webhook.
set -euo pipefail
[[ $(id -u) == 0 && $(hostname -s) == ai-server01 ]]
der=${1:?workspace public key required}
[[ $der =~ ^[A-Za-z0-9+/]{59}=$ ]]
path=/shared/vnbot-community/current
run=(-u discourse:www-data -w /var/www/discourse)
docker exec "${run[@]}" -e COMMUNITY_PUBLIC_DER="$der" app bin/rails runner "$path/enable-native.rb"
for endpoint in events result; do
  status=$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' --data '{}' "https://community.vnbot.run/vnbot-community/$endpoint")
  [[ $status == 403 ]] || { echo "Unexpected unsigned response at $endpoint: $status"; exit 1; }
done
if [[ -n ${2:-} ]]; then
  [[ $2 =~ ^[1-9][0-9]*$ ]]
  docker exec "${run[@]}" -e COMMUNITY_POST_ID="$2" app bin/rails runner "$path/replay-native.rb"
fi
