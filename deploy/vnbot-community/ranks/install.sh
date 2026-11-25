#!/usr/bin/env bash
set -Eeuo pipefail
ref=${1:?Supply a full commit SHA}
[[ $ref =~ ^[0-9a-f]{40}$ && $(id -u) == 0 ]]
cd /var/discourse
exec 9>/run/lock/vnbot-rank-install
flock -n 9
base=/var/discourse/shared/standalone/vnbot-ranks
release=/shared/vnbot-ranks/releases/$ref
plugin=/var/www/discourse/plugins/vnbot-community-ranks
repo=https://raw.githubusercontent.com/vifarmgo-lab/discourse/$ref/deploy/vnbot-community/ranks
files=(plugin.rb controller.rb program.rb publish.rb verify.rb schema.rb navigation.js style.css views/rank/index.html.erb)
install -d -m 0755 "$base" "$base/releases"
stage=$(mktemp -d "$base/releases/.stage.XXXXXXXX")
old=$(readlink "$base/current" || true)
linked=0
switched=0
reload=0
hookadded=0
hook='    - exec: ln -sfnT /shared/vnbot-ranks/current /var/www/discourse/plugins/vnbot-community-ranks'
config=containers/app.yml
hook_edit() {
  python3 - "$config" "$hook" "$1" <<'PY'
import os,sys,shutil,tempfile
from pathlib import Path
p=Path(sys.argv[1]); hook=sys.argv[2]+'\n'; data=p.read_text()
if sys.argv[3]=='add':
    assert data.count('  after_code:\n')==1,'Unrecognized after_code config'
    out=data.replace('  after_code:\n','  after_code:\n'+hook,1)
else:
    out=data.replace(hook,'',1)
fd,n=tempfile.mkstemp(dir=p.parent)
try:
    with os.fdopen(fd,'w') as f: f.write(out)
    shutil.copystat(p,n); s=p.stat(); os.chown(n,s.st_uid,s.st_gid); os.replace(n,p)
finally:
    if os.path.exists(n): os.unlink(n)
PY
}
finish() {
  rc=$?
  trap - EXIT
  set +e
  if ((rc && switched)); then
    echo "Reverting the rank release; diagnostic output is in /var/log/vnbot-ranks-install.log"
    if [[ -n $old ]]; then ln -sfnT "$old" "$base/current"; else rm -f "$base/current"; fi
    if ((linked)); then docker exec app rm -f "$plugin"; fi
    if ((hookadded)); then hook_edit remove; fi
    if ((reload)); then docker exec app sv -w 60 restart unicorn; fi
  fi
  [[ -d $stage ]] && rm -rf "$stage"
  exit "$rc"
}
trap finish EXIT
exec > >(tee /var/log/vnbot-ranks-install.log) 2>&1
echo "Staging verified rank release $ref"
for f in "${files[@]}"; do
  mkdir -p "$stage/$(dirname "$f")"
  curl --retry 2 --max-time 30 -fsSL "$repo/$f" -o "$stage/$f"
done
chmod -R a+rX "$stage"
if [[ -d $base/releases/$ref ]]; then diff -qr "$stage" "$base/releases/$ref"; else mv "$stage" "$base/releases/$ref"; fi
for f in plugin controller program publish verify schema; do docker exec app ruby -c "$release/$f.rb"; done
if docker exec app test -e "$plugin" || docker exec app test -L "$plugin"; then
  [[ $(docker exec app readlink "$plugin") == /shared/vnbot-ranks/current ]] || { echo "Unexpected plugin directory"; exit 1; }
else
  linked=1
fi
run=(docker exec -u discourse:www-data -w /var/www/discourse app bin/rails runner)
docker exec -u discourse:www-data app test -r "$release/schema.rb"
echo "Checking schema"
"${run[@]}" "$release/schema.rb"
switched=1
ln -sfnT "releases/$ref" "$base/current"
if ((linked)); then docker exec app ln -s /shared/vnbot-ranks/current "$plugin"; fi
echo "Testing progression and routes before web restart"
if ! "${run[@]}" "$release/verify.rb" > "$base/.verify-log" 2>&1; then
  head -n 12 "$base/.verify-log"; exit 1
fi
cat "$base/.verify-log"
if ! grep -Fqx "$hook" "$config"; then hook_edit add; hookadded=1; fi
reload=1
docker exec app sv -w 90 restart unicorn
seen=0
for attempt in {1..30}; do
  if curl -fsS --max-time 5 https://community.vnbot.run/lo-trinh -o "$base/.rank-health" 2>/dev/null && grep -Fq 'Lộ trình chuyên gia' "$base/.rank-health"; then seen=1; break; fi
  sleep 2
done
[[ $seen == 1 ]] || { echo 'Public rank page did not pass'; exit 1; }
"${run[@]}" "$release/publish.rb"
echo "PASS live rank page and badge descriptions at community.vnbot.run"
