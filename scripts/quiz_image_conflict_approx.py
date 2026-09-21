#!/usr/bin/env python3
"""算「近似题干」口径下的 B1 冲突集 —— 复现 + 对照。

背景：逐字精确分组（quiz_image_targeting.py 的 norm）会漏掉 OCR 残缺造成的
近似题干。实测案例：同一张情景图被录成 6 道题、题干 4 种写法，
其中「请一下，」「请图中」是 OCR 丢了「判断」。

本脚本对比两种分组：
  A. 严格（现有口径）：norm 去标点后逐字相同
  B. 近似（新口径）：norm 后再做 OCR 残缺归一 + 相似度聚类
报出差值，供用户拍板。

只读题库，不写任何数据。
  ssh -i ~/.ssh/id_ed25519 hermes@47.109.97.1 'python3 -' < scripts/quiz_image_conflict_approx.py
"""
import collections
import difflib
import json
import re
import urllib.request

BASE = "http://127.0.0.1:8799"

IMGKW = [
    "图中", "图上", "如图", "上图", "下图", "见图", "图片",
    "这辆", "该车", "此车", "标志", "手势", "仪表", "操纵装置",
    "标线", "红圈", "箭头", "指示灯", "标牌", "此标志", "这个标志", "路面",
]

# OCR 残缺归一：把实测到的残缺写法收敛回标准写法。
# 全部来自真实题库样本，不凭空造。
OCR_FIX = [
    (r"^请一下", "请判断一下"),        # 「请一下，…」丢了「判断」
    (r"^请图中", "请判断图中"),        # 「请图中…」丢了「判断」
    (r"^请判断一下图中", "请判断图中"),  # 「一下」可有可无
    (r"^请判断一下，图中", "请判断图中"),
    (r"这辆", ""), (r"该", ""), (r"此", ""),   # 这/该/此 混用
]


def get(url):
    for _ in range(4):
        try:
            return json.loads(urllib.request.urlopen(url, timeout=40).read())
        except Exception:
            pass
    raise RuntimeError("fetch failed: " + url)


def dump_bank():
    rows, cursor = {}, 0
    for _ in range(200):
        d = get("%s/api/quiz/sync?cursor=%d&limit=300" % (BASE, cursor))
        for ch in d.get("changes") or []:
            q = ch.get("question")
            if isinstance(q, str):
                try:
                    q = json.loads(q)
                except Exception:
                    q = None
            if isinstance(q, dict):
                rows[q.get("questionId") or ch.get("questionId")] = q
        if not d.get("hasMore"):
            break
        cursor = d.get("nextCursor", cursor)
    return rows


def norm(s):
    """严格口径：去标点空白（与 quiz_image_targeting.py 一致）。"""
    return re.sub(r"[，,。？?、\s（）()【】]", "", s or "")


def approx_key(s):
    """近似口径：norm + OCR 残缺归一。"""
    t = norm(s)
    for pat, rep in OCR_FIX:
        t = re.sub(pat, rep, t)
    return t


def conflict_groups(pool, keyfn):
    groups = collections.defaultdict(list)
    for k, v in pool:
        groups[keyfn(v.get("question"))].append((k, v))
    out = []
    for stem, items in groups.items():
        if len(items) < 2:
            continue
        ans = {(v.get("correctAnswer") or "").strip() for _, v in items}
        if len(ans) > 1:
            out.append((stem, items))
    return out


def main():
    rows = dump_bank()
    pub = {k: v for k, v in rows.items() if v.get("status") == "published"}
    is_imgq = lambda v: any(w in (v.get("question") or "") for w in IMGKW)
    pool = [(k, v) for k, v in pub.items() if is_imgq(v) and not v.get("image")]
    print("published:", len(pub), "| 图题无图:", len(pool))
    print()

    A = conflict_groups(pool, norm)
    B = conflict_groups(pool, approx_key)
    nA = sum(len(i) for _, i in A)
    nB = sum(len(i) for _, i in B)
    print("A 严格口径（现有工单）: %d 条 / %d 组" % (nA, len(A)))
    print("B 近似口径（新）      : %d 条 / %d 组" % (nB, len(B)))
    print("差值                  : +%d 条 / +%d 组" % (nB - nA, len(B) - len(A)))
    print()

    a_ids = {k for _, items in A for k, _ in items}
    b_ids = {k for _, items in B for k, _ in items}
    new_ids = b_ids - a_ids
    print("=== 近似口径新捞出来的 %d 条（严格口径漏掉的）===" % len(new_ids))
    for k, v in sorted(existing_new(pool, new_ids)):
        print("  %-16s | %-42s | %s" % (k, (v.get("question") or "")[:42],
                                         v.get("correctAnswer")))
    print()

    B.sort(key=lambda x: -len(x[1]))
    print("=== 近似口径 TOP10 ===")
    for stem, items in B[:10]:
        ans = len({(v.get("correctAnswer") or "").strip() for _, v in items})
        print("  %3d条 %2d答案 | %s" % (len(items), ans, stem[:44]))

    json.dump({"A": {"items": nA, "groups": len(A)},
               "B": {"items": nB, "groups": len(B)},
               "new_ids": sorted(new_ids)},
              open("/tmp/approx_delta.json", "w"), ensure_ascii=False, indent=1)


def existing_new(pool, ids):
    d = dict(pool)
    return [(k, d[k]) for k in ids if k in d]


if __name__ == "__main__":
    main()
