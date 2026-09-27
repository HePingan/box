# -*- coding: utf-8 -*-
"""静默失败定向扫描：只找"写/网络/持久化路径上吞掉异常"的候选。

判据收窄：catch 所在函数里出现"返回成功/true/正常提示"这类信号，才是用户可见的静默失败。
输出紧凑表：文件:行 · 所在函数 · catch 体 · 同函数里的成功信号。
"""
import re
from pathlib import Path

ROOT = Path('/root/box/lib')
# 只看这几类路径：写操作 / 网络传输 / 持久化
AREAS = ['features/extensions/plugins', 'features/extensions/core', 'features/extensions/market',
         'features/home', 'features/admin']

SUCCESS_SIGNALS = re.compile(
    r'return\s+true|return\s+ok|Saved|已保存|保存成功|上传成功|删除成功|完成|成功', re.I)
EMPTY_CATCH = re.compile(r'catch\s*\([^)]*\)\s*\{\s*\}')
SWALLOW_CATCH = re.compile(r'catch\s*\(([^)]*)\)\s*\{')

def enclosing_func(lines, idx):
    for j in range(idx, -1, -1):
        m = re.match(r'\s{0,4}(?:Future<[^>]*>|void|bool|String|int|List<[^>]*>|[A-Z]\w*)\s+(\w+)\s*\(', lines[j])
        if m:
            return m.group(1)
        if re.match(r'\s{0,4}(?:class|enum|extension)\s+\w+', lines[j]):
            return '<类成员>'
    return '<?>'

rows = []
for area in AREAS:
    for f in sorted((ROOT / area).rglob('*.dart')):
        lines = f.read_text(encoding='utf-8', errors='replace').splitlines()
        for i, line in enumerate(lines):
            if 'catch' not in line:
                continue
            if not (EMPTY_CATCH.search(line) or SWALLOW_CATCH.search(line)):
                continue
            # catch 体（最多看 6 行）里是否有"只留痕/说明理由"的痕迹
            body = '\n'.join(lines[i:i + 7])
            has_reason = ('//' in '\n'.join(lines[i:i + 3])) or 'debugPrint' in body or 'log' in body.lower()
            fn = enclosing_func(lines, i)
            # 同函数内（前后 40 行）有没有成功信号
            ctx = '\n'.join(lines[max(0, i - 40):i + 40])
            sig = SUCCESS_SIGNALS.search(ctx)
            if not has_reason and sig:
                rows.append((str(f.relative_to(ROOT)), i + 1, fn, line.strip()[:60], sig.group(0)[:20]))

print(f'候选 {len(rows)} 处（吞掉异常 + 同函数里有成功信号 + 无留痕/说明）：\n')
cur = None
for path, ln, fn, code, sig in rows:
    if path != cur:
        print(f'--- {path}')
        cur = path
    print(f'  :{ln:<5} {fn:<28} {code:<45} 成功信号={sig}')
