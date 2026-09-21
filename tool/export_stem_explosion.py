#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""B: 导出「同题干候选爆炸」清单。

真机日志证据（2026-09-13 12:43）：
  PARSE qLen=9 opts=4 q="这个标志是何含义？"
  MATCH candidates scored cand=243 passed=243 bestQ=100
  → 253 条题共用题干，答案各不相同，选项对不上，分数密集无赢家
  → 弹「请人工确认」，候选端出无关答案（陡坡）

口径：题干（去空白/标点归一后）在库中出现 >= THRESHOLD 次，即视为
「题干无区分度」，需要靠题图决胜。

只读，不写库。
"""
import json
import urllib.parse
import urllib.request
from collections import defaultdict

BASE = 'http://127.0.0.1:8799'
TOK = open('/tmp/admin_token').read().strip()
THRESHOLD = 30  # 同题干出现次数阈值
OUT_CSV = '/tmp/stem_explosion_worklist.csv'
OUT_MD = '/tmp/stem_explosion_worklist.md'


def api(path):
    req = urllib.request.Request(BASE + path, headers={'Authorization': 'Bearer ' + TOK})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode('utf-8'))


def norm_stem(q):
    """归一题干：去掉空白与常见标点，用于分组。"""
    import re
    s = re.sub(r'\s+', '', q or '')
    s = re.sub(r'[（）()【】\[\]？?。.、,，：:；;！!“”"\'’]', '', s)
    return s


def fetch_all():
    items = []
    cursor = None
    page = 0
    while True:
        path = '/admin/quiz/questions?limit=500'
        if cursor:
            path += '&cursor=' + urllib.parse.quote(str(cursor))
        d = api(path)
        qs = d.get('questions') or []
        if not qs:
            break
        items.extend(qs)
        page += 1
        cursor = d.get('nextCursor') or d.get('cursor')
        if not cursor:
            break
        if page > 60:
            break
    return items


def main():
    items = fetch_all()
    groups = defaultdict(list)
    for it in items:
        groups[norm_stem(it.get('question', ''))].append(it)

    exploded = {k: v for k, v in groups.items() if len(v) >= THRESHOLD}
    exploded = dict(sorted(exploded.items(), key=lambda kv: -len(kv[1])))

    report = {
        'totalQuestions': len(items),
        'threshold': THRESHOLD,
        'groupCount': len(exploded),
        'questionCountInGroups': sum(len(v) for v in exploded.values()),
        'groups': [],
    }
    for stem, v in exploded.items():
        answers = sorted({(x.get('correctAnswer') or '').strip() for x in v})
        withImage = sum(1 for x in v if x.get('image') or x.get('imagePerceptualHash'))
        report['groups'].append({
            'stemSample': (v[0].get('question') or '')[:60],
            'count': len(v),
            'distinctAnswers': len(answers),
            'withImage': withImage,
            'sampleIds': [x['id'] for x in v[:5]],
            'sampleAnswers': answers[:8],
        })

    print(json.dumps(report, ensure_ascii=False, indent=2))

    # 落盘可粘贴工单（CSV 逐题 + MD 概览），随仓库提交。
    import os
    os.makedirs('/tmp', exist_ok=True)
    with open(OUT_CSV, 'w', encoding='utf-8') as f:
        f.write('题干,题号,选项,答案,是否有图\n')
        for stem, v in exploded.items():
            for x in v:
                opts = '|'.join(x.get('options') or [])
                hasimg = '是' if (x.get('image') or x.get('imagePerceptualHash')) else '否'
                q = (x.get('question') or '').replace(',', '，')
                f.write(f'{q},{x["id"]},{opts},{x.get("correctAnswer") or ""},{hasimg}\n')

    with open(OUT_MD, 'w', encoding='utf-8') as f:
        f.write('# 同题干候选爆炸工单（题干无区分度 → 必须靠题图决胜）\n\n')
        f.write(f'- 题库总数：**{len(items)}**\n')
        f.write(f'- 同题干出现 >= {THRESHOLD} 次的组数：**{len(exploded)}**\n')
        f.write(f'- 落入这些组的题目总数：**{sum(len(v) for v in exploded.values())}**\n\n')
        for stem, v in exploded.items():
            answers = sorted({(x.get('correctAnswer') or '').strip() for x in v})
            withImage = sum(1 for x in v if x.get('image') or x.get('imagePerceptualHash'))
            f.write(f'## 题干：「{(v[0].get("question") or "")[:60]}」\n\n')
            f.write(f'- 题目数：**{len(v)}**\n')
            f.write(f'- 互斥答案种数：**{len(answers)}**\n')
            f.write(f'- 已配图：**{withImage}** / {len(v)}（**缺图 {len(v) - withImage} 条**）\n')
            f.write(f'- 答案样例：{"、".join(answers[:10])}\n')
            f.write(f'- 代表题号：{", ".join(x["id"] for x in v[:5])}\n\n')
    print(f'[已写入] {OUT_CSV}')
    print(f'[已写入] {OUT_MD}')


if __name__ == '__main__':
    main()
