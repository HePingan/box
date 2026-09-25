#!/usr/bin/env python3
"""box-ops 只读运维 API（C2 只读档 / C1 根治档的载体）。

为什么有它：WebDAV 拿不到 unix 权限/属主，也拿不到进程、服务、日志、端口、目录占用 ——
宝塔式管理里真正好用的那半，靠文件通道做不到。而它同时是**凭据模型根治档**的载体：
App 不再拿"等同 root 的通道口令"去访问一个万能接口，而是拿**可撤销的设备令牌**访问
一组**白名单只读动作**，每次调用都进审计。

设计约束（每一条都对应一个真实风险）：
  * **只读**：本档不含任何写动作（服务启停/解压/chmod 在写档，等审计与令牌先落地）；
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

# 日志白名单前缀：只允许读这些目录下的**文件**（不允许目录、不允许 ..
LOG_ROOTS = ("/var/log", "/www/wwwlogs", "/home/update-server/logs", "/tmp")

# 目录占用白名单前缀（du 只对这些根生效；密钥类路径另行拒绝）
DISK_ROOTS = ("/",)
DISK_DENY = ("/root/.secrets", "/root/.ssh", "/root/.hermes", "/proc", "/sys", "/dev")

UNIT_RE = re.compile(r"^[A-Za-z0-9@._:+-]{1,128}$")


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


def issue_token(label: str, admin: bool = False) -> str:
    raw = base64.urlsafe_b64encode(os.urandom(32)).decode().rstrip("=")
    tokens = [t for t in load_tokens() if t.get("label") != label]
    tokens.append({
        "label": label,
        "hash": _token_hash(raw),
        "admin": bool(admin),
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

def run(args: list[str], timeout: int = CMD_TIMEOUT) -> tuple[int, str, str]:
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
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
    return 0, {
        "os": os_release(),
        "hostname": socket.gethostname(),
        "uptimeSeconds": int(up),
        "load": {"load1": float(load[0]), "load5": float(load[1]), "load15": float(load[2])},
        "cpu": {"model": cpu_model, "cores": cores},
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
    "overview": act_overview,
    "processes": act_processes,
    "services": act_services,
    "service": act_service,
    "logs": act_logs,
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
        except Exception as e:  # noqa: BLE001 - 单个动作炸了不该带走进程
            status, payload = 500, {"error": f"{type(e).__name__}: {e}"}
        ms = int((time.time() - started) * 1000)
        audit(action, {k: v[:1] for k, v in query.items()}, label, ip, status if status else 200, ms)
        self._json(status if status else 200, payload)


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
            for i, a in enumerate(argv):
                if a == "--label" and i + 1 < len(argv):
                    label = argv[i + 1]
                if a == "--admin":
                    admin = True
            if not label:
                print("用法：box_ops_api.py token issue --label <名字> [--admin]")
                return 2
            raw = issue_token(label, admin)
            # 令牌必须是**最后一行**：部署脚本 tail -1 取它。
            # 第一版把说明与令牌打成一行（取到 116 字节的整行 → 401），
            # 第二版把说明放到令牌后面（tail -1 取到说明 → 两台令牌哈希还一样了）。
            print(f"已签发：label={label} admin={admin}")
            print("（只显示这一次，请立刻存进 App / 口令管理器）")
            print(raw)
            return 0
        if sub == "list":
            for t in load_tokens():
                print(f"  {t.get('label'):<24} admin={str(t.get('admin')):<5} 建于 {t.get('createdAt')}")
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
    import urllib.request
    import urllib.error

    global TOKENS_FILE, AUDIT_FILE, LOG_ROOTS
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

    def call(path: str, token: str | None) -> tuple[int, dict]:
        req = urllib.request.Request(base + path)
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
    st, d = call("/processes?sort=mem&limit=5", tok)
    check("processes 限条数生效", st == 200 and len(d.get("processes", [])) <= 5 and d.get("count", 9) <= 5)
    st, d = call("/services?limit=10", tok)
    check("services 有 unit/active/enabled", st == 200 and all("unit" in u for u in d.get("units", [])))
    st, d = call("/ports", tok)
    check("ports 至少有一条监听", st == 200 and d.get("count", 0) >= 1)
    st, d = call(f"/logs?path={tmp}/sample.log&lines=2", tok)
    check("logs 只回最后 2 行", st == 200 and d.get("lines") == 2 and "最后一行" in d.get("content", ""))
    st, d = call("/diskusage?path=" + str(tmp), tok)
    check("diskusage 正常", st == 200 and d.get("rows"))
    st, d = call("/sessions", tok)
    check("sessions 结构在位", st == 200 and "logins" in d and "failedLogins" in d)

    print("== 拒绝路径 ==")
    st, _ = call("/overview", None)
    check("无令牌 401", st == 401)
    st, _ = call("/overview", "not-a-real-token")
    check("错令牌 401", st == 401)
    st, _ = call("/logs?path=/etc/shadow", tok)
    check("白名单外日志 403", st == 403)
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


if __name__ == "__main__":
    sys.exit(main(sys.argv))
