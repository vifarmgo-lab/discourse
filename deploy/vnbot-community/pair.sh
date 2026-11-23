#!/usr/bin/env bash
set -euo pipefail
[[ $(id -u) == 0 && $(hostname -s) == ai-server01 ]]
dir=/var/discourse/shared/standalone/vnbot-community
[[ -d "$dir" ]]
if [[ ! -s $dir/mention-endpoint ]]; then
  python3 - "$dir" <<'PY'
import getpass,os,re,subprocess,sys,tempfile
from pathlib import Path
from urllib.parse import urlsplit
p=Path(sys.argv[1])
url=getpass.getpass("Dedicated Community routine URL (hidden): ").strip()
u=urlsplit(url)
if (u.scheme!="https" or not re.fullmatch(r"(?:[a-z0-9-]+\.)*vnbot\.run",u.hostname or "") or u.port not in (443,None)
    or u.username or u.password or u.fragment or not u.path.strip("/") or not url.isascii()
    or any(ord(c)<33 for c in url)):
    raise SystemExit("Invalid endpoint, nothing written.")
gid=int(subprocess.check_output(["docker","exec","app","id","-g","discourse"]).strip())
with tempfile.NamedTemporaryFile(mode="w",dir=p,delete=False) as f:
    f.write(url+"\n"); f.flush(); os.fsync(f.fileno()); os.fchown(f.fileno(),0,gid); os.fchmod(f.fileno(),0o640)
os.replace(f.name,p/"mention-endpoint")
print("Dedicated endpoint saved.")
PY
fi
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p /usr/local/lib/vnbot-community
base=https://raw.githubusercontent.com/vifarmgo-lab/discourse/21bf372b4104bd4efb5df087b79929ada0166b03/deploy/vnbot-community
curl -fsSL --retry 3 "$base/mentions.sh" -o "$work/update"
bash "$work/update"
