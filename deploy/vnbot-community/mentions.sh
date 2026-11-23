#!/usr/bin/env bash
# Install the server-only plugin and verify application behavior before reloading web workers.
set -euo pipefail
[[ $(id -u) == 0 && $(hostname -s) == ai-server01 ]]
ref=64f67a8555b66b9a55fc0d2197c779e953edb4db
base="https://raw.githubusercontent.com/vifarmgo-lab/discourse/$ref/deploy/vnbot-community/mentions"
shared=/var/discourse/shared/standalone/vnbot-community
root=/var/www/discourse/plugins/vnbot-community-mentions
config=/var/discourse/containers/app.yml
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
install -d -m 0755 "$shared" "$shared/releases"
release="$shared/releases/$ref"
install -d -m 0755 "$release"
for file in plugin.rb bridge.rb admin_connection.rb init.rb verify.rb; do
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
# Unicorn runs as discourse:www-data and has no supplementary groups. Keep the
# endpoint root-owned and grant its application UID read access even in that group.
if [[ -f "$shared/mention-endpoint" ]]; then
  service_uid=$(docker exec app id -u discourse)
  python3 - "$shared/mention-endpoint" "$service_uid" <<'PY'
import ctypes
import os
import stat
import sys

path, uid = sys.argv[1], int(sys.argv[2])
if uid <= 0:
    raise SystemExit("Invalid Discourse service UID")
lib = ctypes.CDLL("libacl.so.1", use_errno=True)
lib.acl_from_text.argtypes = [ctypes.c_char_p]
lib.acl_from_text.restype = ctypes.c_void_p
lib.acl_set_fd.argtypes = [ctypes.c_int, ctypes.c_void_p]
lib.acl_free.argtypes = [ctypes.c_void_p]
with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), "rb") as f:
    st = os.fstat(f.fileno())
    if not stat.S_ISREG(st.st_mode) or st.st_uid != 0:
        raise SystemExit("Expected a root-owned service endpoint")
    acl = lib.acl_from_text(f"u::rw-,u:{uid}:r--,g::r--,m::r--,o::---".encode())
    if not acl:
        raise OSError(ctypes.get_errno(), "Cannot construct endpoint ACL")
    try:
        if lib.acl_set_fd(f.fileno(), acl) != 0:
            raise OSError(ctypes.get_errno(), "Cannot set endpoint ACL")
    finally:
        lib.acl_free(acl)
PY
  docker exec -u discourse:www-data app test -r /shared/vnbot-community/mention-endpoint
  if docker exec -u discourse:www-data app test -w /shared/vnbot-community/mention-endpoint; then
    echo 'The web service should only have read access to the endpoint.' >&2
    exit 1
  fi
fi
ln -sfnT "releases/$ref" "$shared/current"
docker exec app ln -sfnT /shared/vnbot-community/current "$root"
runner=(docker exec -u discourse:www-data -w /var/www/discourse app bin/rails runner)
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
