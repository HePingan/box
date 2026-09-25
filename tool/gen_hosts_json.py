#!/usr/bin/env python3
"""采样两台服务器的主机指标，产出给 box 运维插件读的 hosts.json。

部署位置：175 上 /opt/ops-monitor/gen_hosts_json.py（本文件是源，改完要同步过去）：
    scp tool/gen_hosts_json.py 175:/opt/ops-monitor/gen_hosts_json.py
cron：*/2 * * * * /usr/bin/python3 /opt/ops-monitor/gen_hosts_json.py >> /var/log/ops-monitor.log 2>&1

设计要点：
  * **采集逻辑只有一份**：本机直接跑，远端用 `ssh <host> python3 - --collect` 把本文件
    喂给远端解释器执行 —— 远端不需要安装任何东西，也不会版本漂移。
  * 数据源是 /proc 与 statvfs，**不碰宝塔面板 API**（面板 API 权限等同 root）。
  * CPU / 网络速率要两次采样求差（间隔 0.4s），所以脚本自身耗时约 1 秒。
  * 单台采不到 = 那台标 online:false（宝塔APP 里"离线、0%"就是这个意思），
    不让一台机器拖垮整份快照。
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone, timedelta

LOCAL_OUT = "/opt/ops-monitor/hosts.json"
EDGE_HOST = "hpa888"
EDGE_PATH = "/home/update-server/public/hosts.json"
PUBLIC_URL = "https://box.hpa888.top/hosts.json"
CST = timezone(timedelta(hours=8))
SAMPLE_GAP = 0.4

# 要监控的机器：id 是稳定标识（插件按它做曲线历史的键），name 是显示名。
# ssh=None 表示"就是跑本脚本的这台"（本脚本部署在 175）。
HOSTS = [
    {"id": "hpa888", "name": "阿里云 · 主服务端", "ip": "47.109.97.1", "ssh": "hpa888"},
    {"id": "tencent175", "name": "腾讯云 · 构建/监控机", "ip": "175.178.248.237",
     "ssh": None},
]


def _read(path: str) -> str:
    with open(path, "r") as f:
        return f.read()


def _cpu_snapshot() -> tuple[int, int]:
    """返回 (总 jiffies, 空闲 jiffies)。"""
    parts = _read("/proc/stat").split("\n")[0].split()
    vals = [int(v) for v in parts[1:]]
    idle = vals[3] + (vals[4] if len(vals) > 4 else 0)
    return sum(vals), idle


def _net_snapshot() -> tuple[int, int]:
    """返回 (rx bytes, tx bytes)，只算非 lo 接口。"""
    rx = tx = 0
    for line in _read("/proc/net/dev").splitlines()[2:]:
        if ":" not in line:
            continue
        iface, rest = line.split(":", 1)
        if iface.strip() == "lo":
            continue
        cols = rest.split()
        rx += int(cols[0])
        tx += int(cols[8])
    return rx, tx


def collect() -> dict:
    """在**本机**采一份指标。远端也用这段代码（喂 stdin 执行）。"""
    total1, idle1 = _cpu_snapshot()
    rx1, tx1 = _net_snapshot()
    time.sleep(SAMPLE_GAP)
    total2, idle2 = _cpu_snapshot()
    rx2, tx2 = _net_snapshot()

    d_total = max(total2 - total1, 1)
    d_idle = max(idle2 - idle1, 0)
    cpu_percent = round((1 - d_idle / d_total) * 100, 1)

    meminfo = {}
    for line in _read("/proc/meminfo").splitlines():
        key, _, rest = line.partition(":")
        meminfo[key.strip()] = int(rest.strip().split()[0]) * 1024  # kB → bytes

    mem_total = meminfo.get("MemTotal", 0)
    # MemAvailable 才是"还能用多少"（MemFree 不含可回收的 cache，会虚报紧张）
    mem_avail = meminfo.get("MemAvailable", meminfo.get("MemFree", 0))
    mem_used = max(mem_total - mem_avail, 0)

    swap_total = meminfo.get("SwapTotal", 0)
    swap_used = max(swap_total - meminfo.get("SwapFree", 0), 0)

    st = os.statvfs("/")
    disk_total = st.f_blocks * st.f_frsize
    disk_avail = st.f_bavail * st.f_frsize
    disk_used = disk_total - disk_avail

    load1, load5, load15 = (float(x) for x in _read("/proc/loadavg").split()[:3])
    uptime_seconds = int(float(_read("/proc/uptime").split()[0]))

    return {
        "cpuPercent": cpu_percent,
        "cpuCount": os.cpu_count() or 1,
        "memTotalBytes": mem_total,
        "memUsedBytes": mem_used,
        "memPercent": round(mem_used / mem_total * 100, 1) if mem_total else None,
        "swapTotalBytes": swap_total,
        "swapUsedBytes": swap_used,
        "diskTotalBytes": disk_total,
        "diskUsedBytes": disk_used,
        "diskPercent": round(disk_used / disk_total * 100, 1) if disk_total else None,
        "load1": load1,
        "load5": load5,
        "load15": load15,
        "uptimeSeconds": uptime_seconds,
        "netRxBytesPerSec": int((rx2 - rx1) / SAMPLE_GAP),
        "netTxBytesPerSec": int((tx2 - tx1) / SAMPLE_GAP),
    }


def collect_remote(ssh_alias: str) -> dict | None:
    """把本文件喂给远端的 python3 执行 --collect；失败返回 None（= 那台离线）。

    远端零安装：不复制脚本、不依赖远端有 requirements，采集逻辑与本机逐字节相同。
    """
    try:
        with open(os.path.abspath(__file__), "r") as f:
            src = f.read()
        proc = subprocess.run(
            ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", ssh_alias,
             "python3", "-", "--collect"],
            input=src, capture_output=True, text=True, timeout=60,
        )
        if proc.returncode != 0:
            return None
        for line in reversed(proc.stdout.strip().splitlines()):
            line = line.strip()
            if line.startswith("{"):
                return json.loads(line)
        return None
    except Exception:
        return None


def build() -> dict:
    hosts = []
    for spec in HOSTS:
        if spec["ssh"] is None:
            metrics = collect()          # 本机
        else:
            metrics = collect_remote(spec["ssh"])
        entry = {
            "id": spec["id"],
            "name": spec["name"],
            "ip": spec["ip"],
            "online": metrics is not None,
        }
        if metrics:
            entry.update(metrics)
        hosts.append(entry)
    return {
        "generatedAt": datetime.now(CST).isoformat(timespec="seconds"),
        "hosts": hosts,
    }


def push_to_edge(payload: bytes) -> None:
    tmp = EDGE_PATH + ".tmp"
    subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", EDGE_HOST,
                    f"cat > {tmp}"], input=payload, check=True)
    subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", EDGE_HOST,
                    f"mv {tmp} {EDGE_PATH}"], check=True)


def main() -> int:
    if "--collect" in sys.argv:
        # 远端模式：只把本机指标打到 stdout，别的都不做。
        print(json.dumps(collect(), ensure_ascii=False))
        return 0

    try:
        doc = build()
    except Exception as e:  # noqa: BLE001 - 采不到也要留痕
        print(f"[error] 采样失败: {e}", file=sys.stderr)
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
    except Exception as e:  # noqa: BLE001 - 推不动时边缘机继续提供上一份
        pushed = f"FAILED: {e}"

    online = [h["id"] for h in doc["hosts"] if h["online"]]
    offline = [h["id"] for h in doc["hosts"] if not h["online"]]
    print(f"[ok] {len(doc['hosts'])} 台 / 在线 {online} / 离线 {offline} / "
          f"{len(payload)}B / push={pushed} / {PUBLIC_URL}")
    # 离线不返回非 0：一台关机是常态，不该让 cron 日志天天报错（页面自己会显示离线）。
    return 0 if pushed == "ok" else 1


if __name__ == "__main__":
    sys.exit(main())
