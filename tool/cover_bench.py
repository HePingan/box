#!/usr/bin/env python3
"""封面加载测速工具 — 直连源站 vs shuabu 代理，逐源实测。

用途
    判断某个采集源的封面该直连还是走代理。多数商业采集源自带 CDN，
    直连最快；只有少数源代理才略快。用真实数字决策，别凭猜测改全局开关。

背景
    app 现状是 mediaEnabled=false（全局直连），经实测对大多数源是最优。
    封面提速的真功臣是客户端解码限尺寸(200px)+首屏预取，对所有源生效。
    要给个别源单独挂代理，正确做法是按 host 建白名单（见
    lib/video/config/video_proxy_config.dart 的 _directVodApiHosts 模式）。

运行
    python3 tool/cover_bench.py            # 打印结果表
    python3 tool/cover_bench.py --save     # 额外写 tool/cover_bench_result.md

读数
    直连s/代理s 取 2 次最优。"建议"列 = 直连(最优) 或 代理快Nx。
    注意：这是运行机器的网络视角(境内服务器)，真机(移动网络/跨境)体感
    可能不同。判定慢源以真机为准，服务器测速仅作初筛。
"""
import json, urllib.request, urllib.parse, time, ssl, sys, datetime
from concurrent.futures import ThreadPoolExecutor, as_completed

SAVE = "--save" in sys.argv

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

UA = {"User-Agent": "okhttp/4.9.2"}
PROXY = "https://proxy.shuabu.eu.org/?url="


def fetch_json(url, timeout=8):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
        return json.loads(r.read().decode("utf-8", "ignore"))


def timed_get(url, timeout=8):
    req = urllib.request.Request(url, headers=UA)
    t = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            data = r.read()
            return time.time() - t, len(data), r.status
    except Exception as e:
        return time.time() - t, 0, f"ERR:{type(e).__name__}"


def best(url, n=2, timeout=8):
    return min(timed_get(url, timeout)[0] for _ in range(n))


_catreq = urllib.request.Request(
    "https://proxy.shuabu.eu.org?format=0&source=jin18", headers=UA)
cat = json.load(urllib.request.urlopen(_catreq, timeout=15, context=ctx))
sites = cat["api_site"]
print(f"共 {len(sites)} 个源\n", flush=True)


def probe(item):
    host, meta = item
    name = meta["name"]
    api = meta["api"]
    try:
        d = fetch_json(api + "?ac=detail&pg=1", timeout=8)
        lst = d.get("list", [])
        pic = None
        for it in lst:
            p = (it.get("vod_pic") or "").strip()
            if p.startswith("http"):
                pic = p
                break
        if not pic:
            return (name, host, "无封面URL", None, None, None)
    except Exception as e:
        return (name, host, f"接口失败:{type(e).__name__}", None, None, None)
    direct = best(pic)
    dstat = timed_get(pic)[2]
    prox = best(PROXY + urllib.parse.quote(pic, safe=''))
    picdom = urllib.parse.urlparse(pic).netloc
    return (name, host, picdom, round(direct, 3), round(prox, 3), dstat)


results = []
with ThreadPoolExecutor(max_workers=8) as ex:
    futs = {ex.submit(probe, it): it for it in sites.items()}
    for f in as_completed(futs, timeout=120):
        try:
            results.append(f.result())
        except Exception as e:
            results.append(("?", "?", f"probe错误:{e}", None, None, None))

# 排序：可测的按直连耗时；不可测的沉底
ok = [r for r in results if r[3] is not None]
bad = [r for r in results if r[3] is None]
ok.sort(key=lambda r: r[3])

print(f"{'源名':<18}{'直连s':>8}{'代理s':>8}  {'状态':<10} 建议", flush=True)
print("-" * 74, flush=True)
for name, host, picdom, d, p, st in ok:
    rec = "直连(最优)" if d <= p else f"代理快{round(d/p,1)}x"
    print(f"{name:<18}{d:>8}{p:>8}  {str(st):<10} {rec:<12} {picdom}", flush=True)
print("\n=== 不可测(死源/无封面) ===", flush=True)
for name, host, msg, *_ in bad:
    print(f"{name:<18} {msg}", flush=True)

if SAVE:
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    lines = [
        "# 封面测速结果",
        "",
        f"生成时间：{ts}（运行机器网络视角，真机体感可能不同）",
        "",
        "| 源名 | 直连s | 代理s | 状态 | 建议 | 图床域名 |",
        "|---|---|---|---|---|---|",
    ]
    for name, host, picdom, d, p, st in ok:
        rec = "直连(最优)" if d <= p else f"代理快{round(d/p,1)}x"
        lines.append(f"| {name} | {d} | {p} | {st} | {rec} | {picdom} |")
    lines += ["", "## 不可测(死源/无封面)", ""]
    for name, host, msg, *_ in bad:
        lines.append(f"- {name}：{msg}")
    out = "/root/box/tool/cover_bench_result.md"
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"\n已写入 {out}", flush=True)
