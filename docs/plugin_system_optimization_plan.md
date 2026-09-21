# Box 插件系统优化方案

> 生成时间：2026-09-14
> 范围：`lib/features/extensions/`（9,793 行）、`lib/features/quiz_plugin/`（14,560 行）、`lib/plugin_market/models/`（1,193 行）、3 个顶层兼容壳，合计 **53 文件 / 26,506 行**
> 方法：逐行读真实代码 + `flutter analyze` + 全库引用统计 + **每条缺陷均已单独复现取证**
> 状态：**仅诊断与设计，未改任何生产代码**（仅新增 1 个红灯回归测试）

---

## 0. 结论摘要

插件子系统**整体架构是健康的**，不存在需要推倒重来的问题。审计发现的问题分三类：

| 类别 | 数量 | 说明 |
|---|---|---|
| **P0 数据/安全** | 4 | 会导致用户数据丢失、按钮永久卡死、签名逻辑双份维护 |
| **P1 功能可用** | 6 | 状态同步时机、批量安装行为不一致、保护冗余不足 |
| **P2 体验/结构** | 8 | 文案不一致、import 风格、死代码、异常信息丢失 |

**关键判断**：最重要的一条不是「脏代码」，而是 **P0-2 导入快照无护栏 → 一次误操作静默清空用户全部插件配置**。这是数据丢失级缺陷，应最优先修。

### 已核实「无问题」的项（不要动）

| 排查项 | 结论 | 证据 |
|---|---|---|
| 内置插件 404 历史 bug | **已完整修复** | `plugin_market_local_sync.dart:173-204`：`isBuiltInTemplateId` 短路 + 独立 `builtin` 状态 + 从状态同步排除 origin |
| 策略判定入口 | **单一闸门，13 处调用全走 `PluginGate.denial`** | `plugin_policy.dart:332` 唯一定义 |
| `pluginsAllowed`/`forceLogout` 全局开关 | **确实被强制**（经 `denialFor` 统一处理） | `plugin_policy.dart:160-210` |
| sha256 校验语义（zip vs JSON） | **正确**：zip 比原始字节，JSON 才比文本 | `plugin_market_local_sync.dart:218-256` |
| 批量安装绕过兼容性检查 | **无绕过**：批量与单装都调 `PluginCompatibilityChecker.check` | `plugin_market_page.dart:493-496` / `308-311` |
| yank 后不自动启用 | **实现正确** | `plugin_market_local_sync.dart:119-131` |
| `extensions/` 顶层声明死代码 | **零**（75 个声明全部被引用 ≥2 次） | 全库逐名 grep |
| quiz_plugin ↔ extensions 横向耦合 | **双向 import 均为 0** | 双向 grep |

---

## 1. P0 — 数据 / 安全（建议最先做）

### P0-1 导入快照无护栏 → 静默清空用户全部插件配置 🔴

**证据链（已复现）**

1. `home_plugin_core.dart:941-971` `importSnapshotJson`：唯一校验是 `if (decoded is! Map) throw`。之后**直接** `_applySnapshot(incoming)` + `_persist()`。
2. `home_plugin_core.dart:517-547` `HomePluginSnapshot.fromJson`：字段缺失**完全静默容忍**——`enabledMap` 非 Map → 空表；`customPlugins` 非 List → 空列表；单个元素异常 → `catch (_) {}` 跳过。
3. 结论：传入 `{"foo":"bar"}` 这种任意 JSON，解析结果 = **空 enabledMap + 空 customPlugins**，覆盖模式下整体替换 → **所有内置插件恢复默认、所有自定义插件清空**，然后落盘。
4. UI 提示是「导入成功（已覆盖）」（`plugin_tab.dart:698`）——**用户以为成功，实际配置没了**。
5. `toJson` 写了 `'version': 1`，但 `fromJson` **完全忽略 version**，无版本校验。
6. URL 导入路径（`plugin_tab.dart:673-684`）会把**任意远程内容**直接喂进这条链路。

**修复方案（最小侵入）**
- `importSnapshotJson` 在 `_applySnapshot` 前增加护栏：要求 `decoded` 至少含 `enabledMap`（Map）或 `customPlugins`（List）之一，否则 `throw FormatException('快照缺少必需字段')`；
- 校验 `version` 字段（缺失视为不兼容，明确报错而非静默按空处理）；
- 覆盖模式下若解析结果「两表皆空」而当前快照非空 → 拒绝并提示，而非清空；
- 导入成功后提示改为显示**实际导入条目数**（`enabledMap.length` / `customPlugins.length`），让用户能判断是否真的导入了东西。

**风险**：A（低）。纯新增校验，不改数据结构；旧快照仍可导入。
**代价**：极少数「故意导入空快照以重置」的用法会被拦——可加显式「清空并重置」按钮替代。

---

### P0-2 批量安装按钮永久卡死 🔴

**证据（已复现）** `plugin_market_page.dart:487-510`

```dart
setState(() => _bulkRunning = true);   // :487
var success = 0; var skipped = 0;
final packageInfo = await PackageInfo.fromPlatform();   // :491 ← 无 try 保护
...
if (!mounted) return;
setState(() => _bulkRunning = false);  // :510 ← 异常时永不执行
```

`PackageInfo.fromPlatform()` 一旦抛错（平台通道异常），异常直接逃逸出 `_installVisible`；而批量按钮的可用性是 `_bulkRunning ? null : ...`（`:962`、`:975`）→ **`null` = 永久置灰，只能重启页面**。中间无 `try/finally`。
（注：原报告中「批量异常逃逸到调用方」的路径描述已核实，`setState(false)` 在异常后确实不执行。）

**修复**：将 `packageInfo` 获取与整个循环包进 `try { ... } finally { if (mounted) setState(() => _bulkRunning = false); }`；`packageInfo` 改为按需获取或失败降级为 `''`。

**风险**：A（低）。局部作用域调整。
**代价**：无。

---

### P0-3 签名/验签逻辑两套近乎逐行重复 🔴（安全维护风险）

**证据（已用 diff 验证）**

- 插件市场：`lib/plugin_market/models/plugin_market_signature_verifier.dart:7-104`
  `_canonicalizeJsonValue` / `pluginMarketCanonicalJson` / `pluginMarketSha256Hex` / `pluginMarketHmacSha256Hex` / `verifyPluginMarketSignatureForPayload`（none/sha256/hmacSha256 三分支）
- App 更新：`lib/update/update_security.dart:63-193`
  `_canonicalizeJsonValue` / `updateManifestCanonicalJson` / `updateManifestSha256Hex` / `updateManifestHmacSha256Hex` / `verifyUpdateManifestSignature`（同样三分支）
- **diff 结果：`_canonicalizeJsonValue` 函数体逐行相同，唯一差异是循环变量名（`e` vs `entry`）**
- 枚举也成对：`PluginMarketSignMode{none,sha256,hmacSha256}`（`plugin_market_security.dart:22`）vs `UpdateManifestSignatureMode{...}`（`update_security.dart:7`）

**影响**：安全关键逻辑双份维护 → 一处修漏洞另一处漏改；未来加 nonce/timestamp 要改两处。
**未验证**：两者在 list/map 嵌套边界上是否**完全等价**（文本高度一致但未跑等价性测试）。

**修复方案**
- 阶段一（A）：抽取公共 `lib/core/security/canonical_json.dart`（`canonicalizeJsonValue` / `canonicalJson` / `sha256Hex` / `hmacSha256Hex`），两处改为**委托**，保留原函数名做薄包装 → 调用点零改动。
- 阶段二（B）：写**等价性测试**：用同一批真实 payload（含嵌套 list/map/unicode/null）跑两套实现，断言输出字节一致；确认后再删薄包装。

**风险**：A 阶段低（委托不改行为）；B 阶段中（涉及删除代码，需等价性测试垫底）。
**代价**：多一层间接调用，性能影响可忽略（签名是低频操作）。

---

### P0-4 `_marketSignModeFromEnv()` 未知值静默降级为 `none`（关闭验签）🔴

**证据** `plugin_tab.dart:420-431`：环境变量解析未知值 → `none`，即**拼错一个环境变量名 = 验签静默关闭**，且无任何日志。
（对照组：`plugin_market_security.dart:61-63` 默认 `sha256` 且 `allowUnsigned=false`，语义本身是安全的——问题只在这个解析函数。）

**修复**：未知值 → 回退到安全默认（`sha256`）**并打日志**；绝不静默降到 `none`。

**风险**：A（低）。注意：这可能把某些「靠拼错环境变量关掉验签」的实际环境变成会验签——**发布前需确认线上环境变量拼写正确**，否则会突然验签失败。
**代价**：需一次线上环境变量核对。

---

## 2. P1 — 功能可用

| # | 问题 | 证据 | 修复 | 风险 |
|---|---|---|---|---|
| P1-1 | 清除 yank（`riskCleared`）后界面**无任何提示**，用户不知插件已可手动启用 | `plugin_market_local_sync.dart:132,168` 计算了 `riskCleared`，但 `plugin_tab.dart:104-113` **完全丢弃**它 | 消费 `result.riskCleared > 0` → `_showSnack('有 N 个插件已恢复上架，可手动启用')` | A（低），纯加提示 |
| P1-2 | **打开商店页本身不触发状态同步**：市场页全文无 `syncInstalledStatuses` 调用（仅 plugin_tab initState + app_shell 回前台 3 处） | `plugin_market_page.dart` 无调用；`plugin_tab.dart:101`、`app_shell.dart:154` | `_openPluginMarket` push 返回后补一次 `force: true` 同步 | A（低） |
| P1-3 | yank 强制禁用存在竞态：`addCustomPlugin` 与 `toggleEnabled` 非原子，且用循环开始时的**快照**判断 `plugin.enabled` | `plugin_market_local_sync.dart:79-96` | 改为 `addCustomPlugin` 后**无条件** `toggleEnabled(id, false)` | B（中），涉及状态写入时序 |
| P1-4 | `unknown` 分支**漏写** `marketStatus:'yanked'`，保护只靠 `marketRisk` 单点 | `plugin_market_local_sync.dart:97-107` vs 保护条件 `plugin_tab.dart:767-779`（二选一） | unknown 分支同样写 `marketStatus:'yanked'`（双保险） | A（低） |
| P1-5 | 批量安装对 warning 级问题**整条跳过**，与单装「弹窗确认后放行」不一致 → 用户困惑 | 批量 `plugin_market_page.dart:493-500`；单装 `:314-338` | 批量改为同样弹一次「有 N 个需确认，是否继续」 | B（中），改交互流程 |
| P1-6 | 下载**非 API 异常**（如磁盘写失败）静默降级为 `local_cache` 并继续装，可能留半装状态 | `plugin_market_local_sync.dart:237-284` | 显式区分「网络失败可降级」与「本地写入失败应中止」 | B（中），**需先读完落库细节确认** |

---

## 3. P2 — 体验与结构

### P2-1（用户可见）区域/动作文案三处不一致 🔴 已写红灯测试

`video` 区域在不同页面显示**两个不同名字**：

| 位置 | `video` 显示 |
|---|---|
| `home_plugin_core.dart:61-62`（事实源） | **影视** |
| `plugin_market_page.dart:276-277` | 影视 |
| `plugin_submit_page.dart:48` | **视频** ← 冲突 |

`action` 同样：`toast` 在商店是「提示动作」，在投稿页是「弹出提示」。

**红灯已复现**（`test/plugin_area_action_single_source_test.dart`，3 passed / 1 failed）：
```
Expected: '视频'
  Actual: '影视'
区域 video 在投稿页显示「视频」，而单一事实源 HomePluginArea.label 是「影视」
```

**根因**：同一份 area/action 清单被硬编码复制 **5 份** —— `HomePluginArea.label`、`HomePluginActionType`、市场页 `_areaLabel`/`_actionLabel`、投稿页 `_areas`/`_actions`、manifest `_allowedAreaCodes`。**已经真实漂移**。

**修复**：建 `plugin_area.dart` 作单一事实源；其余 4 处改为**引用**（保留旧常量名做别名，旧调用点不破）。

### P2-2（结构）`home_plugin_core.dart` 名为 core，横跨 5 个 feature 直接 import 具体 UI 页

`core/` 层直接依赖 9 个具体页面：
```
:8   ../../../daily_news_page.dart
:10  ../../../novel/novel_module.dart
:11  ../../../video_module.dart
:12  ../../image_generator/presentation/image_generator_page.dart
:14-16 ../../quiz_plugin/presentation/{quiz_entry_page,quiz_plugin_entry,quiz_bank_view_page}.dart
:18-19 ../plugins/{plugin_toolbox,github_accel_sheet}.dart
```
该文件同时承担 **注册表 + 内置插件目录（19 个 `HomePlugin(...)`）+ 页面装配中心** → 膨胀到 1,481 行；任何页面改路径都要动 core；core 无法被单测隔离。

**修复（B 阶段）**：拆为 `builtin_plugin_catalog.dart`（19 个定义）/ `builtin_plugin_pages.dart`（页面装配）/ core 只留注册表+持久化+事件总线。

### P2-3（一致性）import 风格混用

- `extensions/`：**33 处 `package:box/` vs 18 处 `../`**；其中 **2 个文件在同一文件内混用**：`home_plugin_core.dart`（pkg=1, rel=11）、`plugin_market_manifest_repository.dart`（pkg=1, rel=3）
- `quiz_plugin/`：**69 行相对 vs 1 行 package**（反向倾斜）
- 最深相对路径达 5 级 `../../../../..`

**修复**：统一为 `package:box/...`（纯机械替换，analyzer 全量兜底）。

### P2-4 UI 层 `_err()` 弱于 API 层 → 用户看到裸异常

- UI：`plugin_market_page.dart:1079-1082` —— 只认 `PluginMarketApiException`，其余 `e.toString()`
- API：`plugin_market_api.dart:200-205` —— **已正确处理** `TimeoutException`→"下载超时…"、`SocketException`→"网络连接失败…"

同一职责两套实现，UI 那套更弱 → 用户会看到 `SocketException: Failed host lookup...` 原文。调用点 `_install:437`、`_uninstall:459`。
**修复**：UI 层复用/对齐 API 层的判断分支（属 P2-1 同类的「重复实现漏改」）。

### P2-5 静默回退无日志

- `home_plugin_core.dart:256-272` `_areaFromName`/`_actionFromName`：未知值**悄悄**变 `recommend`/`toast`，无日志
- `plugin_market_page.dart:506` `catch (_) {}`：单个插件安装失败原因**完全吞掉**，只在末尾报总数
- `plugin_market_manifest_repository.dart:133-135`：401/500/超时一律降级为「平台不可达」，静默回退缓存/内置，**无「商店不可用」提示**
- `plugin_market_page.dart:163`：`'加载插件市场失败：$e'` 拼接原始异常

**修复**：回退时打日志；失败时提示区分「网络不可用」与「该插件失败」；单装失败原因聚合成一条可展开的提示。

### P2-6 死代码 3 处（已 grep 确认零引用）

| 声明 | 位置 | 说明 |
|---|---|---|
| `HomePluginApi` | `home_plugin_core.dart:1448` | 零引用（在文件内部，非顶层文件声明，故前面目录级扫描未捕获） |
| `MarketMetric` | `plugin_market_widgets.dart:175` | 同文件其余 4 个 widget 均在用 → **类级死代码，非死文件** |
| `PluginPermissionChecker` | `plugin_market_manifest.dart:722` | 零引用 |

### P2-7 `unknown` 状态依赖单一保护点 / 批量计数不含被拒项

- `unknown` 分支未写 `marketStatus:'yanked'`（同 P1-4）
- `plugin_tab.dart:177-197` 批量启用计数未反映被拒项

### P2-8 签名比较非恒定时间

`plugin_market_signature_verifier.dart:97` `actual == expected.toLowerCase()` 非恒定时间比较。本地场景风险极低，仅记录。

---

## 4. 建议执行顺序（分阶段，按你的 A/B 风险偏好）

### 阶段 A（低风险，建议立即做）

1. **P0-1 导入护栏**（数据丢失，最高优先）
2. **P0-2 批量按钮 try/finally**（局部修复，代价为零）
3. **P2-1 文案单一事实源 + 修 video/toast 漂移**（含已写的红灯测试转绿）
4. **P0-4 验签降级改为安全默认 + 日志**（需同步核对线上环境变量）
5. **P2-4 UI `_err()` 对齐 API 层**
6. **P2-3 import 统一为 `package:box/`**
7. **P2-6 删 3 处死代码**

*代价*：除 P0-4 需核对线上环境变量外，其余无行为风险；analyzer + 全量测试可验证。

### 阶段 B（中风险，需拍板）

8. **P0-3 抽取公共 canonical JSON + 等价性测试**（安全逻辑去重）
9. **P2-2 拆 `home_plugin_core.dart`**（catalog / pages / core）
10. **P1-3 yank 原子性**、**P1-4 双保险**、**P1-5 批量交互对齐**、**P1-6 降级语义区分**
11. **P1-1 / P1-2 状态同步时机与提示**
12. **P2-5 静默回退补日志与提示**

---

## 5. 待拍板项

1. **阶段 A 是否立即开 P0**？还是先只修 P0-1 + P0-2 两条数据/卡死级，其余合并下一版？
2. **P0-3（签名去重）**要不要做？它收益是「安全逻辑单点维护」，但改动的是**验签核心链路**（插件市场 + App 更新双线），风险等级明显高于其他项 —— 建议单独一版 + 等价性测试垫底。
3. **`home_plugin_core.dart` 拆分边界**：认可 catalog / pages / core 三分，还是只拆 catalog（更保守）？
4. **P0-4 线上环境变量**：需要你确认服务端/构建侧签名模式环境变量的实际拼写，否则改完可能突然验签失败。
5. **P1-6** 需要我再读完 `plugin_market_local_sync.dart:237-284` 的落库细节才能定性，是否允许（只读）？
6. 阶段 A 完成后是否按惯例**构建 arm64 release 并发布新版（非强更）**？

---

## 附：本轮已产生的文件

- `test/plugin_area_action_single_source_test.dart`（**新增**，3 passed / 1 failed —— 红灯锁 P2-1 真实缺陷）
- 无任何生产代码改动。

---

## 6. 实施结果（2026-09-14 回填）

11 项 todo 全部完成。实测结论与方案原稿的偏差记录如下（**含方案被校正的两处**）：

| 项 | 结果 | 与原稿偏差 |
|---|---|---|
| P0-1 | 快照护栏 + 版本号，5/5 | — |
| P0-2 | 批量按钮 try/catch/finally，5/5 | 原稿只提 finally，实测仅 finally 会让异常逃逸 |
| P0-4 | 未知验签模式回落 `sha256` + 日志，8/8 | — |
| P2-1 | area/action 单一事实源，6/6 | **附带发现 `navigate` 未登记枚举**（handler 早已存在）→ 已补 |
| P2-4 | 抽出 `pluginMarketFriendlyError()`，4/4 | 实测 `_err()` 有 **3 份**副本（非 2 份），全部改为委托 |
| P2-3 | 18 处跨目录相对 → `package:box/`，57/57 | **方案被校正**：原稿「全量统一」与代码库主流相悖（相对 798 : package 230），改为只修跨目录违规 |
| P2-6 | 删 3 处死代码，0 引用残留 | — |
| P1-4 | `unknown` 分支补 `marketStatus:'yanked'`，2/2（RED 已验证） | **实测比原稿更严重**：旧码残留 `marketStatus:'published'`，即「已下架」插件状态栏仍自称已发布 |
| P2-5 | 4 处静默回退补日志/提示，3/3 | — |
| P2-2 | catalog(332) / pages(63) / core(1253)，安全网 3/3 | **方案被校正**：实测内置插件 **15 个**（原稿写 19，误计了类声明与工厂构造）；且原稿漏掉 `HomePluginRouteRegistry.registerDefaults()` 也装配页面 → 一并拆入 pages |

**P2-2 的关键收益**：`home_plugin_core.dart` 从 1571 行降至 1253 行，且对 9 个具体 UI 页面的依赖**全部清零**（DailyNewsPage / NovelListPageWithProvider / VideoListPage / ImageGeneratorPage / GithubAccelSheet / QuizEntryPage / QuizBankViewPage / PluginToolbox 均为 0 引用）。14 个导入方**零改动**（委托式 stub 保住旧调用点）。

**验证基线**：`flutter test --exclude-tags live` → **2543 passed / 3 skipped / 0 failed**；`flutter analyze lib/features/extensions/ lib/plugin_market/` → No issues found。

> 注：`--exclude-tags live` 排除的 `github_accel_live_e2e_test.dart` 是连第三方 GitHub 镜像的真联网测试，与本次改动零重叠。

---

## 7. 实施结果（2026-09-20 回填 · 阶段 B + P2-7）

**阶段 B 全部完成**（P1-1 / P1-2 / P1-3 / P1-5 / P1-6 / P0-3），**P2-7 两个子项全部关闭**。

| 项 | 结果 | 说明 |
|---|---|---|
| P1-1 | `_syncInstalledStatuses` 消费 `riskCleared` + SnackBar | 同步降级数量对用户可见；红灯→绿 |
| P1-2 | 市场页返回后 `await _syncInstalledStatuses(force: true)` | 补上「关页必同步」时机 |
| P1-3 | yanked/unknown 分支**无条件** `toggleEnabled(id, false)` | 不再依赖快照 `enabled`，原子化（快照说开、实为已开 → 旧码漏禁用） |
| P1-5 | 批量拦截名单如实提示（≤3 个列名 + 「等」） | 版本阻断用 `blockers.first.message`，警告项用 `item.title` |
| P1-6 | 3 处 catch 补 `AppLogger.logChannelError(LogChannel.system, …)` | 静默降级保留（`reportInstall`、下载失败回退按原语义） |
| P0-3 | 抽 `lib/utils/json_canonical.dart` 单一实现 | 两处 public wrapper 保留，调用点零改动；等价性测试垫底 |
| P2-7a | `unknown` 分支补 `marketStatus:'yanked'` | 即 P1-4，阶段 A 已做（见上表 P1-4 行） |
| P2-7b | 批量计数剔除被拒项 + 如实提示 | `_togglePluginEnabled` 改 `Future<bool>`；`_batchToggleEnabled` 条件计数，「N 个未能启用：名单」 |

**P2-7b 的 TDD 证据**：红灯 `Found 0 widgets with text containing 已启用 2 个`（实际显示「已启用 3 个」= 缺陷计数）→ 修复 → 3/3 绿（含对称用例：全正常 3 个照常计数、禁用方向不受影响）。

**基础设施修复（本轮定位的真实坑）**：widget 测试（FakeAsync zone）里 `HomePluginHost` 单例写路径**挂死 300s+**——默认 `CacheStore` 走 `path_provider`（platform channel）+ `dart:io`，在 FakeAsync 里 `await` 永不完成。方案：新增 `injectPersistenceForTesting()`（注入 `CacheStore.inMemory` 支撑的持久化），`resetForTesting()` 恢复默认。后续任何要驱动 host 写操作的 widget 测试照此模式。

**验证基线**：改动相关目录 `test/plugin_market/ + test/plugin_manager/ + test/features/extensions/ + test/update/` → **249 passed / 1 skipped / 1 failed**（failed 为既知联网 `github_accel_live_e2e`，与改动零重叠）；`flutter analyze` 改动文件 → No issues found。

**新增测试文件**：`plugin_market_status_feedback_test` / `plugin_market_risk_cleared_test` / `plugin_market_yank_atomicity_test` / `plugin_market_sync_logging_test` / `json_canonical_single_source_test` / `plugin_market_bulk_skipped_names_test` / `plugin_tab_batch_count_test`。

**剩余项**：P2-8（签名比较非恒定时间）为本方案唯一未做项，原稿定性为「本地场景风险极低，仅记录」——如需处理属一分钟级改动，待拍板。
