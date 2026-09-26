#!/usr/bin/env python3
"""在**边缘机（hpa888）**上给文件与终端装上"按设备凭据"（C1 剩余）。

要做的事（三件，缺一件这套就不成立）：
  1. nginx：`/dav/`、`/dav175/`、`/term/`、`/term175/` 都走 Basic 认证，用户来自
     `/www/server/nginx/conf/box-ops*.htpasswd`（**多用户**，一行一台设备）；
  2. 作用域：写方法在 `limit_except` 里换成**不含 ro- 用户**的另一个文件 ——
     只读凭据在服务端就写不了；终端 location 直接按 `$remote_user` 前缀拒；
  3. rclone：两个 `serve webdav` 换成 `--htpasswd`（与 nginx 同一个文件），这样
     同一套凭据在 nginx 与 rclone 两层都通；rclone 实测"两套同时给时 --htpasswd 优先"。

外加：给这四个入口单独记一份 access log（含 `$remote_user`）—— 那就是审计。

自检/回滚：备份 → 打补丁 → `nginx -t` → reload/restart → **自动跑真实验证**
（没凭据必须 401、旧口令仍要能进、只读凭据写不了也进不了终端、可写凭据能写、
撤销后立刻 401、密钥路径仍 404、审计日志里看得到用户名）→ 任何一条不过就自动回滚。

用法（在 hpa888 上）：
  apply_channel_gate.py --check        # 只看要改什么（凭据行自动脱敏）
  apply_channel_gate.py --apply        # 真改 + 自动验证（失败自动回滚）
  apply_channel_gate.py --rollback     # 恢复最近一次备份
"""
from __future__ import annotations

import argparse
import json
import re
import secrets
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

VHOST = Path("/www/server/panel/vhost/nginx/box.hpa888.top.conf")
NGINX_CONF = Path("/www/server/nginx/conf/nginx.conf")
BACKUP_DIR = Path("/root/nginx-backups")
SECRETS = Path("/root/.secrets")
SSH_KEY_175 = "/root/.ssh/id_target_175"
HOST_175 = "root@175.178.248.237"
PUBLIC = "https://box.hpa888.top"
ACCESS_LOG = "/www/wwwlogs/box-ops-access.log"
LOG_FORMAT = "boxops_gate"

# 4 个通道 location 的 auth_basic realm（升一次 = 让所有客户端重新问一次凭据）
REALM_FOR = {"hpa888": "box-ops-v2", "175": "box-ops175-v2"}

CHANNELS = {
    "hpa888": {
        "all": "/www/server/nginx/conf/box-ops.htpasswd",
        "rw": "/www/server/nginx/conf/box-ops-rw.htpasswd",
        "unit": "box-ops-dav.service",
        "unit_path": "/etc/systemd/system/box-ops-dav.service",
        "remote_all": None,
        "remote_rw": None,
        "remote_unit": None,
    },
    "175": {
        "all": "/www/server/nginx/conf/box-ops175.htpasswd",
        "rw": "/www/server/nginx/conf/box-ops175-rw.htpasswd",
        "unit": "box-ops175-dav.service",
        "unit_path": "/etc/systemd/system/box-ops175-dav.service",
        # 175 的 rclone 在它自己那台跑，读它自己那份（内容与边缘机保持一致）
        "remote_all": "/etc/box-ops/box-ops175.htpasswd",
        "remote_rw": "/etc/box-ops/box-ops175-rw.htpasswd",
        "remote_unit": "/etc/systemd/system/box-ops175-dav.service",
    },
}
LOCATIONS = {
    "/dav/": "hpa888",
    "/dav175/": "175",
    "/term/": "hpa888",
    "/term175/": "175",
}


def say(*a) -> None:
    print(*a, flush=True)


def sh(cmd: list[str], timeout: int = 90) -> tuple[int, str]:
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return p.returncode, (p.stdout + p.stderr).strip()


def sh_175(remote_cmd: str, timeout: int = 90) -> tuple[int, str]:
    return sh(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
               "-i", SSH_KEY_175, HOST_175, remote_cmd], timeout=timeout)


def read_env(path: Path, key: str) -> str:
    try:
        for line in path.read_text().splitlines():
            if line.startswith(key + "="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    except Exception:  # noqa: BLE001
        pass
    return ""


def verify_crypt(secret: str, hashed: str) -> bool:
    import crypt  # noqa: PLC0415
    import warnings

    with warnings.catch_warnings():
        warnings.simplefilter("ignore", DeprecationWarning)
        return crypt.crypt(secret, hashed) == hashed


def htpasswd_line(path: str, user: str) -> str:
    for line in Path(path).read_text().splitlines() if Path(path).exists() else []:
        if line.startswith(user + ":"):
            return line
    return ""


# ── 补丁 ────────────────────────────────────────────────────────────

def patch_vhost(text: str) -> tuple[str, list[str]]:
    if "box-ops-rw.htpasswd" in text:
        return text, ["vhost 上已经装过（配置里已有 box-ops-rw.htpasswd）"]
    notes: list[str] = []
    for prefix, host in LOCATIONS.items():
        cfg = CHANNELS[host]
        start = text.index(f"    location ^~ {prefix} {{")
        end = text.index("\n    }", start) + len("\n    }")
        block = text[start:end]
        # realm 不只是个名字：客户端（尤其 Android WebView）按 (源 + realm) 缓存 Basic 凭据，
        # 缓存命中时 App 的 onHttpAuthRequest 根本不会被调用 —— 所以"换了口令要让已装的
        # 客户端重新问一次"就靠升 realm（v1 → v2 就是这么来的，真机上遇到过终端页还在用
        # 旧口令的情况）。升了 realm 之后旧凭据仍需保留一个迁移窗口。
        realm = REALM_FOR[host]
        if prefix.startswith("/dav"):
            add = (
                f'        auth_basic "{realm}";\n'
                f"        auth_basic_user_file {cfg['all']};\n"
                "        # 只读凭据不许写：显式 403（用 limit_except 换文件会返回 401，"
                "那语义是\"凭据不对\"，\n"
                "        # 客户端会以为要重填口令；这里直接说清楚）\n"
                "        if ($boxops_ro_write) {\n"
                '            return 403 "这个凭据是只读的：能读文件，不能写\n";\n'
                "        }\n"
            )
            notes.append(f"{prefix} 加 Basic 认证 + 只读凭据写动作 403")
        else:
            add = (
                f'        auth_basic "{realm}";\n'
                f"        auth_basic_user_file {cfg['all']};\n"
                "        # 终端等价于一条 root shell：只读凭据一律拒（服务端判，不靠客户端自觉）\n"
                "        if ($boxops_ro_term) {\n"
                '            return 403 "这个凭据是只读的：能读文件，不能进终端\n";\n'
                "        }\n"
            )
            notes.append(f"{prefix} 保留 Basic 认证 + 拒绝 ro- 凭据")
        add += f"        access_log {ACCESS_LOG} {LOG_FORMAT};\n"
        # 原来可能有 auth_basic 行（终端那两个），先清掉再插，避免重复
        block = re.sub(r"\n\s*auth_basic [^\n]*", "", block)
        block = re.sub(r"\n\s*auth_basic_user_file [^\n]*", "", block)
        block = re.sub(r"\n\s*access_log [^\n]*box-ops-access[^\n]*", "", block)
        new_block = block.replace(f"    location ^~ {prefix} {{",
                                  f"    location ^~ {prefix} {{\n{add}", 1)
        text = text[:start] + new_block + text[end:]
    return text, notes


def patch_nginx_conf(text: str) -> tuple[str, list[str]]:
    if LOG_FORMAT in text and "boxops_ro_write" in text:
        return text, []
    # 这行在线上是没有缩进的（http 块里的 vhost include），别写成带缩进的版本
    maps = (
        "    # box-ops 通道：只读凭据（用户名 ro- 开头）不许用写方法，也不许进终端。\n"
        '    map "$remote_user:$request_method" $boxops_ro_write {\n'
        "        default 0;\n"
        '        "~^ro-[^:]*:(PUT|DELETE|MKCOL|COPY|MOVE|PROPPATCH|LOCK|UNLOCK|POST)$" 1;\n'
        "    }\n"
        "    map $remote_user $boxops_ro_term {\n"
        "        default 0;\n"
        '        "~^ro-" 1;\n'
        "    }\n"
    )
    anchor = "include /www/server/panel/vhost/nginx/*.conf;"
    if anchor not in text:
        raise SystemExit("在 nginx.conf 里找不到 vhost include 那一行，停手人工看一眼")
    fmt = (
        "    # box-ops 通道的审计格式：谁（$remote_user = 凭据的用户名）在什么时候动了什么\n"
        f"    log_format {LOG_FORMAT} '$remote_addr - $remote_user [$time_local] \"$request\" '\n"
        "                             '$status $body_bytes_sent \"$http_user_agent\"';\n"
    )
    return (text.replace(anchor, maps + fmt + "\n" + anchor, 1),
            [f"nginx.conf 加 log_format {LOG_FORMAT}", "nginx.conf 加两个 map（只读凭据的写/终端闸门）"])


def unit_argv(unit: str) -> list[str]:
    _rc, out = sh(["systemctl", "show", "-p", "ExecStart", "--value", unit])
    m = re.search(r"argv\[\]=(.*?)\s*;", out, re.S)
    if not m:
        raise SystemExit(f"读不到 {unit} 的 ExecStart：{out[:200]}")
    return m.group(1).split()


def patch_unit_text(text: str, htpasswd: str) -> tuple[str, str]:
    """把 ExecStart 换成带 --htpasswd 的版本。返回（新内容, 说明）。

    坑：线上的 ExecStart 是**多行续行**（6 行、17 条 --exclude）。只匹配第一行再重写，
    会把续行整段丢掉 —— 那不但把 C4 的排除名单弄没，还会让 systemd 解析失败、rclone 起不来。
    所以这里按"上一行以 \ 结尾就继续吃"把整段读完，再合成一行。
    """
    lines = text.splitlines(keepends=True)
    start = next((i for i, ln in enumerate(lines) if ln.startswith("ExecStart=")), None)
    if start is None:
        raise SystemExit("unit 里找不到 ExecStart")
    end = start
    while lines[end].rstrip("\n").endswith("\\"):
        end += 1
    joined = "".join(lines[start:end + 1])
    joined = joined.replace("\\\n", " ").replace("\n", " ")
    argv = joined.replace("ExecStart=", "", 1).split()
    if "--htpasswd" in argv:
        return text, "unit 上已经有 --htpasswd"
    before_excludes = argv.count("--exclude")
    argv = argv + ["--htpasswd", htpasswd]
    new_line = "ExecStart=" + " ".join(argv) + "\n"
    out = "".join(lines[:start]) + new_line + "".join(lines[end + 1:])
    # 护栏：排除名单一个字都不许少（这是 C4 收口的命根子）
    if new_line.count("--exclude") != before_excludes:
        raise SystemExit("重写 ExecStart 时 --exclude 数量变了，停手")
    return out, (f"ExecStart 加 --htpasswd {htpasswd}"
                 f"（保留 {before_excludes} 条 --exclude，续行合成一行）")


def apply_unit(host: str, do_write: bool) -> list[str]:
    """改某一台的 rclone 单元（含 175 要 ssh 过去改）。do_write=False 时只报告。"""
    cfg = CHANNELS[host]
    notes: list[str] = []
    if host == "hpa888":
        p = Path(cfg["unit_path"])
        text = p.read_text()
        new, note = patch_unit_text(text, cfg["all"])
        notes.append(f"hpa888 {cfg['unit']}: {note}")
        if do_write and new != text:
            Path(f"{p}.bak").write_text(text)
            p.write_text(new)
            sh(["systemctl", "daemon-reload"])
            sh(["systemctl", "restart", cfg["unit"]])
    else:
        rc, text = sh_175(f"cat {cfg['remote_unit']}")
        if rc != 0:
            raise SystemExit(f"读不到 175 的单元：{text[:200]}")
        new, note = patch_unit_text(text, cfg["remote_all"])
        notes.append(f"175 {cfg['unit']}: {note}")
        if do_write and new != text:
            rc, out = sh_175(f"cp {cfg['remote_unit']} {cfg['remote_unit']}.bak")
            sh_175(f"cat > {cfg['remote_unit']} <<'UNITEOF'\n{new}\nUNITEOF")
            sh_175("systemctl daemon-reload")
            rc, out = sh_175(f"systemctl restart {cfg['unit']}")
    return notes


# ── 验证 ────────────────────────────────────────────────────────────

def curl_code(url: str, user: str | None = None, pw: str | None = None,
              method: str = "GET", headers: list[str] | None = None) -> str:
    cmd = ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "-m", "25",
           "-H", "Connection: close", "-X", method]
    if user is not None:
        cmd += ["-u", f"{user}:{pw}"]
    for h in headers or []:
        cmd += ["-H", h]
    cmd.append(url)
    rc, out = sh(cmd, timeout=45)
    return out.strip()[-3:] if out else f"ERR{rc}"


def issue_temp(host: str, label: str, read_only: bool) -> tuple[str, str]:
    """返回（htpasswd 用户名, 口令）。用户名就是 label（只读带 ro- 前缀）。"""
    cmd = (f"python3 /root/box-channel-cred.py issue --label {label} "
           f"--host {host}{' --read-only' if read_only else ''}")
    rc, out = sh(["bash", "-lc", cmd])
    tok = ""
    for line in out.splitlines():
        line = line.strip()
        if line and " " not in line and len(line) >= 30:
            tok = line
    if not tok:
        raise SystemExit(f"签 {host} 的 {label} 失败：{out[:300]}")
    return (("ro-" + label) if read_only else label), tok


def wait_ready(url: str, user: str, pw: str, method: str = "GET",
               tries: int = 12, gap: float = 1.5) -> str:
    """反复试到拿到 2xx/207 为止（重启后 rclone/隧道要一点时间才就绪）。"""
    c = ""
    for _ in range(tries):
        c = curl_code(url, user, pw, method, ["Depth: 0"] if method == "PROPFIND" else None)
        if c in ("200", "201", "204", "207"):
            return c
        time.sleep(gap)
    return c


def verify() -> list[str]:
    fails: list[str] = []

    def check(desc: str, ok: bool, extra: str = "") -> None:
        say(f"  {'✅' if ok else '❌'} {desc}" + (f"  {extra}" if extra and not ok else ""))
        if not ok:
            fails.append(desc)

    # 旧口令的明文在退休时已清理（/root/.secrets/*-rclone.env 删掉了）——
    # 读不到不是失败，只说明"旧口令那组检查没得可查"，后面的检查照跑。
    pw_hpa = read_env(SECRETS / "box-ops-rclone.env", "RCLONE_PASS")
    rc, out175 = sh_175("grep '^RCLONE_PASS=' /root/.secrets/box-ops175-rclone.env")
    pw_175 = out175.split("=", 1)[1].strip() if "=" in out175 else ""
    if not pw_hpa or not pw_175:
        say("  · 旧口令明文已清理（退休后正常）：跳过「旧口令仍能进」这组检查")

    stamp = str(int(time.time()))
    # label 不能重（同一台同一 label 只能有一条），可写/只读分开命名
    made: list[tuple[str, str]] = []
    def new_cred(host: str, name: str, read_only: bool) -> str:
        made.append((host, name))
        return issue_temp(host, name, read_only)

    rw_user, rw = new_cred("hpa888", f"gate-rw-{stamp}", False)
    ro_user, ro = new_cred("hpa888", f"gate-ro-{stamp}", True)
    rw175_user, rw175 = new_cred("175", f"gate-rw-{stamp}", False)
    ro175_user, ro175 = new_cred("175", f"gate-ro-{stamp}", True)
    say(f"（测试凭据的用户名：{rw_user} / {ro_user} / {rw175_user} / {ro175_user}）")

    say("== 1) 门是活的：没凭据必须 401（不许裸奔）==")
    for path in LOCATIONS:
        c = curl_code(PUBLIC + path)
        check(f"{path} 没凭据 → 401", c == "401", f"拿到 {c}")

    # 旧口令已经退休时（htpasswd 里没有 boxops 那一行），这一节改成断言它进不来 ——
    # 否则这个脚本在退休之后每次重跑都会"预检/验证不过"而自动回滚。
    legacy_alive = bool(htpasswd_line(CHANNELS["hpa888"]["all"], "boxops"))
    if not legacy_alive:
        say("== 2) 旧口令已退休：断言它进不来（401）==")
        for path, method, user, pw in (("/dav/", "PROPFIND", "boxops", pw_hpa),
                                       ("/dav175/", "PROPFIND", "boxops", pw_175),
                                       ("/term/", "GET", "boxops", pw_hpa),
                                       ("/term175/", "GET", "boxops", pw_175)):
            c = curl_code(PUBLIC + path, user, pw, method,
                          ["Depth: 0"] if method == "PROPFIND" else None)
            check(f"{path} 旧口令 → 401（已退休）", c == "401", f"拿到 {c}")
    else:
        say("== 2) 旧口令仍然能进（迁移期不能把 App 弄断）==")
        c = wait_ready(PUBLIC + "/dav/", "boxops", pw_hpa, "PROPFIND")
        check("/dav/ 旧口令列目录 → 207", c == "207", f"拿到 {c}")
        c = wait_ready(PUBLIC + "/dav175/", "boxops", pw_175, "PROPFIND")
        check("/dav175/ 旧口令列目录 → 207", c == "207", f"拿到 {c}")
        c = wait_ready(PUBLIC + "/term/", "boxops", pw_hpa)
        check("/term/ 旧口令 → 2xx", c.startswith("2"), f"拿到 {c}")
        c = wait_ready(PUBLIC + "/term175/", "boxops", pw_175)
        check("/term175/ 旧口令 → 2xx", c.startswith("2"), f"拿到 {c}")

    say("== 3) 可写凭据：能写能进终端 ==")
    c = wait_ready(PUBLIC + "/dav/", rw_user, rw, "PROPFIND")
    check("/dav/ 可写凭据列目录 → 207", c == "207", f"拿到 {c}")
    tmp_url = PUBLIC + "/dav/tmp/box-gate-probe.txt"
    c = curl_code(tmp_url, rw_user, rw, "PUT", ["Content-Type: text/plain"])
    check("/dav/ 可写凭据上传 → 201", c in ("201", "204"), f"拿到 {c}")
    c = curl_code(tmp_url, rw_user, rw, "DELETE")
    check("/dav/ 可写凭据删除 → 204", c == "204", f"拿到 {c}")
    c = wait_ready(PUBLIC + "/term/", rw_user, rw)
    check("/term/ 可写凭据进终端 → 2xx", c.startswith("2"), f"拿到 {c}")
    c = wait_ready(PUBLIC + "/dav175/", rw175_user, rw175, "PROPFIND")
    check("/dav175/ 可写凭据列目录 → 207", c == "207", f"拿到 {c}")
    c = wait_ready(PUBLIC + "/term175/", rw175_user, rw175)
    check("/term175/ 可写凭据进终端 → 2xx", c.startswith("2"), f"拿到 {c}")

    say("== 4) 只读凭据：读得到、写不了、进不了终端 ==")
    c = wait_ready(PUBLIC + "/dav/", ro_user, ro, "PROPFIND")
    check("/dav/ 只读凭据列目录 → 207", c == "207", f"拿到 {c}")
    for method, extra in (("PUT", ["Content-Type: text/plain"]), ("DELETE", []),
                          ("MKCOL", []), ("COPY", ["Destination: /tmp/x"])):
        c = curl_code(PUBLIC + "/dav/tmp/box-gate-probe.txt", ro_user, ro, method, extra)
        check(f"/dav/ 只读凭据 {method} → 403", c == "403", f"拿到 {c}")
    c = curl_code(PUBLIC + "/term/", ro_user, ro)
    check("/term/ 只读凭据进终端 → 403", c == "403", f"拿到 {c}")
    c = curl_code(PUBLIC + "/dav175/tmp/box-gate-probe.txt", ro175_user, ro175, "PUT",
                  ["Content-Type: text/plain"])
    check("/dav175/ 只读凭据写 → 403", c == "403", f"拿到 {c}")
    c = curl_code(PUBLIC + "/term175/", ro175_user, ro175)
    check("/term175/ 只读凭据进终端 → 403", c == "403", f"拿到 {c}")

    say("== 5) 撤销立刻生效 + 审计里有用户名 + 密钥路径仍 404 ==")
    sh(["bash", "-lc", "python3 /root/box-channel-cred.py revoke --label "
        f"gate-rw-{stamp} --host hpa888 && python3 /root/box-channel-cred.py revoke "
        f"--label gate-ro-{stamp} --host hpa888"])
    c = curl_code(PUBLIC + "/dav/", rw_user, rw, "PROPFIND", ["Depth: 0"])
    check("/dav/ 撤销后的凭据 → 401", c == "401", f"拿到 {c}")
    c = curl_code(PUBLIC + "/term/", rw_user, rw)
    check("/term/ 撤销后的凭据 → 401", c == "401", f"拿到 {c}")
    sh(["bash", "-lc", "python3 /root/box-channel-cred.py revoke --label "
        f"gate-rw-{stamp} --host 175 && python3 /root/box-channel-cred.py revoke "
        f"--label gate-ro-{stamp} --host 175"])
    c = curl_code(PUBLIC + "/dav175/", rw175_user, rw175, "PROPFIND", ["Depth: 0"])
    check("/dav175/ 撤销后的凭据 → 401", c == "401", f"拿到 {c}")
    # 无论上面哪一步炸，发出去的测试凭据都要收回来（失败路径最容易漏）
    for host, name in made:
        sh(["bash", "-lc", f"python3 /root/box-channel-cred.py revoke --label {name} --host {host}"])

    rc, log = sh(["bash", "-lc", f"tail -200 {ACCESS_LOG} 2>/dev/null"])
    check("审计日志里能看到用户名（新凭据的用户名出现在里面）",
          rw_user in log or ro_user in log, (log[-300:] if log else "（日志是空的）"))
    c = curl_code(PUBLIC + "/dav/root/.secrets/box-update-server.env", rw_user, rw)
    check("/dav/ 密钥路径仍 404", c == "404", f"拿到 {c}")
    c = curl_code(PUBLIC + "/dav175/etc/shadow", rw175_user, rw175)
    check("/dav175/ /etc/shadow 仍 404", c == "404", f"拿到 {c}")
    return fails


# ── 主流程 ──────────────────────────────────────────────────────────

def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--rollback", action="store_true")
    a = ap.parse_args(argv)

    if a.rollback:
        b = sorted(BACKUP_DIR.glob("gate-*"))
        if not b:
            say("没有备份")
            return 1
        d = b[-1]
        say(f"从 {d} 恢复")
        shutil.copy2(d / "box.hpa888.top.conf", VHOST)
        shutil.copy2(d / "nginx.conf", NGINX_CONF)
        for host, cfg in CHANNELS.items():
            bak = d / f"{cfg['unit']}.bak"
            if not bak.exists():
                continue
            if host == "hpa888":
                shutil.copy2(bak, cfg["unit_path"])
            else:
                sh(["scp", "-q", "-o", "BatchMode=yes", "-i", SSH_KEY_175, str(bak),
                    f"{HOST_175}:{cfg['remote_unit']}"])
            say(f"  {host} 的 {cfg['unit']} 已还原")
        rc, out = sh(["nginx", "-t"])
        say(f"nginx -t → {'OK' if rc == 0 else out}")
        if rc == 0:
            sh(["nginx", "-s", "reload"])
        sh(["systemctl", "daemon-reload"])
        sh(["systemctl", "restart", CHANNELS["hpa888"]["unit"]])
        sh_175(f"systemctl daemon-reload && systemctl restart {CHANNELS['175']['unit']}")
        return rc

    # 前置校验：htpasswd 里 boxops 那条必须真的是当前通道口令，
    # 否则切到 --htpasswd 之后**旧口令会失效**（App 的文件通道当场断）
    pre: list[str] = []
    for host, cfg in CHANNELS.items():
        if host == "hpa888":
            pw = ""  # 退休后读不到（下面按"有没有 boxops 那一行"决定要不要用）
        if not htpasswd_line(cfg["all"], "boxops"):
            # 退休之后再跑这个脚本是正常操作：没有那一行就不做"旧口令仍能进"的检查
            pre.append(f"{host}: 旧通道口令已退休（htpasswd 里没有 boxops）—— 跳过旧口令检查 ✅")
            continue
        # 旧口令那一行还在：这时必须能读到当前口令，否则这个预检没法做
        if host == "hpa888":
            pw = read_env(SECRETS / "box-ops-rclone.env", "RCLONE_PASS")
        else:
            _rc, out = sh_175("grep '^RCLONE_PASS=' /root/.secrets/box-ops175-rclone.env")
            pw = out.split("=", 1)[1].strip() if "=" in out else ""
        if not pw:
            pre.append(f"{host}: ⚠ htpasswd 里还有 boxops，但读不到旧口令明文 —— 跳过一致性预检")
            continue
        c = curl_code(PUBLIC + path, "boxops", pw)
        if not c.startswith("2"):
            say(f"✗ {host}: 用当前通道口令打 {path} 拿到 {c}（不是 2xx）—— "
                f"htpasswd 里的 boxops 条目与当前口令不一致，先对齐再装前门")
            return 1
        pre.append(f"{host}: 旧口令在 nginx 这层能过 ✅（htpasswd 与口令一致）")

    vhost_text = VHOST.read_text()
    conf_text = NGINX_CONF.read_text()
    new_vhost, notes1 = patch_vhost(vhost_text)
    new_conf, notes2 = patch_nginx_conf(conf_text)
    notes3 = apply_unit("hpa888", do_write=False) + apply_unit("175", do_write=False)
    for n in pre + notes1 + notes2 + notes3:
        say("  · " + n)

    if a.check:
        say("\n=== vhost diff（只看前 80 行）===")
        import difflib
        for line in list(difflib.unified_diff(vhost_text.splitlines(), new_vhost.splitlines(),
                                              "vhost(现在)", "vhost(改后)", lineterm=""))[:80]:
            say(line)
        return 0

    if not a.apply:
        say("要么 --check 要么 --apply")
        return 2

    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    d = BACKUP_DIR / f"gate-{ts}"
    d.mkdir(parents=True, exist_ok=True)
    shutil.copy2(VHOST, d / "box.hpa888.top.conf")
    shutil.copy2(NGINX_CONF, d / "nginx.conf")
    shutil.copy2(CHANNELS["hpa888"]["unit_path"], d / f"{CHANNELS['hpa888']['unit']}.bak")
    sh_175(f"cp {CHANNELS['175']['remote_unit']} {CHANNELS['175']['remote_unit']}.bak")
    say(f"已备份到 {d}")

    NGINX_CONF.write_text(new_conf)
    VHOST.write_text(new_vhost)
    rc, out = sh(["nginx", "-t"])
    if rc != 0:
        say("nginx -t 失败 → 回滚\n" + out)
        shutil.copy2(d / "box.hpa888.top.conf", VHOST)
        shutil.copy2(d / "nginx.conf", NGINX_CONF)
        return 1
    sh(["nginx", "-s", "reload"])
    say("nginx reload 完成；开始装 rclone 的 --htpasswd")
    apply_unit("hpa888", do_write=True)
    apply_unit("175", do_write=True)
    time.sleep(3)

    say("\n=== 真实验证 ===")
    try:
        fails = verify()
    except SystemExit as e:
        fails = [f"验证脚本自身出错：{e}"]

    if fails:
        say("\n=== 有项没过 → 自动回滚 ===")
        for f in fails:
            say("  ✗ " + f)
        shutil.copy2(d / "box.hpa888.top.conf", VHOST)
        shutil.copy2(d / "nginx.conf", NGINX_CONF)
        # rclone 也要退回原样：配置文件里还有一个 .bak（由 apply_unit 落的）
        shutil.copy2(d / f"{CHANNELS['hpa888']['unit']}.bak", CHANNELS["hpa888"]["unit_path"])
        sh(["systemctl", "daemon-reload"])
        sh(["systemctl", "restart", CHANNELS["hpa888"]["unit"]])
        sh_175(f"cp {CHANNELS['175']['remote_unit']}.bak {CHANNELS['175']['remote_unit']} && "
               f"systemctl daemon-reload && systemctl restart {CHANNELS['175']['unit']}")
        rc2, out2 = sh(["nginx", "-t"])
        if rc2 == 0:
            sh(["nginx", "-s", "reload"])
        say(f"回滚完成（nginx -t {'OK' if rc2 == 0 else out2}）；线上恢复为改动前的样子")
        return 1
    say("\n=== 全部通过 ✅ 文件与终端现在按设备凭据（可撤销、有作用域、有审计）===")
    say("（旧口令："
        + ("仍然有效（审计里用户名还是 boxops 说明那台设备还没换）" if legacy_alive
           else "已退休（用它一律 401）")
        + "）")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
