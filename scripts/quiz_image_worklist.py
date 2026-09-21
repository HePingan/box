#!/usr/bin/env python3
"""出「B1 冲突」补图工单 —— 逐条可照传。

口径 = quiz_image_targeting.py（同 IMGKW + 同 norm），**唯一权威定义**。
见 references/quiz-image-upload-pipeline.md §1.1 / §1.1.1。

产出（写到 /tmp）：
  b1_worklist.csv  一行一题：组号/组内序号/题号/题干/正确答案/选项
  b1_worklist.md   按组排版，供人逐组过

必须在服务端跑（box 后端 127.0.0.1:8799）：
  ssh -i ~/.ssh/id_ed25519 hermes@47.109.97.1 'python3 -' < scripts/quiz_image_worklist.py
只读题库，不写任何数据。
"""
import collections
import csv
import json
import re
import urllib.request

BASE = "http://127.0.0.1:8799"

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
    return re.sub(r"[，,。？?、\s（）()【】]", "", s or "")


def main():
    rows = dump_bank()
    pub = {k: v for k, v in rows.items() if v.get("status") == "published"}
    is_imgq = lambda v: any(w in (v.get("question") or "") for w in IMGKW)
    pool = [(k, v) for k, v in pub.items() if is_imgq(v) and not v.get("image")]

    groups = collections.defaultdict(list)
    for k, v in pool:
        groups[norm(v.get("question"))].append((k, v))

    b1 = []
    for stem, items in groups.items():
        if len(items) == 1:
            continue
        answers = {(v.get("correctAnswer") or "").strip() for _, v in items}
        if len(answers) > 1:
            b1.append((stem, items))
    b1.sort(key=lambda x: -len(x[1]))

    n_b1 = sum(len(i) for _, i in b1)
    print("B1 冲突: %d 条 / %d 组" % (n_b1, len(b1)))

    # ── CSV：一行一题 ──
    crows = []
    for gi, (stem, items) in enumerate(b1, 1):
        nans = len({(v.get("correctAnswer") or "").strip() for _, v in items})
        for ii, (qid, v) in enumerate(items, 1):
            crows.append({
                "组号": gi,
                "组内序号": "%d/%d" % (ii, len(items)),
                "题号": qid,
                "题干": (v.get("question") or "").replace("\n", " "),
                "正确答案": (v.get("correctAnswer") or "").replace("\n", " "),
                "选项": " | ".join(v.get("options") or []),
                "分组题干": stem,
                "组内条数": len(items),
                "组内答案种数": nans,
            })
    with open("/tmp/b1_worklist.csv", "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=list(crows[0].keys()))
        w.writeheader()
        w.writerows(crows)
    print("CSV:", len(crows), "行 → /tmp/b1_worklist.csv")

    # ── MD：按组 ──
    md = [
        "# 补图工单 — B1 冲突题（同题干多答案，无图不可判对错）",
        "",
        "口径 = `scripts/quiz_image_targeting.py`（IMGKW + norm），与服务端实测一致。",
        "总计 **%d** 条 / **%d** 组。" % (n_b1, len(b1)),
        "",
        "> 逐张找图后，按「题号」在管理面板补图。"
        "**别裁、别加白边、别留边框**（唯二破坏 dHash 的操作）；"
        "水印/尺寸/格式/压缩无所谓。",
        "",
    ]
    for gi, (stem, items) in enumerate(b1, 1):
        nans = len({(v.get("correctAnswer") or "").strip() for _, v in items})
        md.append("## 第 %d 组 · %d 条 · %d 种答案" % (gi, len(items), nans))
        md.append("**题干**：%s" % (items[0][1].get("question") or ""))
        md.append("")
        md.append("| # | 题号 | 正确答案 |")
        md.append("|---|---|---|")
        for ii, (qid, v) in enumerate(items, 1):
            md.append("| %d | `%s` | %s |" % (
                ii, qid, (v.get("correctAnswer") or "").replace("|", "/")))
        md.append("")
    open("/tmp/b1_worklist.md", "w", encoding="utf-8").write("\n".join(md))
    print("MD: %d 行 → /tmp/b1_worklist.md" % len(md))

    json.dump({"count": n_b1, "groups": len(b1),
               "items": [{"id": r["题号"], "question": r["题干"],
                          "answer": r["正确答案"], "group": r["组号"]} for r in crows]},
              open("/tmp/b1_worklist.json", "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
