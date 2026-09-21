package top.hpa888.box

/**
 * 悬浮窗几何尺寸的**唯一权威决策点**（纯 Kotlin，零 Android 依赖，可 JVM 单测）。
 *
 * ## 为什么必须存在这个类
 *
 * 用户自 2026-09-13 起**连续五次**反馈尺寸类问题：
 * 「悬浮窗太小」→「还很拥挤」→「扩大 1.5 倍」→「大小没有变化」→「还是没有变化」。
 *
 * 每一次都改了代码、都加了测试、发布后用户都说没变化。根因不是某次改动写错，
 * 而是**结构性缺陷**：窗口该多大这件事，原先散落在
 * `QuizAccessibilityService` 的 6 个函数里
 * （`defaultOverlaySize` / `overlaySizeFloor` / `flooredExpandedSize` /
 * `loadOverlaySize` / `setOverlaySizeFromDp` / `applyCollapsedUi`）、
 * `overlayExpandedWidth/Height` 有 **8 处写点**、`updateViewLayout` 有 **16 处出口**。
 *
 * 后果：**每处修复只覆盖自己知道的那条路径**。254 把「大窗下限」加在
 * `loadOverlaySize()` 与 `flooredExpandedSize()` 里 —— 但用户当时处于**折叠态**，
 * 渲染走的是 `applyCollapsedUi()`（设 `WRAP_CONTENT`），压根不经过那两个函数，
 * 于是修复从未被触发，用户看到「没有变化」。
 *
 * ## 本类的契约
 *
 * - [decide] 是**纯函数**：相同输入必得相同输出，不读全局、不碰 View/WindowManager。
 * - 所有尺寸路径（默认 / 读 prefs / 折叠 / 展开 / 内容自适应 / 考试模式）
 *   **一律经 [decide] 产出**，不再各自 `coerceIn`。
 * - 每个 [Decision] 都带 [Decision.reason]，便于 `logDebug` 与调试面板定位
 *   「改了没变化」卡在哪一环。
 *
 * ## 已知取舍（有意为之，非遗漏）
 *
 * - 用户手拖尺寸若**大于**下限，一律尊重用户（[Reason.SAVED]）。
 * - 用户手拖尺寸若**小于**下限，抬到下限（[Reason.FLOOR_RAISED]）——
 *   这是真机五连报的正面修复。
 * - 折叠态在**没有内容**时仍是 `WRAP_CONTENT` 细条（用户选择，须尊重）；
 *   一旦**有 AI 过程内容**就必须自动展开（[Decision.shouldExpand]）——
 *   否则过程③步被挤出视口，用户看到「AI 搜题只显示一半」。
 */
object OverlayGeometryPolicy {

    /** 与 `QuizAccessibilityService.OVERLAY_MIN_WIDTH_DP` 同口径（单一事实源）。 */
    const val MIN_WIDTH_DP = 240
    /** 与 `QuizAccessibilityService.OVERLAY_MIN_HEIGHT_DP` 同口径。 */
    const val MIN_HEIGHT_DP = 140

    /** 大窗默认：屏宽比例。2026-09-18 用户要求「窗口往小、少挡题」：0.94→0.80。 */
    private const val DEFAULT_WIDTH_RATIO = 0.80f
    /** 大窗默认：高度 = 宽度 × 该系数。 */
    private const val DEFAULT_HEIGHT_RATIO_OF_WIDTH = 0.9f
    /** 默认高度不得低于屏高的该比例。2026-09-18 缩小：0.55→0.42（少挡题面）。 */
    private const val DEFAULT_MIN_HEIGHT_RATIO_OF_SCREEN = 0.42f
    /** 内容自适应时，窗口高度上限 = 屏高 × 该系数。 */
    private const val CONTENT_FIT_MAX_HEIGHT_RATIO = 0.92f

    // ── 考试模式三档：一律用「占屏宽比例」，绝不用固定 px（那正是原 bug）。 ──

    /** 考试窗·小：尽量不挡题。 */
    private const val EXAM_WIDTH_RATIO_SMALL = 0.36f
    /** 考试窗·标准：平衡（与普通窗 0.94 刻意拉开，保留「考试=紧凑」的语义）。 */
    private const val EXAM_WIDTH_RATIO_STANDARD = 0.58f
    /**
     * 考试窗·大：答案优先、**肯挡题换宽度**。
     * 0.86 是「能完整放下标题栏 204dp + 正文可读」与「仍露出部分题目」的折中：
     * 真机 360dp 屏 → 310dp 窗，标题栏可用约 300dp > 204dp ✅。
     */
    private const val EXAM_WIDTH_RATIO_LARGE = 0.86f
    /** 考试窗高度 = 宽度 × 该系数（接近方形 = 答案卡片）。 */
    private const val EXAM_HEIGHT_RATIO_OF_WIDTH = 0.92f
    /**
     * 考试窗最小可读宽度（dp）。
     *
     * ⚠️ 必须**低于** [EXAM_WIDTH_RATIO_SMALL] 在窄屏上的产出，否则三档会被
     * 这个下限抬平、塌成一档（「小」和「标准」都变成同一个尺寸，用户会
     * 再次报「改了没变化」）。窄屏 360dp × 0.36 = 130dp，故取 120dp 留出余量。
     */
    private const val EXAM_MIN_WIDTH_DP = 120
    /** 考试窗最小可读高度（dp）。 */
    private const val EXAM_MIN_HEIGHT_DP = 120

    /**
     * 「紧凑卡片」迁移 schema（2026-09-19）。
     *
     * 0.80 新默认（ab80376）上线后用户仍报「窗大」：prefs 里躺着旧时代
     * SAVED 尺寸，[Reason.SAVED] 优先级高于 [Reason.DEFAULT]，新默认
     * 永远轮不到。且 254 的 floor 抬升会把抬升值**写回** prefs
     * （`loadOverlaySize`），让 SAVED 永远 ≥ 旧 floor——一次性清除是
     * 唯一能让新默认落地的手段。
     *
     * ⚠️ 吸取 v4/v5/v6「一次性迁移」教训：这里清的是**尺寸记忆**而非
     * 强设新值；清除后 `loadOverlaySize` 走 [Reason.DEFAULT]（0.80 口径），
     * 用户手拖仍会正常保存（schema 已 ≥8 不再清）。仅清一次、代价可控。
     */
    const val COMPACT_SIZE_SCHEMA = 8

    /**
     * schema 低于 [COMPACT_SIZE_SCHEMA] 的历史保存尺寸应清除一次，
     * 让 0.80 紧凑新默认生效；之后用户手拖照常记忆。
     */
    fun shouldDropSavedSizeForCompact(schema: Int): Boolean = schema < COMPACT_SIZE_SCHEMA

    /** 考试窗标题栏「完整平铺」所需宽度（dp）。
     *
     * = 相似度胶囊 56 + ⋯26 + AI40 + 框选30 + 眼睛26 + 题库26 = 204，
     * 再留内边距/边框余量 16dp（[TITLE_BAR_SIDE_PADDING_DP] 12 + 4dp 边框防漏）。
     * 故 204 + 16 = 220。
     *
     * 2026-09-17 ②-B：此处的 16dp 余量 = 标题栏左右内边距（layout 真值
     * [TITLE_BAR_SIDE_PADDING_DP] = 12）+ 4dp 边框/抗锯齿余量。拆开后两处
     * 口径可互相追溯，避免再出现「padding 余量与 layout 实际值脱节」。
     */
    const val TITLE_BAR_REQUIRED_DP = 220

    /**
     * 收拢后必须**常驻**的高频三键（⋯26 + AI40 + 眼睛26）所需宽度（dp）。
     *
     * 2026-09-17 P2：原值 92dp 以 `val highFreqDp = 92` 硬编码在
     * [QuizAccessibilityService] 里（「拍脑袋估算值」，未走 policy）。收进
     * 本文件作单一事实源，便于真机校准时只改一处。
     *
     * ⚠️ 这是**估算值**，基于按钮在 360dp 宽设计稿上的实测宽度之和；
     * 红米 K80（density 4.0）等真机尚未校准。若收拢后仍被裁，优先调大这里，
     * 而不是在 service 里另写一个数。
     */
    const val TITLE_BAR_HIGH_FREQ_DP = 92

    /**
     * 考试窗标题栏**左右内边距合计**（dp）。
     *
     * 2026-09-17 ②-B：**对齐 layout 真值**。原以 `16 * d` 字面量散在
     * [QuizAccessibilityService] 的 `applyTitleBarCollapseIfNeeded` 里，
     * 但 `quiz_overlay.xml` 的 `title_bar` 实际是 `paddingStart=12dp` +
     * `paddingEnd=0dp`（右滑区贴边，靠 HorizontalScrollView 自己收），
     * 合计 = **12dp**。收进本文件作单一事实源后校准到 12。
     *
     * 对应 [titleBarFits] 的可用宽度口径（`widthPixels - 12 * d`），
     * 与 [TITLE_BAR_REQUIRED_DP] 里的内边距分量同源。
     *
     * ⚠️ 若 layout 改 padding（或改为 0 / 挂到子控件），只改这里一处，
     * 不要在 service 再写新的估算。
     */
    const val TITLE_BAR_SIDE_PADDING_DP = 12

    /**
     * 决策结果。
     *
     * @param width  最终窗口宽度（px）。**等于** [WindowManager.LayoutParams.WRAP_CONTENT]
     *               时表示交给系统按内容量算（仅折叠小窗用）。
     * @param height 最终窗口高度（px）。同上。
     * @param reason 命中哪条规则（打日志 / 调试面板 / 单测断言用）。
     * @param shouldExpand 折叠态下是否**应当自动展开**。非折叠态恒为 false。
     */
    data class Decision(
        val width: Int,
        val height: Int,
        val reason: Reason,
        val shouldExpand: Boolean = false,
    ) {
        /** 是否交给系统按内容量算尺寸（折叠细条）。 */
        val isWrapContent: Boolean
            get() = width == WRAP_CONTENT || height == WRAP_CONTENT

        companion object {
            /**
             * 与 `android.view.ViewGroup.LayoutParams.WRAP_CONTENT` 同为 -2。
             * 纯 Kotlin 类不能 import Android，故本地定义（值必须一致）。
             */
            const val WRAP_CONTENT = -2
        }
    }

    /** 命中哪条规则。顺序即优先级。 */
    enum class Reason {
        /** 考试模式：完全独立的一套尺寸口径。 */
        EXAM_MODE,

        /** 折叠且无内容：`WRAP_CONTENT` 细条（用户选择，尊重）。 */
        COLLAPSED_WRAP,

        /** 折叠但有内容：应自动展开，改用展开尺寸。 */
        COLLAPSED_AUTO_EXPAND,

        /** 无保存值：用大窗默认（屏宽 94%）。 */
        DEFAULT,

        /** 保存值 ≥ 下限：尊重用户手拖。 */
        SAVED,

        /** 保存值 < 下限：抬到下限（真机五连报的正面修复）。 */
        FLOOR_RAISED,

        /** 内容自适应：按内容需要的高度撑开（受屏高上限约束）。 */
        CONTENT_FIT,
    }

    /**
     * 决策输入。**全部显式传入**，不读全局状态。
     *
     * @param screenW/screenH 屏幕像素尺寸
     * @param density         `DisplayMetrics.density`
     * @param savedW/savedH   prefs 里保存的用户尺寸（px）；无则 null
     * @param collapsed       是否折叠态
     * @param examMode        是否考试模式
     * @param contentNeededH  内容需要的高度（px）；0 表示「无内容需求」
     */
    data class Input(
        val screenW: Int,
        val screenH: Int,
        val density: Float,
        val savedW: Int? = null,
        val savedH: Int? = null,
        val collapsed: Boolean = false,
        val examMode: Boolean = false,
        /** 考试模式专用：已由 `examOverlayDimensions()` 算好的尺寸。 */
        val examW: Int = 0,
        val examH: Int = 0,
        val contentNeededH: Int = 0,
    )

    /** 大窗默认尺寸（px）——原先 `defaultOverlaySize()` 的公式，原样搬来。 */
    fun defaultSize(screenW: Int, screenH: Int, density: Float): Pair<Int, Int> {
        if (density <= 0f) return screenW to screenH
        val screenWDp = screenW / density
        val screenHDp = screenH / density
        val wDp = (screenWDp * DEFAULT_WIDTH_RATIO)
            .coerceIn(MIN_WIDTH_DP.toFloat(), screenWDp)
        val hDp = (wDp * DEFAULT_HEIGHT_RATIO_OF_WIDTH)
            .coerceIn(
                maxOf(MIN_HEIGHT_DP.toFloat(), screenHDp * DEFAULT_MIN_HEIGHT_RATIO_OF_SCREEN),
                screenHDp,
            )
        return (wDp * density).toInt() to (hDp * density).toInt()
    }

    /** 大窗下限（px）——原先 `overlaySizeFloor()`，即 defaultSize 夹到屏幕内。 */
    fun floorSize(screenW: Int, screenH: Int, density: Float): Pair<Int, Int> {
        val (w, h) = defaultSize(screenW, screenH, density)
        return w.coerceAtMost(screenW) to h.coerceAtMost(screenH)
    }

    /** 用户尺寸下限（px）——原先散落的 `OVERLAY_MIN_*_DP * density`。 */
    fun userMinSize(density: Float): Pair<Int, Int> =
        (MIN_WIDTH_DP * density).toInt() to (MIN_HEIGHT_DP * density).toInt()

    /**
     * **唯一权威决策**。所有尺寸路径都走这里。
     *
     * 优先级（自上而下，先命中先返回）：
     * 1. 考试模式 → [Reason.EXAM_MODE]
     * 2. 折叠 + 有内容 → [Reason.COLLAPSED_AUTO_EXPAND]（`shouldExpand = true`）
     * 3. 折叠 + 无内容 → [Reason.COLLAPSED_WRAP]
     * 4. 有内容需求 → [Reason.CONTENT_FIT]
     * 5. 有保存值 → [Reason.SAVED] 或 [Reason.FLOOR_RAISED]
     * 6. 否则 → [Reason.DEFAULT]
     */
    fun decide(input: Input): Decision {
        val (screenW, screenH, density) = Triple(input.screenW, input.screenH, input.density)
        val (floorW, floorH) = floorSize(screenW, screenH, density)

        // ① 考试模式：完全独立口径，不受折叠/保存值影响。
        if (input.examMode) {
            if (input.examW > 0 && input.examH > 0) {
                return Decision(
                    input.examW.coerceIn(1, screenW),
                    input.examH.coerceIn(1, screenH),
                    Reason.EXAM_MODE,
                )
            }
            return Decision(floorW, floorH, Reason.EXAM_MODE)
        }

        // ②③ 折叠态。
        if (input.collapsed) {
            // 折叠是**用户的选择**，不能一见内容就弹开 —— 但 AI 作答过程一旦有内容，
            // 窗口是 WRAP_CONTENT 细条就必然把它裁掉（用户报「只显示一半 / 没优化」）。
            // 故：有内容 → 自动展开；无内容 → 保持细条。
            if (input.contentNeededH > 0) {
                // ⚠️ 这里必须**同时**考虑内容高度，不能只给展开尺寸：
                // 自动展开的目的就是让被裁的 ②③ 步可见，若展开后的高度仍装不下内容，
                // 用户看到的还是「只显示一半」——等于没修。测试曾在此红过一次。
                val (ew, eh0) = expandedSize(input, floorW, floorH)
                val maxH = (screenH * CONTENT_FIT_MAX_HEIGHT_RATIO).toInt()
                val eh = maxOf(eh0, input.contentNeededH)
                    .coerceIn(floorH, maxH.coerceAtLeast(floorH))
                return Decision(ew, eh, Reason.COLLAPSED_AUTO_EXPAND, shouldExpand = true)
            }
            return Decision(Decision.WRAP_CONTENT, Decision.WRAP_CONTENT, Reason.COLLAPSED_WRAP)
        }

        // ④ 内容自适应：按内容需要的高度定高（决策 3：允许收敛）。
        //
        // ⚠️ 这里**不能**写成 maxOf(eh, contentNeededH)：
        // `eh` 是「保存的展开高度」，只会随用户拉大而变大、永不回收，
        // 于是长答案把窗撑高后，后续短答案仍留一大片空白（用户会当成 bug 报）。
        // 正确做法：**以内容需求定高**，再夹到 [floorH, maxH] —— 内容少就缩小，
        // 但绝不小于下限（下限是「连续五次报太小」的修复成果，不能丢）。
        if (input.contentNeededH > 0) {
            val (ew, _) = expandedSize(input, floorW, floorH)
            val maxH = (screenH * CONTENT_FIT_MAX_HEIGHT_RATIO).toInt()
            val target = input.contentNeededH
            // 内容少就缩小、内容多就长高，但绝不越过 [floorH, maxH]。
            // 下限保护是「连续五次报太小」的修复成果，绝不能被收敛吃掉。
            val h = target.coerceIn(floorH, maxH.coerceAtLeast(floorH))
            return Decision(ew, h, Reason.CONTENT_FIT)
        }

        // ⑤⑥ 常规：保存值优先，低于下限则抬到下限。
        val (ew, eh) = expandedSize(input, floorW, floorH)
        val reason = if (input.savedW == null && input.savedH == null) {
            Reason.DEFAULT
        } else if (ew > (input.savedW ?: 0) || eh > (input.savedH ?: 0)) {
            Reason.FLOOR_RAISED
        } else {
            Reason.SAVED
        }
        return Decision(ew, eh, reason)
    }

    // ─────────────────────────────────────────────────────────────
    // 考试模式
    // ─────────────────────────────────────────────────────────────

    /** 考试模式档位（与 Flutter `QuizConfig.examOverlaySize` 同口径）。 */
    object ExamSize {
        const val SMALL = "small"
        const val STANDARD = "standard"
        const val LARGE = "large"

        /** 规整为三档之一；未知值一律回落 [STANDARD]。 */
        fun normalize(raw: String?): String = when (raw) {
            SMALL, STANDARD, LARGE -> raw
            else -> STANDARD
        }
    }

    /**
     * 考试模式窗口尺寸（px）——**唯一权威**。
     *
     * ## 为什么必须收进这里
     *
     * 原实现在 `QuizAccessibilityService.examOverlayDimensions()` 里长这样：
     *
     * ```kotlin
     * val w = (dm.widthPixels * 0.46f).toInt().coerceIn(300, 500)
     * ```
     *
     * 它在 **px 域**算出 `579`，却用**照 dp 直觉写的** `300/500` 去夹。
     * `WindowManager.LayoutParams.width` 的单位是 px，于是真机
     * （1260px / density 3.5）上窗口被夹成 `500px = 143dp`，只占屏宽 **40%**。
     * 三档的固定上限 `390 / 500 / 590` 全部中招 —— **连「大」档都只有 169dp**。
     *
     * 后果：标题栏 6 个按钮共需 204dp，而三档可用宽度分别只有
     * 103 / 135 / 161 dp —— **没有一档装得下**，按钮必然被裁
     * （用户截图里 AI 按钮只剩「AI-」，就是这一条）。
     *
     * 这正是用户 2026-09-16 反馈的「开启考试模式就一直是小窗」：
     * **不是设计成小窗，而是上限值被 px/dp 混淆压小了约 1/density 倍**。
     *
     * ## 修法
     *
     * 与 [defaultSize] 同口径：**全程在 dp 域算比例，最后才 `× density` 换回 px**。
     * 三档改为「占屏宽的百分比」，不再出现任何固定 px 数字 —— 固定 px 上限
     * 正是原 bug 的载体；换成比例后在任何 density / 分辨率上都成立。
     *
     * ## 三档取舍（用户 2026-09-16 拍板）
     *
     * 考试窗「不挡题」优先：题目在下方，窗盖在上面。故：
     * - [ExamSize.SMALL]    尽量不挡 → 窄
     * - [ExamSize.STANDARD] 平衡
     * - [ExamSize.LARGE]    **答案优先、肯挡题换宽度** → 唯一放得下完整标题栏的档
     *
     * @param screenW 屏宽（px）
     * @param screenH 屏高（px）
     * @param density 屏幕密度（px/dp）
     * @param preference 档位；未知值回落 [ExamSize.STANDARD]
     */
    fun examSize(
        screenW: Int,
        screenH: Int,
        density: Float,
        preference: String? = null,
    ): Pair<Int, Int> {
        if (density <= 0f) return screenW to screenH
        val ratio = when (ExamSize.normalize(preference)) {
            ExamSize.SMALL -> EXAM_WIDTH_RATIO_SMALL
            ExamSize.LARGE -> EXAM_WIDTH_RATIO_LARGE
            else -> EXAM_WIDTH_RATIO_STANDARD
        }
        val screenWDp = screenW / density
        val screenHDp = screenH / density
        // 宽度：屏宽 × 比例，夹到「不超屏」且不低于最小可读宽度。
        val wDp = (screenWDp * ratio).coerceIn(EXAM_MIN_WIDTH_DP.toFloat(), screenWDp)
        // 高度：由宽度推导（接近方形 = 答案卡片设计），再夹进屏内。
        val hDp = (wDp * EXAM_HEIGHT_RATIO_OF_WIDTH)
            .coerceIn(EXAM_MIN_HEIGHT_DP.toFloat(), maxOf(EXAM_MIN_HEIGHT_DP.toFloat(), screenHDp))
        return (wDp * density).toInt() to (hDp * density).toInt()
    }

    /**
     * 考试窗标题栏能否**完整平铺**全部按钮（不做任何隐藏/收缩）。
     *
     * 供 `applyTitleBarAdaptive` / 收拢判定决定走「平铺」还是「收进更多菜单」。
     * 阈值以 dp 表达；调用方传入**标题栏此刻真正能布局的像素宽度**。
     *
     * ⚠️ **口径说明（2026-09-17 ③-A）**：不同调用点算出的「标题栏可用宽度」来源不同，
     * 但语义统一为「标题栏实际能排按钮的像素」，**不是屏幕宽度**：
     * - examSize 路径：传**考试窗宽度**（实测窗宽 px）；
     * - 收拢路径（`applyTitleBarCollapseIfNeeded`）：传**屏宽 − 左右内边距**
     *   （`widthPixels - TITLE_BAR_SIDE_PADDING_DP * d`），因为此时窗口尚未测量。
     * 两者都是「标题栏可用的像素」，只是取值时机不同。调用方务必保证传入的是
     * 该口径下的值，勿混入裸屏宽（会让收拢判定偏松）。
     *
     * @param titleBarUsableWidthPx 标题栏实际可布局宽度（px，见上方口径说明）
     * @param density               屏幕密度
     * @param requiredDp            全部按钮所需宽度（dp）
     */
    fun titleBarFits(
        titleBarUsableWidthPx: Int,
        density: Float,
        requiredDp: Int = TITLE_BAR_REQUIRED_DP,
    ): Boolean {
        if (density <= 0f) return true
        return titleBarUsableWidthPx >= requiredDp * density
    }

    /**
     * 展开尺寸（px）：保存值优先，但**一律不低于下限**。
     *
     * 这是 254 修复的正确形态 —— 但 254 只把它接在了 `loadOverlaySize()` /
     * `flooredExpandedSize()` 上，折叠路径绕过了它，所以没生效。
     * 现在所有路径都经 [decide] 调用本函数，结构上不可能再漏。
     */
    fun expandedSize(input: Input, floorW: Int, floorH: Int): Pair<Int, Int> {
        val (minW, minH) = userMinSize(input.density)
        val rawW = input.savedW ?: 0
        val rawH = input.savedH ?: 0
        // 保存值先夹到屏幕内（防历史脏值），再抬到下限。
        val w0 = if (rawW > 0) rawW.coerceIn(minW, input.screenW) else floorW
        val h0 = if (rawH > 0) rawH.coerceIn(minH, input.screenH) else floorH
        val w = w0.coerceAtLeast(floorW).coerceAtMost(input.screenW)
        val h = h0.coerceAtLeast(floorH).coerceAtMost(input.screenH)
        return w to h
    }

    // ───────────────────────── 位置（考试窗） ─────────────────────────
    //
    // 背景（2026-09-16）：尺寸决策早已收口到本文件，**位置没有** —— `params.x =`
    // 在 service 里散落 12 处，其中考试模式的两处（:826 / :1181）**硬编码右上角**，
    // 导致用户拖走考试窗后，下次进入考试模式必被弹回右上角。
    // 而普通模式的位置是**有记忆**的（KEY_OVERLAY_GEOMETRY）。
    // 同一个「窗口该在哪」两套口径 —— 属 USER.md 点名的「同类能力散落多处」。

    /** 考试窗锚点比例：右侧留白 / 顶部留白（屏宽、屏高占比）。 */
    const val EXAM_ANCHOR_END_RATIO = 0.03f
    const val EXAM_ANCHOR_TOP_RATIO = 0.08f

    /**
     * 默认右上锚点（px）——考试模式**首次**进入时使用，保证从不记忆的用户体验不变。
     *
     * 与旧硬编码 `widthPixels - w - widthPixels * 0.03f` 逐位等价。
     */
    fun examAnchor(
        screenW: Int,
        screenH: Int,
        width: Int,
        height: Int,
        endRatio: Float = EXAM_ANCHOR_END_RATIO,
        topRatio: Float = EXAM_ANCHOR_TOP_RATIO,
    ): Pair<Int, Int> {
        val maxX = (screenW - width).coerceAtLeast(0)
        val maxY = (screenH - height).coerceAtLeast(0)
        val x = (screenW - width - screenW * endRatio).toInt().coerceIn(0, maxX)
        val y = (screenH * topRatio).toInt().coerceIn(0, maxY)
        return x to y
    }

    /**
     * 解析持久化的位置串 `"x,y"` 并夹进取景范围。
     *
     * @return 合法位置；无法解析或超界时返回 null（调用方回退到 [examAnchor]）。
     */
    fun parsePosition(
        raw: String?,
        screenW: Int,
        screenH: Int,
        width: Int,
        height: Int,
    ): Pair<Int, Int>? {
        if (raw.isNullOrBlank()) return null
        val p = raw.split(',').mapNotNull { it.trim().toIntOrNull() }
        if (p.size < 2) return null
        val maxX = (screenW - width).coerceAtLeast(0)
        val maxY = (screenH - height).coerceAtLeast(0)
        // 夹取而非判废：旋转屏幕后旧坐标可能只有一边超界，夹回来比丢弃更贴近用户意图。
        return p[0].coerceIn(0, maxX) to p[1].coerceIn(0, maxY)
    }

    /**
     * 考试窗位置：**记忆优先，否则右上角**。
     *
     * 这是 P1-1 的核心 —— 让考试模式与普通模式口径一致（都有记忆），
     * 同时保留「从未拖过 → 右上角」的默认体验。
     *
     * @param savedRaw 持久化的 `"x,y"`（可为 null）
     */
    fun examPosition(
        savedRaw: String?,
        screenW: Int,
        screenH: Int,
        width: Int,
        height: Int,
    ): Pair<Int, Int> =
        parsePosition(savedRaw, screenW, screenH, width, height)
            ?: examAnchor(screenW, screenH, width, height)
}
