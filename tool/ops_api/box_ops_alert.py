#!/usr/bin/env python3
"""资源越线告警（C3）：用只读运维接口取数，越线才发飞书，带冷却与恢复通知。

与既有监控的分工（**重复报 = 噪声**，见 host-monitoring-and-alerting 技能）：
  * Uptime Kuma：服务可用性（HTTP 探活，10 项）
  * disk-guard.sh：磁盘档位（日检，80/90 两档，两台）
  * security-patrol.py：安全与系统巡检（日检：失败登录、端口变化、证书、待更新）
  * **本脚本**：资源越线，5 分钟级 —— CPU / 内存 / swap / 负载，
    外加"**采不到数据**"这条状态机。磁盘**默认关**（那是 disk-guard 的活，配置里留了开关）。

口径（每条都对应一个踩过的坑）：
  * 只在**档位变化**时发（ok→warn、warn→crit、恢复）；warn 要连续 `samples_before_alert` 次
    才算数（一次采样撞上瞬时尖峰就报警，等于训练人忽略消息）；crit 当次就报；
  * `--check` **不落状态** —— 否则"试跑一次"就把当天告警自己吃掉了（security-patrol 的教训）；
  * **采不到数据 ≠ 一切正常**：连续失败要报，而且报的是"采不到"，绝不能在采不到时说"资源正常"；
  * 消息里只有主机名与数值，**不放令牌/口令**（消息会进飞书、会被转发、会被截屏）。

用法：
  box_ops_alert.py --check      # 试跑：打当前值 + 会发什么，不落状态、不真发
  box_ops_alert.py --once       # 真跑一次（cron 用的就是这个）
  box_ops_alert.py --test       # 故意发一条，证明告警链路通（不知道它通不通=没有告警）
  box_ops_alert.py --selftest   # 逻辑自检：假数据跑状态机，不联网、不发消息
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

DEFAULT_CONFIG = "/etc/box-ops-alert/config.json"
DEFAULT_STATE = "/var/lib/box-ops-alert/state.json"
CST = timezone(timedelta(hours=8))

RANK = {"ok": 0, "warn": 1, "crit": 2}

DEFAULT_THRESHOLDS = {
    "cpu_warn": 85,
    "cpu_crit": 95,
    "mem_warn": 85,
    "mem_crit": 95,
    "swap_warn": 50,
    "swap_crit": 80,
    "load_per_core_warn": 1.5,
    "load_per_core_crit": 3.0,
    # 磁盘默认关：disk-guard.sh 已经在管（日检 + 档位），两边都报就是噪声。
    "disk_enabled": False,
    "disk_warn": 80,
    "disk_crit": 90,
    # warn 要连续几次才发（crit 不看这个，当次就发）
    "samples_before_alert": 2,
    # 一直没恢复时，每隔多久再提醒一次；两次之内同样的消息不再发。
    "repeat_minutes": 360,
    # 连续多少次采不到数据才报（一次网络抖动不该吵人）
    "fail_before_alert": 3,
    # 单次取数的超时
    "timeout_seconds": 20,
}


def now() -> datetime:
    return datetime.now(CST)


def load_config(path: str) -> dict:
    cfg = json.loads(Path(path).read_text())
    th = dict(DEFAULT_THRESHOLDS)
    th.update(cfg.get("thresholds", {}))
    cfg["thresholds"] = th
    return cfg


def read_token(host_cfg: dict) -> str:
    """令牌从文件读（600），**绝不**从命令行参数或环境变量拿（会进 ps/日志）。"""
    tf = host_cfg.get("token_file")
    if not tf:
        return ""
    p = Path(tf)
    if not p.exists():
        return ""
    return p.read_text().strip()


def fetch_overview(host_cfg: dict, timeout: int) -> dict:
    base = host_cfg["base"].rstrip("/")
    token = read_token(host_cfg)
    if not token:
        raise RuntimeError("没有读到令牌文件（见配置里的 token_file）")
    req = urllib.request.Request(
        base + "/overview",
        headers={"Authorization": "Bearer " + token, "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


# ── 规则 ────────────────────────────────────────────────────────────

def _disk_pct(disk: dict) -> float | None:
    raw = str(disk.get("usePercent", "")).strip().rstrip("%")
    try:
        return float(raw)
    except ValueError:
        return None


def evaluate(host_cfg: dict, ov: dict, th: dict) -> list[dict]:
    """把一次快照变成 findings（每条 = 一个规则的档位与数值）。"""
    out: list[dict] = []
    mem = ov.get("memory", {})
    cpu = ov.get("cpu", {})
    load = ov.get("load", {})
    cores = int(cpu.get("cores") or 1) or 1

    def add(rule: str, level: str, text: str, value: float) -> None:
        out.append({"rule": rule, "level": level, "text": text, "value": value})

    cpu_pct = cpu.get("usedPercent")
    if isinstance(cpu_pct, (int, float)):
        lv = _level(cpu_pct, th["cpu_warn"], th["cpu_crit"])
        add("cpu", lv, f"CPU 使用率 {cpu_pct}%", float(cpu_pct))

    mem_pct = mem.get("memUsedPercent")
    if isinstance(mem_pct, (int, float)):
        gb = lambda b: f"{b / 1024 / 1024 / 1024:.1f}G"  # noqa: E731
        lv = _level(mem_pct, th["mem_warn"], th["mem_crit"])
        add("mem", lv,
            f"内存 {mem_pct}%（{gb(mem.get('memUsed', 0))} / {gb(mem.get('memTotal', 0))}）",
            float(mem_pct))

    swap_pct = mem.get("swapUsedPercent")
    if mem.get("swapTotal") and isinstance(swap_pct, (int, float)):
        lv = _level(swap_pct, th["swap_warn"], th["swap_crit"])
        add("swap", lv, f"swap {swap_pct}%", float(swap_pct))

    load1 = load.get("load1")
    if isinstance(load1, (int, float)):
        per_core = round(load1 / cores, 2)
        lv = _level(per_core, th["load_per_core_warn"], th["load_per_core_crit"])
        add("load", lv, f"负载 {load1}（{cores} 核，每核 {per_core}）", per_core)

    if th.get("disk_enabled"):
        for d in ov.get("disks", []):
            pct = _disk_pct(d)
            if pct is None:
                continue
            mount = d.get("mount", "?")
            lv = _level(pct, th["disk_warn"], th["disk_crit"])
            add(f"disk:{mount}", lv, f"{mount} 已用 {pct:.0f}%", pct)

    return out


def _level(value: float, warn: float, crit: float) -> str:
    if value >= crit:
        return "crit"
    if value >= warn:
        return "warn"
    return "ok"


# ── 状态机 ──────────────────────────────────────────────────────────

def decide(prev: dict, findings: list[dict], th: dict, ts: float) -> list[dict]:
    """比对上一次的档位，决定这次要发什么。

    prev[rule] 里有两个档位，别混：
      * `level`       —— 当前**测到**的档位（每次都更新）
      * `alert_level` —— 上次**报过**的档位（只有真发了消息才更新）
    判断"要不要报"必须跟 `alert_level` 比：早先拿 `level` 比，攒次数的第二轮
    （level 已经是 warn、alert_level 还是 ok）就判成"没升档"→ 一条也不发，
    整个 warn 档等于哑的（自检当场抓到）。
    """
    messages: list[dict] = []
    for f in findings:
        rule, lvl = f["rule"], f["level"]
        st = prev.get(rule, {})
        old_level = st.get("level", "ok")
        streak = (int(st.get("streak", 0)) + 1) if lvl == old_level else (1 if lvl != "ok" else 0)
        if lvl == "ok":
            # 之前报过（alert_level 不是 ok）才发恢复
            if RANK.get(st.get("alert_level", "ok"), 0) > 0:
                messages.append({
                    "rule": rule,
                    "level": "ok",
                    "title": f"🟢 {rule} 已恢复",
                    "body": f["text"],
                })
            continue
        # warn 要连续几次才算数（crit 当次就报）
        need = 1 if lvl == "crit" else int(th["samples_before_alert"])
        if streak < need:
            continue
        if RANK[lvl] > RANK.get(st.get("alert_level", "ok"), 0):
            messages.append({
                "rule": rule,
                "level": lvl,
                "title": f"{'🔴' if lvl == 'crit' else '🟠'} {rule} 越线",
                "body": f["text"],
            })
        elif lvl == st.get("alert_level") and st.get("last_alert") \
                and ts - float(st["last_alert"]) >= int(th["repeat_minutes"]) * 60:
            messages.append({
                "rule": rule,
                "level": lvl,
                "title": f"🟠 {rule} 仍未恢复",
                "body": f["text"],
            })
    return messages


def apply_findings(prev: dict, findings: list[dict], messages: list[dict], ts: float) -> dict:
    """把这次的结果落成新状态（消息发没发都要落，否则会反复触发）。"""
    by_rule = {m["rule"]: m for m in messages}
    for f in findings:
        rule, lvl = f["rule"], f["level"]
        st = dict(prev.get(rule, {}))
        old_level = st.get("level", "ok")
        if lvl == "ok":
            st["streak"] = 0
        else:
            st["streak"] = int(st.get("streak", 0)) + 1 if lvl == old_level else 1
            if lvl != old_level:
                st["since"] = ts
        m = by_rule.get(rule)
        if m is not None:
            st["last_alert"] = ts
            st["alert_level"] = m["level"]  # 'ok' 表示这次发的是恢复
        st["level"] = lvl
        st["value"] = f["value"]
        prev[rule] = st
    return prev


# ── 发消息 ──────────────────────────────────────────────────────────

def send_feishu(title: str, body: str, dry: bool = False) -> bool:
    text = title + "\n" + body
    if dry:
        print("  [dry-run 会发] " + text.replace("\n", " / "))
        return True
    for cmd in (["/root/.local/bin/hermes", "send", "-t", "feishu", text],
                ["hermes", "send", "-t", "feishu", text]):
        try:
            r = subprocess.run(cmd, capture_output=True, timeout=60)
            if r.returncode == 0:
                return True
        except Exception:  # noqa: BLE001
            continue
    return False


def compose(host_cfg: dict, ov: dict, messages: list[dict]) -> list[tuple[str, str]]:
    label = host_cfg.get("label", host_cfg.get("id", "?"))
    hostname = ov.get("hostname", "?")
    mem = ov.get("memory", {})
    cpu = ov.get("cpu", {})
    load = ov.get("load", {})
    cores = cpu.get("cores") or 1
    ctx = (f"{label}（{hostname}）\n"
           f"CPU {cpu.get('usedPercent')}% · 内存 {mem.get('memUsedPercent')}% · "
           f"swap {mem.get('swapUsedPercent')}% · 负载 {load.get('load1')}（{cores} 核）\n"
           f"{now().strftime('%Y-%m-%d %H:%M')}")
    return [(f"{host_cfg.get('icon', '')}{m['title']}".strip(), m["body"] + "\n" + ctx)
            for m in messages]


# ── 主流程 ──────────────────────────────────────────────────────────

def read_state(path: str) -> dict:
    p = Path(path)
    if not p.exists():
        return {}
    try:
        return json.loads(p.read_text())
    except Exception:  # noqa: BLE001
        return {}


def write_state(path: str, state: dict) -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=2))
    tmp.replace(p)


def run_once(cfg: dict, state_path: str, dry: bool, verbose: bool = True) -> int:
    th = cfg["thresholds"]
    state = read_state(state_path)
    ts = time.time()
    sent = 0
    failed_hosts = []

    for host_cfg in cfg["hosts"]:
        hid = host_cfg["id"]
        hs = state.setdefault(hid, {})
        try:
            ov = fetch_overview(host_cfg, int(th["timeout_seconds"]))
        except Exception as e:  # noqa: BLE001
            fails = int(hs.get("fails", 0)) + 1
            hs["fails"] = fails
            failed_hosts.append((host_cfg, str(e), fails))
            if verbose:
                print(f"[{hid}] 采不到数据（第 {fails} 次）：{e}")
            if fails >= int(th["fail_before_alert"]) and not hs.get("fail_alerted"):
                title = f"🟠 采不到 {hid} 的数据"
                body = (f"连续 {fails} 次调用只读接口失败：{e}\n"
                        f"**这不代表机器正常** —— 是监控这条链断了（令牌被撤？服务没起？网络不通？）\n"
                        f"{now().strftime('%Y-%m-%d %H:%M')}")
                if send_feishu(title, body, dry):
                    hs["fail_alerted"] = True
                    sent += 1
            continue

        # 采集恢复
        if hs.get("fails") and hs.get("fail_alerted"):
            if send_feishu(f"🟢 {hid} 的采集已恢复",
                           f"只读接口又能取到数据了（之前连续 {hs['fails']} 次失败）",
                           dry):
                sent += 1
        hs["fails"] = 0
        hs["fail_alerted"] = False

        host_cfg = dict(host_cfg)
        host_cfg["icon"] = host_cfg.get("icon", "")
        findings = evaluate(host_cfg, ov, th)
        prev = hs.get("rules", {})
        messages = decide(prev, findings, th, ts)
        if verbose:
            brief = " · ".join(f"{f['rule']}={f['value']}" for f in findings)
            print(f"[{hid}] {brief or '（没有可评估的指标）'}"
                  f"{'  → 要发 ' + str(len(messages)) + ' 条' if messages else ''}")
        for title, body in compose(host_cfg, ov, messages):
            if send_feishu(title, body, dry):
                sent += 1
        hs["rules"] = apply_findings(prev, findings, messages, ts)
        hs["lastOk"] = now().isoformat()

    if not dry:
        write_state(state_path, state)
    if verbose:
        print(f"本轮：发出 {sent} 条，采不到 {len(failed_hosts)} 台"
              f"{'（--check，未落状态）' if dry else ''}")
    return 0


# ── 自检（假数据跑状态机；不联网、不发消息）────────────────────────────

def selftest() -> int:
    import tempfile

    ok = 0
    bad = 0

    def check(desc: str, cond: bool, extra: str = "") -> None:
        nonlocal ok, bad
        if cond:
            ok += 1
            print(f"  ✅ {desc}")
        else:
            bad += 1
            print(f"  ❌ {desc} {extra}")

    th = dict(DEFAULT_THRESHOLDS)
    host = {"id": "175", "label": "构建机", "base": "http://127.0.0.1:8095", "hostname": "VM-0-15"}

    def ov(cpu=10, mem=20, swap=5, load=0.5, disks=None):
        return {
            "hostname": "VM-0-15",
            "cpu": {"cores": 4, "usedPercent": cpu},
            "memory": {"memTotal": 4 * 1024 ** 3, "memUsed": int(4 * 1024 ** 3 * mem / 100),
                       "memUsedPercent": mem, "swapTotal": 4 * 1024 ** 3,
                       "swapUsed": int(4 * 1024 ** 3 * swap / 100), "swapUsedPercent": swap},
            "load": {"load1": load, "load5": load, "load15": load},
            "disks": disks or [{"mount": "/", "usePercent": "10%"}],
            "generatedAt": "x",
        }

    print("== 规则 ==")
    f = {x["rule"]: x for x in evaluate(host, ov(cpu=96, mem=20, load=0.5), th)}
    check("CPU 96% 判 crit", f["cpu"]["level"] == "crit")
    f = {x["rule"]: x for x in evaluate(host, ov(cpu=88), th)}
    check("CPU 88% 判 warn", f["cpu"]["level"] == "warn")
    f = {x["rule"]: x for x in evaluate(host, ov(cpu=50), th)}
    check("CPU 50% 判 ok", f["cpu"]["level"] == "ok")
    f = {x["rule"]: x for x in evaluate(host, ov(load=13.0), th)}
    check("4 核机器 load 13 判 crit（每核 3.25）", f["load"]["level"] == "crit", f["load"]["text"])
    f = {x["rule"]: x for x in evaluate(host, ov(load=7.0), th)}
    check("4 核机器 load 7 判 warn（每核 1.75）", f["load"]["level"] == "warn", f["load"]["text"])
    f = {x["rule"]: x for x in evaluate(host, ov(disks=[{"mount": "/", "usePercent": "95%"}]), th)}
    check("磁盘默认不报（disk-guard 在管）", "disk:/" not in f)
    th_disk = dict(th, disk_enabled=True)
    f = {x["rule"]: x for x in evaluate(host, ov(disks=[{"mount": "/", "usePercent": "95%"}]), th_disk)}
    check("开了磁盘规则就报 crit", f.get("disk:/", {}).get("level") == "crit")
    f = {x["rule"]: x for x in evaluate(host, ov(swap=90), th)}
    check("swap 90% 判 crit", f["swap"]["level"] == "crit")

    print("== 状态机 ==")
    t0 = 1_000_000.0
    prev: dict = {}
    fs = evaluate(host, ov(cpu=88), th)
    msgs = decide(prev, fs, th, t0)
    check("warn 第一次先攒不报", msgs == [], str(msgs))
    prev = apply_findings(prev, fs, msgs, t0)
    msgs = decide(prev, fs, th, t0 + 300)
    check("第二次还是 warn → 报一条", len(msgs) == 1 and msgs[0]["title"].endswith("越线"), str(msgs))
    prev = apply_findings(prev, fs, msgs, t0 + 300)
    msgs = decide(prev, fs, th, t0 + 600)
    check("第三次同档位不再重复报", msgs == [], str(msgs))
    prev = apply_findings(prev, fs, msgs, t0 + 600)

    fs = evaluate(host, ov(cpu=97), th)
    msgs = decide(prev, fs, th, t0 + 900)
    check("升到 crit 当次就报", len(msgs) == 1 and msgs[0]["level"] == "crit", str(msgs))
    prev = apply_findings(prev, fs, msgs, t0 + 900)

    fs = evaluate(host, ov(cpu=97), th)
    msgs = decide(prev, fs, th, t0 + 900 + th["repeat_minutes"] * 60 + 1)
    check("crit 超过 repeat_minutes 再提醒一次", len(msgs) == 1 and "仍未恢复" in msgs[0]["title"],
          str(msgs))
    prev = apply_findings(prev, fs, msgs, t0 + 900 + th["repeat_minutes"] * 60 + 1)

    fs = evaluate(host, ov(cpu=10), th)
    msgs = decide(prev, fs, th, t0 + 4000)
    check("恢复时发一条", any(m["level"] == "ok" and "已恢复" in m["title"] for m in msgs), str(msgs))
    prev = apply_findings(prev, fs, msgs, t0 + 4000)
    msgs = decide(prev, fs, th, t0 + 5000)
    check("恢复后不再重复发", msgs == [], str(msgs))

    print("== 采不到数据 ==")
    with tempfile.TemporaryDirectory(dir="/tmp") as tmp:
        cfg = {
            "hosts": [{"id": "ghost", "base": "http://127.0.0.1:1",
                       "token_file": os.path.join(tmp, "tok"), "label": "假机器"}],
            "thresholds": dict(DEFAULT_THRESHOLDS, fail_before_alert=2),
        }
        Path(tmp, "tok").write_text("faketoken")
        sent = []
        global send_feishu  # noqa: PLW0603
        real_send = send_feishu
        send_feishu = lambda t, b, dry=False: sent.append((t, b)) or True  # noqa: E731
        try:
            state_path = os.path.join(tmp, "state.json")
            run_once(cfg, state_path, dry=False, verbose=False)
            check("第 1 次失败不报（不吵人）", sent == [], str(sent))
            run_once(cfg, state_path, dry=False, verbose=False)
            check("第 2 次失败报「采不到」", len(sent) == 1 and "采不到" in sent[0][0], str(sent))
            check("报的是采不到，不是「资源正常」", "不代表机器正常" in sent[0][1], sent[0][1])
            state = read_state(state_path)
            check("状态里记了失败次数", state["ghost"]["fails"] == 2, json.dumps(state))
        finally:
            send_feishu = real_send

    print("== --check 不落状态 ==")
    with tempfile.TemporaryDirectory(dir="/tmp") as tmp:
        cfg = {
            "hosts": [{"id": "ghost2", "base": "http://127.0.0.1:1",
                       "token_file": os.path.join(tmp, "tok")}],
            "thresholds": dict(DEFAULT_THRESHOLDS),
        }
        Path(tmp, "tok").write_text("faketoken")
        state_path = os.path.join(tmp, "state.json")
        run_once(cfg, state_path, dry=True, verbose=False)
        check("--check 之后没有状态文件", not Path(state_path).exists())

    print(f"\n自检：通过 {ok} / 失败 {bad}")
    return 0 if bad == 0 else 1


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="资源越线告警（用只读运维接口取数）")
    ap.add_argument("--config", default=DEFAULT_CONFIG)
    ap.add_argument("--state", default=DEFAULT_STATE)
    ap.add_argument("--check", action="store_true", help="试跑：不落状态、不真发")
    ap.add_argument("--once", action="store_true", help="真跑一次（cron 用）")
    ap.add_argument("--test", action="store_true", help="故意发一条，验证告警链路")
    ap.add_argument("--quiet", action="store_true",
                    help="只在真发了消息或采集失败时输出（cron 用）")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)

    if a.selftest:
        return selftest()

    if a.test:
        cfg = load_config(a.config)
        names = "、".join(h.get("label", h["id"]) for h in cfg["hosts"])
        okk = send_feishu(
            "🔧 资源告警自检",
            f"这是自检消息，证明「资源越线 → 飞书」这条链路可用。\n"
            f"被监控：{names}\n阈值与冷却见 {a.config}\n"
            f"{now().strftime('%Y-%m-%d %H:%M')}",
        )
        print("自检消息已发出" if okk else "自检消息发送失败（检查 hermes send 这条链路）")
        return 0 if okk else 1

    cfg = load_config(a.config)
    if a.quiet:
        # cron 口径：没消息就一个字都不输出（日志里只剩"真发生过的事"）
        import io
        import contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = run_once(cfg, a.state, dry=a.check, verbose=True)
        text = buf.getvalue()
        if "发出 0 条" not in text or "采不到 0 台" not in text:
            sys.stdout.write(text)
        return rc
    return run_once(cfg, a.state, dry=a.check)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
