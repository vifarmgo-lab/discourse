#!/usr/bin/env bash
set -euo pipefail
[[ $(id -u) == 0 && $(hostname -s) == ai-server01 ]]
base=https://raw.githubusercontent.com/vifarmgo-lab/discourse/4451418126f1612c0e1b915f34e28482d02c9e44/deploy/vnbot-community
dir=/usr/local/lib/vnbot-community
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
curl -fsSL "$base/verify_operations.rb" -o "$tmp/verify.rb"
curl -fsSL "$base/connect.py" -o "$tmp/connect.py"
install -m 0700 "$tmp/connect.py" "$dir/connect-vnbot"
docker cp "$tmp/verify.rb" app:/tmp/verify-community-ops.rb
docker exec -u discourse -w /var/www/discourse app bin/rails runner /tmp/verify-community-ops.rb
