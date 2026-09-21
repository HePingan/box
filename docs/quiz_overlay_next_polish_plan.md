# 答题悬浮窗 · 下一步打磨方案

> 起因：用户 2026-09-15 第二次反馈「答题悬浮窗还是没有变化，ai搜题显示也没有优化」。
> 254（`7ed584c`）声称修了「展开尺寸下限」，代码是对的 —— 真机却没变化。
> 255（`9145905`，id=97）定位到真因（折叠态卡死）并已发布，**待真机验收**。
>
> 本方案回答的是：**在 255 之上，下一步该打磨什么、为什么、按什么顺序。**
> 所有条目均已回读真实代码取证，标注了证据位置。

---

## 0. 先讲清楚 255 修了什么、没修什么

| | 状态 |
|---|---|
| 真因（折叠态持久化 + 自适应早退） | ✅ 已修并发布（id=97） |
| 尺寸逻辑分散导致「同一现象五连报」的**结构性根因** | ❌ **未修** —— 255 只是又堵了一个漏点 |
| 「AI 作答过程」默认收起的产品决策 | ❌ **未动** |

**255 是止血，不是根治。** 本方案的核心就是第 1 节。

---

## 1. 【P0】尺寸/折叠状态收口到唯一入口（结构根治）

### 为什么这是第一优先

用户从 2026-09-13 起**连续五次**反馈尺寸类问题：

> 「悬浮窗太小」→「还很拥挤」→「扩大 1.5 倍」→「大小没有变化」→「还是没有变化」

每一次都改了代码、都加了测试、发布后用户都说没变化。这不是巧合，是**结构性缺陷**：

**证据（回读 `QuizAccessibilityService.kt`，4200 行）**

```
169 个成员声明（153 个 fun + 16 个字段），尺寸/布局相关约 30 个：
  defaultOverlaySize()      // 初始默认
  overlaySizeFloor()        // 下限
  flooredExpandedSize()     // 施加下限的展开尺寸
  loadOverlaySize()         // 读 prefs + 夹逼
  setOverlaySizeFromDp()    // Flutter 侧入口
  applyExamOverlayDimensions()
  applyCollapsedUi()        // WRAP_CONTENT
  ...

尺寸内存态 overlayExpandedWidth/Height —— 有 8 处写点：
  :1354  :1585  :1839  :1983  :2107  :3466  :3526  (+:486 声明)

直接调 updateViewLayout 的点 —— 16 处（绕过任何统一入口）
```

**缺陷形态**：同一件事（窗口该多大）有 6+ 个函数、8 个写点、16 个出口。
「谁最后写谁赢」，且**每处只覆盖自己知道的那条路径**。
254 的下限加在 `loadOverlaySize()` 和 `flooredExpandedSize()` 里 —— 但用户当时处于
**折叠态**，走的是 `applyCollapsedUi()`，压根不经过那两个函数。

> 这正是用户 USER.md 里那条偏好的技术具象：
> 「同类能力散落多处 → 视为缺陷，合并时保留旧调用点兼容」。

### 为什么测试没拦住（这是关键）

尺寸类测试**几乎全是源码文本正则**：

| 测试文件 | 断言方式 |
|---|---|
| `quiz_size_log_prompt_user_asks_v5_test.dart` | `readAsStringSync` + 正则 |
| `quiz_overlay_scale_v6_and_vision_degenerate_test.dart` | 正则 |
| `quiz_overlay_expanded_size_floor_test.dart`（254 的） | 正则 |
| `quiz_overlay_width_and_vision_timeout_test.dart` | 正则 |
| `quiz_titlebar_adaptive_test.dart` | 正则 |

> 注意文件名里的 **v3 / v5 / v6** —— 每报一次就加一个正方正则，
> 断言「源码里有这个修复」。**源码里有 ≠ 运行时窗口是大的。**

**这个失败模式本仓库早就诊断过并解决过。** `RegionWindowAttachPolicy.kt` 的注释原文：

> 「抽成纯函数的原因：这段逻辑原先内联在 `QuizAccessibilityService.enterRegionMode`
> 里，依赖 WindowManager，纯 JVM 单测碰不到。**此前 `P0FixLogicTest` 声称验证它，
> 实际是在测试方法里 throw 两个自造异常再断言自己的局部变量 —— 生产代码改坏了照样绿。**」

尺寸逻辑**没有**做这个抽取，于是重蹈了这个坑。

### 落地方案

**抽 `OverlayGeometryPolicy`（纯 Kotlin object，零 Android 依赖）**，作为尺寸决策的**单一事实源**：

```kotlin
// android/app/src/main/kotlin/top/hpa888/box/OverlayGeometryPolicy.kt
object OverlayGeometryPolicy {
    /** 输入：屏幕、密度、prefs 原始值、折叠态、是否考试模式、内容需求高度 */
    data class Input(
        val screenW: Int, val screenH: Int, val density: Float,
        val savedW: Int?, val savedH: Int?,
        val collapsed: Boolean, val examMode: Boolean,
        val contentNeededH: Int,
    )
    /** 输出：唯一权威尺寸 + 为什么（可断言、可打日志） */
    data class Decision(
        val width: Int, val height: Int,
        val reason: String,           // "saved" / "floor" / "collapsed-wrap" / "content-fit"
        val shouldExpand: Boolean,    // 折叠态是否该自动展开
    )
    fun decide(input: Input): Decision { ... }
}
```

然后：
1. **8 个写点全部改为经 `decide()` 产出**（旧的 6 个函数保留为薄委托，不删调用点 —— 符合「保留旧调用点兼容」）。
2. **16 处 `updateViewLayout` 收敛为 1 个 `applyGeometry(decision)`**，内部统一 `logDebug(decision.reason)`。
3. 新增 **JVM 单测** `OverlayGeometryPolicyTest.kt`（同 `OverlayLayoutCommitterTest` 范式），
   覆盖**状态机全组合**：折叠×考试×有保存值×保存值小于下限×内容超屏×内容为空……
   —— 这才是能拦住「同一个 bug 报五次」的东西。

### 收益 / 风险 / 代价

| | |
|---|---|
| **收益** | 尺寸决策从「6 函数 8 写点 16 出口」→「1 入口」；新增任何路径都不可能再漏加下限；JVM 单测能测运行时行为（而非源码文本） |
| **风险** | **中**。改动面大（30 函数 + 16 出口），必须行为等价迁移 |
| **缓解** | ① 先在 JVM 单测里把**当前**行为钉死（含已知缺陷，作为「现状快照」）；② 逐条迁移并保持单测绿；③ 保留旧函数签名委托，调用点零改动 |
| **代价** | 预计 1 个较大改动；`logDebug` 会多一行 reason（调试面板可见，符合既有习惯） |
| **可调参数** | `OVERLAY_MIN_WIDTH_DP` / `OVERLAY_MIN_HEIGHT_DP`（调大→窗口下限更高）、`0.92f` 屏高上限 |

### 与 255 的测试关系

255 已加 `quiz_overlay_collapsed_stuck_regression_test.dart`（4 条，**行为不变量**而非源码文本）。
P0 落地后，该测试应**改为调用 `OverlayGeometryPolicy.decide()` 断言**，从「正则看源码」升级为「真跑逻辑」。

---

## 2. 【P0】「AI 作答过程」默认收起 —— 产品决策待拍板

### 现状（回读代码）

`toggleAiProcessExpanded()`（:1191）注释写着：

> 「AI 作答过程：展开/收起（**默认收起**，避免挤占答案首屏）」

而 `updateAiProcess()`（:1222）在**折叠态**时把摘要塞进标题右侧：

> 「折叠态时把内容摘要放进标题右侧，让用户不展开也能看到关键一步。」

### 这解释了用户的第二句话

用户说「**ai搜题显示也没有优化**」。当前设计是：
- 过程面板**默认收起**，只显示一行摘要
- 用户截图里正是这个状态（只有 ① 一行，被截断）

**「默认收起」和「用户以为没优化」在体验上是同一件事。**
255 修了「折叠态下自适应不跑」的 bug，但**没有改「默认收起」这个产品决策** ——
所以 255 之后，用户打开答题窗看到的**仍然是一行摘要**（除非他手动点展开）。

### 待拍板（三选一）

| 选项 | 效果 | 代价 |
|---|---|---|
| **A. 保持默认收起** | 答案首屏最干净 | 用户可能继续觉得「没优化」 |
| **B. 默认展开、用完自动收起** | 搜题时用户能实时看到 ①②③ 进度，出答案后自动收 | 过程期窗更高；需定「自动收」时机 |
| **C. 默认收起，但标题栏摘要显示到 2 行且明确提示「点此展开全过程」** | 折中，最省改动 | 仍不是「全程可见」 |

**我的建议：B。** 理由 —— 用户连续反馈「显示一半 / 没优化」，核心诉求是**想看到 AI 在干什么**
（这条产品线的主打卖点就是「AI 作答过程」）。过程本身是**短时的**（几秒），
搜完自动收起既不挤占答案首屏，又满足了「看得见」。但**自动收起的时机需要真机手感确认**。

---

## 3. 【P1】`ensureAnswerOverlayFitsContent` 的测量滞后

### 现状（回读 :3511-3528）

```kotlin
val answerH = answer.height          // ← 用 ScrollView 的**当前**高度
val needed = titleH + statusH + dividerH + questionH + progressH + answerH + processH
if (needed > current.height) { ... }
```

**两个问题：**

1. **`answer.height` 是被 `clampQuestionScrollMaxHeight()` 夹过的当前值**，
   不是内容的**期望**高度。窗口只增不减的前提下，这意味着：
   若某轮内容变矮，`needed` 偏大 → 窗口不会缩（可接受）；
   但若 ScrollView 本身高度已被夹小，`needed` 偏小 → **该涨的时候不涨**。
2. **只增不减**：`if (needed > current.height)` —— 一旦涨上去就不会降。
   多次搜题后窗口可能越来越大。目前有 `0.92 × 屏高` 上限兜底，但**没到上限时无收敛**。

### 落地方案

- 用**子视图测量值**而非已夹过的 `height`：对 `scroll_answer` 调 `measure()` 取 measuredHeight（或直接取内部 TextView 的 `lineCount × lineHeight`）。
- 增加**收敛**：内容变矮且用户未手动调过尺寸时，允许回落到「内容高 + 边距」，下限仍走 `overlaySizeFloor()`。
- 这条并入 P0 的 `OverlayGeometryPolicy.decide()`（作为 `contentNeededH` 的计算函数）。

**风险：中**（改测量方式可能引起抖动）。**缓解**：真机手感确认；保留 `0.92` 上限；只增不减的行为作为已知取舍写明。

---

## 4. 【P1】真机诊断能力（为下一个 bug 提速）

### 现状

已有 `logDebug`，且 App 内有「关于页 → 调试日志」。
255 的排查我给了三个前缀（`migrate:` / `overlay.load` / `overlay.apply`）。

**问题**：这些日志是**我临时拼的**，没有成套的「悬浮窗几何快照」。

### 落地方案

在调试面板加一个 **「悬浮窗几何」诊断块**，一键复制：

```
overlay.geometry
  screen=1080x2400 density=2.75 (393x873dp)
  collapsed=false  examMode=false  answerOnly=false
  rawPrefs=430,900          ← prefs 里躺着的原始值
  floor=1352x1900px (491x691dp)
  decision=saved→floor height raised reason=floor
  applied=1352x1900px  pos=(690,1200)
  expandedW/H(mem)=1352x1900
  aiProcess: box=VISIBLE lines=2 textLen=68
  fitNeeded=1980px (title96+status0+div1+q420+prog0+ans980+proc483)
```

**收益**：下次用户报「还是没变化」，一行日志就能定位在哪一环，不必再来回三轮。
**风险：低**（纯新增）。**符合用户偏好**：「诊断 UI 走既有菜单项，不各自建悬浮按钮」。

---

## 5. 【P2】`QuizAccessibilityService.kt` 拆分（4200 行）

153 个函数挤在一个文件里，是 P0 那个「同类能力散落」的**温床**。

**建议**：按已有可用性边界拆（**不是现在做**，等 P0 落地后）。
参考插件域 P2-2 的成功范式（catalog / pages / core 三分，14 调用点零改动）。

| 拆分候选 | 依据 |
|---|---|
| `OverlayGeometryController` | P0 抽出的尺寸决策 + 应用 |
| `OverlayAiProcessRenderer` | :1191-1250 过程面板 |
| `OverlayCaptureController` | 抓题扫描 / gate（已有 policy 类） |
| `OverlayMenuController` | 菜单项 / 重置 / 字号 / 不透明度 |

**风险：高**（4200 行的服务类，Android 生命周期耦合）。**建议**：**P0 落地并真机验收通过后**再评估，且必须先建行为快照。

---

## 6. 建议执行顺序

```
255（已发布，待验收）
  ↓
① 真机验收 255  ← ★ 现在就该做，方案再对也得先确认止血有效
  ↓
② P0-1 抽 OverlayGeometryPolicy + JVM 单测        ← 结构根治，最高价值
   P0-2 「AI过程默认展开」拍板 + 落地              ← 直接回应「没优化」
  ↓
③ P1-1 测量滞后修复（并入 P0 的 decide()）
   P1-2 悬浮窗几何诊断块
  ↓
④ P2   4200 行拆分（评估，非必须）
```

**为什么不先做 ④**：拆一个 4200 行、耦合 Android 生命周期的服务，在没有行为快照前风险远大于收益；
而 P0-1 抽 policy 恰好**就是在为拆分铺路**（把纯逻辑先拿出来，剩下的是真·平台胶水）。

---

## 7. 待拍板项

| # | 事项 | 选项 | 我的建议 |
|---|---|---|---|
| 1 | 「AI 作答过程」默认状态 | A 保持收起 / B 默认展开+完事自动收 / C 收起但摘要 2 行 | **B** |
| 2 | P0-1 是否现在就做（较大改动） | 做 / 先只做 P0-2 / 都先不做 | **做**（这是五连报的根因） |
| 3 | P1-1 是否允许窗口「可缩小」 | 允许收敛 / 保持只增不减 | **允许收敛**（加下限保护） |
| 4 | P2 拆分 | 现在做 / P0 后评估 / 不做 | **P0 后评估** |
| 5 | 255 真机验收结果 | 好 / 还是小窗 / 其他 | —— |

**请用编号短答即可**（如「1.B 2.做 3.允许 4.以后 5.好」），我据此落成 todo 直接开做。

---

## 附：本方案的全部取证位置

| 结论 | 证据 |
|---|---|
| 折叠态是 39% 窄条 | 真机截图 PIL 逐像素：424px/1080px |
| 254 修的下限走不到 | `loadOverlaySize()` :3363 / `flooredExpandedSize()` :3350 均在折叠路径之外 |
| 五连报历史 | `loadOverlaySize()` 内注释原文（:3368-3380） |
| 153 个 fun / 169 成员声明 / 30 尺寸函数 | `grep -c` + 分类统计 |
| 8 个尺寸写点 | `:1354 :1585 :1839 :1983 :2107 :3466 :3526` + `:486` |
| 16 处 updateViewLayout | `grep -c updateViewLayout` |
| 尺寸测试为源码正则 | 5 个测试文件 `readAsStringSync` 计数 |
| 抽取政策类的既有范式 | `RegionWindowAttachPolicy.kt` 头注释（含「改动照样绿」原文） |
| 有可跑的 JVM 测试骨架 | `android/app/src/test/kotlin/.../` 11 个 `*PolicyTest.kt` |
| 过程面板默认收起 | `toggleAiProcessExpanded()` :1191 注释 |
| 测量滞后 | `ensureAnswerOverlayFitsContent()` :3511-3528 |
