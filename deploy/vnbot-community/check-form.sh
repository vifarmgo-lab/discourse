#!/usr/bin/env bash
# Read-only support check for the Community administrator's connection form.
set -euo pipefail
[[ $(hostname -s) == ai-server01 ]]
docker exec -i -u discourse -w /var/www/discourse app bin/rails runner - <<'RUBY'
m = VNBotCommunityMentions
url = "https://community.vnbot.run"
puts "canonical HTTPS origin matches: #{Discourse.base_url == url}"
puts "credential saved: #{m.active?}"
form = VnBotCommunityConnectionController.new
form.set_response!(ActionDispatch::Response.new)
form.send(:private_response)
puts "form referrer policy: #{form.response.headers['Referrer-Policy']}"
Logster.store.latest(limit: 100).each do |entry|
  next unless entry.respond_to?(:message)
  trace = Array(entry.backtrace).join("\n")
  msg = entry.message.to_s
  scoped = trace.include?("admin_connection.rb") || msg.include?("VnBotCommunityConnectionController") ||
    Array.wrap(entry.env).any? { |e| e.is_a?(Hash) && e["REQUEST_URI"].to_s.split("?", 2).first == "/vnbot-community/connection" }
  next unless scoped
  kind = msg[/\b(?:[A-Z][a-zA-Z0-9]*::)*[A-Z][a-zA-Z0-9]*(?:Error|Exception|InvalidAuthenticityToken)\b/]
  frames = (trace + "\n" + msg).scan(/(?:admin_connection|application_controller|request_forgery_protection|plugin_store|controller|parameters|bridge)\.rb:\d+/).uniq.first(7)
  puts "form exception: #{kind || 'unspecified'}; frames: #{frames.join(', ')}"
end
RUBY
python3 - <<'PY'
from pathlib import Path
import re
from collections import deque
path = Path('/var/discourse/shared/standalone/log/var-log/nginx/access.log')
if not path.is_file():
    print('No nginx log at expected path')
else:
    records = deque(maxlen=16)
    with path.open(errors='replace') as log:
        log.seek(0, 2)
        start = max(0, log.tell() - 2000000)
        log.seek(start)
        if start:
            log.readline()
        for line in log:
            fields = line.split('"')
            if len(fields) < 10:
                continue
            req = re.fullmatch(r'(GET|POST) /vnbot-community/connection(?:\?saved=1)? HTTP/[0-9.]+', fields[3])
            code = re.fullmatch(r'\s*(\d{3})\s+(\d+)\s*', fields[8])
            if req and code:
                stamp = fields[0].split(']', 1)[0]
                route = fields[7] if re.fullmatch(r'[a-zA-Z0-9_/#:. -]{0,120}', fields[7]) else '?'
                records.append((stamp+']', req[1], code[1], route))
    for rec in records:
        print(*rec)
PY
