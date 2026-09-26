#!/usr/bin/env python3
"""门票巡检：确认文件 / 终端那两个入口**仍然**只认设备凭据（C1 剩余）。

为什么单独要有这么个东西：这份收窄（nginx 的 auth_basic + 只读凭据的 403 闸门）写在
**面板管的 vhost 文件**里。面板只要重新生成一次站点配置，这几行就可能被抹掉 ——
而抹掉的后果是"任何人拿旧口令/空凭据都能进"（终端的另一端是一条 root shell）。
rclone 那层（--htpasswd）在 systemd 单元里，面板碰不到，但它自己也拦不住"只读凭据写文件"。

所以每 10 分钟查两件事：
  1. **活的**（真的打公网入口）：没凭据必须 401；只读凭据能读、不能写、不能进终端；
     密钥类路径与 /etc/shadow 仍然 404（C4）。
  2. **配置**（ssh 到边缘机看文件）：vhost 里那几行还在不在、两台 rclone 的 --htpasswd 还在不在。

只在"状态变化"时发消息（正常时一声不出）；恢复时补一条，免得一直以为坏着。

用法：
  box-ops-gate-probe.py --check      # 人工看一遍
  box-ops-gate-probe.py --quiet      # cron 用：只在出问题/恢复时发消息
  box-ops-gate-probe.py --test       # 发一条测试消息，确认投递链路通
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request
from base64 import b64encode
from datetime import datetime, timedelta, timezone
from pathlib import Path

CST = timezone(timedelta(hours=8))
PUBLIC = "https://box.hpa888.top"
CRED_FILE = Path("/var/lib/box-ops-gate/creds.json")     # 只读巡检凭据（600）
STATE_FILE = Path("/var/lib/box-ops-gate/state.json")
LOG_FILE = Path("/var/log/box-ops-gate.log")
EDGE_VHOST = "/www/server/panel/vhost/nginx/box.hpa888.top.conf"
SSH = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "hpa888"]

# 每个入口：路径、只读凭据属于哪台、PROPFIND 用 Depth:0
ENTRIES = {
    "hpa888": {"root": "/dav/", "term": "/term/", "shadow": "/dav/root/.secrets/box-update-server.env"},
    "175": {"root": "/dav175/", "term": "/term175/", "shadow": "/dav175/etc/shadow"},
}


def now() -> datetime:
    return datetime.now(CST)


def log(msg: str) -> None:
    line = f"{now().strftime('%F %T')} {msg}"
    print(line, flush=True)
    try:
        with LOG_FILE.open("a") as f:
            f.write(line + "\n")
    except Exception:  # noqa: BLE001
        pass


def http(url: str, user: str | None = None, pw: str | None = None,
         method: str = "GET", depth: bool = False, timeout: int = 25) -> str:
    req = urllib.request.Request(url, method=method)
    req.add_header("Connection", "close")
    if depth:
        req.add_header("Depth", "0")
    if user is not None:
        req.add_header("Authorization",
                       "Basic " + b64encode(f"{user}:{pw}".encode()).decode())
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return str(r.status)
    except urllib.error.HTTPError as e:  # 4xx/5xx 都从这里出来
        return str(e.code)
    except Exception as e:  # noqa: BLE001
        return f"ERR({type(e).__name__})"


def load_creds() -> dict:
    try:
        return json.loads(CRED_FILE.read_text())
    except Exception:  # noqa: BLE001
        return {}


def load_state() -> dict:
    try:
        return json.loads(STATE_FILE.read_text())
    except Exception:  # noqa: BLE001
        return {}


def save_state(st: dict) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(st, ensure_ascii=False, indent=2))
    STATE_FILE.chmod(0o600)


def send_feishu(title: str, body: str, dry: bool = False) -> bool:
    text = title + "\n" + body
    if dry:
        print(f"  [dry-run 会发] {text}")
        return True
    for cmd in (["/root/.local/bin/hermes", "send", "-t", "feishu", text],
                ["hermes", "send", "-t", "feishu", text]):
        try:
            if subprocess.run(cmd, capture_output=True, timeout=60).returncode == 0:
                return True
        except Exception:  # noqa: BLE001
            continue
    return False


def probe_config() -> list[str]:
    """配置侧：vhost 与 systemd 单元里，那几行还在不在。"""
    fails: list[str] = []
    try:
        vhost = subprocess.run(SSH + [f"cat {EDGE_VHOST}"], capture_output=True,
                               text=True, timeout=60).stdout
    except Exception as e:  # noqa: BLE001
        return [f"读不到边缘机 vhost（{type(e).__name__}）—— 无法确认配置，先当问题报"]
    if not vhost:
        return ["边缘机 vhost 是空的（ssh 不通？）"]
    checks = [
        ("/dav/ 的 Basic 认证", "auth_basic_user_file /www/server/nginx/conf/box-ops.htpasswd;"),
        ("/dav175/ 的 Basic 认证", "auth_basic_user_file /www/server/nginx/conf/box-ops175.htpasswd;"),
        ("只读凭据的写闸门（文件）", "if ($boxops_ro_write)"),
        ("只读凭据的终端闸门", "if ($boxops_ro_term)"),
        ("审计日志（谁动了什么）", "box-ops-access.log"),
    ]
    for name, marker in checks:
        if vhost.count(marker) < (2 if marker.startswith(("auth_basic_user_file /", "if (")) else 1):
            fails.append(f"vhost 里少了「{name}」（面板重新生成过配置？）")

    # 这个脚本跑在 175 上：hpa888 的单元要走 ssh 去读，175 的就地读
    for unit, here in (("box-ops-dav.service", False),      # hpa888 的
                       ("box-ops175-dav.service", True)):    # 175 的（本机）
        cmd = (["systemctl", "show", "-p", "ExecStart", "--value", unit] if here else
               SSH + [f"systemctl show -p ExecStart --value {unit}"])
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=60).stdout
        except Exception:  # noqa: BLE001
            out = ""
        if "--htpasswd" not in out:
            fails.append(f"{unit} 的 --htpasswd 没了（rclone 那层会退回单口令）")
        if out.count("--exclude") < 17:
            fails.append(f"{unit} 的 --exclude 少于 17 条（C4 的密钥路径收口被改动了）")
    return fails


def probe_live() -> list[str]:
    """在线侧：真的打公网入口。"""
    fails: list[str] = []
    creds = load_creds()

    for host, path in ((h, ENTRY["root"]) for h, ENTRY in ENTRIES.items()):
        c = http(PUBLIC + path, method="PROPFIND", depth=True)
        if c != "401":
            fails.append(f"{path} 没凭据拿到 {c}（应当是 401 —— 门没了？）")

    for host, ENTRY in ENTRIES.items():
        cred = creds.get(host) or {}
        user, pw = cred.get("user"), cred.get("secret")
        if not user or not pw:
            fails.append(f"缺 {host} 的巡检凭据（{CRED_FILE}）—— 在线侧只能查\"没凭据\"那一条")
            continue
        c = http(PUBLIC + ENTRY["root"], user, pw, "PROPFIND", depth=True)
        if c != "207":
            fails.append(f"{ENTRY['root']} 只读凭据列目录拿到 {c}（应当是 207）")
        c = http(PUBLIC + ENTRY["root"] + "tmp/box-gate-probe.txt", user, pw, "PUT")
        if c != "403":
            fails.append(f"{ENTRY['root']} 只读凭据 PUT 拿到 {c}（应当是 403 —— 只读闸门破了）")
        c = http(PUBLIC + ENTRY["term"], user, pw)
        if c != "403":
            fails.append(f"{ENTRY['term']} 只读凭据拿到 {c}（应当是 403 —— 终端不认只读了）")
        c = http(PUBLIC + ENTRY["shadow"], user, pw)
        if c != "404":
            fails.append(f"{ENTRY['shadow']} 拿到 {c}（应当是 404 —— C4 的收口被放开了）")
    return fails


def run(quiet: bool) -> int:
    fails = probe_live() + probe_config()
    st = load_state()
    was = st.get("state", "ok")
    if not fails:
        if was != "ok":
            log("已恢复：门票与 C4 收口都正常")
            if not quiet:
                pass
            send_feishu("✅ 运维通道门票已恢复", "文件/终端入口重新只认设备凭据，密钥路径仍然 404。")
        st["state"] = "ok"
        st["since"] = st.get("since") if was == "ok" else now().isoformat(timespec="seconds")
        st.pop("failures", None)   # 恢复了就把上次的问题清掉，别让人以为还坏着
        save_state(st)
        if not quiet:
            print("✅ 巡检通过：没凭据 401、只读不能写不能进终端、密钥路径 404、配置里的闸门都在")
        return 0

    log("发现问题：" + " | ".join(fails))
    if was != "bad":
        send_feishu("🚨 运维通道门票出问题了",
                    "文件/终端入口的凭据闸门有项不对：\n\n"
                    + "\n".join("• " + f for f in fails)
                    + "\n\n先别往这两个入口贴重要口令；查法："
                      "ssh hpa888 看 vhost 的 auth_basic 与 rclone 单元的 --htpasswd。")
    st["state"] = "bad"
    st["since"] = st.get("since") if was == "bad" else now().isoformat(timespec="seconds")
    st["failures"] = fails
    save_state(st)
    if not quiet:
        print("❌ 巡检不过：")
        for f in fails:
            print("   • " + f)
    return 1


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--test", action="store_true")
    a = ap.parse_args(argv)
    if a.test:
        ok = send_feishu("🔔 门票巡检：测试消息",
                         "这条是 box-ops-gate-probe.py --test 发的；收到就说明巡检能报出来。")
        print("已发出" if ok else "发送失败（检查 hermes send 那条链路）")
        return 0 if ok else 1
    return run(quiet=a.quiet)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))