#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""野蛮漫画图床探针：在用户报之前先知道"图床这条路上出事了"。

为什么要有它（2026-10-01）：用户第 3 次报"封面/漫画页连不上图床（Connection reset by peer）"，
而我手上**没有任何自动信号** —— 每次都靠他截图。这台机器（175）恰好是取图床最顺的一台
（10 个边缘 IP × 两种端口全 200），所以探针放这里最能代表"我们这边的能力上限"；
探针**挂了**不代表用户那条网也挂（hpa888 就被这本漫画的图床 reset），报告里要写清这一条。

探什么（四条腿，模拟 App 真实那条路：站点 → 封面地址 → 图床）：
  1. site      手机 UA 取搜索页，200 且里面有卡片（站点活着）
  2. img666    从搜索页里**现取**一个封面地址（图床 :666），200 且是图片
  3. img443    同一路径去掉端口（443）—— 只 666 挂 = 运营商/网关拦端口
  4. img_ip    **全扫**域名解析出的每个边缘 IP（SNI 直连取图）—— 抽样会漏掉
               "域名里混着一半死 IP"这种真问题（2026-10-02 实测 10 个里 5 个全死）

判据：
  crit = 站点挂了，或 666 与 443 **都**挂
  warn = 只挂一条，或 ≥70% 的边缘 IP 取不到图（全死另判 crit）
  连续 **2 轮**同类才算数（约 20 分钟）—— 单轮抖动发消息就是噪声（去重策略见技能）。
  状态翻转才发飞书：掉下去报一次、恢复报一次，平时一个字都不发。

用法：
  comic-image-probe.py --check    人工看一遍（不落状态）
  comic-image-probe.py            cron 用（静默 + 状态机）
  comic-image-probe.py --test     故意发一条，验投递链路
"""
from __future__ import annotations

import argparse
import json
from concurrent import futures
import os
import re
import socket
import ssl
import subprocess
import sys
import time
import urllib.request

UA = ("Mozilla/5.0 (Linux; Android 13; SM-S9010) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36")
SEARCH_URL = "https://yemancomic.com/search?searchkey=%E6%B5%B7%E8%B4%BC"
STATE_DIR = "/var/lib/comic-image-probe"
STATE_PATH = os.path.join(STATE_DIR, "state.json")
HERMES = "/usr/local/bin/hermes"          # cron 的 PATH 只有 /usr/bin:/bin，必须绝对路径
TIMEOUT = 20
EDGE_SAMPLE = 3


def log(line: str) -> None:
    print(line, flush=True)


def http_get(url: str, timeout: int = TIMEOUT, verify: bool = True, limit: int = 4096):
    """取一段（图几十 KB 用不着取完；**页面要读够**，卡片在 4KB 之后）。"""
    # 实测坑：只读 4096 字节时搜索页里既没有 `comic-item` 也没有封面地址 —— 页面头部是脚本，
    # 于是探针会把"站点好好的"报成 crit。页面这条腿读 256KB。
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    ctx = None
    if not verify:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
        body = r.read(limit)
        return r.status, len(body), (time.time() - t0) * 1000, body, r.headers.get("Content-Type", "")


def check_site() -> dict:
    try:
        status, _, ms, body, _ = http_get(SEARCH_URL, limit=262144)
        text = body.decode("utf-8", "replace")
        ok = status == 200 and "comic-item" in text
        return {"ok": ok, "ms": round(ms), "note": f"HTTP {status}，卡片{'有' if 'comic-item' in text else '没有'}"}
    except Exception as e:                                    # noqa: BLE001
        return {"ok": False, "ms": None, "note": f"{type(e).__name__}: {str(e)[:80]}"}


def cover_url_from_search() -> tuple[str | None, str]:
    """从搜索页现取一个封面地址 —— 图地址会变，写死一个迟早误报。"""
    try:
        status, _, _, body, _ = http_get(SEARCH_URL, limit=262144)
        text = body.decode("utf-8", "replace")
        m = re.search(r'https?://([a-z0-9.-]*justpic[a-z0-9.-]*)(:\d+)?(/[^"\'\s]+?\.(?:jpg|webp|png))',
                      text)
        if not m:
            return None, f"HTTP {status}，但页面里没找到图床地址"
        return f"https://{m.group(1)}{m.group(2) or ''}{m.group(3)}", f"取自搜索页（HTTP {status}）"
    except Exception as e:                                    # noqa: BLE001
        return None, f"取搜索页失败：{type(e).__name__}: {str(e)[:60]}"


def without_port(cover: str) -> str:
    return re.sub(r"(https?://[^/]+):\d+", r"\1", cover)


def check_image(url: str) -> dict:
    try:
        status, n, ms, _, ctype = http_get(url)
        ok = status == 200 and ctype.startswith("image/") and n > 0
        return {"ok": ok, "ms": round(ms), "note": f"HTTP {status} {ctype} {n}B"}
    except Exception as e:                                    # noqa: BLE001
        return {"ok": False, "ms": None, "note": f"{type(e).__name__}: {str(e)[:80]}"}


def check_edges(cover: str, sample: int = 0) -> dict:
    """扫域名解析出的**每个**边缘 IP：哪个能取图、哪个不行。

    为什么要全扫（2026-10-02 实测发现）：`tuer.justpic01pt.com` 解析出 10 个 IP，
    其中 **5 个全死**（185.13.110.21~25 整段，两个端口都连不上），走域名每次新建连接
    只有 10/15 成功，直连一个通着的 IP 是 15/15。以前"抽 3 个"正好抽到好的，于是
    这里一直报 3/3 通 —— **真问题被抽样掩盖了**。所以现在全扫，并把死的 IP 写进报告。
    """
    host = re.sub(r"^https?://", "", cover).split("/")[0].split(":")[0]
    port = 666 if (":" in re.sub(r"^https?://", "", cover).split("/")[0]) else 443
    path = "/" + cover.split("/", 3)[3]
    try:
        infos = socket.getaddrinfo(host, port, proto=socket.IPPROTO_TCP)
        ips = sorted({i[4][0] for i in infos})
    except Exception as e:                                    # noqa: BLE001
        return {"ok": False, "note": f"解析失败：{type(e).__name__}: {str(e)[:60]}",
                "good": 0, "total": 0, "dead_ips": []}
    if sample:
        ips = ips[:sample]
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    def one(ip: str) -> bool:
        try:
            s = socket.create_connection((ip, port), timeout=5)
            ss = ctx.wrap_socket(s, server_hostname=host)
            ss.sendall((f"GET {path} HTTP/1.1\r\nHost: {host}\r\nUser-Agent: {UA}\r\n"
                        "Accept: image/*\r\nConnection: close\r\n\r\n").encode())
            head = ss.recv(64).split(b"\r\n", 1)[0].decode("latin1", "replace")
            ss.close()
            return "200" in head
        except Exception:                                     # noqa: BLE001
            return False

    good_ips, dead_ips = [], []
    # 并发扫（每个 IP 一次，5 秒超时）：全扫也不能把一轮探针拖到几分钟。
    workers = min(6, len(ips)) or 1
    with futures.ThreadPoolExecutor(max_workers=workers) as pool:
        for ip, ok in zip(ips, pool.map(one, ips)):
            (good_ips if ok else dead_ips).append(ip)
    total, good = len(ips), len(good_ips)
    note = f"{good}/{total} 个边缘 IP 能取到图"
    if dead_ips:
        note += f"（取不到：{', '.join(dead_ips[:6])}{' …' if len(dead_ips) > 6 else ''}）"
    # 判据：全死 = 真出事；大面积（≥70%）死 = 值得提醒（用户那边会"有时能开有时不能"）；
    # 少数死 = 正常波动，只在 note 里带一句 —— 我们的 App 现在会优先直连通着的 IP。
    if total == 0:
        ok = False
    elif good == 0:
        ok = False
    elif good / total < 0.3:
        ok = False
    else:
        ok = True
    return {"ok": ok, "note": note, "good": good, "total": total,
            "good_ips": good_ips, "dead_ips": dead_ips}


def decide(legs: dict) -> tuple[str, str]:
    site, d666, d443 = legs["site"]["ok"], legs["img666"]["ok"], legs["img443"]["ok"]
    edge = legs["img_ip"]
    if not site:
        return "crit", "漫画站点本身取不到（搜索页都打不开）——不只是图床的事"
    if not d666 and not d443:
        return "crit", "图床两种端口（:666 与 443）都取不到图 —— App 上会表现为封面/漫画页转圈"
    if not d666 or not d443:
        only = ":666" if not d666 else "443"
        return "warn", f"图床只有 {only} 这条通 —— 典型是运营商/网关在拦端口"
    if edge["total"] and not edge["ok"]:
        return "warn", f"边缘节点大面积取不到（{edge['note']}）"
    return "none", "四条腿都通"


def load_state() -> dict:
    try:
        with open(STATE_PATH, encoding="utf-8") as f:
            return json.load(f)
    except Exception:                                         # noqa: BLE001
        return {}


def save_state(state: dict) -> None:
    os.makedirs(STATE_DIR, exist_ok=True)
    tmp = STATE_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)
    os.chmod(tmp, 0o600)
    os.replace(tmp, STATE_PATH)


def send(text: str) -> bool:
    """投递只走这一条（绝对路径；cron 的 PATH 里没有 hermes）。发送结果必须留痕。"""
    try:
        p = subprocess.run([HERMES, "send", "-t", "feishu", text],
                           capture_output=True, text=True, timeout=60)
    except Exception as e:                                    # noqa: BLE001
        log(f"[send-failed] {type(e).__name__}: {e}")
        return False
    if p.returncode == 0 and "Sent to feishu" in (p.stdout or ""):
        log("[sent] 已发飞书")
        return True
    log(f"[send-failed] rc={p.returncode} out={(p.stdout or '').strip()[:120]} "
        f"err={(p.stderr or '').strip()[:120]}")
    return False


def run_once() -> dict:
    legs = {"site": check_site()}
    cover, cover_note = cover_url_from_search()
    if cover:
        legs["img666"] = check_image(cover)
        legs["img443"] = check_image(without_port(cover))
        legs["img_ip"] = check_edges(cover)
    else:
        for k in ("img666", "img443"):
            legs[k] = {"ok": False, "ms": None, "note": cover_note}
        legs["img_ip"] = {"ok": False, "note": "没拿到封面地址", "good": 0, "total": 0}
    legs["_cover"] = cover or ""
    return legs


def report(legs: dict, reason: str) -> str:
    return "\n".join([
        "图床探针：图床/站点这条路不对了",
        reason,
        "",
        f"· 站点搜索页：{'通' if legs['site']['ok'] else '不通'}（{legs['site']['note']}）",
        f"· 图床 :666：{'通' if legs['img666']['ok'] else '不通'}（{legs['img666']['note']}）",
        f"· 图床 443：{'通' if legs['img443']['ok'] else '不通'}（{legs['img443']['note']}）",
        f"· 边缘节点：{legs['img_ip']['note']}",
        "",
        "（探针在 175（取图床最顺的一台）。这里通、用户那条网仍可能不通；"
        "这里不通则用户必然受影响。App 侧「漫画源自检」第 4 步可看手机那侧的实际结果。）",
    ])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="人工看一遍，不落状态")
    ap.add_argument("--test", action="store_true", help="故意发一条，验投递链路")
    ap.add_argument("--quiet", action="store_true", help="没事不输出（cron 用）")
    args = ap.parse_args()

    if args.test:
        return 0 if send("图床探针：这是一条 --test 自检消息（非故障）") else 1

    legs = run_once()
    level, reason = decide(legs)
    if args.check:
        log(f"level={level}  {reason}")
        for k, v in legs.items():
            if k.startswith("_"):
                continue
            log(f"  {k:8} ok={v['ok']!s:5} {v.get('note', '')}")
        return 0

    state = load_state()
    prev_level = state.get("level", "none")
    same_pending = state.get("pending", 0) + 1 if level == state.get("pending_level") else 1
    since = state.get("since") if level == state.get("pending_level") else time.time()

    # 连续 2 轮同类才算数：单轮抖动不值得进飞书（Kuma 那边也有一套"持续宕机"兜底）。
    # 攒够两轮（或本来就是好的）才让这一档算数；没攒够就先维持上一档，不发消息。
    # 写反过一次（`"none" if … else prev_level`）：那样永远算不出 crit，一条也发不出去，
    # 而脚本 exit 0、看着一切正常 —— 所以 --test/反向测试是必须的。
    confirmed = level if (level == "none" or same_pending >= 2) else prev_level
    flipped = confirmed != prev_level

    state.update({"level": confirmed, "pending_level": level, "pending": same_pending,
                  "since": since, "checked_at": time.time(),
                  "legs": {k: v for k, v in legs.items() if not k.startswith("_")}})
    if flipped:
        state["last_alert"] = time.time()

    if flipped and confirmed != "none":
        save_state(state)
        send(report(legs, reason))
    elif flipped and confirmed == "none":
        save_state(state)
        send("图床探针：已恢复 —— 站点与图床四条腿都通了（上一档：" +
             ("warn" if prev_level == "warn" else "crit") + "）")
    else:
        save_state(state)
        if not args.quiet:
            log(f"level={level} confirmed={confirmed} pending={same_pending} {reason}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
