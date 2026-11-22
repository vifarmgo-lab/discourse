#!/usr/bin/env bash
# Read-only inventory, run directly on the intended GDATA instance.
set -eu
expected=${1:?Pass the expected server hostname}
name=$(hostname -s)
if [[ "${name,,}" != "${expected,,}" ]]; then
  printf 'Wrong target host: %s\n' "$name" >&2
  exit 1
fi
hostname
uname -m
df -h /
free -h
ss -ltn '( sport = :80 or sport = :443 )'
if command -v docker >/dev/null 2>&1; then
  docker version --format '{{.Server.Version}}'
  docker ps --format 'table {{.Names}}\t{{.Ports}}\t{{.Status}}'
fi
if [[ -e /var/discourse/containers/app.yml ]]; then
  printf '%s\n' 'Existing Discourse configuration found. Check the installation before running setup.'
fi
