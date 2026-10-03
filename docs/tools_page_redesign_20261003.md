# 工具页重设计（2026-10-03）

面向工具 tab（`lib/features/tools/presentation/tool_page.dart`）。目标：**首页 5 秒内到常用工具**、
让"有什么能用的"可以浏览、不再拿没做的东西当承诺、一个能力只有一份实现。

## 一、改前的实测基线

| 项 | 数字 | 出处 |
|---|---|---|
| 目录条目 | **122** = **66 可用** + 56 未接线（无重复、无孤儿） | `tool_catalog.dart`（`availableToolEntries()` / `allToolEntries()`） |
| 可用构成 | 36 API 面板 + **28 纯本地** + 在线PS(WebView) + 拉源码 | `kToolTargets` 按 `ToolTarget` 子类统计 |
| 平铺代价 | 3 列 × 22 行、卡高 ≈113px → **≈2660px ≈ 4~5 屏** | 旧 `available_tool_grid.dart`：`/104` 列宽、`childAspectRatio 0.92` |
| 「计划中」 | **56 条**，点进去只弹「【X】还没做，先别点了」 | 旧 `planned_tools_section.dart` + `available_tool_grid.dart:38-47` |
| 顶部指标 | 「66 可用 · 56 计划」 | 旧 `tool_page.dart` `_buildHeroWithSearch()` |
| 双份实现 | 6 个能力在工具页/扩展页各一份（`PluginToolbox` 约 750 行） | `extensions/plugins/plugin_toolbox.dart`（已删） |
| 「最近/常用」 | 无（ApiHub 页有一份**写死 6 个 id** 的「最近使用」） | 原 `api_hub_page.dart` `_recentToolIds` |

## 二、新的版式

```
① 顶卡：工具台 + 「66 个工具」/「匹配 N 个」 + 搜索
② 常用一行（记录非空）/「试试这些」（无记录，写明是推荐）
③ 分类芯片：全部 66 · 离线可用 · 各分类（带计数）
④ 分区网格：每分类一个区；折叠态只露第一行 + 「还有 N 个」收口；点芯片进那一区=直接展开
⑤ 我的收藏（网址书签，默认收成一行，空库时给引导）
⑥ 想要什么工具？→ 关于页反馈渠道
```

分类沿用目录自己的分类（不另造一套映射）：日常工具 9 · 系统操作 8 · 图片工具 1 · 查询工具 8 ·
开发工具 13 · 文本工具 11 · API 能力中心 1 · 计算工具 9 · 其他工具 5 · 趣味游戏 1（合计 66）。

## 三、五项改动与落点

1. **常用/最近**：新增 `tool_usage_store.dart`（SharedPreferences `tools_usage_v1`，最多 40 条，
   排序=次数优先/最近其次，写盘后通知）。记录点在**唯一派发点** `openToolTarget()`，
   所以不存在"某个入口漏记"。**刻意不进备份**（`BackupPrefKeys` 里没有它）：使用痕迹是设备本地的。
2. **分类芯片 + 分区网格**：`tool_sections.dart`（`ToolCategorySection` / `ToolCategoryChips` /
   `RecentToolsRow` / `ToolRequestRow`）。卡片宽目标 82 → 360dp 能排 **4 列**。
   「离线可用」放在「全部」旁边（全局开关不埋在横滑末尾）。
3. **「计划中」下线**：删 `planned_tools_section.dart` + `tool_widgets.dart`（后者只被它调用）；
   目录里改成 `unwiredToolNames()`（**只在代码里留名单，不上界面**）；顶部指标去掉"计划"；
   补一行「想要什么工具？→ 关于 → 反馈」。
4. **我的收藏收成一行**：默认 `_expanded = false`（空库时仍给引导），添加/导入导出/删除/展开照旧。
5. **「最近使用」共用一份记录**：`ApiHubPage` 去掉写死的 `_recentToolIds`，改读 `ToolUsageStore`；
   切面板（`_switchTool`）也记一笔（`toolNameForApiHubPanel()` 反查工具名）；空记录不渲染那一行。
6. **六个能力收敛成一份实现**：`builtin_json_formatter` / `base64` / `password_gen` / `timestamp` /
   `url_codec` → `LocalToolPage(localId: …)`；`builtin_qrcode` → `ApiHubPage(initialTool: 'qr')`；
   删除 `plugin_toolbox.dart`（零引用）。

## 四、明确不做

- API Hub 页的面板本体不动（独立子系统，工具页只是它 26 个入口之一）—— 但它那个
  **写死 6 个 id 的「最近使用」**（`api_hub_page.dart` 原 `_recentToolIds = ['qr', …]`）
  改成读同一份 `ToolUsageStore`：记录以工具名为键，用 `toolNameForApiHubPanel()` 换成面板 id；
  一条记录都没有时整块不渲染（拿没点过的工具冒充「最近使用」也是假承诺）。
- 不重写目录分类（那是 `tool_entry_structure_test` 钉住的唯一事实源）。
- 不给工具加"描述副标题"（会让卡片更高，66 个的量级不值这个钱）。
- 不按实现方式（API/本地/网页）分区 —— 那是实现细节；只用「离线可用」做一个筛选。

## 五、验证

- 新增/改写用例：`tool_usage_store_test.dart`（14 条：计数、排序、上限、冷启动重读、坏数据、
  不进备份、派发点记账、常用行文案）、`tool_entry_structure_test.dart`（模型契约 + 分区/折叠/芯片/
  离线/未接线不上界面/指标真数 + 源码护栏）、`builtin_plugin_single_implementation_test.dart`
  （6 个能力两边同源 + `PluginToolbox` 零引用）、`custom_site_section_test.dart`（默认收起）。
- `flutter analyze`：0 error / 0 warning。
- 全量回归：见本次汇报（`--exclude-tags live`）。

## 六、真机验收（手机上五步）

1. 工具页首屏：顶卡写「66 个工具」，下面一行「试试这些」。
2. 任意点开一个工具（如科学计算器）返回 → 那一行变成「常用」，第一个就是它。
3. 横滑芯片点「开发工具 13」→ 这一区直接铺开；退回「全部」→ 各区只露一行 + 「还有 N 个」。
4. 点「离线可用」→ 只剩纯本地工具（如进制转换），天气预报/在线PS 消失。
5. 搜「扫雷」→ 说"没有匹配的工具"（不再假装有）；页尾「想要什么工具？」能进关于页。
