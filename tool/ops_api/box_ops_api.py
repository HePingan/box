#!/usr/bin/env python3
"""box-ops 只读运维 API（C2 只读档 / C1 根治档的载体）。

为什么有它：WebDAV 拿不到 unix 权限/属主，也拿不到进程、服务、日志、端口、目录占用 ——
宝塔式管理里真正好用的那半，靠文件通道做不到。而它同时是**凭据模型根治档**的载体：
App 不再拿"等同 root 的通道口令"去访问一个万能接口，而是拿**可撤销的设备令牌**访问
一组**白名单只读动作**，每次调用都进审计。

设计约束（每一条都对应一个真实风险）：
  * **两级动作、两个作用域**：只读动作（进程/服务/日志/端口/…）与**写动作**
    （服务启停/建目录/改权限/改属主/解压）。写动作要求令牌带 `write` 作用域 ——
    手机上那把默认只有读+admin，想写就得显式签发 `--write`（撤销写权限不必连读一起收回）；
  * **写动作有"自杀黑名单"**：停 sshd、停本服务、停隧道/NetworkManager、禁用 systemd 自身
    这些动作直接拒绝 —— 从手机上做这些等于把自己锁在门外（尤其本服务：停了它，
    App 就再也没法把它启回来）；
  * **没有 shell**：所有命令都是固定 argv 模板 + 校验过的参数，绝不拼字符串；
  * **白名单优先**：单位名走正则 + 必须在 systemctl 里真实存在；日志/目录走前缀白名单，
    并显式拒绝 .. 与密钥类路径（/root/.secrets、/root/.ssh、/root/.hermes 等）；
  * **有上限**：行数 ≤ 500、进程数 ≤ 200、超时 ≤ 15 秒、响应 ≤ 256 KB；
  * **全量审计**：每次调用一行 JSONL（动作/参数/令牌标签/来源 IP/状态/耗时），可读回；
  * **令牌可撤销**：文件里只存 sha256 哈希，比较用 hmac.compare_digest。

用法（在目标机上）：
    box_ops_api.py serve [--port 8095]                 起服务（systemd 会用这个）
    box_ops_api.py token issue --label phone-an [--admin]
    box_ops_api.py token list
    box_ops_api.py token revoke --label phone-an
    box_ops_api.py selftest                            自检（起临时实例打一圈，含拒绝路径）
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.parse
from datetime import datetime, timezone, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

VERSION = "1.0.0"
CST = timezone(timedelta(hours=8))

SECRETS_DIR = Path(os.environ.get("BOX_OPS_SECRETS", "/root/.secrets"))
TOKENS_FILE = Path(os.environ.get("BOX_OPS_TOKENS", str(SECRETS_DIR / "box-ops-api-tokens.json")))
AUDIT_FILE = Path(os.environ.get("BOX_OPS_AUDIT", "/var/log/box-ops-api/audit.jsonl"))
AUDIT_MAX_BYTES = 5 * 1024 * 1024

# 上限（每一条都是为了"接口被误用/滥用时别把机器拖死"）
MAX_LINES = 500
MAX_PROCS = 200
MAX_SERVICES = 400
CMD_TIMEOUT = 15
MAX_RESPONSE = 256 * 1024

# 通道访问日志（边缘机 nginx 给 4 个通道 location 写的，log_format=boxops_gate）
# 形状：<ip> - <user> [<time>] "<METHOD> <PATH> <PROTO>" <status> <bytes> "<ua>"
CHANNEL_LOG = "/www/wwwlogs/box-ops-access.log"
CHANNEL_HTPASSWD = ("/www/server/nginx/conf/box-ops.htpasswd",
                    "/www/server/nginx/conf/box-ops175.htpasswd")
CHANNEL_ENTRIES = {"dav": "hpa888 文件", "dav175": "175 文件",
                   "term": "hpa888 终端", "term175": "175 终端"}
CHANNEL_LOG_MAX_BYTES = 4 * 1024 * 1024
CHANNEL_WINDOW_MAX_DAYS = 30
CHANNEL_OWNER_HOST = "hpa888"

# 日志清单（logfiles）的上限：只列两层、最多这么多条 —— 只是给界面选文件用
LOG_LIST_MAX = 200
LOG_LIST_DEFAULT = 60
LOG_LIST_DEPTH = 2

# 日志白名单前缀：只允许读这些目录下的**文件**（不允许目录、不允许 ..
LOG_ROOTS = ("/var/log", "/www/wwwlogs", "/home/update-server/logs")

# 目录占用白名单前缀（du 只对这些根生效；密钥类路径另行拒绝）
DISK_ROOTS = ("/",)
DISK_DENY = ("/root/.secrets", "/root/.ssh", "/root/.hermes", "/proc", "/sys", "/dev")

UNIT_RE = re.compile(r"^[A-Za-z0-9@._:+-]{1,128}$")
MODE_RE = re.compile(r"^[0-7]{3,4}$")

# 写动作**一律拒绝**的路径前缀（口令/密钥/审计/本服务自身）。
# 用 resolve() 之后的真实路径比对，防止"用软链接绕过去"。
WRITE_DENY_PREFIXES = (
    "/proc", "/sys", "/dev", "/boot",
    "/root/.secrets", "/root/.ssh", "/root/.hermes",
    "/var/log/box-ops-api",
    "/usr/local/sbin/box-ops-api.py",
    "/etc/systemd/system/box-ops-api.service",
    "/etc/systemd/system/box-ops175-tunnel.service",
)

# 停/禁用这些单元 = 把自己锁在门外（从手机上尤其明显）。
# start/restart/reload 不拦（那是在救人），只拦 stop/disable。
SELF_DESTRUCTIVE_UNITS = (
    "sshd.service", "ssh.service",
    "box-ops-api.service", "box-ops175-tunnel.service",
    "systemd-logind.service", "systemd-journald.service", "systemd-udevd.service",
    "dbus.service", "dbus-broker.service",
    "network.service", "networking.service", "NetworkManager.service",
)

# 解压上限：拒绝膨胀炸弹/巨包（真在手机上解一个 5G 的包也不是场景）
EXTRACT_MAX_TOTAL = 2 * 1024 * 1024 * 1024
EXTRACT_TIMEOUT = 180
ARCHIVE_SUFFIXES = (".zip", ".tar", ".tar.gz", ".tgz", ".tar.bz2", ".tbz2",
                    ".tar.xz", ".txz", ".gz")

# 打包：上限与超时。不是"手机上传一个 8G 包"的场景，是"把日志/站点目录收成一个包"。
COMPRESS_MAX_INPUT_MB = 4096
COMPRESS_TIMEOUT = 300
COMPRESS_FREE_RESERVE_MB = 256      # 目标分区至少还要留这么多空闲

# 清理动作（都是"公认可以清"的三类，配额与保留期写死在这里，不接受客户端指定）
CLEANUP_MODES = ("journal", "tmp", "apt")
CLEANUP_JOURNAL_KEEP_MB = 200       # journal 只清到剩这么多
CLEANUP_TMP_DAYS = 7                # /tmp 只删 7 天没动过的**普通文件**


def now_iso() -> str:
    return datetime.now(CST).isoformat(timespec="seconds")


def _log(msg: str) -> None:
    print(f"[{now_iso()}] {msg}", flush=True)


# ── 令牌 ────────────────────────────────────────────────────────────────

def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def load_tokens() -> list[dict]:
    if not TOKENS_FILE.exists():
        return []
    try:
        doc = json.loads(TOKENS_FILE.read_text(encoding="utf-8"))
        return list(doc.get("tokens", []))
    except Exception as e:  # noqa: BLE001 - 文件坏了要能看出来，而不是静默放行
        _log(f"[error] 令牌文件读不出来：{e}")
        return []


def save_tokens(tokens: list[dict]) -> None:
    SECRETS_DIR.mkdir(parents=True, exist_ok=True)
    tmp = TOKENS_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps({"tokens": tokens}, ensure_ascii=False, indent=2), encoding="utf-8")
    os.chmod(tmp, 0o600)
    os.replace(tmp, TOKENS_FILE)


def issue_token(label: str, admin: bool = False, write: bool = False) -> str:
    raw = base64.urlsafe_b64encode(os.urandom(32)).decode().rstrip("=")
    tokens = [t for t in load_tokens() if t.get("label") != label]
    tokens.append({
        "label": label,
        "hash": _token_hash(raw),
        "admin": bool(admin),
        # 写作用域是**单独一个开关**：这样"收回写权限"不必连读一起收回。
        "write": bool(write),
        "createdAt": now_iso(),
    })
    save_tokens(tokens)
    return raw


def revoke_token(label: str) -> bool:
    tokens = load_tokens()
    kept = [t for t in tokens if t.get("label") != label]
    if len(kept) == len(tokens):
        return False
    save_tokens(kept)
    return True


def match_token(raw: str) -> dict | None:
    """常量时间比较；返回命中的令牌条目（含 label/admin）。"""
    if not raw:
        return None
    h = _token_hash(raw)
    for t in load_tokens():
        if hmac.compare_digest(str(t.get("hash", "")), h):
            return t
    return None


# ── 审计 ────────────────────────────────────────────────────────────────

_audit_lock = threading.Lock()


def audit(action: str, params: dict, label: str, ip: str, status: int, ms: int, note: str = "") -> None:
    rec = {
        "at": now_iso(),
        "action": action,
        "params": params,
        "token": label,
        "ip": ip,
        "status": status,
        "ms": ms,
    }
    if note:
        rec["note"] = note
    try:
        with _audit_lock:
            AUDIT_FILE.parent.mkdir(parents=True, exist_ok=True)
            if AUDIT_FILE.exists() and AUDIT_FILE.stat().st_size > AUDIT_MAX_BYTES:
                AUDIT_FILE.replace(AUDIT_FILE.with_suffix(".jsonl.1"))
            with AUDIT_FILE.open("a", encoding="utf-8") as f:
                f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except Exception as e:  # noqa: BLE001 - 审计写不进去不该让请求失败，但必须留痕
        _log(f"[error] 审计写入失败：{e}")


def read_audit(limit: int) -> list[dict]:
    if not AUDIT_FILE.exists():
        return []
    lines: list[str] = []
    with AUDIT_FILE.open("r", encoding="utf-8", errors="replace") as f:
        for line in f:
            lines.append(line)
    out = []
    for line in reversed(lines[-limit:]):
        try:
            out.append(json.loads(line))
        except Exception:  # noqa: BLE001
            continue
    return out


# ── 命令执行（固定 argv，无 shell）──────────────────────────────────────

def run(args: list[str], timeout: int = CMD_TIMEOUT,
        cwd: str | None = None) -> tuple[int, str, str]:
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout,
                           cwd=cwd)
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        return 124, "", f"超时（{timeout}s）"
    except FileNotFoundError:
        return 127, "", f"命令不存在：{args[0]}"


def cap(text: str, limit: int = MAX_RESPONSE) -> tuple[str, bool]:
    if len(text) <= limit:
        return text, False
    return text[:limit], True


# ── 动作实现（全部只读）──────────────────────────────────────────────────

def os_release() -> dict:
    info = {}
    try:
        for line in Path("/etc/os-release").read_text(encoding="utf-8").splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                info[k.lower()] = v.strip().strip('"')
    except Exception:  # noqa: BLE001
        pass
    return {"pretty": info.get("pretty_name", "?"), "kernel": os.uname().release}


def _meminfo() -> dict:
    want = {"MemTotal": 0, "MemAvailable": 0, "SwapTotal": 0, "SwapFree": 0, "Buffers": 0, "Cached": 0}
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            k, _, rest = line.partition(":")
            if k in want:
                want[k] = int(rest.strip().split()[0]) * 1024
    except Exception:  # noqa: BLE001
        pass
    total = want["MemTotal"] or 1
    used = want["MemTotal"] - want["MemAvailable"]
    st = want["SwapTotal"]
    return {
        "memTotal": want["MemTotal"],
        "memUsed": used,
        "memUsedPercent": round(used * 100.0 / total, 1),
        "swapTotal": st,
        "swapUsed": st - want["SwapFree"],
        "swapUsedPercent": round((st - want["SwapFree"]) * 100.0 / st, 1) if st else 0.0,
    }


def _cpu_busy_percent(sample_gap: float = 0.25) -> float | None:
    """主机 CPU 使用率：/proc/stat 取两次，算 busy 占比。

    为什么不用 load：load 只说明"排队长度"，一台 4 核机器 load 2.0 可能 CPU 很闲
    （都在等 IO），也可能很忙 —— 告警必须看**占用率**，load 只能当辅证。
    采样的 0.25 秒是刻意的：太短会被瞬时抖动带跑，太长就把这次只读请求拖慢了。
    """
    def snap() -> tuple[int, int]:
        fields = Path("/proc/stat").read_text().splitlines()[0].split()[1:]
        nums = [int(x) for x in fields]
        idle = nums[3] + (nums[4] if len(nums) > 4 else 0)  # idle + iowait
        return sum(nums), idle

    try:
        total1, idle1 = snap()
        time.sleep(sample_gap)
        total2, idle2 = snap()
        dt, di = total2 - total1, idle2 - idle1
        if dt <= 0:
            return None
        return round(max(0.0, min(100.0, (dt - di) * 100.0 / dt)), 1)
    except Exception:  # noqa: BLE001
        return None


def act_overview(_q: dict, _label: str) -> tuple[int, dict]:
    up = float(Path("/proc/uptime").read_text().split()[0])
    load = Path("/proc/loadavg").read_text().split()[:3]
    cpu_model, cores = "?", os.cpu_count() or 1
    try:
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("model name"):
                cpu_model = line.split(":", 1)[1].strip()
                break
    except Exception:  # noqa: BLE001
        pass

    disks = []
    seen: set[str] = set()
    try:
        code, out, _ = run(["df", "-P", "-h"])
        if code == 0:
            for line in out.splitlines()[1:]:
                cols = line.split()
                if len(cols) < 6 or cols[0] in seen:
                    continue
                if not cols[0].startswith("/dev/"):
                    continue
                seen.add(cols[0])
                disks.append({"mount": " ".join(cols[5:]), "size": cols[1],
                              "used": cols[2], "avail": cols[3], "usePercent": cols[4]})
    except Exception:  # noqa: BLE001
        pass
    busy = _cpu_busy_percent()
    return 0, {
        "os": os_release(),
        "hostname": socket.gethostname(),
        "uptimeSeconds": int(up),
        "load": {"load1": float(load[0]), "load5": float(load[1]), "load15": float(load[2])},
        "cpu": {"model": cpu_model, "cores": cores, "usedPercent": busy},
        "memory": _meminfo(),
        "disks": disks,
        "generatedAt": now_iso(),
    }


def act_processes(q: dict, _label: str) -> tuple[int, dict]:
    sort = (q.get("sort") or ["cpu"])[0]
    limit = min(int((q.get("limit") or ["20"])[0]), MAX_PROCS)
    key = {"cpu": "-pcpu", "mem": "-pmem", "rss": "-rss"}.get(sort, "-pcpu")
    code, out, err = run(["ps", "-eo", "pid,user:20,pcpu,pmem,rss,etime,comm:24,args",
                          "--sort=" + key, "--no-headers"])
    if code != 0:
        return 502, {"error": f"ps 失败：{err.strip()}"}
    procs = []
    for line in (out or "").splitlines()[:limit]:
        cols = line.split(None, 7)
        if len(cols) < 8:
            continue
        procs.append({
            "pid": int(cols[0]) if cols[0].isdigit() else 0,
            "user": cols[1],
            "cpuPercent": float(cols[2]),
            "memPercent": float(cols[3]),
            "rssKb": int(cols[4]) if cols[4].isdigit() else 0,
            "elapsed": cols[5],
            "name": cols[6],
            "args": cols[7][:300],
        })
    return 0, {"sort": sort, "count": len(procs), "processes": procs, "generatedAt": now_iso()}


def _unit_files() -> dict[str, str]:
    """unit → enabled 状态（一次取全，避免逐个 is-enabled 拖慢）。"""
    code, out, _ = run(["systemctl", "list-unit-files", "--type=service",
                        "--no-legend", "--no-pager", "--plain"])
    res: dict[str, str] = {}
    if code == 0:
        for line in out.splitlines():
            cols = line.split()
            if len(cols) >= 2 and cols[0].endswith(".service"):
                res[cols[0]] = cols[1]
    return res


def act_services(q: dict, _label: str) -> tuple[int, dict]:
    limit = min(int((q.get("limit") or [str(MAX_SERVICES)])[0]), MAX_SERVICES)
    needle = (q.get("q") or [""])[0].lower()
    code, out, err = run(["systemctl", "list-units", "--type=service", "--all",
                          "--no-legend", "--no-pager", "--plain"])
    if code != 0:
        return 502, {"error": f"systemctl 失败：{err.strip()}"}
    enabled = _unit_files()
    items = []
    for line in out.splitlines():
        cols = line.split(None, 4)
        if len(cols) < 4 or not cols[0].endswith(".service"):
            continue
        unit, load, active, sub = cols[0], cols[1], cols[2], cols[3]
        desc = (cols[4] if len(cols) > 4 else "").strip()
        if needle and needle not in unit.lower() and needle not in desc.lower():
            continue
        items.append({"unit": unit, "active": active, "sub": sub,
                      "enabled": enabled.get(unit, "?"), "description": desc})
        if len(items) >= limit:
            break
    interesting = [i for i in items if i["active"] in ("active", "failed")]
    return 0, {"count": len(items), "units": items, "interesting": interesting[:60],
               "generatedAt": now_iso()}


def _valid_unit(unit: str) -> bool:
    return bool(UNIT_RE.match(unit)) and unit.endswith(".service")


def act_service(q: dict, _label: str) -> tuple[int, dict]:
    unit = (q.get("unit") or [""])[0]
    lines = min(int((q.get("lines") or ["20"])[0]), MAX_LINES)
    if not _valid_unit(unit):
        return 400, {"error": "unit 不合法（要形如 xxx.service 且只含字母数字 @._:+-）"}
    code, out, err = run(["systemctl", "show", unit, "-p",
                          "ActiveState,SubState,UnitFileState,ExecMainStartTimestamp,MainPID,MemoryCurrent,NRestarts"])
    if code != 0:
        return 404, {"error": f"查不到这个服务：{err.strip()}"}
    props = {}
    for line in (out or "").splitlines():
        k, _, v = line.partition("=")
        props[k] = v
    if not props.get("ActiveState"):
        return 404, {"error": f"没有这个服务：{unit}"}
    jcode, jout, jerr = run(["journalctl", "-u", unit, "-n", str(lines), "--no-pager", "-o", "short-iso"])
    return 0, {
        "unit": unit,
        "activeState": props.get("ActiveState"),
        "subState": props.get("SubState"),
        "unitFileState": props.get("UnitFileState"),
        "mainPid": props.get("MainPID"),
        "memoryBytes": int(props["MemoryCurrent"]) if props.get("MemoryCurrent", "").isdigit() else None,
        "restarts": props.get("NRestarts"),
        "since": props.get("ExecMainStartTimestamp"),
        "journal": (jout or jerr).strip() if jcode == 0 else f"journalctl 失败：{jerr.strip()}",
        "generatedAt": now_iso(),
    }


def _safe_log_path(raw: str) -> Path | None:
    if not raw or ".." in raw:
        return None
    p = Path(raw)
    if not p.is_absolute():
        return None
    if not any(str(p).startswith(root + "/") for root in LOG_ROOTS):
        return None
    try:
        p = p.resolve()
    except Exception:  # noqa: BLE001
        return None
    # resolve 之后必须**再查一次前缀**：白名单目录里的一条符号链接
    # （例如 /var/log/box-x -> /etc/shadow）能在这一步把白名单整个绕过去。
    if not any(str(p).startswith(root + "/") for root in LOG_ROOTS):
        return None
    if not p.is_file():
        return None
    return p


def _tail(path: Path, lines: int) -> str:
    """从文件尾部读 N 行（不整文件载入：日志可能几个 G）。"""
    with path.open("rb") as f:
        f.seek(0, os.SEEK_END)
        size = f.tell()
        block = 8192
        data = b""
        while size > 0 and data.count(b"\n") <= lines:
            step = min(block, size)
            size -= step
            f.seek(size)
            data = f.read(step) + data
            block = min(block * 2, 1024 * 1024)
    return data.decode("utf-8", errors="replace")


def act_logs(q: dict, _label: str) -> tuple[int, dict]:
    raw = (q.get("path") or [""])[0]
    lines = min(int((q.get("lines") or ["100"])[0]), MAX_LINES)
    p = _safe_log_path(raw)
    if p is None:
        return 403, {"error": f"路径不在白名单内或不存在：{raw}（只允许 {'、'.join(LOG_ROOTS)} 下的文件）"}
    text = _tail(p, lines)
    tail = text.splitlines()[-lines:]
    body, cut = cap("\n".join(tail))
    return 0, {"path": str(p), "lines": len(tail), "truncated": cut,
               "content": body, "generatedAt": now_iso()}


_CHANNEL_LINE = re.compile(
    r'^(?P<ip>\S+) \S+ (?P<user>\S+) \[(?P<time>[^\]]+)\] '
    r'"(?P<method>\S+) (?P<path>\S+)[^"]*" (?P<status>\d{3}) ')


def _channel_log_tail() -> str:
    """读通道访问日志的尾部（按字节，不整个读进来 —— 它可能有几百 MB）。"""
    p = Path(CHANNEL_LOG)
    if not p.is_file():
        return ""
    try:
        size = p.stat().st_size
        with p.open("r", errors="replace") as f:
            if size > CHANNEL_LOG_MAX_BYTES:
                f.seek(size - CHANNEL_LOG_MAX_BYTES)
                f.readline()  # 丢掉被截断的半行
            return f.read()
    except OSError:
        return ""


def _channel_known_users() -> tuple[set[str], bool]:
    """htpasswd 里的用户名（**只要用户名**，哈希一个字节都不往外带）。"""
    users: set[str] = set()
    readable = False
    for path in CHANNEL_HTPASSWD:
        p = Path(path)
        if not p.is_file():
            continue
        try:
            text = p.read_text(errors="replace")
            readable = True
        except OSError:
            continue
        for line in text.splitlines():
            line = line.strip()
            if line and not line.startswith("#") and ":" in line:
                users.add(line.split(":", 1)[0])
    return users, readable


def act_channel(q: dict, _label: str) -> tuple[int, dict]:
    """文件/终端通道**凭据使用情况**汇总（最近 N 天）。

    回答的是："现在还有谁在用通道口令，用的是哪一条，最近什么时候、从哪个 IP"。
    这也是"旧口令什么时候能退休"的唯一依据 —— 没有它，只能靠人 ssh 上去 awk。

    硬约束（和 A9/C2 一致）：
      * **不返回 URI**：只到"入口 + 方法 + 状态码"，不记用户在翻哪个目录/文件；
      * **不返回任何哈希/口令**：htpasswd 只取用户名，用来判断这条凭据还算不算数；
      * 只读动作，进审计。
    """
    try:
        days = int((q.get("days") or ["7"])[0])
    except ValueError:
        return 400, {"error": "days 必须是整数"}
    if days < 1 or days > CHANNEL_WINDOW_MAX_DAYS:
        return 400, {"error": f"days 只能取 1~{CHANNEL_WINDOW_MAX_DAYS}"}

    text = _channel_log_tail()
    if not text:
        return 0, {"available": False, "logPath": CHANNEL_LOG,
                   "reason": "这台机器上没有通道访问日志（它由边缘机写）",
                   "hint": f"换到 {CHANNEL_OWNER_HOST} 那条看", "windowDays": days,
                   "generatedAt": now_iso()}

    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    users: dict[str, dict] = {}
    scanned = 0
    matched = 0
    skipped_old = 0
    for line in text.splitlines():
        scanned += 1
        m = _CHANNEL_LINE.match(line)
        if not m:
            continue
        try:
            when = datetime.strptime(m.group("time"), "%d/%b/%Y:%H:%M:%S %z")
        except ValueError:
            continue
        if when < cutoff:
            skipped_old += 1
            continue
        # 入口 = 路径的第一段（/dav175/... → dav175）；不在白名单里的行直接跳过
        seg = m.group("path").split("/")[1] if "/" in m.group("path") else ""
        if seg not in CHANNEL_ENTRIES:
            continue
        matched += 1
        user = m.group("user") if m.group("user") != "-" else "(未认证)"
        status = int(m.group("status"))
        u = users.setdefault(user, {
            "user": user, "count": 0, "lastSeenTs": 0.0, "lastSeen": "",
            "lastIp": "", "entries": {}, "methods": {}, "denied": 0,
        })
        u["count"] += 1
        u["entries"][CHANNEL_ENTRIES[seg]] = u["entries"].get(CHANNEL_ENTRIES[seg], 0) + 1
        u["methods"][m.group("method")] = u["methods"].get(m.group("method"), 0) + 1
        if status == 401 or status == 403:
            u["denied"] += 1
        ts = when.timestamp()
        if ts > u["lastSeenTs"]:
            u["lastSeenTs"] = ts
            u["lastSeen"] = _iso_local(ts)
            u["lastIp"] = m.group("ip")

    known, htpasswd_readable = _channel_known_users()
    for u in users.values():
        u["stillValid"] = u["user"] in known
        u["readOnly"] = u["user"].startswith("ro-")
        u.pop("lastSeenTs", None)
    rows = sorted(users.values(), key=lambda x: x["count"], reverse=True)
    used = set(users)
    return 0, {
        "available": True,
        "logPath": CHANNEL_LOG,
        "ownerHost": CHANNEL_OWNER_HOST,
        "windowDays": days,
        "scannedLines": scanned,
        "matchedLines": matched,
        "htpasswdReadable": htpasswd_readable,
        "users": rows,
        # 签了但窗口内没用过的凭据（可能是发出去忘了收，也可能是新签的还没填进 App）
        "unused": sorted(known - used),
        "generatedAt": now_iso(),
    }


def _iso_local(ts: float) -> str:
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S")


def act_logfiles(q: dict, _label: str) -> tuple[int, dict]:
    """列出白名单里**有哪些日志文件**（名字/大小/最后修改），按最近改动排前面。

    为什么需要它：`logs` 是按路径读尾部，但客户端得先知道"有哪些文件可读"——
    以前这一步只能靠人在终端里 ls。这里只走白名单根下的两层目录（/var/log 与
    /var/log/nginx 这种），不做全盘递归；符号链接一律不看（和 `logs` 同一口径）。
    """
    try:
        limit = min(int((q.get("limit") or [str(LOG_LIST_DEFAULT)])[0]), LOG_LIST_MAX)
    except ValueError:
        return 400, {"error": "limit 必须是整数"}
    if limit <= 0:
        return 400, {"error": "limit 必须大于 0"}
    want = (q.get("root") or [""])[0]
    if want and want not in LOG_ROOTS:
        return 403, {"error": f"root 只能取 {'、'.join(LOG_ROOTS)} 之一"}

    found = []
    for root in ([want] if want else list(LOG_ROOTS)):
        rp = Path(root)
        if not rp.is_dir():
            continue
        stack = [(rp, 1)]
        while stack:
            d, depth = stack.pop()
            try:
                children = sorted(d.iterdir())
            except OSError:
                continue
            for c in children:
                try:
                    if c.is_symlink():
                        continue
                    if c.is_dir():
                        if depth < LOG_LIST_DEPTH:
                            stack.append((c, depth + 1))
                        continue
                    if not c.is_file():
                        continue
                    st = c.stat()
                except OSError:
                    continue
                found.append({"path": str(c), "name": c.name, "root": root,
                              "size": st.st_size, "mtimeTs": st.st_mtime})
    total = len(found)
    found.sort(key=lambda x: x["mtimeTs"], reverse=True)
    items = [{"path": x["path"], "name": x["name"], "root": x["root"],
              "size": x["size"], "mtime": _iso_local(x["mtimeTs"])}
             for x in found[:limit]]
    return 0, {"count": len(items), "total": total, "roots": list(LOG_ROOTS),
               "list": items, "generatedAt": now_iso()}


def act_ports(_q: dict, _label: str) -> tuple[int, dict]:
    code, out, err = run(["ss", "-ltnp"])
    if code != 0:
        return 502, {"error": f"ss 失败：{err.strip()}"}
    items = []
    for line in (out or "").splitlines()[1:]:
        cols = line.split(None, 5)
        if len(cols) < 4:
            continue
        local = cols[3]
        proc = ""
        if len(cols) > 5:
            m = re.search(r'users:\(\("([^"]+)"', cols[5])
            proc = m.group(1) if m else cols[5][:120]
        items.append({"proto": cols[0], "state": cols[1], "local": local, "process": proc})
    return 0, {"count": len(items), "listeners": items, "generatedAt": now_iso()}


def act_diskusage(q: dict, _label: str) -> tuple[int, dict]:
    raw = (q.get("path") or ["/var/log"])[0]
    if not raw or ".." in raw:
        return 400, {"error": "路径不合法"}
    p = Path(raw)
    if not p.is_absolute() or not p.is_dir():
        return 400, {"error": f"不是目录：{raw}"}
    for deny in DISK_DENY:
        if str(p) == deny or str(p).startswith(deny + "/"):
            return 403, {"error": f"这个路径被拒绝：{deny}"}
    code, out, err = run(["du", "-x", "--max-depth=1", "-h", str(p)], timeout=20)
    if code != 0 and not out:
        return 502, {"error": f"du 失败：{err.strip()}"}
    rows = []
    for line in (out or "").splitlines():
        parts = line.split("\t", 1)
        if len(parts) == 2:
            rows.append({"size": parts[0], "path": parts[1]})
    rows.sort(key=lambda r: r["path"])
    return 0, {"path": str(p), "count": len(rows), "rows": rows[:200], "generatedAt": now_iso()}


def act_sessions(_q: dict, _label: str) -> tuple[int, dict]:
    def parse(cmd: list[str]) -> list[dict]:
        code, out, _ = run(cmd)
        res = []
        if code != 0:
            return res
        for line in out.splitlines():
            if not line.strip() or "wtmp begins" in line or "btmp begins" in line:
                continue
            cols = line.split(None, 9)
            if len(cols) < 4:
                continue
            res.append({"user": cols[0], "tty": cols[1],
                        "from": cols[2] if len(cols) > 2 else "",
                        "at": " ".join(cols[3:7]) if len(cols) >= 7 else line[:60],
                        "extra": cols[7] if len(cols) > 7 else ""})
        return res[:12]
    return 0, {"logins": parse(["last", "-n", "12"]),
               "failedLogins": parse(["lastb", "-n", "12"]),
               "note": "lastb 需要 root 且机器装过 wtmp/btmp；空表示没有记录",
               "generatedAt": now_iso()}


def act_audit(q: dict, _label: str) -> tuple[int, dict]:
    limit = min(int((q.get("limit") or ["50"])[0]), 500)
    return 0, {"count": len(read_audit(limit)), "items": read_audit(limit), "generatedAt": now_iso()}


ACTIONS = {
    "health": lambda q, l: (0, {"ok": True, "version": VERSION, "time": now_iso()}),
    # capabilities 是"读元数据"，GET 就能问（客户端据此决定写按钮显不显示）
    "capabilities": lambda q, l: act_capabilities(q, l),
    "overview": act_overview,
    "processes": act_processes,
    "services": act_services,
    "service": act_service,
    "logs": act_logs,
    "logfiles": act_logfiles,
    "channel": act_channel,
    "ports": act_ports,
    "diskusage": act_diskusage,
    "sessions": act_sessions,
    "audit": act_audit,
}

# 需要 admin 令牌的动作（读审计等跨设备可见的数据）
ADMIN_ACTIONS = {"audit"}


# ── HTTP 层 ─────────────────────────────────────────────────────────────

_RATE: dict[str, list[float]] = {}
_RATE_LOCK = threading.Lock()
RATE_WINDOW = 10.0
RATE_MAX = 60


def rate_ok(key: str) -> bool:
    now = time.time()
    with _RATE_LOCK:
        hits = [t for t in _RATE.get(key, []) if now - t < RATE_WINDOW]
        hits.append(now)
        _RATE[key] = hits
        if len(_RATE) > 500:  # 防止键无限增长
            for k in list(_RATE)[:250]:
                _RATE.pop(k, None)
        return len(hits) <= RATE_MAX


class Handler(BaseHTTPRequestHandler):
    server_version = f"box-ops-api/{VERSION}"
    protocol_version = "HTTP/1.1"
    baseurl = ""          # 由 serve 设置（如 /opsapi），用于剥离前缀
    verbose = True

    # 默认实现会把每个请求打到 stderr，journald 里够用了
    def log_message(self, fmt: str, *args) -> None:  # noqa: A003
        if self.verbose:
            _log(f"{self.address_string()} {fmt % args}")

    def _json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Ops-Version", VERSION)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _action_and_query(self) -> tuple[str, dict]:
        parsed = urllib.parse.urlsplit(self.path)
        path = parsed.path
        if self.baseurl and path.startswith(self.baseurl):
            path = path[len(self.baseurl):]
        path = path.strip("/")
        action = path.split("/")[0] if path else "health"
        return action, urllib.parse.parse_qs(parsed.query)

    def _token_raw(self) -> str:
        auth = self.headers.get("Authorization", "")
        if auth.lower().startswith("bearer "):
            return auth[7:].strip()
        return (self.headers.get("X-Ops-Token") or "").strip()

    def do_GET(self) -> None:  # noqa: N802
        started = time.time()
        action, query = self._action_and_query()
        raw = self._token_raw()
        entry = match_token(raw)
        label = entry.get("label", "-") if entry else "-"
        ip = self.client_address[0]

        if entry is None:
            # 没令牌/令牌不对：也进审计（否则"谁在试"没痕迹）
            audit(action, {"path": self.path[:200]}, label, ip, 401, 0, "令牌无效或缺失")
            self._json(401, {"error": "令牌无效或缺失"})
            return
        if not rate_ok(label or ip):
            audit(action, {"path": self.path[:200]}, label, ip, 429, 0, "限流")
            self._json(429, {"error": "请求太频繁（10 秒内 60 次上限）"})
            return
        if action in ADMIN_ACTIONS and not entry.get("admin"):
            audit(action, {}, label, ip, 403, int((time.time() - started) * 1000), "需要 admin 令牌")
            self._json(403, {"error": f"{action} 需要 admin 令牌"})
            return
        fn = ACTIONS.get(action)
        if fn is None:
            audit(action, {}, label, ip, 404, 0, "未知动作")
            self._json(404, {"error": f"未知动作：{action}",
                             "actions": sorted(ACTIONS)})
            return
        try:
            status, payload = fn(query, label)
        except WriteError as e:
            status, payload = e.status, {"error": e.message}
        except Exception as e:  # noqa: BLE001 - 单个动作炸了不该带走进程
            status, payload = 500, {"error": f"{type(e).__name__}: {e}"}
        ms = int((time.time() - started) * 1000)
        audit(action, {k: v[:1] for k, v in query.items()}, label, ip, status if status else 200, ms)
        self._json(status if status else 200, payload)


    MAX_BODY = 8192

    def do_POST(self) -> None:  # noqa: N802
        started = time.time()
        action, _query = self._action_and_query()
        entry = match_token(self._token_raw())
        ip = self.client_address[0]
        label = entry.get("label", "-") if entry else "-"

        if entry is None:
            audit(action, {}, label, ip, 401, 0, "令牌无效或缺失（写请求）")
            self._json(401, {"error": "令牌无效或缺失"})
            return
        if not rate_ok(label or ip):
            audit(action, {}, label, ip, 429, 0, "限流")
            self._json(429, {"error": "请求太频繁（10 秒内 60 次上限）"})
            return

        length = int(self.headers.get("Content-Length") or 0)
        if length > self.MAX_BODY:
            audit(action, {}, label, ip, 413, 0, f"body 太大（{length}）")
            self._json(413, {"error": f"请求体太大（上限 {self.MAX_BODY} 字节）"})
            return
        raw_body = self.rfile.read(length) if length else b""
        try:
            payload = json.loads(raw_body.decode("utf-8") or "{}")
        except Exception:  # noqa: BLE001
            audit(action, {}, label, ip, 400, 0, "JSON 解析失败")
            self._json(400, {"error": "请求体不是合法 JSON"})
            return
        if not isinstance(payload, dict):
            audit(action, {}, label, ip, 400, 0, "JSON 不是对象")
            self._json(400, {"error": "请求体要是 JSON 对象"})
            return

        fn = WRITE_ACTIONS.get(action)
        if fn is None:
            fn = ACTIONS.get(action)
            is_write = False
        else:
            is_write = action != "capabilities"
        if fn is None:
            audit(action, {}, label, ip, 404, 0, "未知动作")
            self._json(404, {"error": f"未知动作：{action}",
                             "readActions": sorted(ACTIONS),
                             "writeActions": sorted(WRITE_ACTIONS)})
            return
        # **写动作要 write 作用域**：手机上那把默认只读+admin，想写要显式签发 --write。
        if is_write and not entry.get("write"):
            audit(action, {"_denied": ["write 作用域"]}, label, ip, 403,
                  int((time.time() - started) * 1000), "令牌没有 write 作用域")
            self._json(403, {"error": "这个令牌没有写权限（要 write 作用域）："
                                      "服务端用 box-ops-api.py token issue --label <名字> --write 重新签发"})
            return

        params = {
            k: [("true" if v is True else "false" if v is False else str(v))]
            for k, v in payload.items()
        }
        try:
            status, out = fn(params, label)
        except WriteError as e:
            status, out = e.status, {"error": e.message}
        except Exception as e:  # noqa: BLE001
            status, out = 500, {"error": f"{type(e).__name__}: {e}"}
        ms = int((time.time() - started) * 1000)
        audit(action, params, label, ip, status or 200, ms, "写动作" if is_write else "")
        self._json(status or 200, out)


def make_server(port: int, baseurl: str = "", verbose: bool = True) -> ThreadingHTTPServer:
    Handler.baseurl = baseurl.rstrip("/")
    Handler.verbose = verbose
    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)  # 只绑回环：外网入口由边缘机 nginx 代理
    srv.daemon_threads = True
    return srv


# ── CLI ─────────────────────────────────────────────────────────────────

def main(argv: list[str]) -> int:
    cmd = argv[1] if len(argv) > 1 else "serve"
    if cmd == "serve":
        port = 8095
        baseurl = ""
        for i, a in enumerate(argv):
            if a == "--port" and i + 1 < len(argv):
                port = int(argv[i + 1])
            if a == "--baseurl" and i + 1 < len(argv):
                baseurl = argv[i + 1]
        _log(f"监听 127.0.0.1:{port}（baseurl={baseurl or '/'}），令牌文件 {TOKENS_FILE}，"
             f"审计 {AUDIT_FILE}，动作 {len(ACTIONS)} 个")
        make_server(port, baseurl).serve_forever()
        return 0

    if cmd == "token":
        sub = argv[2] if len(argv) > 2 else "list"
        if sub == "issue":
            label = ""
            admin = False
            write = False
            for i, a in enumerate(argv):
                if a == "--label" and i + 1 < len(argv):
                    label = argv[i + 1]
                if a == "--admin":
                    admin = True
                if a == "--write":
                    write = True
            if not label:
                print("用法：box_ops_api.py token issue --label <名字> [--admin] [--write]")
                return 2
            raw = issue_token(label, admin, write)
            # 令牌必须是**最后一行**：部署脚本 tail -1 取它。
            # 第一版把说明与令牌打成一行（取到 116 字节的整行 → 401），
            # 第二版把说明放到令牌后面（tail -1 取到说明 → 两台令牌哈希还一样了）。
            print(f"已签发：label={label} admin={admin} write={write}")
            print("（只显示这一次，请立刻存进 App / 口令管理器）")
            print(raw)
            return 0
        if sub == "list":
            for t in load_tokens():
                print(f"  {t.get('label'):<24} admin={str(t.get('admin')):<5} "
                      f"write={str(bool(t.get('write'))):<5} 建于 {t.get('createdAt')}")
            return 0
        if sub == "revoke":
            # 与 issue 一样**按 --label 取值**：第一版写成 argv[3] 位置参数，于是
            # `token revoke --label x` 把字面量 "--label" 当成了名字 —— 命令"成功"返回，
            # 令牌其实没被撤（真机上实测到的：撤销后照样 200）。
            label = ""
            for i, a in enumerate(argv):
                if a == "--label" and i + 1 < len(argv):
                    label = argv[i + 1]
            if not label and len(argv) > 3 and not argv[3].startswith("--"):
                label = argv[3]
            if not label:
                print("用法：box_ops_api.py token revoke --label <名字>")
                return 2
            print("已撤销" if revoke_token(label) else "没有这个 label")
            return 0
        print(f"未知子命令：{sub}")
        return 2

    if cmd == "selftest":
        return selftest()

    print(__doc__)
    return 2


def selftest() -> int:
    """起一个临时实例打一圈：正常动作 + 各类拒绝 + 审计留痕。不碰线上文件。"""
    import tempfile
    import urllib.error
    import urllib.request
    import zipfile

    global TOKENS_FILE, AUDIT_FILE, LOG_ROOTS, CHANNEL_LOG, CHANNEL_HTPASSWD
    # 显式用 /tmp：TMPDIR 可能指向 /root/.hermes（那是被 du 拒绝的密钥类路径），
    # 用默认值会让自检自己撞上 denylist（第一次就是这么"红"的）。
    tmp = Path(tempfile.mkdtemp(prefix="box-ops-api-selftest-", dir="/tmp"))
    TOKENS_FILE = tmp / "tokens.json"
    AUDIT_FILE = tmp / "audit.jsonl"
    LOG_ROOTS = (str(tmp),)

    (tmp / "sample.log").write_text("第一行\n" * 3 + "最后一行\n", encoding="utf-8")
    tok = issue_token("selftest", admin=False)
    admin_tok = issue_token("selftest-admin", admin=True)

    port = _free_port()
    srv = make_server(port, "", verbose=False)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{port}"

    def call(path: str, token: str | None, payload: dict | None = None) -> tuple[int, dict]:
        data = None if payload is None else json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            base + path, data=data, method="GET" if payload is None else "POST"
        )
        if payload is not None:
            req.add_header("Content-Type", "application/json")
        if token:
            req.add_header("Authorization", "Bearer " + token)
        try:
            with urllib.request.urlopen(req, timeout=25) as r:
                return r.status, json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            try:
                return e.code, json.loads(e.read().decode())
            except Exception:  # noqa: BLE001
                return e.code, {}

    fails: list[str] = []

    def check(name: str, cond: bool, extra: str = "") -> None:
        print(("  ✅ " if cond else "  ❌ ") + name + (f"  {extra}" if extra and not cond else ""))
        if not cond:
            fails.append(name)

    print("== 正常路径 ==")
    st, d = call("/health", tok)
    check("health 200 且带版本", st == 200 and d.get("version"))
    st, d = call("/overview", tok)
    check("overview 带内存/磁盘/负载", st == 200 and "memory" in d and "disks" in d and "load" in d)
    # CPU 使用率（告警的取数口）：必须有、且在 0~100 之间 —— 采不到要回 null，绝不回 0 冒充"很闲"。
    cpu = d.get("cpu", {})
    check(
        "overview 带 CPU 使用率（0~100）",
        isinstance(cpu.get("usedPercent"), (int, float))
        and 0 <= cpu["usedPercent"] <= 100,
        f"cpu={cpu}",
    )
    st, d = call("/processes?sort=mem&limit=5", tok)
    check("processes 限条数生效", st == 200 and len(d.get("processes", [])) <= 5 and d.get("count", 9) <= 5)
    st, d = call("/services?limit=10", tok)
    check("services 有 unit/active/enabled", st == 200 and all("unit" in u for u in d.get("units", [])))
    st, d = call("/ports", tok)
    check("ports 至少有一条监听", st == 200 and d.get("count", 0) >= 1)
    st, d = call(f"/logs?path={tmp}/sample.log&lines=2", tok)
    check("logs 只回最后 2 行", st == 200 and d.get("lines") == 2 and "最后一行" in d.get("content", ""))
    st, d = call("/logfiles", tok)
    check("logfiles 列出白名单里的文件（含刚建的 sample.log）",
          st == 200 and any(i["name"] == "sample.log" for i in d.get("list", [])),
          f"count={d.get('count')} total={d.get('total')}")
    check("logfiles 每条都带 size/mtime 且路径真实存在",
          all(isinstance(i.get("size"), int) and i.get("mtime") and os.path.isfile(i["path"])
              for i in d.get("list", [])))
    check("logfiles 的 total ≥ count（被 limit 截过也说得清）",
          d.get("total", 0) >= d.get("count", 0))
    st, d2 = call("/logfiles?limit=1", tok)
    check("logfiles 的 limit 生效", st == 200 and len(d2.get("list", [])) == 1)
    st, _ = call("/logfiles?root=/etc", tok)
    check("logfiles 里 root 只能取白名单", st == 403)

    # ── 通道凭据使用情况（channel）──
    # 时间戳按"现在"现算：写死日期的话，过几天这条用例会因为超出窗口而假失败。
    def _ts(**kw):
        return (datetime.now(timezone.utc) - timedelta(**kw)).strftime("%d/%b/%Y:%H:%M:%S %z")

    clog = tmp / "channel-access.log"
    clog.write_text("\n".join([
        f'9.9.9.9 - phone-x [{_ts(minutes=3)}] "PROPFIND /dav/root/secret-thing.txt HTTP/1.1" 207 51 "Dart/3.12"',
        f'9.9.9.9 - phone-x [{_ts(minutes=5)}] "GET /dav/root/secret-thing.txt HTTP/1.1" 200 10 "Dart/3.12"',
        f'8.8.8.8 - boxops [{_ts(minutes=10)}] "GET /term/ HTTP/1.1" 200 500 "Mozilla"',
        f'7.7.7.7 - ro-ro [{_ts(minutes=20)}] "PUT /dav175/tmp/x.txt HTTP/1.1" 403 52 "Python-urllib/3.11"',
        f'1.1.1.1 - gone-user [{_ts(hours=2)}] "GET /dav/ HTTP/1.1" 200 1 "x"',
        f'2.2.2.2 - - [{_ts(minutes=8)}] "GET /dav/ HTTP/1.1" 401 0 "curl"',
        f'3.3.3.3 - phone-x [{_ts(days=20)}] "GET /dav/ HTTP/1.1" 200 1 "x"',
        f'4.4.4.4 - phone-x [{_ts(minutes=6)}] "GET /not-an-entry/x HTTP/1.1" 200 1 "x"',
    ]) + "\n")
    chp = tmp / "box-ops.htpasswd"
    chp.write_text("phone-x:$apr1$abc$hashhashhash\nro-ro:$2y$05$bcrypthash\n"
                   "unused-one:$apr1$zzz$hashhash\n")
    CHANNEL_LOG, CHANNEL_HTPASSWD = str(clog), (str(chp),)
    st, d = call("/channel?days=7", tok)
    by = {u["user"]: u for u in d.get("users", [])}
    check("channel 汇总出四类用户", st == 200 and d.get("available") is True
          and {"phone-x", "boxops", "ro-ro", "gone-user", "(未认证)"} <= set(by),
          f"st={st} users={sorted(by)}")
    check("channel 计数正确（phone-x 2 次，含窗口外那条不算）",
          by.get("phone-x", {}).get("count") == 2, f"count={by.get('phone-x', {}).get('count')}")
    check("channel 认出入口（dav175 那条进的是 175 文件）",
          "175 文件" in by.get("ro-ro", {}).get("entries", {}))
    check("channel 记了拒绝次数（ro-ro 的 PUT 403）",
          by.get("ro-ro", {}).get("denied") == 1)
    check("channel 标了 stillValid（htpasswd 里有 = true，没有 = false）",
          by.get("phone-x", {}).get("stillValid") is True
          and by.get("gone-user", {}).get("stillValid") is False)
    check("channel 标了 readOnly（ro- 前缀）", by.get("ro-ro", {}).get("readOnly") is True)
    check("channel 列出'签了但没用过'的凭据", d.get("unused") == ["unused-one"], str(d.get("unused")))
    check("channel 的最后时间/IP 只取窗口内最新的那条",
          by.get("phone-x", {}).get("lastIp") == "9.9.9.9" and bool(by.get("phone-x", {}).get("lastSeen")))
    body = json.dumps(d, ensure_ascii=False)
    check("channel **不带 URI**（只到入口+方法）", "secret-thing" not in body and "/dav/root" not in body)
    check("channel **不带任何哈希/口令**", "apr1" not in body and "bcrypt" not in body and "$2y$" not in body)
    st, _ = call("/channel?days=0", tok)
    check("channel 的 days 越界 → 400", st == 400)
    st, _ = call("/channel?days=99", tok)
    check("channel 的 days 上限 → 400", st == 400)
    CHANNEL_LOG = str(tmp / "no-such-log")
    st, d = call("/channel", tok)
    check("channel 在看不到通道日志的机器上给 available=false + 说明",
          st == 200 and d.get("available") is False and "hpa888" in d.get("hint", ""))
    CHANNEL_LOG = str(clog)
    st, d = call("/diskusage?path=" + str(tmp), tok)
    check("diskusage 正常", st == 200 and bool(d.get("rows")),
          f"st={st} body={str(d)[:150]}")
    st, d = call("/sessions", tok)
    check("sessions 结构在位", st == 200 and "logins" in d and "failedLogins" in d)

    print("== 拒绝路径 ==")
    st, _ = call("/overview", None)
    check("无令牌 401", st == 401)
    st, _ = call("/overview", "not-a-real-token")
    check("错令牌 401", st == 401)
    st, _ = call("/logs?path=/etc/shadow", tok)
    check("白名单外日志 403", st == 403)
    # 符号链接绕过：白名单目录里放一条指向 /etc/shadow 的链接，必须照样 403
    link = Path(tmp) / "escape.log"
    try:
        if link.exists() or link.is_symlink():
            link.unlink()
        link.symlink_to("/etc/shadow")
    except OSError:
        pass
    st, _ = call(f"/logs?path={link}", tok)
    check("白名单目录里的符号链接**不算白名单**（403）", st == 403, f"拿到 {st}")
    st, d = call("/logfiles", tok)
    check("logfiles 也不列符号链接",
          st == 200 and not any(i["name"] == "escape.log" for i in d.get("list", [])))
    st, _ = call(f"/logs?path={tmp}/../etc/passwd", tok)
    check("带 .. 的路径 403", st == 403)
    st, _ = call("/diskusage?path=/root/.secrets", tok)
    check("密钥目录 du 403", st == 403)
    st, _ = call("/service?unit=../../etc/passwd", tok)
    check("非法 unit 400", st == 400)
    st, _ = call("/audit?limit=5", tok)
    check("普通令牌读审计 403", st == 403)
    st, d = call("/audit?limit=5", admin_tok)
    check("admin 令牌读审计 200 且有记录", st == 200 and d.get("count", 0) >= 5)
    st, _ = call("/rm-rf", tok)
    check("未知动作 404", st == 404)

    print("== 写档：作用域闸门 ==")
    write_tok = issue_token("selftest-write", admin=False, write=True)
    st, d = call("/capabilities", tok)
    check("capabilities：只读令牌 write=false、admin=false",
          st == 200 and d.get("write") is False and d.get("admin") is False, str(d)[:120])
    st, d = call("/capabilities", write_tok)
    check("capabilities：写令牌 write=true 且列出写动作",
          st == 200 and d.get("write") is True and "extract" in (d.get("writeActions") or []))
    st, d = call("/mkdir", tok, {"path": str(tmp / "nope")})
    check("只读令牌调写动作 → 403（并提示要 --write 重签）",
          st == 403 and "write" in d.get("error", ""))

    print("== 写档：路径保护 ==")
    st, d = call("/chmod", write_tok, {"path": "/root/.secrets", "mode": "700"})
    check("受保护路径（/root/.secrets）→ 403", st == 403)
    st, d = call("/chmod", write_tok, {"path": str(tmp / ".." / "etc"), "mode": "700"})
    check("路径里带 .. → 400", st == 400)
    st, d = call("/chmod", write_tok, {"path": str(tmp), "mode": "000"})
    check("权限设成 000 → 400（那是把自己锁在外面）", st == 400)
    st, d = call("/chmod", write_tok, {"path": str(tmp), "mode": "abc"})
    check("非法权限写法 → 400", st == 400)
    st, d = call("/chown", write_tok, {"path": str(tmp), "owner": "没有这个用户"})
    check("不存在的用户 → 400", st == 400)

    print("== 写档：正常路径 ==")
    target = tmp / "made-by-api"
    st, d = call("/mkdir", write_tok, {"path": str(target)})
    check("mkdir 建成（权限 755）",
          st == 200 and target.is_dir() and oct(target.stat().st_mode & 0o777) == "0o755", str(d)[:120])
    st, d = call("/mkdir", write_tok, {"path": str(target)})
    check("重复 mkdir → 400", st == 400)
    st, d = call("/chmod", write_tok, {"path": str(target), "mode": "700"})
    check("chmod 成 700", st == 200 and oct(target.stat().st_mode & 0o777) == "0o700", str(d)[:120])

    print("== 写档：解压（含 zip 穿越）==")
    good = tmp / "good.zip"
    with zipfile.ZipFile(good, "w") as zf:
        zf.writestr("a.txt", "hello")
        zf.writestr("sub/b.txt", "world")
    st, d = call("/extract", write_tok, {"path": str(good), "dest": str(tmp)})
    check("正常 zip 解压出 2 个条目",
          st == 200 and d.get("count") == 2 and (tmp / "sub" / "b.txt").is_file(), str(d)[:160])
    bad = tmp / "evil.zip"
    with zipfile.ZipFile(bad, "w") as zf:
        zf.writestr("../escaped.txt", "bad")
    st, d = call("/extract", write_tok, {"path": str(bad), "dest": str(tmp)})
    check("zip 穿越（../escaped.txt）→ 403",
          st == 403 and "穿越" in d.get("error", "") and not (tmp.parent / "escaped.txt").exists())
    st, d = call("/extract", write_tok, {"path": str(tmp / "sample.log"), "dest": str(tmp)})
    check("不是压缩包 → 400", st == 400)

    print("== 写档：打包 / 清理 ==")
    packdir = tmp / "packme"
    packdir.mkdir()
    (packdir / "one.txt").write_text("hello")
    (packdir / "two.txt").write_text("world")
    st, d = call("/compress", write_tok, {"path": str(packdir)})
    check("打包目录 → tar.gz 落在同目录且非空",
          st == 200 and (tmp / "packme.tar.gz").is_file() and d.get("sizeBytes", 0) > 0,
          str(d)[:160])
    st, d = call("/compress", write_tok, {"path": str(packdir)})
    check("同名包已存在 → 409（不覆盖）", st == 409, str(d)[:120])
    st, d = call("/compress", write_tok, {"path": str(packdir), "name": "inner",
                                          "dest": str(packdir)})
    check("把包裹进它自己的输入目录 → 400", st == 400, str(d)[:120])
    st, d = call("/compress", write_tok, {"path": str(packdir), "name": "x", "format": "rar"})
    check("不支持的打包格式 → 400", st == 400)
    st, d = call("/compress", write_tok, {"path": "/root/.secrets"})
    check("打包受保护路径 → 403", st == 403)
    st, d = call("/compress", write_tok, {"path": str(tmp / "sample.log"), "name": "single"})
    check("打包单个文件 → 200", st == 200 and (tmp / "single.tar.gz").is_file())
    st, d = call("/cleanup", write_tok, {"what": "没有这个"})
    check("不认的清理项 → 400", st == 400)
    st, d = call("/cleanup", write_tok, {"what": "journal", "dry": "1"})
    check("清理预览（dry）→ 200 且 dry=true（不动手）",
          st == 200 and d.get("dry") is True, str(d)[:160])
    st, d = call("/cleanup", write_tok, {"what": "tmp", "dry": "1"})
    check("/tmp 清理预览能报出条数与体积",
          st == 200 and isinstance(d.get("count"), int) and isinstance(d.get("bytes"), int),
          str(d)[:160])
    st, d = call("/cleanup", tok, {"what": "apt"})
    check("只读令牌调清理 → 403", st == 403)

    print("== 写档：服务启停 ==")
    st, d = call("/service", write_tok, {"unit": "sshd.service", "op": "stop"})
    check("停 sshd → 403（自杀动作）", st == 403 and "停掉/禁用" in d.get("error", ""), str(d)[:140])
    st, d = call("/service", write_tok, {"unit": "../../etc/passwd", "op": "restart"})
    check("非法 unit → 400", st == 400)
    st, d = call("/service", write_tok, {"unit": "no-such-unit-xyz.service", "op": "restart"})
    check("不存在的服务 → 404", st == 404)
    st, d = call("/service", write_tok, {"unit": "box-ops-api.service", "op": "selfdestruct"})
    check("不支持的操作名 → 400", st == 400)

    print("== 写档：审计留痕 ==")
    items = read_audit(300)
    check("审计里有写动作（note=写动作）",
          any(i.get("note") == "写动作" for i in items))
    check("审计里有被拒的写动作（403）",
          any(i["status"] == 403 and i.get("note") == "写动作" for i in items))

    print("== 撤销（函数级）==")
    revoke_token("selftest")
    st, _ = call("/overview", tok)
    check("撤销后 401", st == 401)

    # 审计里"被拒绝的调用"也要有痕迹（这正是审计的意义）
    items = read_audit(200)
    check("审计含 401/403/404 记录",
          any(i["status"] == 401 for i in items) and any(i["status"] == 403 for i in items)
          and any(i["status"] == 404 for i in items))
    check("审计不记令牌本身", all("hash" not in json.dumps(i) for i in items))

    print("== 撤销（走 CLI，含 --label 解析）==")
    # 为什么多这一步：直接调 revoke_token() 会漏掉 CLI 的参数解析。
    # 上一版就是这么漏的 —— `token revoke --label x` 把字面量 "--label" 当成了名字，
    # 命令"成功"返回、令牌其实还在（真机上撤销后照样 200，是审计流水把它戳穿的）。
    cli_tok = issue_token("selftest-cli", admin=False)
    proc = subprocess.run(
        [sys.executable, __file__, "token", "revoke", "--label", "selftest-cli"],
        capture_output=True, text=True,
        env={**os.environ, "BOX_OPS_TOKENS": str(TOKENS_FILE),
             "BOX_OPS_AUDIT": str(AUDIT_FILE)},
    )
    st_after_cli, _ = call("/overview", cli_tok)
    check("CLI `token revoke --label` 真的撤掉了（撤销后 401）",
          st_after_cli == 401 and "已撤销" in proc.stdout,
          f"stdout={proc.stdout.strip()!r} stderr={proc.stderr.strip()[:120]!r}")

    srv.shutdown()
    shutil.rmtree(tmp, ignore_errors=True)
    print(f"\n自检结论：{'全部通过 ✅' if not fails else f'{len(fails)} 项失败 ❌ {fails}'}")
    return 1 if fails else 0


def _free_port() -> int:
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port




# ── 写动作（白名单；要 write 作用域）────────────────────────────────────
#
# 设计口径（每一条都对应一个真实的"从手机上把自己搞死"的方式）：
#   * 没有 shell、没有任意命令：动作是固定的几个，参数逐个校验；
#   * 路径先 resolve() 再比对保护名单（软链接绕不过去）；
#   * 停/禁用"自杀单元"直接拒（sshd、本服务、隧道、NetworkManager、systemd 自身）；
#   * 解压必须防 zip 穿越（条目路径跑到目标目录之外）与膨胀炸弹（总量上限）。
#   * 打包不许覆盖同名包、不许把包裹进自己的输入目录（tar 会把刚生成的包也收进去）。
#   * 清理的配额与保留期写死在服务端（journal 只清到 200M、/tmp 只删 7 天前的普通文件）；
#     调用方只能选"清哪一类"，不能选"清多狠"；dry=1 只报数不动手。

class WriteError(Exception):
    """写动作的参数/权限问题（带 HTTP 状态）。"""

    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.message = message


def _safe_write_path(raw: str, *, must_exist: bool, must_be_dir: bool = False) -> Path:
    if not raw or "\x00" in raw:
        raise WriteError(400, "路径为空或不合法")
    if not raw.startswith("/"):
        raise WriteError(400, f"路径必须是绝对路径：{raw}")
    if ".." in Path(raw).parts:
        raise WriteError(400, f"路径里不允许 ..：{raw}")
    p = Path(raw)
    if must_exist and not p.exists():
        raise WriteError(404, f"路径不存在：{raw}")
    if must_be_dir and not p.is_dir():
        raise WriteError(400, f"不是目录：{raw}")
    # 解析软链接之后再看保护名单（否则 ln -s 一下就能绕过）
    try:
        real = p.resolve()
    except Exception:  # noqa: BLE001
        raise WriteError(400, f"路径解析失败：{raw}") from None
    for deny in WRITE_DENY_PREFIXES:
        if str(real) == deny or str(real).startswith(deny.rstrip("/") + "/"):
            raise WriteError(403, f"这个路径受保护，写动作一律拒绝：{deny}")
    return real


def _unit_exists(unit: str) -> bool:
    code, out, _ = run(["systemctl", "list-unit-files", "--type=service",
                        "--no-legend", "--no-pager", "--plain", unit])
    if code != 0 or not (out or "").strip():
        code2, out2, _ = run(["systemctl", "show", unit, "-p", "LoadState"])
        return code2 == 0 and "LoadState=loaded" in (out2 or "")
    return True


def act_capabilities(_q: dict, label: str) -> tuple[int, dict]:
    entry = match_token_by_label(label)
    return 0, {
        "hostname": socket.gethostname(),
        "version": VERSION,
        "admin": bool(entry.get("admin")) if entry else False,
        "write": bool(entry.get("write")) if entry else False,
        "readActions": sorted(ACTIONS),
        "writeActions": sorted(WRITE_ACTIONS),
        "selfDestructiveUnits": list(SELF_DESTRUCTIVE_UNITS),
        "protectedPaths": list(WRITE_DENY_PREFIXES),
        "note": "写作用域要令牌带 write；不带的令牌调写动作一律 403",
        "generatedAt": now_iso(),
    }


def match_token_by_label(label: str) -> dict:
    for t in load_tokens():
        if t.get("label") == label:
            return t
    return {}


def act_service_op(q: dict, _label: str) -> tuple[int, dict]:
    unit = (q.get("unit") or [""])[0]
    op = (q.get("op") or [""])[0]
    if not _valid_unit(unit):
        raise WriteError(400, "unit 不合法（形如 xxx.service，只含字母数字 @._:+-）")
    if op not in ("start", "stop", "restart", "reload", "enable", "disable"):
        raise WriteError(400, f"不支持的操作：{op}（只允许 start/stop/restart/reload/enable/disable）")
    if op in ("stop", "disable") and unit in SELF_DESTRUCTIVE_UNITS:
        raise WriteError(
            403,
            f"拒绝把 {unit} 停掉/禁用：它是「能让你再连上来」的那一层"
            f"（本服务被停之后，App 就再也没法从手机上把它启回来）",
        )
    if not _unit_exists(unit):
        raise WriteError(404, f"没有这个服务：{unit}")
    code, out, err = run(["systemctl", op, unit], timeout=30)
    if code != 0:
        raise WriteError(502, f"systemctl {op} 失败：{(err or out).strip()[:300]}")
    time.sleep(0.4)
    code2, out2, _ = run(["systemctl", "show", unit, "-p", "ActiveState,SubState,UnitFileState"])
    props = dict(line.split("=", 1) for line in (out2 or "").splitlines() if "=" in line)
    return 0, {
        "unit": unit,
        "op": op,
        "activeState": props.get("ActiveState"),
        "subState": props.get("SubState"),
        "unitFileState": props.get("UnitFileState"),
        "generatedAt": now_iso(),
    }


def act_mkdir(q: dict, _label: str) -> tuple[int, dict]:
    path = _safe_write_path((q.get("path") or [""])[0], must_exist=False)
    if path.exists():
        raise WriteError(400, f"已经存在：{path}")
    if not path.parent.exists():
        raise WriteError(400, f"上一级目录不存在（不做递归创建）：{path.parent}")
    try:
        path.mkdir()
        os.chmod(path, 0o755)
    except OSError as e:
        raise WriteError(502, f"建目录失败：{e}") from None
    return 0, {"path": str(path), "created": True, "generatedAt": now_iso()}


def act_chmod(q: dict, _label: str) -> tuple[int, dict]:
    path = _safe_write_path((q.get("path") or [""])[0], must_exist=True)
    mode = (q.get("mode") or [""])[0]
    recursive = (q.get("recursive") or ["0"])[0] in ("1", "true", "yes")
    if not MODE_RE.match(mode):
        raise WriteError(400, f"权限要写成八进制三位或四位：{mode}")
    if mode in ("0000", "000"):  # 0000 是"把自己关在门外"的经典做法
        raise WriteError(400, "拒绝把权限设成 000：那等于把自己锁在外面")
    args = ["chmod"]
    if recursive:
        if path.parent == path:  # 根目录
            raise WriteError(403, "拒绝在 / 上递归改权限")
        args.append("-R")
    args += [mode, str(path)]
    code, out, err = run(args, timeout=60)
    if code != 0:
        raise WriteError(502, f"chmod 失败：{(err or out).strip()[:300]}")
    return 0, {"path": str(path), "mode": oct(path.stat().st_mode & 0o7777)[2:],
               "recursive": recursive, "generatedAt": now_iso()}


def act_chown(q: dict, _label: str) -> tuple[int, dict]:
    import grp
    import pwd

    path = _safe_write_path((q.get("path") or [""])[0], must_exist=True)
    owner = (q.get("owner") or [""])[0].strip()
    group = (q.get("group") or [""])[0].strip()
    recursive = (q.get("recursive") or ["0"])[0] in ("1", "true", "yes")
    if not owner and not group:
        raise WriteError(400, "要给 owner 或 group 之一")
    # 名字必须在 /etc/passwd、/etc/group 里真实存在（不猜 uid/gid）
    for name, lookup, what in ((owner, pwd.getpwnam, "用户"), (group, grp.getgrnam, "组")):
        if not name:
            continue
        try:
            lookup(name)
        except KeyError:
            raise WriteError(400, f"没有这个{what}：{name}") from None
    args = ["chown"]
    if recursive:
        if path.parent == path:
            raise WriteError(403, "拒绝在 / 上递归改属主")
        args.append("-R")
    args += [f"{owner}:{group}" if group else owner, str(path)]
    code, out, err = run(args, timeout=60)
    if code != 0:
        raise WriteError(502, f"chown 失败：{(err or out).strip()[:300]}")
    return 0, {"path": str(path), "owner": owner or "(不改)", "group": group or "(不改)",
               "recursive": recursive, "generatedAt": now_iso()}


def _archive_kind(p: Path) -> str:
    name = p.name.lower()
    for suf in sorted(ARCHIVE_SUFFIXES, key=len, reverse=True):
        if name.endswith(suf):
            if suf == ".zip":
                return "zip"
            if suf in (".tar", ".tar.gz", ".tgz", ".tar.bz2", ".tbz2", ".tar.xz", ".txz"):
                return "tar"
            if suf == ".gz":
                return "gz"
    return ""


def act_extract(q: dict, _label: str) -> tuple[int, dict]:
    import tarfile
    import zipfile

    src = _safe_write_path((q.get("path") or [""])[0], must_exist=True)
    dest_raw = (q.get("dest") or [""])[0].strip()
    dest = _safe_write_path(dest_raw, must_exist=True, must_be_dir=True) if dest_raw else src.parent
    if not src.is_file():
        raise WriteError(400, f"不是文件：{src}")
    kind = _archive_kind(src)
    if not kind:
        raise WriteError(400, f"不认的压缩格式（支持 {', '.join(ARCHIVE_SUFFIXES)}）：{src.name}")

    dest_str = str(dest)
    extracted: list[str] = []
    total = 0

    def check_target(name: str) -> Path:
        """条目落到哪儿；越界（zip 穿越）一律拒。"""
        candidate = (dest / name).resolve()
        if not (str(candidate) == dest_str or str(candidate).startswith(dest_str.rstrip("/") + "/")):
            raise WriteError(403, f"压缩包里有越界条目（zip 穿越），拒绝解压：{name}")
        for deny in WRITE_DENY_PREFIXES:
            if str(candidate) == deny or str(candidate).startswith(deny.rstrip("/") + "/"):
                raise WriteError(403, f"压缩包里有指向受保护路径的条目：{name}")
        return candidate

    try:
        if kind == "zip":
            with zipfile.ZipFile(src) as zf:
                for info in zf.infolist():
                    total += info.file_size
                    if total > EXTRACT_MAX_TOTAL:
                        break  # 停止解压，下面按"被截断"报回来
                    check_target(info.filename)
                    zf.extract(info, dest_str)
                    extracted.append(info.filename)
            truncated = total > EXTRACT_MAX_TOTAL
        elif kind == "tar":
            mode = "r:*"
            with tarfile.open(src, mode) as tf:
                for member in tf:
                    total += member.size
                    if total > EXTRACT_MAX_TOTAL:
                        break
                    check_target(member.name)
                    tf.extract(member, dest_str)
                    extracted.append(member.name)
            truncated = total > EXTRACT_MAX_TOTAL
        else:  # 单文件 .gz
            import gzip
            import shutil as _sh

            target = check_target(src.name[:-3] if src.name.lower().endswith(".gz") else src.name + ".out")
            with gzip.open(src, "rb") as fin, target.open("wb") as fout:
                _sh.copyfileobj(fin, fout, 1024 * 1024)
            extracted.append(target.name)
            truncated = False
    except WriteError:
        raise
    except Exception as e:  # noqa: BLE001
        raise WriteError(502, f"解压失败：{type(e).__name__}: {e}") from None

    return 0, {
        "archive": str(src),
        "kind": kind,
        "dest": dest_str,
        "count": len(extracted),
        "totalBytesUncompressed": total,
        "truncated": truncated,
        "sample": extracted[:20],
        "generatedAt": now_iso(),
    }


def act_compress(q: dict, _label: str) -> tuple[int, dict]:
    """把一个文件/目录打包成 .tar.gz / .zip，落在它的父目录（或 dest 指定的目录）里。"""
    src = _safe_write_path((q.get("path") or [""])[0], must_exist=True)
    fmt = ((q.get("format") or ["tar.gz"])[0] or "tar.gz").strip().lower()
    if fmt not in ("tar.gz", "zip"):
        raise WriteError(400, f"打包格式只支持 tar.gz 与 zip：{fmt}")
    dest_raw = (q.get("dest") or [""])[0].strip()
    dest_dir = (_safe_write_path(dest_raw, must_exist=True, must_be_dir=True)
                if dest_raw else src.parent)
    name = (q.get("name") or [""])[0].strip() or (src.name or "archive")
    if "/" in name or name in (".", ".."):
        raise WriteError(400, f"打包名不合法：{name}")
    suffix = ".tar.gz" if fmt == "tar.gz" else ".zip"
    out = dest_dir / (name if name.endswith(suffix) else name + suffix)

    # 目标不许已经存在：覆盖会静默吃掉别人（或者你自己）的东西
    if out.exists():
        raise WriteError(409, f"目标已存在：{out.name}（换个名字，或先删掉）")
    # 不许把包裹在**它自己的输入**里面：tar 会边写边把刚生成的包也收进去
    out_in_src = src.is_dir() and (
        str(out) == str(src) or str(out).startswith(str(src).rstrip("/") + "/"))
    if out_in_src:
        raise WriteError(400, "不能把压缩包放进它自己正在打包的目录里（会越打越大）")

    du_code, du_out, _ = run(["du", "-sx", "--block-size=1048576", str(src)], timeout=120)
    size_mb = 0
    if du_code == 0 and (du_out or "").split():
        try:
            size_mb = int((du_out or "0").split()[0])
        except ValueError:
            size_mb = 0
    if size_mb > COMPRESS_MAX_INPUT_MB:
        raise WriteError(400, f"输入太大（约 {size_mb} MB），打包上限 "
                              f"{COMPRESS_MAX_INPUT_MB} MB")
    free_mb = shutil.disk_usage(str(dest_dir)).free // (1024 * 1024)
    if free_mb < size_mb + COMPRESS_FREE_RESERVE_MB:
        raise WriteError(400, f"目标分区只剩 {free_mb} MB，装不下"
                              f"（输入约 {size_mb} MB，还要留 "
                              f"{COMPRESS_FREE_RESERVE_MB} MB 余量）")

    if fmt == "tar.gz":
        code, _, err = run(["tar", "-czf", str(out), "-C", str(src.parent), src.name],
                           timeout=COMPRESS_TIMEOUT)
    else:
        code, _, err = run(["zip", "-qr", str(out), src.name],
                           timeout=COMPRESS_TIMEOUT, cwd=str(src.parent))
    if code != 0:
        try:
            out.unlink()
        except OSError:
            pass
        raise WriteError(502, f"打包失败：{(err or '').strip()[:200]}")

    return 0, {
        "archive": str(out),
        "format": fmt,
        "source": str(src),
        "inputMB": size_mb,
        "sizeBytes": out.stat().st_size,
        "generatedAt": now_iso(),
    }


def act_cleanup(q: dict, _label: str) -> tuple[int, dict]:
    """清理三类公认可以清的东西：journal 日志 / /tmp 陈旧文件 / apt 缓存。

    配额与保留期写死在服务端（不接受客户端指定）：这台机器是别人的生产机，
    "清到什么程度"不该由手机上的参数决定。dry=1 只报"能清多少"，不动手。
    """
    what = ((q.get("what") or [""])[0] or "").strip().lower()
    dry = str((q.get("dry") or ["0"])[0]).strip().lower() in ("1", "true", "yes")
    if what not in CLEANUP_MODES:
        raise WriteError(400, f"不认的清理项（支持 {', '.join(CLEANUP_MODES)}）：{what}")

    before = shutil.disk_usage("/").free
    detail: dict = {
        "what": what,
        "dry": dry,
        # 配额/保留期**报给客户端**：App 里就不用写死"200MB / 7天"，
        # 以后改这里，手机上的文案跟着变（不写死的地方不会漂）。
        "limits": {"journalKeepMB": CLEANUP_JOURNAL_KEEP_MB,
                   "tmpKeepDays": CLEANUP_TMP_DAYS},
    }

    if what == "journal":
        # journalctl --vacuum-size 会把超出部分删掉；先报当前的量
        code, out, err = run(["journalctl", "--disk-usage"], timeout=60)
        detail["before"] = (out or "").strip()[:200]
        if not dry:
            code, out, err = run(["journalctl", f"--vacuum-size={CLEANUP_JOURNAL_KEEP_MB}M"],
                                 timeout=180)
            if code != 0:
                raise WriteError(502, f"清理 journal 失败：{(err or '').strip()[:200]}")
            detail["log"] = (out or "").strip()[-300:]
    elif what == "apt":
        code, out, err = run(["du", "-sh", "/var/cache/apt"], timeout=60)
        detail["before"] = (out or "").strip()[:200]
        if not dry:
            code, out, err = run(["apt-get", "clean"], timeout=180)
            if code != 0:
                raise WriteError(502, f"清理 apt 缓存失败：{(err or '').strip()[:200]}")
    else:  # tmp
        # 只删**普通文件**、且 7 天没被访问过；目录、软链接、最近用过的都不动
        code, out, _ = run(["find", "/tmp", "-xdev", "-type", "f",
                            "-mtime", f"+{CLEANUP_TMP_DAYS}", "-printf", "%s\n"],
                           timeout=120)
        sizes = [int(x) for x in (out or "").split() if x.isdigit()]
        detail["count"] = len(sizes)
        detail["bytes"] = sum(sizes)
        if not dry and sizes:
            code, _, err = run(["find", "/tmp", "-xdev", "-type", "f",
                                "-mtime", f"+{CLEANUP_TMP_DAYS}", "-delete"], timeout=180)
            if code != 0:
                raise WriteError(502, f"清理 /tmp 失败：{(err or '').strip()[:200]}")

    after = shutil.disk_usage("/").free
    detail["freedBytes"] = max(0, after - before)
    detail["generatedAt"] = now_iso()
    return 0, detail


WRITE_ACTIONS = {
    "compress": act_compress,
    "cleanup": act_cleanup,
    "capabilities": act_capabilities,
    "service": act_service_op,
    "mkdir": act_mkdir,
    "chmod": act_chmod,
    "chown": act_chown,
    "extract": act_extract,
}


if __name__ == "__main__":
    sys.exit(main(sys.argv))
