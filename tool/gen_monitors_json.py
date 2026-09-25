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

LINE_RE = re.compile(
    r'^monitor_(status|response_time|cert_days_remaining|cert_is_valid)'
    r'\{(.*)\}\s+([0-9.eE+-]+)\s*$'
)

# 采样链自身故障时的告警（Kuma 已经会报"某个站点挂了"，这里只管"我没采到/没送到"，
# 避免同一次故障两条消息）。
ALERT_STATE = "/opt/kuma-monitor/alert_state.json"

# 最近 N 次采样的环形缓冲（287 P3）：给界面画迷你折线、回答"是不是刚开始抖/刚开始不通"。
# 只留 60 个点（cron 每 2 分钟一次 ≈ 最近 2 小时）：静态快照要够小，不该越滚越大。
SERIES_STATE = "/opt/kuma-monitor/series.json"
SERIES_LEN = 60
SERIES_STEP_SEC = 120
ALERT_MIN_GAP_SEC = 3600
FEISHU_TARGET = "feishu"


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
    status, ping, cert_days, cert_valid = {}, {}, {}, {}
    buckets = {
        "status": status,
        "response_time": ping,
        "cert_days_remaining": cert_days,
        "cert_is_valid": cert_valid,
    }
    for line in text.splitlines():
        m = LINE_RE.match(line.strip())
        if not m:
            continue
        kind, labels_raw, value = m.group(1), m.group(2), float(m.group(3))
        labels = parse_labels(labels_raw)
        name = labels.get("monitor_name")
        if not name:
            continue
        buckets[kind][name] = value

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
        if name in cert_days:
            entry["certDays"] = int(round(cert_days[name]))
        if name in cert_valid:
            entry["certValid"] = cert_valid[name] >= 1
        if mid is not None and mid in up24:
            entry["uptime24h"] = up24[mid]
        monitors.append(entry)

    # 历史序列（287 P3）：先并进环形缓冲，再把每项最近的点写进快照。
    series = update_series(monitors, read_series())
    write_series(series)
    for m in monitors:
        rec = series.get(m.get("name"))
        if not rec:
            continue
        m["seriesPing"] = rec["ping"]
        m["seriesUp"] = rec["up"]

    monitors.sort(key=lambda m: (m["up"], m.get("id", 0)))  # 异常的排前面
    up = sum(1 for m in monitors if m["up"])
    generated_at = datetime.now(CST).isoformat(timespec="seconds")
    return {
        "generatedAt": generated_at,
        "panelUrl": PANEL_URL,
        "seriesStepSec": SERIES_STEP_SEC,
        "seriesAt": generated_at,
        "summary": {"total": len(monitors), "up": up, "down": len(monitors) - up},
        "monitors": monitors,
    }


def read_series() -> dict:
    """读上次的环形缓冲。坏文件/结构不对一律当没有（宁可少画一段线，不能中断采样）。"""
    try:
        with open(SERIES_STATE) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def write_series(data: dict) -> None:
    tmp = SERIES_STATE + ".tmp"
    try:
        with open(tmp, "w") as f:
            json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
        os.replace(tmp, SERIES_STATE)
    except Exception:
        pass  # 存不下序列不影响快照本身


def update_series(monitors: list, prev: dict) -> dict:
    """把这一轮采样并进环形缓冲；每项最多 SERIES_LEN 个点。

    ping 缺采样时写 null（**不能拿 0 冒充**，否则折线会把"没采到"画成"延迟 0ms"）。
    """
    out = {}
    for m in monitors:
        name = m.get("name")
        if not name:
            continue
        rec = prev.get(name) if isinstance(prev.get(name), dict) else {}
        raw_ping = rec.get("ping")
        raw_up = rec.get("up")
        ping = raw_ping if isinstance(raw_ping, list) else []
        ups = raw_up if isinstance(raw_up, list) else []
        ping = [p for p in ping if p is None or isinstance(p, (int, float))]
        ups = [1 if u == 1 else 0 for u in ups]
        ping = ping[-(SERIES_LEN - 1):]
        ups = ups[-(SERIES_LEN - 1):]
        ping_ms = m.get("pingMs")
        ping.append(int(ping_ms) if isinstance(ping_ms, (int, float)) else None)
        ups.append(1 if m.get("up") else 0)
        out[name] = {"ping": ping, "up": ups}
    return out


def notify(title: str, body: str) -> None:
    """发一条到飞书（复用 hermes send；失败只记日志，不因为通知失败影响采样）。"""
    try:
        subprocess.run(
            ["hermes", "send", "-t", FEISHU_TARGET, f"{title}\n{body}"],
            check=True, timeout=60, capture_output=True,
        )
        print(f"[alert] 已发送: {title}")
    except Exception as e:  # noqa: BLE001
        print(f"[warn] 告警发送失败: {e}", file=sys.stderr)


def read_alert_state() -> dict:
    try:
        with open(ALERT_STATE) as f:
            return json.load(f)
    except Exception:  # noqa: BLE001
        return {}


def write_alert_state(state: dict) -> None:
    try:
        tmp = ALERT_STATE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(state, f)
        os.replace(tmp, ALERT_STATE)
    except Exception as e:  # noqa: BLE001
        print(f"[warn] 告警状态写盘失败: {e}", file=sys.stderr)


def alert_on_failure(reason: str) -> None:
    """采样链自身出问题时的告警：只在"故障"和"恢复"两个边沿发，且最多每小时一条。

    注意**不报单个站点宕机** —— 那是 Kuma 自己通知的事，重复报只会让人麻木。
    """
    now = int(time.time())
    state = read_alert_state()
    failures = int(state.get("failures", 0)) + 1
    last = int(state.get("lastAlertTs", 0))
    should_send = now - last >= ALERT_MIN_GAP_SEC
    if should_send:
        notify("🔴 监控快照采样异常", f"{reason}\n（已连续失败 {failures} 次）")
    write_alert_state({"failures": failures, "lastAlertTs": now if should_send else last,
                       "state": "fail"})


def alert_on_recovery() -> None:
    state = read_alert_state()
    if state.get("state") == "fail" and int(state.get("failures", 0)) > 0:
        notify("🟢 监控快照采样已恢复",
               f"连续失败 {state.get('failures')} 次后恢复正常。")
    write_alert_state({"failures": 0, "lastAlertTs": int(state.get("lastAlertTs", 0)),
                       "state": "ok"})


def push_to_edge(payload: bytes) -> None:
    tmp = EDGE_PATH + ".tmp"
    subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", EDGE_HOST,
                    f"cat > {tmp}"], input=payload, check=True)
    subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", EDGE_HOST,
                    f"mv {tmp} {EDGE_PATH}"], check=True)


def main() -> int:
    started = time.time()
    try:
        doc = build()
    except Exception as e:  # noqa: BLE001 - 采不到（Kuma 挂了/账号变了/网络）也要留痕并告警
        print(f"[error] 采样失败: {e}", file=sys.stderr)
        alert_on_failure(f"采样失败：{e}")
        return 1

    s = doc["summary"]
    if s["total"] == 0:
        # 0 项通常是"读到了 metrics 但解析不出监控项"，比采样失败更隐蔽 —— 也要报。
        print("[error] 快照里 0 个监控项", file=sys.stderr)
        alert_on_failure("快照里 0 个监控项（metrics 读到了但没解析出监控项）")
        return 1

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

    if pushed == "ok":
        alert_on_recovery()
    else:
        alert_on_failure(f"推送到边缘机失败：{pushed}")
    print(f"[{doc['generatedAt']}] 共 {s['total']} 项，在线 {s['up']}，异常 {s['down']}，"
          f"{len(payload)}B，推送边缘机={pushed}，{time.time() - started:.1f}s")
    return 0 if pushed == "ok" else 1


if __name__ == "__main__":
    sys.exit(main())
