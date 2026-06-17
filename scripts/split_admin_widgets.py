#!/usr/bin/env python3
"""Split admin_widgets.dart into 3 files using git blob to avoid file modification issues."""
import os, re, subprocess

root = os.path.expanduser('~/box-inspect/lib/features/account/presentation/widgets')
src = os.path.join(root, 'admin_widgets.dart')

# Use git show to get the exact content from HEAD
result = subprocess.run(
    ['git', 'show', f'HEAD:{src.replace(os.path.expanduser("~/box-inspect"), ".") }'] if os.path.exists(src) else ['git', 'show', 'HEAD:lib/features/account/presentation/widgets/admin_widgets.dart'],
    capture_output=True, text=True, cwd=os.path.expanduser('~/box-inspect')
)

# Actually src should exist since we restored it
with open(src, 'r', encoding='utf-8') as f:
    content = f.read()

lines = content.split('\n')

# Find ALL class boundaries precisely using brace counting
classes = []
i = 0
while i < len(lines):
    m = re.match(r'^(\s*)(class|abstract class|mixin|extension)\s+(\w+)', lines[i])
    if m:
        indent = len(m.group(1))
        cls_name = m.group(3)
        cls_start = i  # 0-indexed
        brace_depth = 0
        started = False
        cls_end = cls_start
        for j in range(cls_start, len(lines)):
            brace_depth += lines[j].count('{') - lines[j].count('}')
            if not started:
                started = '{' in lines[j]
            if started and brace_depth <= 0:
                cls_end = j
                break
        classes.append((cls_start, cls_end, cls_name, indent))
    i += 1

print(f"Found {len(classes)} classes")
for s, e, name, _ in classes:
    print(f"  Lines {s+1}-{e+1}: {name}")

# Now we need to figure out which helpers belong to which file
# Private functions:
helpers = {}
for i, line in enumerate(lines):
    m = re.match(r'^(\w+)\s+(\w+)\s*\(', line)
    if m and m.group(1) in ('String', 'int', 'double', 'bool', 'void') and m.group(2).startswith('_'):
        helpers[m.group(2)] = i  # 0-indexed

print(f"\nPrivate helpers: {helpers}")

# Dependency graph: which classes use which helpers?
deps = {}  # class_name -> set of helpers/functions/classes it references
for idx, (s, e, name, indent) in enumerate(classes):
    cls_lines = lines[s:e+1]
    cls_text = '\n'.join(cls_lines)
    referenced = set()
    
    for hname in helpers:
        if hname in cls_text:
            referenced.add(hname)
    
    for other_idx, (os2, oe2, oname, oindent) in enumerate(classes):
        if other_idx != idx and oname in cls_text and cls_lines[0].strip() != oname:
            referenced.add(f"CLASS:{oname}")
    
    deps[name] = referenced

print(f"\nDependency analysis:")
for cls_name, refs in deps.items():
    if refs:
        print(f"  {cls_name} -> {refs}")
