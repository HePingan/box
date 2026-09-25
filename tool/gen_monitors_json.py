#!/usr/bin/env python3
"""采样 Uptime Kuma 的监控状态，产出给 box 插件读的 monitors.json。

部署位置：175 上 /opt/kuma-monitor/gen_monitors_json.py（本文件是源，改完要同步过去）：
    scp tool/gen_monitors_json.py 175:/opt/kuma-monitor/gen_monitors_json.py
cron：*/2 * * * * /usr/bin/python3 /opt/kuma-monitor/gen_monitors_json.py >> /var/log/kuma-monitor.log 2>&1

数据来源（都在本机，不走公网）：
  1. Kuma 的 Prometheus /metrics（需要 Kuma 账号；Basic 认证）→ 状态与延迟
  2. Kuma 的 SQLite（只读 URI，绝不写）→ 24 小时可用率

产出两个副本：
  * 本机 /opt/kuma-monitor/monitors.json（留档，出问题先看它）
  * 边缘机（box.hpa888.top 的 nginx 静态根）→ 公网 https://box.hpa888.top/monitors.json

字段刻意最小：**不含被监控的 URL**（该端点是公开的，不泄露内网/服务地址）。
"""
from __future__ import annotations

import base64
import json
import os
import re
import sqlite3
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone, timedelta

KUMA = "http://127.0.0.1:3010"
KUMA_DB = "/opt/uptime-kuma/kuma.db"
PW_FILE = "/opt/uptime-kuma/admin-password.txt"
LOCAL_OUT = "/opt/kuma-monitor/monitors.json"
EDGE_HOST = "hpa888"
EDGE_PATH = "/home/update-server/public/monitors.json"
PANEL_URL = "https://ham.hpa888.top/"
PUBLIC_URL = "https://box.hpa888.top/monitors.json"
CST = timezone(timedelta(hours=8))

LINE_RE = re.compile(r'^monitor_(status|response_time)\{(.*)\}\s+([0-9.eE+-]+)\s*$')


def parse_labels(raw: str) -> dict:
    """解析 Prometheus 标签串，处理 \" 与 \\\\ 转义。"""
    labels, i, n = {}, 0, len(raw)
    while i < n:
        eq = raw.find("=", i)
        if eq < 0:
            break
        key = raw[i:eq].strip()
        if eq + 1 >= n or raw[eq + 1] != '"':
            break
        j, buf = eq + 2, []
        while j < n:
            ch = raw[j]
            if ch == "\\" and j + 1 < n:
                buf.append(raw[j + 1])
                j += 2
                continue
            if ch == '"':
                break
            buf.append(ch)
            j += 1
        labels[key] = "".join(buf)
        i = j + 2
    return labels


def fetch_metrics() -> str:
    pw = open(PW_FILE).read().strip()
    tok = base64.b64encode(f"admin:{pw}".encode()).decode()
    req = urllib.request.Request(f"{KUMA}/metrics", headers={"Authorization": f"Basic {tok}"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read().decode("utf-8", "replace")


def uptime_24h() -> dict:
    """{monitor_id: 可用率%}；读不到就返回空 dict（插件侧容忍缺字段）。"""
    out = {}
    try:
        db = sqlite3.connect(f"file:{KUMA_DB}?mode=ro", uri=True, timeout=5)
        rows = db.execute(
            "select monitor_id, count(*), sum(case when status=1 then 1 else 0 end) "
            "from heartbeat where time >= datetime('now', '-1 day') group by monitor_id"
        ).fetchall()
        db.close()
        for mid, total, ok in rows:
            if total:
                out[int(mid)] = round(100.0 * (ok or 0) / total, 2)
    except Exception as e:  # noqa: BLE001 - 可用率是加分项，读不到不影响主流程
        print(f"[warn] 24h 可用率读取失败: {e}", file=sys.stderr)
    return out


def monitor_ids_by_name() -> dict:
    try:
        db = sqlite3.connect(f"file:{KUMA_DB}?mode=ro", uri=True, timeout=5)
        rows = db.execute("select id, name from monitor").fetchall()
        db.close()
        return {str(name): int(mid) for mid, name in rows}
    except Exception:  # noqa: BLE001
        return {}


def build() -> dict:
    text = fetch_metrics()
    status, ping = {}, {}
    for line in text.splitlines():
        m = LINE_RE.match(line.strip())
        if not m:
            continue
        kind, labels_raw, value = m.group(1), m.group(2), float(m.group(3))
        labels = parse_labels(labels_raw)
        name = labels.get("monitor_name")
        if not name:
            continue
        (status if kind == "status" else ping)[name] = value

    ids = monitor_ids_by_name()
    up24 = uptime_24h()
    monitors = []
    for name in status:  # 以 status 指标为准（Kuma 只对它认识的监控项输出）
        mid = ids.get(name)
        entry = {
            "name": name,
            "up": status[name] >= 1,
        }
        if mid is not None:
            entry["id"] = mid
        if name in ping:
            entry["pingMs"] = int(round(ping[name]))
        if mid is not None and mid in up24:
            entry["uptime24h"] = up24[mid]
        monitors.append(entry)

    monitors.sort(key=lambda m: (m["up"], m.get("id", 0)))  # 异常的排前面
    up = sum(1 for m in monitors if m["up"])
    return {
        "generatedAt": datetime.now(CST).isoformat(timespec="seconds"),
        "panelUrl": PANEL_URL,
        "summary": {"total": len(monitors), "up": up, "down": len(monitors) - up},
        "monitors": monitors,
    }


def push_to_edge(payload: bytes) -> None:
    tmp = EDGE_PATH + ".tmp"
    subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", EDGE_HOST,
                    f"cat > {tmp}"], input=payload, check=True)
    subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", EDGE_HOST,
                    f"mv {tmp} {EDGE_PATH}"], check=True)


def main() -> int:
    started = time.time()
    doc = build()
    payload = json.dumps(doc, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    os.makedirs(os.path.dirname(LOCAL_OUT), exist_ok=True)
    tmp = LOCAL_OUT + ".tmp"
    with open(tmp, "wb") as f:
        f.write(payload)
    os.replace(tmp, LOCAL_OUT)
    try:
        push_to_edge(payload)
        pushed = "ok"
    except Exception as e:  # noqa: BLE001 - 推不动时边缘机继续提供上一份（含旧 generatedAt）
        pushed = f"FAILED: {e}"
    s = doc["summary"]
    print(f"[{doc['generatedAt']}] 共 {s['total']} 项，在线 {s['up']}，异常 {s['down']}，"
          f"{len(payload)}B，推送边缘机={pushed}，{time.time() - started:.1f}s")
    return 0 if pushed == "ok" else 1


if __name__ == "__main__":
    sys.exit(main())
