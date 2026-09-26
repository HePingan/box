#!/usr/bin/env python3
"""文件通道 / 终端的凭据（C1 剩余）：一台设备一条，可撤销、有作用域、有审计。

为什么是 htpasswd 而不是"自建认证代理"：
  * 文件（rclone serve webdav）与终端（ttyd）都在 nginx 后面，**nginx 自带 Basic 认证**
    就能按用户校验 —— 不需要额外进程，也不需要在数据路径上搬字节（大文件传输最怕这个）；
  * rclone v1.71 支持 `--htpasswd`（多用户），于是 nginx 与 rclone 可以读**同一个文件**，
    同一套凭据在两层都通；
  * 曾试过 nginx `auth_request` + box-ops-api 当认证后端（更"正统"），但这台 nginx 没编
    `ngx_http_auth_request_module`（只有源码没 .so），`nginx -t` 直接报 unknown directive。
    重编线上 nginx 不值当，于是换成这条路。

凭据模型：
  * 一个凭据 = htpasswd 里一行（用户名 = label；**只读**凭据的用户名带 `ro-` 前缀）；
  * 只读的判定在 nginx：`limit_except` 里的写方法用另一个文件（不含 ro- 用户），
    终端 location 直接按前缀拒 —— 于是"只读凭据进不了终端"是**服务端**保证的，不靠客户端自觉；
  * 撤销 = 删掉那一行 + 重启 rclone + reload nginx，**立即生效**；
  * 旧的通道口令（用户名 `boxops`）原样保留 —— 迁移期 App 不必改；
    审计里看 `$remote_user`：还是 `boxops` 就是在用旧口令。

用法（在边缘机 hpa888 上跑）：
  box_channel_cred.py issue --label phone-hpa --host hpa888          # 可写（文件 + 终端）
  box_channel_cred.py issue --label phone-hpa --host hpa888 --read-only
  box_channel_cred.py list
  box_channel_cred.py revoke --label phone-hpa --host hpa888
  box_channel_cred.py --selftest
"""
from __future__ import annotations

import argparse
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

CST = timezone(timedelta(hours=8))
NGINX_CONF_DIR = Path("/www/server/nginx/conf")
STATE = Path("/etc/box-ops/channel-creds.json")
LEGACY_USER = "boxops"          # 旧口令的用户名：它的那一行永远保留
SSH_KEY_175 = "/root/.ssh/id_target_175"
HOST_175 = "root@175.178.248.237"

# 每台机器一对文件：全量（nginx 校验一切）与只写（仅在 limit_except 里用）
FILES = {
    "hpa888": {
        "all": NGINX_CONF_DIR / "box-ops.htpasswd",
        "rw": NGINX_CONF_DIR / "box-ops-rw.htpasswd",
        "remote": None,
        "unit": "box-ops-dav.service",
        "restart_local": True,
    },
    "175": {
        "all": NGINX_CONF_DIR / "box-ops175.htpasswd",
        "rw": NGINX_CONF_DIR / "box-ops175-rw.htpasswd",
        # 175 的 rclone 读自己那份（内容与边缘机这边保持同步）
        "remote": "/etc/box-ops/box-ops175.htpasswd",
        "remote_rw": "/etc/box-ops/box-ops175-rw.htpasswd",
        "unit": "box-ops175-dav.service",
        "restart_local": False,
    },
}
LABEL_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{2,39}$")


def say(*a) -> None:
    print(*a, flush=True)


def now_iso() -> str:
    return datetime.now(CST).isoformat(timespec="seconds")


def sh(cmd: list[str], timeout: int = 60) -> tuple[int, str]:
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return p.returncode, (p.stdout + p.stderr).strip()


def hash_secret(secret: str) -> str:
    """bcrypt（$2b$）。nginx 与 rclone 都认；stdlib 的 crypt 在 Debian/Anolis 上都能出这个格式。"""
    import crypt  # noqa: PLC0415  （3.11 还在，3.13 才移除；这里显式导入并压住告警）
    import warnings

    with warnings.catch_warnings():
        warnings.simplefilter("ignore", DeprecationWarning)
        return crypt.crypt(secret, crypt.mksalt(crypt.METHOD_BLOWFISH))


def verify_secret(secret: str, hashed: str) -> bool:
    import crypt  # noqa: PLC0415
    import warnings

    with warnings.catch_warnings():
        warnings.simplefilter("ignore", DeprecationWarning)
        return crypt.crypt(secret, hashed) == hashed


def read_lines(path: Path) -> list[str]:
    if not path.exists():
        return []
    return [ln for ln in path.read_text().splitlines() if ln.strip()]


def write_lines(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text("\n".join(lines) + ("\n" if lines else ""))
    os.chmod(tmp, 0o644)  # nginx worker 要读得到
    tmp.replace(path)


def user_of(label: str, read_only: bool) -> str:
    return ("ro-" + label) if read_only else label


def load_state() -> dict:
    if not STATE.exists():
        return {}
    try:
        return json.loads(STATE.read_text())
    except Exception:  # noqa: BLE001
        return {}


def save_state(state: dict) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, ensure_ascii=False, indent=2))
    os.chmod(STATE, 0o600)


def sync_175(cfg: dict) -> None:
    """把 175 那一对文件推过去，并重启 175 的 rclone（它启动时读一次文件）。"""
    for src_key, dst in (("all", cfg.get("remote")), ("rw", cfg.get("remote_rw"))):
        if not dst:
            continue
        src = str(cfg[src_key])
        # 先落临时文件再 install 到位：避免 rclone 读到半截文件
        tmp_remote = f"/tmp/box-channel-{secrets.token_hex(4)}"
        sh(["scp", "-q", "-o", "BatchMode=yes", "-i", SSH_KEY_175, src, f"{HOST_175}:{tmp_remote}"])
        rc, out = sh(["ssh", "-o", "BatchMode=yes", "-i", SSH_KEY_175, HOST_175,
                      # -D：175 上 /etc/box-ops/ 可能还不存在，让 install 顺手建目录
                      f"install -D -m 644 {tmp_remote} {dst} && rm -f {tmp_remote}"])
        if rc != 0:
            raise SystemExit(f"同步到 175 失败（{src_key} → {dst}）：{out[:200]}")


def restart_channel(cfg: dict) -> None:
    if cfg.get("restart_local"):
        sh(["systemctl", "restart", cfg["unit"]])
    else:
        sh(["ssh", "-o", "BatchMode=yes", "-i", SSH_KEY_175, HOST_175,
            f"systemctl restart {cfg['unit']}"])
    sh(["nginx", "-s", "reload"])


def cmd_issue(a) -> int:
    host = a.host
    cfg = FILES[host]
    label = a.label
    if not LABEL_RE.match(label):
        say("label 只能用字母数字与 . _ -（3~40 位），且要以字母数字开头")
        return 2
    if label == LEGACY_USER or label.startswith("ro-"):
        say(f"label 不能叫 {LEGACY_USER}，也不能以 ro- 开头（ro- 是本工具给只读凭据留的前缀）")
        return 2
    state = load_state()
    if any(v.get("label") == label and v.get("host") == host for v in state.values()):
        say(f"{host} 上已经有 label={label} 的凭据；要换就先 revoke")
        return 2

    user = user_of(label, a.read_only)
    secret = secrets.token_urlsafe(32)
    line = f"{user}:{hash_secret(secret)}"

    all_lines = [ln for ln in read_lines(cfg["all"]) if not ln.startswith(user + ":")]
    all_lines.append(line)
    write_lines(cfg["all"], all_lines)

    rw_lines = read_lines(cfg["rw"])
    if not rw_lines:
        # 第一次生成：把全量文件里**非 ro-** 的行拷过去（旧口令 + 写凭据）
        rw_lines = [ln for ln in all_lines if not ln.startswith("ro-")]
    else:
        rw_lines = [ln for ln in rw_lines if not ln.startswith(user + ":")]
        if not a.read_only:
            rw_lines.append(line)
    if not any(ln.startswith(LEGACY_USER + ":") for ln in rw_lines):
        rw_lines = [ln for ln in all_lines if ln.startswith(LEGACY_USER + ":")] + rw_lines
    write_lines(cfg["rw"], rw_lines)

    state[f"{host}/{label}"] = {
        "label": label, "host": host, "user": user,
        "readOnly": bool(a.read_only), "createdAt": now_iso(),
    }
    save_state(state)

    if host == "175":
        sync_175(cfg)
    restart_channel(cfg)

    say(f"✓ {host} 上签发了{'只读' if a.read_only else '可写'}凭据 label={label}（用户名 {user}）")
    say("  把它填进 App 的「口令」那一格（文件与终端都用它）；这一行只在下面出现一次：")
    # 令牌/口令单独占最后一行（与 box-ops-api token issue 同一约定，便于脚本 tail -1）
    say(secret)
    return 0


def cmd_list(a) -> int:
    state = load_state()
    if not state:
        say("（还没有设备凭据：现在只有旧的通道口令 boxops）")
    for key, v in sorted(state.items()):
        say(f"  {v['host']:>7}  {v['user']:<28} "
            f"{'只读' if v.get('readOnly') else '可写'}  建于 {v.get('createdAt', '?')}")
    say("")
    for host, cfg in FILES.items():
        users = [ln.split(":", 1)[0] for ln in read_lines(cfg["all"])]
        say(f"  {host} 的 htpasswd 里有：{', '.join(users) or '（空）'}")
    return 0


def cmd_revoke(a) -> int:
    cfg = FILES[a.host]
    state = load_state()
    key = f"{a.host}/{a.label}"
    rec = state.get(key)
    if not rec:
        say(f"{a.host} 上没有 label={a.label} 的凭据")
        return 2
    user = rec["user"]
    for f in (cfg["all"], cfg["rw"]):
        lines = [ln for ln in read_lines(f) if not ln.startswith(user + ":")]
        write_lines(f, lines)
    state.pop(key, None)
    save_state(state)
    if a.host == "175":
        sync_175(cfg)
    restart_channel(cfg)
    say(f"✓ 已撤销 {a.host} 上的 {user}（那一行已删，rclone 已重启、nginx 已 reload）—— 旧凭据立刻失效")
    return 0


def selftest() -> int:
    ok = bad = 0

    def check(desc: str, cond: bool, extra: str = "") -> None:
        nonlocal ok, bad
        if cond:
            ok += 1
            say(f"  ✅ {desc}")
        else:
            bad += 1
            say(f"  ❌ {desc} {extra}")

    say("== 哈希 ==")
    h = hash_secret("s3cret-value")
    check("bcrypt 格式（$2b$）", h.startswith("$2b$"), h[:10])
    check("同一个口令能验过", verify_secret("s3cret-value", h))
    check("别的口令验不过", not verify_secret("s3cret-valuE", h))

    with tempfile.TemporaryDirectory(dir="/tmp") as tmp:
        tmpd = Path(tmp)
        cfg = {"all": tmpd / "box-ops.htpasswd", "rw": tmpd / "box-ops-rw.htpasswd",
               "remote": None, "remote_rw": None, "unit": "none", "restart_local": False}
        global FILES, STATE
        saved_files, saved_state = FILES, globals()["STATE"]
        FILES = {"hpa888": cfg, "175": cfg}
        globals()["STATE"] = tmpd / "state.json"
        # 旧口令那一行先放进去（模拟线上）
        write_lines(cfg["all"], [f"{LEGACY_USER}:$2b$12$legacy"])
        try:
            import contextlib
            import io

            class A:
                host, label, read_only = "hpa888", "phone-x", False
            # 自检里的"凭据"是假的，但它长得与真的无异：一律不往屏幕上打
            with contextlib.redirect_stdout(io.StringIO()):
                rc = cmd_issue(A())
            users = [ln.split(":", 1)[0] for ln in read_lines(cfg["all"])]
            check("签发成功（rc=0）", rc == 0)
            check("凭据进了 all 文件", "phone-x" in users, str(users))
            check("旧口令那一行还在", LEGACY_USER in users, str(users))
            check("可写凭据也进了 rw 文件", "phone-x" in
                  [ln.split(":", 1)[0] for ln in read_lines(cfg["rw"])])

            class B:
                host, label, read_only = "hpa888", "phone-ro", True
            with contextlib.redirect_stdout(io.StringIO()):
                cmd_issue(B())
            all_users = [ln.split(":", 1)[0] for ln in read_lines(cfg["all"])]
            rw_users = [ln.split(":", 1)[0] for ln in read_lines(cfg["rw"])]
            check("只读凭据用户名带 ro- 前缀", "ro-phone-ro" in all_users, str(all_users))
            check("只读凭据**不进** rw 文件（写方法那层认不到它）",
                  "ro-phone-ro" not in rw_users, str(rw_users))

            class C:
                host, label, read_only = "hpa888", "phone-x", False
            with contextlib.redirect_stdout(io.StringIO()):
                check("同一个 label 不能重复签", cmd_issue(C()) == 2)

            class D:
                host, label, read_only = "hpa888", "boxops", False
            with contextlib.redirect_stdout(io.StringIO()):
                check("不能占用 legacy 用户名", cmd_issue(D()) == 2)

            class E:
                host, label, read_only = "hpa888", "ro-hack", False
            with contextlib.redirect_stdout(io.StringIO()):
                check("不能自造 ro- 前缀", cmd_issue(E()) == 2)

            class F:
                host, label, read_only = "hpa888", "phone-x", False
            with contextlib.redirect_stdout(io.StringIO()):
                check("撤销返回 0", cmd_revoke(F()) == 0)
            after = [ln.split(":", 1)[0] for ln in read_lines(cfg["all"])]
            check("撤销后那一行没了", "phone-x" not in after, str(after))
            check("撤销只删自己那一行（ro-phone-ro 还在）", "ro-phone-ro" in after, str(after))
            check("撤销后 rw 文件里也没有了",
                  "phone-x" not in [ln.split(":", 1)[0] for ln in read_lines(cfg["rw"])])
            left = [v["label"] for v in load_state().values()]
            check("状态文件里只剩没被撤销的那条", left == ["phone-ro"], str(left))
        finally:
            FILES = saved_files
            globals()["STATE"] = saved_state

    say(f"\n自检：通过 {ok} / 失败 {bad}")
    return 0 if bad == 0 else 1


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="文件通道 / 终端的设备凭据（htpasswd 多用户）")
    ap.add_argument("--selftest", action="store_true")
    sub = ap.add_subparsers(dest="cmd")
    p1 = sub.add_parser("issue")
    p1.add_argument("--label", required=True)
    p1.add_argument("--host", required=True, choices=["hpa888", "175"])
    p1.add_argument("--read-only", action="store_true")
    p2 = sub.add_parser("list")
    p3 = sub.add_parser("revoke")
    p3.add_argument("--label", required=True)
    p3.add_argument("--host", required=True, choices=["hpa888", "175"])
    a = ap.parse_args(argv)

    if a.selftest:
        return selftest()
    if a.cmd == "issue":
        return cmd_issue(a)
    if a.cmd == "list":
        return cmd_list(a)
    if a.cmd == "revoke":
        return cmd_revoke(a)
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))