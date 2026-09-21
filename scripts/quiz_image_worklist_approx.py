#!/usr/bin/env python3
"""出「B1 冲突」补图工单（**近似口径**，用户拍板「并进」）。

口径 = quiz_image_conflict_approx.py 的 B 分组（norm + OCR 残缺归一）。
比严格口径多捞「OCR 丢了判断/这辆/该/此」导致的近似题干冲突。

与 quiz_image_worklist.py（严格口径）并列存在，两者都只读不写。
用户拍板「并进」后，**本脚本的产出才是当前权威工单**。

产出（写到 /tmp）：
  b1_worklist_approx.csv  一行一题：组号/组内序号/题号/题干/正确答案/选项
  b1_worklist_approx.md   按组排版，供人逐组过

必须在服务端跑：
  ssh -i ~/.ssh/id_ed25519 hermes@47.109.97.1 'python3 -' < scripts/quiz_image_worklist_approx.py
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

# OCR 残缺归一：与 quiz_image_conflict_approx.py 保持一致（唯一事实源）。
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
    return re.sub(r"[，,。？?、\s（）()【】]", "", s or "")


def approx_key(s):
    t = norm(s)
    for pat, rep in OCR_FIX:
        t = re.sub(pat, rep, t)
    return t


def main():
    rows = dump_bank()
    # 冲突池 = published + 人工标记为问题题（incomplete）。
    # 标记不改变「它属于这组冲突」这一事实，只是给它挂了个待处理标记，
    # 故工单必须仍收进来，否则一标记就从工单上消失、图就永远补不上。
    live = {k: v for k, v in rows.items()
            if v.get("status") in ("published", "incomplete")}
    is_imgq = lambda v: any(w in (v.get("question") or "") for w in IMGKW)
    pool = [(k, v) for k, v in live.items() if is_imgq(v) and not v.get("image")]
    flagged = {k for k, v in live.items() if v.get("status") == "incomplete"}
    print("published+flagged:", len(live), "| 图题无图:", len(pool),
          "| 其中已标记问题题:", len(flagged))

    groups = collections.defaultdict(list)
    for k, v in pool:
        groups[approx_key(v.get("question"))].append((k, v))

    b1 = []
    for stem, items in groups.items():
        if len(items) < 2:
            continue
        answers = {(v.get("correctAnswer") or "").strip() for _, v in items}
        if len(answers) > 1:
            b1.append((stem, items))
    b1.sort(key=lambda x: -len(x[1]))

    n_b1 = sum(len(i) for _, i in b1)
    n_ans = sum(len({(v.get("correctAnswer") or "").strip() for _, v in i}) for _, i in b1)
    print("B1 冲突（近似口径）: %d 条 / %d 组 / %d 种答案" % (n_b1, len(b1), n_ans))

    # ── CSV ──
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
                "已标记问题题": "是" if qid in flagged else "",
            })
    with open("/tmp/b1_worklist_approx.csv", "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=list(crows[0].keys()))
        w.writeheader()
        w.writerows(crows)
    print("CSV:", len(crows), "行 → /tmp/b1_worklist_approx.csv")

    # ── MD ──
    md = [
        "# 补图工单 — B1 冲突题（近似口径 · 用户拍板「并进」）",
        "",
        "口径 = `scripts/quiz_image_worklist_approx.py`"
        "（IMGKW + norm + OCR 残缺归一），与 `quiz_image_conflict_approx.py` 的 B 分组一致。",
        "总计 **{N}** 条 / **{G}** 组 / **{A}** 种答案。".format(
            N=n_b1, G=len(b1), A=n_ans),
        "",
        "> 逐张找图后，按「题号」在管理面板补图。",
        "**别裁、别加白边、别留边框**（唯二破坏 dHash 的操作）；",
        "水印/尺寸/格式/压缩无所谓。",
        "",
    ]
    for gi, (stem, items) in enumerate(b1, 1):
        nans = len({(v.get("correctAnswer") or "").strip() for _, v in items})
        md.append("## 第 %d 组 · %d 条 · %d 种答案" % (gi, len(items), nans))
        md.append("**题干**：%s" % (items[0][1].get("question") or ""))
        md.append("")
        md.append("| # | 题号 | 正确答案 | 已标记 |")
        md.append("|---|---|---|---|")
        for ii, (qid, v) in enumerate(items, 1):
            md.append("| %d | `%s` | %s | %s |" % (
                ii, qid, (v.get("correctAnswer") or "").replace("|", "/"),
                "⚑" if qid in flagged else ""))
        md.append("")
    open("/tmp/b1_worklist_approx.md", "w", encoding="utf-8").write("\n".join(md))
    print("MD: %d 行 → /tmp/b1_worklist_approx.md" % len(md))

    json.dump({"count": n_b1, "groups": len(b1), "answers": n_ans,
               "items": [{"id": r["题号"], "question": r["题干"],
                          "answer": r["正确答案"], "group": r["组号"]} for r in crows]},
              open("/tmp/b1_worklist_approx.json", "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
