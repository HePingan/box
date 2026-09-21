#!/usr/bin/env python3
"""算「图题池」分档：哪些题必须补图、哪些其实不用传图。

对应用户口径：「我不需要全部补图，只需要补无图判断不了的题」。

产出三档（见 references/quiz-image-upload-pipeline.md §1.1）：
  B1 冲突  — 同题干、答案有多个不同值  → 每条各配一张图（硬核，先做）
  B3 唯一  — 题干唯一、答案依赖图      → 需补图（建议做）
  B2 真重复 — 同题干、答案完全一致      → 归档重复即可，不用图

⚠️⚠️ 本脚本 = **这几个数字的唯一权威定义**（IMGKW 关键词表 + norm 去标点口径）。
文档里写的 1297 / 524 / 715 / 58 都是它跑出来的。**要交付给用户的条数必须用它重算**，
不要凭记忆里的关键词临时拼一个过滤器 —— 实测这样拼出过 645/138、1995/485 等
互不相同的数，跟原数对不上，会让用户白干。复现不了就停下来问，别凑数字。
（见 references/quiz-image-upload-pipeline.md §1.1.1）

必须在题库服务端跑（box 后端 127.0.0.1:8799，见 quiz-confirm-triage.md 说明）：
  ssh -i ~/.ssh/id_ed25519 hermes@47.109.97.1 'python3 -' < scripts/quiz_image_targeting.py

只读，不写任何数据。
"""
import collections
import json
import re
import urllib.request

BASE = "http://127.0.0.1:8799"

# 命中「这道题答案取决于图」的题干关键词（实测命中 1297/3533）
IMGKW = [
    "图中", "图上", "如图", "上图", "下图", "见图", "图片",
    "这辆", "该车", "此车", "标志", "手势", "仪表", "操纵装置",
    "标线", "红圈", "箭头", "指示灯", "标牌", "此标志", "这个标志", "路面",
]


def get(url):
    for _ in range(4):
        try:
            return json.loads(urllib.request.urlopen(url, timeout=40).read())
        except Exception:
            pass
    raise RuntimeError("fetch failed: " + url)


def dump_bank():
    """增量链拉全库 → {questionId: question}。"""
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
    """归一化题干：去标点/空白，用于分组。报数必须说明用了哪种口径。"""
    return re.sub(r"[，,。？?、\s（）()【】]", "", s or "")


def main():
    rows = dump_bank()
    pub = {k: v for k, v in rows.items() if v.get("status") == "published"}
    print("published:", len(pub))

    with_img = [(k, v) for k, v in pub.items() if v.get("image")]
    is_imgq = lambda v: any(w in (v.get("question") or "") for w in IMGKW)
    pool = [(k, v) for k, v in pub.items() if is_imgq(v) and not v.get("image")]

    print("已有图:", len(with_img))
    print("图题池（图题且无图）:", len(pool))

    groups = collections.defaultdict(list)
    for k, v in pool:
        groups[norm(v.get("question"))].append((k, v))

    b1, b2, b3 = [], [], []
    for stem, items in groups.items():
        if len(items) == 1:
            b3.append((stem, items))
            continue
        answers = {(v.get("correctAnswer") or "").strip() for _, v in items}
        (b1 if len(answers) > 1 else b2).append((stem, items))

    n_b1 = sum(len(i) for _, i in b1)
    n_b2 = sum(len(i) for _, i in b2)
    n_b3 = sum(len(i) for _, i in b3)

    print()
    print("B1 冲突（同题干不同答案）→ 必须补图: %d 条 / %d 组" % (n_b1, len(b1)))
    print("B3 唯一（题干唯一，答案依赖图）→ 建议补图: %d 条" % n_b3)
    print("B2 真重复（同题干答案一致）→ 归档即可，无需图: %d 条 / %d 组" % (n_b2, len(b2)))
    print()
    print("⇒ 硬核需补:", n_b1, " | 全部需上传:", n_b1 + n_b3)

    cat = collections.Counter()
    for _, v in pool:
        q = v.get("question") or ""
        if "标志" in q:
            cat["交通标志类"] += 1
        elif "手势" in q:
            cat["交警手势类"] += 1
        elif "仪表" in q or "指示灯" in q:
            cat["仪表/指示灯类"] += 1
        elif "标线" in q or "红圈" in q:
            cat["标线/箭头类"] += 1
        elif "操纵装置" in q:
            cat["操纵装置类"] += 1
        else:
            cat["情景/其他"] += 1
    print()
    for c, n in cat.most_common():
        print("  %s: %d" % (c, n))

    print()
    print("=== B1 冲突 TOP10（优先出工单）===")
    b1.sort(key=lambda x: -len(x[1]))
    for stem, items in b1[:10]:
        ans = len({(v.get("correctAnswer") or "").strip() for _, v in items})
        print("  %3d条 %2d答案 | %s" % (len(items), ans, items[0][1].get("question")[:40]))


if __name__ == "__main__":
    main()
