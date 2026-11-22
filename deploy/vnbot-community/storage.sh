#!/usr/bin/env bash
# Private off-site copies for a standalone Discourse install on GDATA.
set -euo pipefail
umask 077
if [[ $(id -u) != 0 || $(hostname -s) != ai-server01 ]]; then
  echo 'Run on AI-Server01 as root.' >&2
  exit 1
fi
data=/var/discourse/shared/standalone
config=/etc/vnbot-community/rclone.conf
media=vnbot-community-media
backup=vnbot-community-backup

copy_files() {
  rclone --config "$config" copy "$data/uploads/" "r2:$media/uploads/"
  if [[ -d $data/backups/default ]]; then
    rclone --config "$config" copy --include '*.tar.gz' --include '*.sql.gz' \
      "$data/backups/default/" "r2:$backup/default/"
  fi
}

if [[ ${1:-} == copy ]]; then
  copy_files
  exit
fi
[[ -d $data/uploads && -t 0 ]]
if ! command -v rclone >/dev/null; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y rclone
fi
install -d -m 0700 /etc/vnbot-community
if [[ ! -s $config ]]; then
  read -rp 'R2 S3 endpoint: ' endpoint
  [[ $endpoint =~ ^https://[[:xdigit:]]{32}\.r2\.cloudflarestorage\.com/?$ ]]
  read -rsp 'R2 Access Key ID (hidden): ' key
  echo
  read -rsp 'R2 Secret Access Key (hidden): ' secret
  echo
  [[ $key =~ ^[[:xdigit:]]{32}$ && $secret =~ ^[A-Za-z0-9/+=_-]{32,128}$ ]]
  pending=$(mktemp /etc/vnbot-community/rclone.XXXXXX)
  trap 'rm -f -- "$pending"' EXIT
  cat > "$pending" <<CONFIG
[r2]
type = s3
provider = Cloudflare
access_key_id = $key
secret_access_key = $secret
endpoint = $endpoint
region = auto
no_check_bucket = true
CONFIG
  unset key secret
  for bucket in "$media" "$backup"; do
    probe="setup-check/$(cat /proc/sys/kernel/random/uuid)"
    printf 'VNBot private storage check' | rclone --config "$pending" rcat "r2:$bucket/$probe"
    [[ $(rclone --config "$pending" cat "r2:$bucket/$probe") == 'VNBot private storage check' ]]
    rclone --config "$pending" deletefile "r2:$bucket/$probe"
    echo "Verified read/write: $bucket"
  done
  mv "$pending" "$config"
  trap - EXIT
fi
install -m 0700 "$0" /usr/local/sbin/vnbot-community-storage
cat > /etc/systemd/system/vnbot-community-storage.service <<'UNIT'
[Unit]
Description=Copy VNBot community uploads and completed backups to private R2 buckets
Wants=network-online.target
After=network-online.target
[Service]
Type=oneshot
UMask=0077
ExecStart=/usr/local/sbin/vnbot-community-storage copy
UNIT
cat > /etc/systemd/system/vnbot-community-storage.timer <<'UNIT'
[Unit]
Description=Copy new community files to R2 every hour
[Timer]
OnCalendar=hourly
Persistent=true
[Install]
WantedBy=timers.target
UNIT
chmod 0644 /etc/systemd/system/vnbot-community-storage.{service,timer}
systemctl daemon-reload
systemctl enable --now vnbot-community-storage.timer
systemctl start vnbot-community-storage.service
echo "Private R2 storage configured. Uploads continue to load through the forum."
