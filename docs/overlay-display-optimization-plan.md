# 答题悬浮窗「显示优化」方案（2026-09-19）

> 目标：针对用户选的「显示优化」全选（文字排版 / 尺寸位置 / 动画交互 / 性能），
> 读真实代码后按「收益高 + 风险低」优先，拆成可独立拍板的优化项。
> 原则：**不改既有几何策略**（`OverlayGeometryPolicy` 已成熟），只在渲染层做
> 可读性、交互、性能的增强；每项独立可回退，标注了已验证 / 未验证。

---

## 背景：真实代码现状（不是臆测）

| 模块 | 文件 | 行数 | 现状 |
|---|---|---|---|
| 几何策略（尺寸） | `OverlayGeometryPolicy.kt` | 494 | 单一事实源，纯函数，已收口（**不需要再动**） |
| 悬浮窗协调 | `QuizOverlayManager.kt` | 925 | 显示 / 降级 / 区域选择逻辑 |
| 悬浮窗服务 | `QuizAccessibilityService.kt` | 4751 | 渲染、字号、折叠、AI 过程框（**改动最密集**） |
| 悬浮窗布局 | `res/layout/quiz_overlay.xml` | 738 | 标题栏 + 题 + 答案 + AI 过程 + 折叠药丸 |

关键事实（已读码核实）：
- **字号**：题干 14sp / 答案 13sp，`applyFontScale` 默认 `baseA = 11f`（答案比题干小），
  有 `FONT_SCALE_STEPS` 循环切换。
- **排版**：题干区 `maxHeight=80dp` 自滚、答案区 `maxHeight=200dp` 自滚、
  AI 过程 `maxHeight=132dp`。都是 `wrap_content + maxHeight`。
- **折叠态**：`collapsed_pill`（40dp 药丸）+ `WRAP_CONTENT` 细条。
- **背景**：`quiz_overlay_bg`（圆角白底）+ `elevation=10dp`（阴影）。
- **动画**：目前**没有**展开/收起动画，`visibility` 直接 VISIBLE/GONE。
- **性能**：标题栏 `HorizontalScrollView` + 6 按钮 + 答案滚动，
  每 `updateContent` 全量 `set*` 一次。

---

## 优化项清单（按 收益/风险 排序，逐项可拍板）

### 【A 低风险】可读性 / 排版

**A1. 答案区字号对齐题干（13sp → 12.5sp 提一档）**
- 现状：答案 13sp、`applyFontScale` 里 `baseA = 11f`，答案比题干还小，
  长答案在窄屏读起来吃力。
- 改法：`baseA` 从 `11f` 提到 `12f`，题干 `baseQ` 保持 14f，让答案「略小于题干但可读」。
- 代价：答案区 `maxHeight=200dp` 不变，字大一点会早触发自滚，但滚动区本就存在。
- **已验证**：仅调常量，无逻辑分支；**未验证**：真机红米 K80（density 4.0）手感。
- 风险：极低（一个常量 + 一行 XML）。

**A2. AI 过程框字号 11sp → 12sp、行距 2dp → 3dp**
- 现状：`tv_ai_process` 11sp / lineSpacingExtra 2dp，过程①②③步小字偏小。
- 改法：XML 两处（textSize + lineSpacingExtra）。
- 代价：过程框 `maxHeight=132dp` 不变，字大一点行数变少、更早自滚。
- 风险：极低。

**A3. 题干区「等待捕获题目…」占位样式弱化**
- 现状：占位文与真实题同色（#101828），用户分不清「还没出题」和「已出题」。
- 改法：占位时 `tv_question` 设 `alpha=0.5` + 颜色 #94A3B8，真实题 `alpha=1.0`。
- 代价：零（只在 `updateContent` 里按 `question.isEmpty()` 切 alpha）。
- 风险：极低。

### 【A 低风险】尺寸 / 位置（仅微调，不动策略）

**A4. 折叠态药丸显示相似度胶囊（当前药丸只有「答题助手」+ 展开箭头）**
- 现状：折叠成 40dp 药丸后，相似度 / 状态信息全丢，用户看不清「检索中 / 已命中」。
- 改法：药丸左侧加一个 9sp 胶囊（复用 `tv_similarity_badge` 的样式，id 另起 `tv_pill_status`），
  在 `applyCollapsedUi` / `updateCollapsedPill` 里跟随状态着色。
- 代价：药丸宽度从 wrap 略增（+ 约 40dp），几何策略的折叠路径用的是 WRAP_CONTENT，
  不受影响（窗口自动跟着药丸宽度走）。
- 风险：低（新增一个 View，不动尺寸公式）。

### 【B 中风险】动画 / 交互

**B1. 折叠 ↔ 展开加 200ms 高度动画（ValueAnimator 驱动 `updateViewLayout`）**
- 现状：`visibility` 直接 GONE/VISIBLE，「咔」一下，观感生硬。
- 改法：折叠时 `animate` 高度从展开 → WRAP_CONTENT 药丸高度；展开反向。
  用 `view.animate().translationY` 不需要，仅改 `params.height` + `updateViewLayout`。
- 代价：动画期间几何策略的 `decide` 仍正常（只驱动高度），**但**动画帧会多次
  `updateViewLayout`，与 `ensureAnswerOverlayFitsContent` 的内容自适应有竞争——
  需要把动画期间 `contentNeededH` 的自适应临时锁住（1 行标志），否则动画会被打断。
- 风险：**中**——动画与内容自适应抢 `params.height`，需要小心加锁，否则会出现
  「动画到一半被内容撑高」的跳变。
- 已验证：单测可锁「动画标志开启时不自适应」；**未验证**：真机流畅度（掉帧）。

**B2. 按钮点击涟漪 / 缩放反馈（`scaleX/Y` 200ms）**
- 现状：标题栏 6 个 `ImageButton` 点击无反馈。
- 改法：`android:foreground="?android:attr/selectableItemBackground"`（纯 XML，零代码），
  或对 `btn_ai_vision` 加 `scale` 动画。
- 代价：零（系统涟漪）或极低（一个 View 动画）。
- 风险：低（纯 XML 优先推荐）。

**B3. 拖动 / 缩放时实时显示「位置吸附提示」**
- 现状：拖动悬浮窗无反馈，用户不确定「松手会不会弹回」。
- 改法：拖动中显示 200ms 的 Toast / 角标「已记忆位置」，松手时淡出。
- 代价：低（复用现有 `Toast` 路径 + 拖动监听里加一行）。
- 风险：低。

### 【B 中风险】性能

**B4. 答案 / 过程区 TextView 用 `setLayerType` 软件层（圆角阴影不卡）**
- 现状：`answer_container` 有 `elevation=10dp`（硬件阴影），国产 ROM 上
  滚动时掉帧常见。
- 改法：`answer_container` 加 `setLayerType(LAYER_TYPE_HARDWARE)`（API 24+），
  圆角阴影走硬件层，滚动不掉帧。
- 代价：多占一点 GPU 显存（一个悬浮窗，可忽略）。
- 风险：低（只加一行）。

**B5. `updateContent` 全文字不变时跳过 `invalidate`**
- 现状：每次 `updateContent` 无条件 `setText` + `ensureAnswerOverlayFitsContent`
  （后者会 `requestLayout` 全子树），即便内容没变也重排。
- 改法：`updateContent` 开头加「newContent == oldContent 且非状态切换 → 直接 return」，
  避免无意义重排。
- 代价：零；**但**要小心：状态色（检索中 / 命中 / 失配）变化时**不能**被这条短路掉，
  得把状态色纳入比较键。
- 风险：中（短路条件写错会让「状态变了但文字没变」的 UI 不刷新——这是回归风险）。

---

## 推荐执行顺序

1. **先做 A 全部（A1–A4）**——全是常量 / XML / 一行，零逻辑竞争，
   真机「显示没变化」的体感改善最明显。
2. **再做 B2（涟漪，纯 XML）+ B4（硬件层，一行）**——低成本高收益的交互 / 性能。
3. **B1（高度动画）单独做**——有竞争点，做完单独跑真机回归再发。
4. **B3 / B5 看余量**——B5 是回归风险点，建议放最后，且必须先写红灯测试。

---

## 待拍板项（用户回编号）

| 编号 | 项 | 风险 | 一句话 |
|---|---|---|---|
| 1 | **A 全做（A1–A4）** | 极低 | 字号对齐 + 占位弱化 + 药丸状态，纯常量/XML |
| 2 | **A + B2/B4**（推荐） | 低 | A 全部 + 按钮涟漪 + 硬件层，零逻辑竞争 |
| 3 | **A + B2/B4 + B1** | 中 | 加 200ms 高度动画（有与内容自适应的竞争点） |
| 4 | **A + B2/B4 + B1 + B5** | 中 | 再加「内容不变不重排」优化（回归风险点） |
| 5 | 只挑其中某几项（我列出编号你再选） | — | — |

**我的推荐：2**（A 全部 + 涟漪 + 硬件层）——全是低风险、真机立刻有感知的改动，
动画 B1 和重排 B5 单独排下一轮做，避免一次塞太多竞争点不好定位。

---

## 执行结果（2026-09-19，方案 2 已落地，随 v270 发布）

**已实施（P0）**：
- **A1'**（口径修正）：`applyFontScale` `baseA 11f → 12f`。注：运行时默认答案字号
  实为 13sp（XML + `applyAnswerStyle` 每次渲染覆写），11f 只在字号循环路径生效——
  原方案的「答案比题干小」表述不准，真实缺陷是「循环一按答案骤缩 2sp」的口径分裂，
  12f 后循环档与静态默认只差 1 档。
- **A2**：AI 过程框 11sp→12sp、行距 2dp→3dp（`quiz_overlay.xml`）。
- **A3**：占位题干弱化——`overlayQuestion` 为空时 `alpha 0.55` + `#94A3B8`，
  真实题干 `alpha 1.0` + `#101828`（`updateAccessibilityOverlayView`）。
- **B2**：7 处按钮加 `foreground=@drawable/quiz_btn_ripple`（自建 ripple，
  硬编码 `#40FFFFFF` 不引用 `?attr`——本布局历史上因 `?attr` 解析失败整页
  inflate 崩过，涟漪不值得再引入主题依赖）。原 selector 背景全部保留。
- **B4**：`answer_container` 加 `LAYER_TYPE_HARDWARE`（硬件层合成阴影/圆角）。
  注：原方案标题写「软件层」是笔误，落地为硬件层（API 24+ 全覆盖，项目 minSdk≥24）。

**撤回（核实后不成立，单独列出）**：
- **A4**（折叠药丸加状态胶囊）：读码核实无障碍主路径折叠态走 `applyCollapsedUi`
  的 WRAP_CONTENT 细条，标题栏 + `answer_container` 仍可见（答案/相似度不丢）；
  40dp `collapsed_pill` 是无障碍路径不经过的遗留分支。前提不成立，**不做**。
- **B4 前提修正**：项目 minSdk≥24（`LAYER_TYPE_HARDWARE` 无需版本分支）。

**延后（下一轮）**：B1（高度动画，与内容自适应抢 `params.height` 需加锁）、
B3（拖动位置提示）、B5（内容不变跳过重排，须先写红灯测试锁状态色不被短路）。

**验证状态**：`flutter analyze` 无新增 issue（220 条全为 test/ 既有基线）；
9/9 单测通过；XML/Kotlin 编译验证 = release 构建；**未验证**：真机手感
（字号档位、涟漪观感、阴影流畅度）。
