#!/usr/bin/env python3
"""刷新 AI HOT 的「真实响应快照」夹具，并报告它与客户端假设的差异。

背景（这个脚本为什么存在）：353 发出去的修复里，最贵的那一步不是改代码，
而是发现**客户端的主机白名单写的是接口主机、上游给的却是另一个域名** ——
测试里那份「真实 permalink」是人手写的，真实响应里从来没有过那个地址，
于是用例永远绿、功能永远是坏的。所以夹具必须**从上游抓**，而且抓完要
自动跟客户端的假设对一遍。

用法：
  python3 tool/refresh_ai_hot_fixture.py            # 抓上游 → 重写夹具 → 打报告
  python3 tool/refresh_ai_hot_fixture.py --check    # 不写盘；夹具与上游不一致时退出码 1
  python3 tool/refresh_ai_hot_fixture.py --fixture <路径>

只依赖标准库。网络不可达时退出码 2（不写盘）。
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FIXTURE = REPO / "test/fixtures/ai_hot_selected_v1.json"
POLICY = REPO / "lib/daily_news_url_policy.dart"
MODELS = REPO / "lib/features/home/data/ai_hot_models.dart"
ITEMS_URL = "https://aihot.news/api/v1/items?mode=selected&window=7d&limit=50"
UA = "Mozilla/5.0 (Linux; Android 13; box-fixture-refresh)"


def fetch(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=25) as resp:
        return json.loads(resp.read().decode("utf-8"))


def allowed_hosts() -> set[str]:
    """从 lib/daily_news_url_policy.dart 的 allowedHosts 块里取主机名（文本匹配）。

    文本匹配是刻意的：这里只用来「提示」，真正的判据在 tool/check_ai_hot_live.dart
    （那边直接用客户端自己的类）。宁可漏报，不误报。
    """
    src = POLICY.read_text(encoding="utf-8")
    m = re.search(r"allowedHosts\s*=\s*\{(.*?)\};", src, re.S)
    if not m:
        return set()
    return set(re.findall(r"'([A-Za-z0-9.-]+)'", m.group(1)))


def labelled_categories() -> set[str]:
    """从 categoryLabel 的 switch 里取已经写好中文名的分类。"""
    src = MODELS.read_text(encoding="utf-8")
    m = re.search(r"String get categoryLabel \{(.*?)\n  \}", src, re.S)
    if not m:
        return set()
    return set(re.findall(r"case '([^']+)'", m.group(1)))


def pick_items(items: list[dict]) -> list[dict]:
    """每个分类留一条（按分类名排序，保证两次抓取顺序稳定）。"""
    by_cat: dict[str, dict] = {}
    for it in items:
        cat = it.get("category") or "(无分类)"
        by_cat.setdefault(cat, it)
    return [by_cat[k] for k in sorted(by_cat)]


def build_fixture(payload: dict) -> dict:
    return {
        "schemaVersion": payload.get("schemaVersion"),
        "source": ITEMS_URL,
        "note": "真实响应快照（tool/refresh_ai_hot_fixture.py 生成；每个分类一条，字段字节未改）",
        "items": pick_items(payload.get("items") or []),
    }


def report(new: dict, old: dict | None) -> list[str]:
    lines: list[str] = []
    items = new["items"]

    hosts = sorted({(it.get("links") or {}).get("aihot", "").split("/")[2] for it in items if (it.get("links") or {}).get("aihot")})
    missing_hosts = [h for h in hosts if h not in allowed_hosts()]
    lines.append(f"条目页主机: {', '.join(hosts) or '(无)'}")
    lines.append(
        "  白名单: " + ("✅ 都在" if not missing_hosts else f"❌ 缺 {missing_hosts} — 点开会被判成站外（353 就是这个 bug）")
    )

    cats = sorted({it.get("category") or "(无分类)" for it in items})
    missing_cats = [c for c in cats if c not in labelled_categories() and c != "(无分类)"]
    lines.append(f"分类: {', '.join(cats)}")
    lines.append(
        "  中文标签: " + ("✅ 都有" if not missing_cats else f"❌ 缺 {missing_cats} — 界面上会直接显示英文 slug")
    )

    keys = sorted({k for it in items for k in it})
    if old:
        old_keys = sorted({k for it in old.get("items") or [] for k in it})
        added = [k for k in keys if k not in old_keys]
        gone = [k for k in old_keys if k not in keys]
        lines.append(f"条目字段: {len(keys)} 个" + (f"；新增 {added}" if added else "") + (f"；消失 {gone}" if gone else ""))
        old_cats = sorted({it.get('category') or '(无分类)' for it in old.get("items") or []})
        if old_cats != cats:
            lines.append(f"  分类集合变化: 旧 {old_cats} → 新 {cats}")
    else:
        lines.append(f"条目字段: {', '.join(keys)}")
    return lines


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fixture", type=Path, default=FIXTURE)
    ap.add_argument("--check", action="store_true", help="不写盘；夹具与上游不一致时退出码 1")
    args = ap.parse_args()

    old = None
    if args.fixture.exists():
        old = json.loads(args.fixture.read_text(encoding="utf-8"))

    try:
        payload = fetch(ITEMS_URL)
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        print(f"[跳过] 上游不可达（{exc}）；未改动夹具。", file=sys.stderr)
        return 2

    new = build_fixture(payload)
    if not new["items"]:
        print("[失败] 上游返回 0 条，不覆盖夹具（避免把夹具清空）。", file=sys.stderr)
        return 2

    body = json.dumps(new, ensure_ascii=False, indent=1) + "\n"
    changed = old is None or json.dumps(old, ensure_ascii=False, indent=1) != json.dumps(new, ensure_ascii=False, indent=1)

    for line in report(new, old):
        print(line)
    print(f"夹具: {args.fixture.relative_to(REPO)} — {'需要更新' if changed else '与上游一致'}")

    if args.check:
        return 1 if changed else 0

    if changed:
        args.fixture.parent.mkdir(parents=True, exist_ok=True)
        args.fixture.write_text(body, encoding="utf-8")
        # 落盘后回读校验：写坏夹具比不写更糟。
        back = json.loads(args.fixture.read_text(encoding="utf-8"))
        assert back == new, "夹具回读与写入不一致"
        print("已写入。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
