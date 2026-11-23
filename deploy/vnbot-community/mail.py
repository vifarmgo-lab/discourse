#!/usr/bin/env python3
"""Configure Resend on the existing VNBot Community container without upgrading Discourse."""
import getpass
import os
from pathlib import Path
import re
import shutil
import smtplib
import ssl
import subprocess
import sys
import tempfile
import time
import fcntl

ROOT = Path("/var/discourse")
CONFIG = ROOT / "containers/app.yml"
HOST = "community.vnbot.run"
SMTP = "smtp.resend.com"
SENDER = "congdong@" + HOST


def run(*args, capture=False):
    return subprocess.run(args, check=True, text=True,
                          stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).stdout


def write_config(contents):
    with tempfile.NamedTemporaryFile(mode="w", dir=CONFIG.parent, delete=False) as out:
        out.write(contents)
        out.flush()
        os.fsync(out.fileno())
    os.replace(out.name, CONFIG)


def endpoint_ready():
    try:
        return run("curl", "-fsS", "--max-time", "4", "--resolve",
                   f"{HOST}:443:127.0.0.1", f"https://{HOST}/srv/status", capture=True).strip() == "ok"
    except subprocess.CalledProcessError:
        return False


def configure():
    os.umask(0o077)
    if os.geteuid() or os.uname().nodename.split(".")[0] != "ai-server01":
        sys.exit("Run on AI-Server01 as root.")
    lock = open("/run/lock/vnbot-community-mail.lock", "w")
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    os.chdir(ROOT)
    old = CONFIG.read_text()
    marker = '  DISCOURSE_SKIP_EMAIL_SETUP: "1"'
    if old.count(marker) != 1 or "DISCOURSE_SMTP_" in old or not endpoint_ready():
        sys.exit("Existing mail settings, unexpected config, or forum unavailable; inspect before changing.")
    image = run("docker", "inspect", "-f", "{{.Image}}", "app", capture=True).strip()
    if run("docker", "image", "inspect", "-f", "{{.Id}}", "local_discourse/app", capture=True).strip() != image:
        sys.exit("Local image differs from the running image.")
    if not sys.stdin.isatty():
        sys.exit("Use an interactive private console.")
    secret = getpass.getpass("Resend SMTP key (hidden): ")
    if not re.fullmatch(r"re_[A-Za-z0-9_-]{16,160}", secret):
        sys.exit("Invalid key format.")
    for port in (465, 2465):
        try:
            with smtplib.SMTP_SSL(SMTP, port, timeout=9, context=ssl.create_default_context()) as smtp:
                smtp.login("resend", secret)
            break
        except smtplib.SMTPAuthenticationError:
            sys.exit("Resend did not accept the credential. Forum untouched.")
        except OSError:
            continue
    else:
        sys.exit("Resend SMTPS unreachable. Forum untouched.")
    env = {"SMTP_ADDRESS": SMTP, "SMTP_PORT": str(port), "SMTP_USER_NAME": "resend",
           "SMTP_PASSWORD": secret, "SMTP_FORCE_TLS": "true",
           "SMTP_OPENSSL_VERIFY_MODE": "peer", "NOTIFICATION_EMAIL": SENDER}
    settings = "\n".join(f'  DISCOURSE_{name}: "{value}"' for name, value in env.items())
    stamp = str(time.time_ns())
    saved = CONFIG.parent / ("app.yml.before-community-mail-" + stamp)
    shutil.copy2(CONFIG, saved)
    os.chmod(saved, 0o600)
    prev = "vnbot-mail-previous-" + stamp
    policy = run("docker", "inspect", "-f", "{{.HostConfig.RestartPolicy.Name}}", "app", capture=True).strip()
    renamed = False
    try:
        write_config(old.replace(marker, settings))
        run("docker", "update", "--restart=no", "app")
        run("docker", "stop", "-t", "120", "app")
        run("docker", "rename", "app", prev)
        renamed = True
        run("./launcher", "start", "app")
        for _ in range(80):
            if endpoint_ready():
                break
            time.sleep(3)
        else:
            raise RuntimeError("New container failed its HTTPS health check")
        verify = ("s=ActionMailer::Base.smtp_settings; abort unless s[:address]=='smtp.resend.com' && "
                  "(s[:ssl] || s[:tls]); abort unless SiteSetting.notification_email=='" + SENDER + "' && "
                  "SiteSetting.invite_only && SiteSetting.enable_discourse_id && SiteSetting.disable_emails=='no'")
        run("docker", "exec", "-u", "discourse", "-w", "/var/www/discourse", "app", "bin/rails", "r", verify)
    except BaseException:
        if renamed:
            new = subprocess.run(["docker","inspect","app"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            if new.returncode == 0:
                run("docker", "stop", "-t", "120", "app")
                run("docker", "rename", "app", "vnbot-mail-failed-" + stamp)
                run("docker", "update", "--restart=no", "vnbot-mail-failed-" + stamp)
            run("docker", "rename", prev, "app")
        write_config(old)
        run("docker", "update", "--restart=" + policy, "app")
        run("docker", "start", "app")
        raise
    print("PASS: forum HTTPS, Resend TLS, sender, invitation-only and Discourse ID verified.")


if __name__ == "__main__":
    configure()
