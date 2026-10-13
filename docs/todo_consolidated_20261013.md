# 待办清单收口（2026-10-13 核对）

> **这份文档的用途**：替代重翻 docs/ 下 20+ 份历史规划文档。把「文档说要做的」逐条
> 去代码里验证过，分「已完成 / 已废弃 / 仍有效未做」三类。以后看待办只看这一份，
> 不用再从 box_next_steps_286.md 一路翻到 335。
>
> **核对日期**：2026-10-13。**核对口径**：版本 1.21.12+369（HEAD `c024693`）。
> 每一条结论都附代码证据（文件路径或 commit hash），可复核。

---

## 一、仍有效未做（真正的欠债，只有 2 件）

判断标准：**「没做」不等于「欠债」**。只有「用户看得见、跨多份文档反复提、且无
『有意不做』标记」的才算欠债。其余「没做」要么是有意为之（如实披露了），要么是
「可选增强、看使用频率」，已归到第四节。

### 1. 音乐区真入口（P1，跨 312/315/335 三份文档连续提了三次）

- **现状（代码证据）**：`lib/features/music/presentation/music_placeholder_page.dart`
  仍是占位页；`HomePluginArea.music` 分区插件数为 0（`lib/features/extensions/core/home_plugin_core.dart:53`）。
- **为什么是欠债**：三份主线文档连续列为待办，用户直接看得见（内容页「音乐」是真入口，
  但点进去是「播放器还没开发」的占位页）。
- **最小实现形态（已在 335 论证过）**：复用 remote_storage 已有的 `video_player`/`chewie`
  音频播放能力，把「远端存储里的音频」做成音乐区入口，**不新写播放器**。
- **成本**：1-2 天。

### 2. 图片工具第一批（P1，315/335 两次列为待办）

- **现状（代码证据）**：`pubspec.yaml` 无任何图片处理依赖（仅 `cached_network_image`、
  `image_picker`，均为展示/选择用途，非处理）；全仓无 `*compress*`/`*format_convert*`
  相关实现文件。
- **内容**：压缩 / 格式转换 / 九宫格 / 拼接（纯客户端可做）。
- **成本**：1-2 天。**风险**：需新增依赖，网络受限时是成本（315 原文）。
- **注**：315/335 均记「图片工具 8/9 未接线」，具体条目名待核实（`tool_catalog.dart`
  中未直接搜到「压缩/格式转换」字样，可能条目名不同）。

---

## 二、有意为之、不算欠债（如实披露，维持现状）

这几项「没做」是**主动决定**，代码里都已如实说明，不应再当债追。

| 项 | 现状证据 | 结论 |
|---|---|---|
| **繁转简（t2s）** | `comic_source_engine.dart:102` `t2s: function (s) { return s; }` 恒等 + 注释「未实现繁转简：原样返回」；界面 `comic_source_check_page.dart:306` 明写「已知差异（不藏着）：书源里的「繁转简」本 App 未实现」；335 明确「建议不做，除非他明确要看」 | **维持不做**。三处一致披露，不是欠债 |
| **音乐占位页本身** | `music_placeholder_page.dart` 注释明写「播放器还没开发，这里必须如实说明还没做」 | 占位是**对的**（不弹假 Toast）。要消除的是「音乐区没有真功能」，见第一节第 1 条 |
| **主机指标 24h 窗口（SERIES_LEN=720）** | `tool/gen_hosts_json.py:45` `SERIES_LEN = 720`，`:37` 注释「留 24 小时（720 点）」；客户端 `host_models.dart:309` 注释「每 2 分钟一点、留 24 小时」；折线图 `host_tab.dart:217`/`host_sparkline.dart` 真实消费 `snapshot.series` | **720 是对的**，采集端+客户端模型+折线渲染三处一致按 24h 设计。7 天只是 312 的一个可选项，从未拍板。见第四节第 2 条 |

---

## 三、已完成（文档主张已在代码验证，从待办移除）

主线 next_steps 文档（286→287→312→315→335）都是「自包含」的——每份尾部都写了
落地记录，且后续版本持续兑现。以下为关键项核对结果：

| 文档主张 | 代码证据（commit 或文件） |
|---|---|
| 335 组1 五项（中转收口/更新续传/漫画缓存上限/自检同路/失败态自检） | 文档自带 336 落地记录 |
| 335 组2 第一项「下一话预取」 | `comic_prefetch.dart` + `comic_online_page.dart:1249` |
| 335「留给下一版」**漫画整话离线缓存+已下载** | `comic_offline_page.dart` / `comic_offline_downloader.dart` / `comic_offline_store.dart` |
| 315 组1 五项（漫画真入口/备份看板/恢复哨兵/网络诊断并发/源码获取） | 文档自带 316 落地记录 |
| 312 组1+投稿链路+占位治理+网络诊断插件 | 文档自带落地记录；`plugins/net_diag/` 存在 |
| 286/287 服务监控插件 | `plugins/monitor/` 完整 |
| 视频坏源过滤①②（`video_source_health_and_line_memory.md`） | `d5b3cf7 feat(video): 坏源过滤`、`1e13055 线路可用性前置标注`、`55aabe0 换源找片` |
| 起播优化（`video_startup_optimization.md`） | `aa5fbbf perf(video): 起播不再为坏线路干等` |
| 后台播放+PiP（`video_background_and_pip.md`） | `android:supportsPictureInPicture="true"` + `PlayerPipChannel.kt` + `player_pip_channel.dart` |
| 云播页三处修复（`video_cloud_page_resolution.md`） | `ff78516`、`aa5fbbf` |
| 工具页重设计 / 本地工具卡片 | `5e752da feat(tools)`、`c00a8c8 feat(local-tools)` |
| 插件系统 10 项 FIX | `plugin_system_fix_rollup.md` 自带总账 |
| AI HOT 迁 v1（`ai_hot_source_migration_353.md`） | `daily_news_url_policy.dart` 白名单含 `aihot.news` |
| 读屏上游切 flr（`quiz-vision-upstream-switch-20261010.md`） | `3d0b9c1`、`b484db2` |
| 运维通道 + 175 双服务器（server_ops 系列） | `server_ops_settings.dart:189` `defaultApiUrl175`、`:194` 多服务器模型 |
| 深色模式四轮改造 | git log：`13fe53b`→`5d2c275`→`b80374b`→`30d9324`→`bac646d`→`0f9036a`（批次1~第四轮） |

---

## 四、可选增强（不是欠债，看使用频率再定）

| 项 | 现状证据 | 说明 |
|---|---|---|
| 文件编辑器第 2 版（多文件/语法高亮/行号跳转） | `file_editor_page.dart` 无 `SyntaxHighlighter`/行号/多文件 tab | 312 列为「候选，收益看使用频率」；315 误记「上一轮拍过」但 312 原文未拍板。**属可选** |
| 主机指标历史 24h→7 天 | `gen_hosts_json.py:45` `SERIES_LEN = 720` | 见第二节。当前 24h 是完整设计，7 天是 312 的 F 项可选项，从未拍板 |

---

## 五、已废弃/被取代（不建议再按原样做）

| 文档 | 原因 |
|---|---|
| `plugin_system_optimization.md`（2026-07-12） | 被 `plugin_system_optimization_plan.md`（9月）取代，后者落地成 `plugin_system_fix_rollup.md`。旧文档目录结构已漂移 |
| `plans/2026-06-06-mobile-ui-redesign.md` | 早期 UI 总蓝图，已被 tools_page_redesign、深色改造、design-system 实际取代 |
| `quiz_overlay_next_polish_plan.md` / `quiz_plugin_next_steps_259.md` / `overlay-display-optimization-plan.md` | 答题悬浮窗迭代稿，已被 259+ 多轮落地覆盖 |
| `design-ai-vision-auto-submit.md` / `quiz-vision-credential-delivery-plan.md` | 设计稿（待拍板），非待办，属方案沉淀 |

---

## 六、数据清单类（非规划，不入待办）

`docs/worklists/` 下 8 个文件（b1-image-worklist、image_backfill_master_worklist、
incomplete_repair_worklist、stem_explosion_worklist 的 .csv/.md）是题库图片补图等
数据表，不是规划文档，随需求单独处理，本清单不纳入。

---

## 七、机器现状（核对时快照，非待办）

- 磁盘 85%（剩 6.3G），已从 335 时的 95%/剩 2.2G 缓解。
- 未提交改动 3 个文件（admin 模块，与本清单无关）。
