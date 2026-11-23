#!/usr/bin/env bash
# Run on the GDATA production host. Install a monthly staff-only VIP review.
set -euo pipefail
[[ "$(hostname -s)" == ai-server01 && "$(id -u)" == 0 ]]
base=/usr/local/lib/vnbot-community
install -d -m 0755 "$base"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
curl -fsSL --retry 3 https://raw.githubusercontent.com/vifarmgo-lab/discourse/833ea89506becac28522cc0d0c5f0ec06bca4bde/deploy/vnbot-community/community_operations.rb -o "$work/ops.rb"
docker cp "$work/ops.rb" app:/tmp/community_operations_install.rb
docker exec app ruby -c /tmp/community_operations_install.rb
docker exec -w /var/www/discourse -u discourse app bin/rails runner /tmp/community_operations_install.rb
install -m 0644 "$work/ops.rb" "$base/community_operations.rb"
cat > "$work/review" <<'RUN'
#!/usr/bin/env bash
set -euo pipefail
docker cp /usr/local/lib/vnbot-community/community_operations.rb app:/tmp/community_operations.rb
docker exec -w /var/www/discourse -u discourse app bin/rails runner /tmp/community_operations.rb
RUN
install -m 0755 "$work/review" "$base/review-vip"
cat > "$work/ops.service" <<'UNIT'
[Unit]
Description=VNBot Community staff-only VIP review
After=docker.service
[Service]
Type=oneshot
ExecStart=/usr/local/lib/vnbot-community/review-vip
UNIT
cat > "$work/ops.timer" <<'UNIT'
[Unit]
Description=Review VNBot VIP membership on the first morning of each month
[Timer]
OnCalendar=*-*-01 09:00:00 Asia/Ho_Chi_Minh
Persistent=true
[Install]
WantedBy=timers.target
UNIT
install -m 0644 "$work/ops.service" /etc/systemd/system/vnbot-community-vip.service
install -m 0644 "$work/ops.timer" /etc/systemd/system/vnbot-community-vip.timer
systemctl daemon-reload
systemctl enable --now vnbot-community-vip.timer
systemctl list-timers vnbot-community-vip.timer --no-pager
