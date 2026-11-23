#!/usr/bin/env python3
"""Connect the new VNBot Community routine from a terminal without recording its token."""
import getpass
import json
import os
from pathlib import Path
import re
import socket
import stat
import subprocess
import tempfile
import urllib.parse

def main():
    if os.geteuid() != 0 or socket.gethostname().split(".")[0].casefold() != "ai-server01":
        raise SystemExit("Run as root in the GDATA console on AI-Server01.")
    root = Path("/var/discourse/shared/standalone/vnbot-community")
    if not (root / "current" / "bridge.rb").is_file():
        raise SystemExit("Install and verify mentions.sh first.")
    url = getpass.getpass("VNBot Community routine URL (hidden): ").strip()
    parts = urllib.parse.urlsplit(url)
    if (parts.scheme != "https" or not re.fullmatch(r"(?:[a-z0-9-]+\.)*vnbot\.run",parts.hostname or "")
            or parts.username or parts.password or parts.fragment or parts.port not in (None,443)):
        raise SystemExit("Expected an HTTPS webhook belonging to VNBot.run. No file written.")
    header = getpass.getpass("Complete webhook authorization header (hidden): ").strip()
    if ":" in header:
        name, value = (s.strip() for s in header.split(":",1))
    elif header.startswith("Bearer "):
        name, value = "Authorization", header
    else:
        raise SystemExit("Copy the full header including its name. No file written.")
    if (not re.fullmatch(r"authorization|x-[a-z0-9-]+", name, re.I)
            or not 12 <= len(value) <= 2048 or not value.isascii() or not value.isprintable()):
        raise SystemExit("Invalid webhook header. No file written.")
    group_id = int(subprocess.check_output(["docker","exec","app","id","-g","discourse"],text=True).strip())
    final = root / "mention-connection.json"
    tmp = None
    try:
        with tempfile.NamedTemporaryFile("w", dir=root, delete=False) as f:
            tmp = Path(f.name)
            os.fchown(f.fileno(),0,group_id)
            os.fchmod(f.fileno(),stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP)
            json.dump({"url":url,"header":name,"value":value},f)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp,final)
    finally:
        if tmp is not None:
            tmp.unlink(missing_ok=True)
    print("Private webhook configuration saved. Run the Community verification and then test one mention.")

if __name__ == "__main__":
    main()
