# 答题插件设计审计与优化方案（2026-11-18）

> 只读审计，未改任何代码。方法：4 路并行审计（Dart 表现层 / Dart 数据领域层 / Android 原生层 / 端到端流程与配置面）
> + 我对每条 P0 结论逐条回验（下文标 ✅ 的为我亲自跑命令或读码确认过）。

## 0. 规模与结构

| 层 | 规模 | 备注 |
|---|---|---|
| Dart `lib/features/quiz_plugin/` | 37 文件 / 16,348 行 | 最大单文件 `quiz_plugin_entry.dart` 2,494 行（零 Widget，全是编排+业务） |
| Android 原生 | `QuizAccessibilityService.kt` 4,837 行、`QuizOverlayManager.kt` 932、`QuizOcrEntryOverlay.kt` 1,035 | `quiz_overlay.xml` 745 行 |
| 测试 | 127 个 `*quiz*` 测试 / 约 715 用例 | 覆盖偏纯函数与引擎匹配；设置面板、悬浮窗布局零覆盖 |

**一句话结论**：核心读屏链路被测试钉得很硬（这轮 11-17 的 bug 修复没白做），但**同一件事往往有 2~5 份实现**；
最影响体验的不是架构，而是几个**默认值/文案/额度语义**上的真 bug（OCR 兜底整条链路已死、失败也扣额度、限流被说成"今日已用完"）。

---

## 1. P0 —— 直接影响"出不出答案"（建议先做，全部 S 级）

### P0-1 ✅ OCR 兜底整条链路是死的，而它默认开着
- `QuizConfig.ocrSearch = true`、`ocrEndpoint = 'https://ocr.hpa888.top'`（`domain/quiz_config.dart:26-27`）。
- 实测 `ocr.hpa888.top`：证书 `subject=` `issuer=` 全空、10 年自签（`notAfter=May 28 2036`），
  `curl` 直接 `SSL certificate problem: self-signed certificate` ⇒ Dart http 必握手失败。
- 即便跳过证书：该域名在本机 nginx **没有 vhost**，`/api/ocr/health`、`/api/ocr/upload` 一律 **404**。
- 本地 OCR 容器 `zocr`（`/opt/zocr/docker-compose.yml`，`helloz/zocr`，:5080）**当前根本没起**（`docker ps -a` 里没有）。
- 后果：新用户每道题都先跑一次必然失败的 OCR，多一次截图 + 一条红字，然后才轮到 AI 读屏。

**改法（二选一，建议先止血再做长线）**
1. 止血（S）：`ocrSearch` 默认改 `false`；配置页把"OCR 截图搜题"标注「未启用（默认关闭）」，并加一次 `/api/ocr/health` 探活后才允许打开。
2. 长线（M，值得做）：把 `zocr` 起起来 + 给 `ocr.hpa888.top` 签 Let's Encrypt + 补 vhost + 核对契约
   （客户端要 `POST /api/ocr/upload` → `{"code":200,"data":{"texts":[],"full_text":""}}`）。
   **本地 OCR 免费且快**，OCR 命中能省 AI 读屏额度，这是省钱项，不只是修 bug。

### P0-2 ✅「未命中」覆盖守卫只接了 3/9 处，11-17 的故障还能复发
- 守卫 `_missPaintBlocked` 只在 `1331 / 1425 / 1449` 三处生效；`status: 'miss'` 推送共 8 处
  （`1190 / 1199 / 1268 / 1336 / 1392 / 1430 / 1599 / 1608`），其中 **6 处裸奔**
  —— 都是 `visionOnly 失败 / 未开启搜题方式 / OCR 失败 / 未授权 / OCR 低置信度` 这些路径。
- 真机复现形态：15s 读屏刚把答案画上去，同题下一轮抓屏走 OCR 分支失败 → 直接画"未搜到答案"。

**改法（S）**：把守卫收进唯一出口 —— 新增 `_pushMiss(fingerprint, question, config, text)`，内部先问守卫再推；
6 个调用点只改调用名，不动分支结构，不碰 15s 慢链路。

### P0-3 ✅ 失败也扣额度 + 预算倒挂（客户端 45s < 后端 90s）
- 后端 `image_platform_quota_server.dart:1794`：`userCounts[dayKey] = usedToday + 1` **在判断上游非 2xx 之后仍无条件执行**
  （只有抛异常那支 `1782` 提前 return）⇒ 上游 502/503 也烧掉一次日额度。
- 后端上游超时 `1919`：`req.close().timeout(90s)`；客户端硬顶 45s（`quiz_vision_timeouts.dart:39`）。
- 后果：慢模型场景客户端 45s 放弃 → 后端跑到 90s → 仍算一次额度、日志记 `upstream=200`"成功" ⇒
  **用户被扣额度、没拿到答案、运维统计里还没有失败**。

**改法（S）**：① 上游非 2xx 不计（或按 1/3 计）额度；② 后端上游预算降到 35s（< 客户端 45s）并回可识别的 504。

### P0-4 ✅ 限流/封禁文案指向错误方向
- 后端两种 429 其实分得开：突发限流 `1745`「请稍等几秒再试」、日额度 `1757`「今日已用完」；
  但客户端一律映射成"今日 AI 读屏次数已用完，明天再来吧" ⇒ 正常连做几题撞突发限流，被告知今天没了。
- 额度日键是 **UTC**（`1425/1740/1837`），文案却说"明天" ⇒ 北京 0:00–08:00 期间用户被告知明天再来，实际要等到 8 点。
- 403 也不分：设备被撤销 / 账号停用 / 代理未开放，客户端都显示"代理未开放"，用户会去重装或重登。

**改法（S）**：后端三种 429/403 都带 `error.code`（`burst_limited` / `daily_cap_exhausted` / `device_revoked` /
`account_disabled`），客户端按 code 出文案；日界文案改成"每日 08:00（北京时间）恢复"或直接把日键换成 UTC+8。

### P0-5 ✅ 外部检索会给"高置信度的错答案"，且把 key 放进 URL
- `quiz_engine.dart:1749-1752` 两个硬编码第三方公共 API；`1803` `confidence: answers.isEmpty ? 0.9 : 0.5`
  —— 第三方返回的**任意文本行**都被当成 0.9 置信度答案；`1836` 非 JSON 响应时整段当答案。
- 同一函数用全局 `http.get`（不是注入的 `_http`）⇒ 这条路径无法单测。
- `config.apiUrl` 一个字段双用：读屏 base（`POST {apiUrl}/chat/completions`）与搜题 GET（`apiKey` 进 query string）。

**改法（S）**：外部来源答案置信度封顶 0.5 并标注"未校验来源"；`apiKey` 改进 header；
`apiUrl` 拆成 `visionBaseUrl` / `textApiUrl`（旧值兼容映射）。这是"宁缺不错"的底线。

---

## 2. P1 —— 结构性冗余（消除"改一处漏三条路径"）

| # | 问题 | 证据 | 改法 | 量 |
|---|---|---|---|---|
| 1 | **结果→悬浮窗的组装复制 5 份且已漂移**（歧义/爆题/相似度 marker/参数），其中一份缺 `imageQuestion` 分支、单次调用里 `_answersListForOverlay` 算 5 次 | `entry.dart:1100-1137 / 1156-1181 / 1231-1260 / 1299-1326 / 1450-1465` | 抽 `pushResultOverlay()` 统一组装，5 处各删 25~30 行 | M |
| 2 | **云端同步卡与分类选择器双实现**（~300 行，含逐字相同的确认弹窗/SnackBar，一份 `List<dynamic>` 一份强类型） | `cloud_widgets.part.dart:43-194` vs `quiz_bank_view_page.dart:571-706` | 抽公共 widget（`quiz_cloud_sync_card.dart` / `quiz_cloud_category_picker.dart`） | M |
| 3 | **题干清洗 6 处实现、两套口径**：`isOptionLine` 认 A-H vs OCR 的 `_optLine` 只认 A-D；噪声词表两份 | `quiz_bank.dart:869-929`、`ocr_quiz_parser.dart:40-123`、`quiz_search_policy.dart:52`、`quiz_cloud_push.dart:289` | 只收口"清洗原语"（并集口径）；`stemFingerprint` 语义**不许动** | M |
| 4 | **工具函数重复**：`_lcs` 逐字相同两份；`_similarity` 同算法不同限幅（90 vs 72）；`isImageLikeOption*` 两份；选项字母前缀 5 份 | `aligner:741/779-856` vs `engine:992/1018/1129-1157`；`bank_view:275/288/1677` | 抽 `domain/quiz_text_metrics.dart`，限幅参数化（行为零变化） | M |
| 5 | **死代码**：批量录入三方法两侧都无对端（调了必然 MissingPluginException）；`pushAiProcess` / `probeFromSavedRegion` / `hideOcrEntryOverlay` / `_regionPreviewNotifier`（只写不读）/ 空 `cycleMatch` 分支；`QuizOverlayManager` 300+ 行不可达（`regionOverlayView` 只被赋 null） | `entry.dart:88-90/142-168/356/2072/2091/1969/1979`；`QuizOverlayManager.kt:326-466` | 分批删，先删无调用点的入口函数 | S |
| 6 | **4 个死配置字段**（零消费者） | ✅ grep 全仓 `bankPriority/overlayX/overlayY/regionForImage` 除 `quiz_config.dart` 外均 0 命中 | 删字段 + 对应测试 | S |
| 7 | **确认 bug：主题色 6 色块 vs 5 色板** ⇒ 点第 6 个永不选中、落盘 index=5 渲染成第 1 色 | ✅ `config_widgets.part.dart:178-185`（硬编码 6 个）vs `quiz_config.dart:74-80`（5 个） | 色块改为取 `QuizConfig.themeColors`，选中判定改等值 | S |
| 8 | **入库校验三套不一致**：OCR 入口要求 ≥2 选项，应用内录入页 ≥1 选项就能写 | `entry.dart:2218-2252` vs `quiz_entry_page.dart:87-164` | 下沉 `QuizBankEntryValidator` 纯函数，三入口共用 | M |
| 9 | **`jsonDecode(response.body)` 未 utf8 解码** + 5 套 JSON 解析错误处理风格混用 | ✅ `engine.dart:1713`（对比 `1347` 的 `utf8.decode(bodyBytes)`） | 收 `utils/quiz_json.dart` | S |
| 10 | **超时/重试各写四套**（`quiz_vision_timeouts` 自称唯一来源，云同步/OCR/device-token 各自定义） | `cloud_sync:44-45`、`ocr_client:53`、`device_token_client`；`retry` 4 种 | 常量收口 + `retryWithBackoff()`；**不改 45s 预算算法** | M |

---

## 3. P2 —— 悬浮窗界面布局（按用户痛点排序）

悬浮窗信息层现状（全部可见态）：

```
标题栏 36dp：[相似度胶囊 18dp/9sp·maxWidth44] [拖动把手 20dp] [⟵ HorizontalScrollView：
              ⋯26dp | AI胶囊26dp | 框选30dp | 眼睛26dp | 录入26dp + 4 个 1dp GONE 占位]
status_row（恒 GONE，已被胶囊取代）
题干 ScrollView（maxHeight 80dp，14sp）
读屏进度横幅（11sp + 3dp ProgressBar）      ← 与下面"AI 作答过程"重复
答案 ScrollView（maxHeight 200dp，13sp）
AI 作答过程（maxHeight 200dp，12sp，可展开/收起）
隐身圆点 28dp ／ 折叠药丸 40dp（代码强制 GONE） ／ 右下缩放手柄 36dp
区域选择层（全屏 + 底部 4 主按钮 + 更多面板 7 项）
```

| # | 问题 | 证据 | 改法 | 量 |
|---|---|---|---|---|
| 1 | **进度显示两套并存**：读屏横幅 + 作答过程区同时可见，同一件事画两遍 | ✅ `QuizAccessibilityService.kt:1650-1689` vs `:1400` | 横幅只留一行状态，过程区默认 `maxHeight` 200→120（已有展开开关） | S |
| 2 | **答案区高度策略自相矛盾**：XML 注释写明"不要 weight，否则把过程框顶出窗外（用户 09-14 报障真因）"，而 `applyExamChrome` 每次渲染都写回 `weight=1/height=0` | `quiz_overlay.xml:296-309` vs `kt:1933-1941` | 只在 examMode 切换时改一次 | S |
| 3 | **考试模式极简 chrome 失效**：`applyExamChrome` 先 GONE 一批，末尾又调 `applyTitleBarAdaptive` 无条件设 VISIBLE | `kt:1908-1919 / 1977-1985 / 1949` | `applyTitleBarAdaptive(allowedIds)` 白名单 | S |
| 4 | **触控目标普遍 < 48dp**：⋯26 / AI 26 / 框选 30 / 眼睛 26 / 录入 26 / 圆点 28 / 手柄 36 | `quiz_overlay.xml:97-176/405/463` | `TouchDelegate` 扩大命中区 ±3~6dp（先给 AI、眼睛） | S |
| 5 | **死视图**：`status_bar`(1dp GONE 且每渲染染色) / `status_row`(恒 GONE) / `btn_area`(1dp GONE，却承载"区域未配置"状态色) / `btn_close` / `btn_font`(0dp) | `xml:68-72/208-211/200-206/475-480`；`kt:1631/1730/1922/2723-2737` | 状态色迁到胶囊描边 → 删死节点与写点；区域状态迁到"框选"按钮 | S |
| 6 | **题干限高两套**：XML `maxHeight 80dp` vs 代码 `96dp` 且改的是 `height`（不回落） | `xml:231` vs `kt:4176-4186` | 只留一处，按 `maxHeight` 赋值 | S |
| 7 | **暗色完全不覆盖**：题干/答案/过程底色与文字全硬编码 `#FFFFFF/#F8FAFC/#101828/#344054`，无 `values-night` 颜色 | `xml:244/246/319/321/337`、`drawable/quiz_overlay_bg.xml` | 抽 4 个 `@color` + `values-night/colors.xml`（纯资源，零代码） | S |
| 8 | **默认位置必然压题干**：窗口 80% 屏宽 / ≥0.42 屏高、贴 `y=10%`，而默认识别区是"屏幕上 55%" | `OverlayGeometryPolicy.kt:48-52`、`kt:3656-3658/4729-4736` | 首次安装默认 `y=52%`（仅 `raw==null` 分支），老用户位置记忆不变 | S |
| 9 | 折叠态语义缺失：折叠时 pill 强制 GONE，窗口只是缩到内容高，用户看不出"已折叠" | `kt:1594/2320/2330/2350/2863`（多处 GONE；待真机复核是否完全不可见） | 二选一：真显示 pill，或删除整块 pill 并把标题栏压到 28dp | S |
| 10 | 配置页 21 项可调 → 建议压到 11 项；"恢复推荐尺寸"写死 320×300 与原生按屏宽 0.8 比例不一致；题库页推送入口 3 处 / 更新 2 处 / 空状态与筛选无结果同文案 | `config_widgets:623-668`、`bank_view:854/1046/1050/1363/1160` | 配置分"常用/高级"；题库页入口归一 + 空状态三态化 | M |

---

## 4. P3 —— 功能完善（按价值排序）

1. **答案依据可见（M）**：payload 加 `source`（题库/OCR/AI）与 `visionMode`（代理/直连），胶囊扩成短标签。现在题库命中（0 延迟、准）与 AI 读屏（15s、可能错）在界面上一模一样。
2. **失败一键重试 + 失败原因可见（M）**：miss 态给"重试读屏"动作（走既有 manual 通道，不受冷却）；自检页加一行"上次失败：<分类>（<时刻>）"。
3. **失败上报端点（M）**：现在 `QuizVisionReporter` 只在成功时上报，后台 `failed` 只统计上游非 2xx，看不到"客户端放弃/解析失败/45s 超时"。加 `POST /api/quiz/vision/failure`（只带 stage/errCode/耗时/模型，**不带题干与截图**）。
4. **额度可见（S）**：`X-Quiz-Vision-Used/-Cap` 已经回传也解析了，只躺在自检页；把"今日 n/100"放到配置页顶部，剩余 ≤10 提示。
5. **答题历史/错题本（M）**：新建 `answer_history` 表（**不要复用** `vision_candidates`，那是投稿留档）。
6. **题库与 AI 一致性校验（M）**：读屏命中后比对本地题库同指纹答案，不一致时上屏加标记并以 `conflict=true` 上报。
7. **后台联动（S）**：`GET /api/quiz/vision/config` 上线至今**客户端一次没调用过**；自检页拉一次显示"生效模型/代理开关"，后台切错模型立刻可见。
8. **连续做题（M）**：同屏冷却判据从"整串 fingerprint（含 dHash）"改成纯题干，避免换题被挡；可选"连续模式"。
9. 近似题推荐、图题 dHash 预筛（均 M，**风险高**，需真机样本锁定后再动）。

---

## 5. 明确不做（避免好心办坏事）

- **不整体重写** 4,837 行的 AccessibilityService。抽类按 `纯函数 → 回退窗/OCR 窗接线 → 主窗` 的顺序，每步独立可验证（原生层 21 个职责区块的边界已列出）。
- **不动** `stemFingerprint`（纯题干）语义、dHash 只做消歧 —— 这是 11-17 真机 bug 的修复结论。
- **不放宽**同题干爆炸闸门（243 条同题干会让"候选1：陡坡路段"类误导复活）。
- **不动**相似度阈值/权重（20+ 测试压着），要动先补直接单测。
- **不碰** 45s 硬顶的重试预算算法（要改的是后端 90s，让它落进 45s 里）。

## 6. 建议执行批次

| 批次 | 内容 | 预期 |
|---|---|---|
| **第 1 批（1 次发版）** | P0-1 止血（OCR 默认关+探活）、P0-2 守卫收口、P0-4 错误码分流、P0-5 外部答案降置信度 + key 进 header、P1-7 主题色 bug、P1-6 死配置 | 用户侧：少一次必败 OCR、不再"答案被未搜到覆盖"、文案不再指错方向 |
| **第 2 批（后端 + 悬浮窗）** | P0-3 失败不计额度 + 后端预算 35s、P3-7 自检页拉后台配置、P3-4 额度可见、P2-1/2/3/5/6/7 悬浮窗布局与暗色 | 用户侧：扣额度不再无声、夜间不刺眼、考试模式真极简 |
| **第 3 批（结构）** | P1-1 pushResultOverlay、P1-2 云同步 widget 收口、P1-3/4 文本工具收口、P1-5 死代码清理 | 维护侧：同类 bug 不再"改一处漏三条路径" |
| **长期** | P3-2/3 失败可见与上报、P3-5 历史/错题本、P3-6 一致性校验、OCR 长线（起 zocr + 证书） | 产品侧：从"能用"到"可信任、可运营" |
