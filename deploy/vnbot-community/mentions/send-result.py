#!/usr/bin/env python3
"""Send a signed VNBot Community answer. Reads JSON from stdin in the bot workspace."""
import base64
import json
import os
from pathlib import Path
import ssl
import subprocess
import sys
import tempfile
import uuid
from http.client import HTTPSConnection

HOST = "community.vnbot.run"
ENDPOINT = "/vnbot-community/result"


def make_body(data):
    event = data["event_id"]
    post = data["post_id"]
    answer = data["answer"].strip()
    if str(uuid.UUID(event)) != event or type(post) is not int or not 1 <= post <= 2_147_483_647:
        raise ValueError("Invalid event reference")
    if not 2 <= len(answer) <= 1500:
        raise ValueError("Invalid answer length")
    return json.dumps({"event_id": event, "post_id": post, "answer": answer},
                      ensure_ascii=False, separators=(",", ":")).encode()


def signed_body(body, key):
    if key.is_symlink() or key.stat().st_mode & 0o077 or key.stat().st_uid != os.getuid():
        raise ValueError("Expected a protected key belonging to this workspace")
    # Ed25519 requires a seekable input file with OpenSSL pkeyutl 3.x.
    with tempfile.NamedTemporaryFile() as payload:
        payload.write(body)
        payload.flush()
        signature = subprocess.run(["openssl", "pkeyutl", "-sign", "-rawin", "-inkey", str(key),
                                    "-in", payload.name], stdout=subprocess.PIPE, check=True).stdout
    return base64.b64encode(signature).decode("ascii")


def main():
    raw = sys.stdin.buffer.read(12_289)
    if len(raw) > 12_288:
        raise ValueError("Input too large")
    body = make_body(json.loads(raw))
    key = Path(__file__).resolve().with_name("signing.pem")
    signature = signed_body(body, key)
    client = HTTPSConnection(HOST, timeout=20, context=ssl.create_default_context())
    try:
        client.request("POST", ENDPOINT, body=body, headers={
            "Content-Type": "application/json", "X-VNBot-Signature": signature})
        code = client.getresponse().status
    finally:
        client.close()
    print(f"Community HTTP {code}")
    return 0 if code in {200, 202} else 1


if __name__ == "__main__":
    sys.exit(main())
