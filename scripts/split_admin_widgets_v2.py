#!/usr/bin/env python3
"""Split admin_widgets.dart into 3 files + 1 shared file."""
import os, re

root = os.path.expanduser('~/box-inspect/lib/features/account/presentation/widgets')
src = os.path.join(root, 'admin_widgets.dart')

with open(src, 'r', encoding='utf-8') as f:
    lines = f.readlines()

header = ''.join(lines[:5])

# Class index: (start_0idx, end_0idx, name)
classes = [
    (6, 140, 'AdminProviderCard'),
    (155, 211, '_ProviderTestBanner'),
    (212, 416, 'AdminUsageSummaryCard'),
    (417, 524, 'AdminUsageCard'),
    (525, 600, '_UsageFilterBar'),
    (601, 620, '_UsageEmptyState'),
    (621, 700, '_UsageRecordTile'),
    (707, 860, 'AdminUserQuotaCard'),
    (861, 894, 'AdminEmptyCard'),
    (895, 928, 'AdminErrorBanner'),
    (929, 938, 'QuotaEditSheet'),
    (939, 1055, '_QuotaEditSheetState'),
    (1056, 1075, 'ProviderConfigSheet'),
    (1076, 1190, '_ProviderConfigSheetState'),
    (1076, 1190, '_ProviderConfigSheetState'),
    (1191, 1206, 'CreateAccountSheet'),
    (1207, 1304, '_CreateAccountSheetState'),
    (1305, 1315, 'AccountEditSheet'),
    (1316, 1393, '_AccountEditSheetState'),
    (1394, 1432, '_SheetFrame'),
    (1433, 1451, '_SegmentedRole'),
    (1452, 1469, '_SheetError'),
    (1470, 1497, '_SheetSaveButton'),
    (1498, 1524, '_RoleBadge'),
    (1525, 1547, '_StatusBadge'),
    (1548, 1587, '_MetricPill'),
]

# Deduplicate and sort
seen = set()
unique_classes = []
for s, e, name in classes:
    if name not in seen:
        seen.add(name)
        unique_classes.append((s, e, name))

# Re-find from file
unique_classes = []
i = 0
while i < len(lines):
    m = re.match(r'^\s*(class|abstract class|mixin|extension)\s+(\w+)', lines[i])
    if m:
        cls_start = i
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
        unique_classes.append((cls_start, cls_end, m.group(2)))
    i += 1

# Build a map: class_name -> (start, end)
cls_map = {name: (s, e) for s, e, name in unique_classes}

# Helper functions
helpers = {
    '_formatDate': (141, 146),
    '_formatShortDate': (148, 153),
    '_formatUsageTime': (701, 705),
}

# Groups based on dependency analysis
# Group 1: provider_cards - AdminProviderCard, _ProviderTestBanner
#   needs: _MetricPill (from group 3)
# Group 2: usage_cards - AdminUsageSummaryCard, AdminUsageCard, _UsageFilterBar,
#   _UsageEmptyState, _UsageRecordTile, AdminUserQuotaCard, AdminEmptyCard, AdminErrorBanner
#   needs: _formatDate, _formatShortDate, _formatUsageTime, _MetricPill, _RoleBadge, _StatusBadge
# Group 3: sheets - QuotaEditSheet, _QuotaEditSheetState, ProviderConfigSheet,
#   _ProviderConfigSheetState, CreateAccountSheet, _CreateAccountSheetState,
#   AccountEditSheet, _AccountEditSheetState, _SheetFrame, _SegmentedRole,
#   _SheetError, _SheetSaveButton, _RoleBadge, _StatusBadge, _MetricPill
#   needs: _MetricPill, _RoleBadge, _StatusBadge

# Best approach: put _MetricPill, _RoleBadge, _StatusBadge in admin_shared.dart
# Put _formatDate, _formatShortDate, _formatUsageTime in admin_usage_cards.dart

# Shared classes
shared_classes = ['_MetricPill', '_RoleBadge', '_StatusBadge']

# Provider cards classes
provider_classes = ['AdminProviderCard', '_ProviderTestBanner']

# Usage cards classes
usage_classes = ['AdminUsageSummaryCard', 'AdminUsageCard', '_UsageFilterBar',
                 '_UsageEmptyState', '_UsageRecordTile', 'AdminUserQuotaCard',
                 'AdminEmptyCard', 'AdminErrorBanner']

# Sheets classes
sheets_classes = ['QuotaEditSheet', '_QuotaEditSheetState', 'ProviderConfigSheet',
                  '_ProviderConfigSheetState', 'CreateAccountSheet', '_CreateAccountSheetState',
                  'AccountEditSheet', '_AccountEditSheetState', '_SheetFrame', '_SegmentedRole',
                  '_SheetError', '_SheetSaveButton']

def extract_classes(class_names):
    result = []
    for name in class_names:
        if name in cls_map:
            s, e = cls_map[name]
            result.extend(lines[s:e+1])
            result.append('\n')
    return result

# Write admin_shared.dart
shared_content = ("import 'package:flutter/material.dart';\n\n"
                  "import '../../../../design_system/app_tokens.dart';\n"
                  "import '../../domain/admin_models.dart';\n"
                  "import '../../domain/usage_models.dart';\n\n"
                  ''.join(extract_classes(shared_classes)))

with open(os.path.join(root, 'admin_shared.dart'), 'w', encoding='utf-8') as f:
    f.write(shared_content)
print(f"Created admin_shared.dart ({len(shared_classes)} classes)")

# Write admin_provider_cards.dart
provider_content = (header + '\n'
                    ''.join(extract_classes(provider_classes)))
with open(os.path.join(root, 'admin_provider_cards.dart'), 'w', encoding='utf-8') as f:
    f.write(provider_content)
print(f"Created admin_provider_cards.dart ({len(provider_classes)} classes)")

# Write admin_usage_cards.dart
usage_content = (header + '\n'
                 # Insert helpers between imports and classes
                 'String _formatDate(DateTime value) {\n'
                 '  if (value.millisecondsSinceEpoch == 0) return \'--\';\n'
                 '  final month = value.month.toString().padLeft(2, \'0\');\n'
                 '  final day = value.day.toString().padLeft(2, \'0\');\n'
                 '  return \'${value.year}-$month-$day\';\n'
                 '}\n\n'
                 'String _formatShortDate(DateTime value) {\n'
                 '  if (value.millisecondsSinceEpoch == 0) return \'--\';\n'
                 '  final month = value.month.toString().padLeft(2, \'0\');\n'
                 '  final day = value.day.toString().padLeft(2, \'0\');\n'
                 '  return \'$month-$day\';\n'
                 '}\n\n'
                 'String _formatUsageTime(DateTime value) {\n'
                 '  final local = value.toLocal();\n'
                 '  String two(int n) => n.toString().padLeft(2, \'0\');\n'
                 '  return \'${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}\';\n'
                 '}\n\n'
                 ''.join(extract_classes(usage_classes)))
with open(os.path.join(root, 'admin_usage_cards.dart'), 'w', encoding='utf-8') as f:
    f.write(usage_content)
print(f"Created admin_usage_cards.dart ({len(usage_classes)} classes)")

# Write admin_sheets.dart
sheets_content = (header + '\n'
                  ''.join(extract_classes(sheets_classes)))
with open(os.path.join(root, 'admin_sheets.dart'), 'w', encoding='utf-8') as f:
    f.write(sheets_content)
print(f"Created admin_sheets.dart ({len(sheets_classes)} classes)")

# Add shared import to all three files
for fn in ['admin_provider_cards.dart', 'admin_usage_cards.dart', 'admin_sheets.dart']:
    fp = os.path.join(root, fn)
    with open(fp, 'r', encoding='utf-8') as f:
        content = f.read()
    lines = content.split('\n')
    last_import = -1
    for i, line in enumerate(lines):
        if line.startswith('import'):
            last_import = i
    lines.insert(last_import + 1, "import 'admin_shared.dart';")
    with open(fp, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))

# Replace original with barrel
with open(src, 'w', encoding='utf-8') as f:
    f.write("export 'admin_provider_cards.dart';\n")
    f.write("export 'admin_usage_cards.dart';\n")
    f.write("export 'admin_sheets.dart';\n")
print("Replaced admin_widgets.dart with export barrel")

print("\nDone!")
