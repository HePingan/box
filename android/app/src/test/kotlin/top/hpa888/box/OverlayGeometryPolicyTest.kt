package top.hpa888.box

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * [OverlayGeometryPolicy] 的状态机全组合测试。
 *
 * ## 为什么这个测试与以往不同
 *
 * 尺寸类问题此前有 5 个测试文件（`quiz_size_log_prompt_user_asks_v5`、
 * `quiz_overlay_scale_v6_and_vision_degenerate`、`quiz_overlay_expanded_size_floor` …），
 * 但它们**全是 Dart 侧对 `.kt` 源码做正则文本断言** —— 只验证「源码里有这个修复」，
 * 从不执行折叠路径。所以 254 的修复测试是绿的，真机却完全没变化。
 *
 * 本测试直接**调用生产代码的 [OverlayGeometryPolicy.decide]**，断言**输出值**。
 * 生产代码改坏了，这里必红。
 *
 * ## 覆盖的状态空间
 *
 * 折叠 × 考试 × 有/无保存值 × 保存值小于下限 × 内容超屏 × 内容为空 × 脏值超屏
 */
class OverlayGeometryPolicyTest {

    /** iQOO 真机（用户报告机之一）：1080×2400，密度 2.75。 */
    private val iqoo = Triple(1080, 2400, 2.75f)

    /** 红米 K80（另一台报障机）：1220×2712，密度 2.75。 */
    private val redmi = Triple(1220, 2712, 2.75f)

    /** 高密度机（早期注释提到的 1440px / 3.5）：1440×3200，密度 3.5。 */
    private val hiDpi = Triple(1440, 3200, 3.5f)

    private fun input(
        screen: Triple<Int, Int, Float>,
        savedW: Int? = null,
        savedH: Int? = null,
        collapsed: Boolean = false,
        examMode: Boolean = false,
        contentNeededH: Int = 0,
        examW: Int = 0,
        examH: Int = 0,
    ) = OverlayGeometryPolicy.Input(
        screenW = screen.first,
        screenH = screen.second,
        density = screen.third,
        savedW = savedW,
        savedH = savedH,
        collapsed = collapsed,
        examMode = examMode,
        contentNeededH = contentNeededH,
        examW = examW,
        examH = examH,
    )

    // ────────────────────────────────────────────────────────────
    // ① 回归核心：折叠态 + 有 AI 过程内容 → 必须自动展开
    //     这正是用户 2026-09-15 报「ai搜题显示也没有优化」的真因：
    //     窗口是 WRAP_CONTENT 细条，②③ 步被裁掉，只看得见 ① 行。
    // ────────────────────────────────────────────────────────────
    @Test
    fun `折叠态有内容时必须自动展开且给足高度`() {
        val d = OverlayGeometryPolicy.decide(
            input(iqoo, collapsed = true, contentNeededH = 1980)
        )
        assertTrue("折叠态有内容必须要求展开", d.shouldExpand)
        assertEquals(
            "折叠自动展开应走 COLLAPSED_AUTO_EXPAND",
            OverlayGeometryPolicy.Reason.COLLAPSED_AUTO_EXPAND, d.reason,
        )
        assertFalse("自动展开后不应再是 WRAP_CONTENT 细条", d.isWrapContent)
        val (floorW, floorH) = OverlayGeometryPolicy.floorSize(1080, 2400, 2.75f)
        assertTrue("宽度不得低于大窗下限 $floorW，实际 ${d.width}", d.width >= floorW)
        assertTrue("高度不得低于大窗下限 $floorH，实际 ${d.height}", d.height >= floorH)
        assertTrue("高度需容下内容 1980，实际 ${d.height}", d.height >= 1980)
    }

    // ② 折叠态无内容 → 保持细条（尊重用户折叠选择，不无脑弹开）
    @Test
    fun `折叠态无内容时保持 WRAP_CONTENT 细条`() {
        val d = OverlayGeometryPolicy.decide(input(iqoo, collapsed = true))
        assertEquals(OverlayGeometryPolicy.Reason.COLLAPSED_WRAP, d.reason)
        assertTrue("无内容时应是 WRAP_CONTENT", d.isWrapContent)
        assertFalse("无内容不应自动展开", d.shouldExpand)
    }

    // ③ 非折叠态永不应报告 shouldExpand（避免调用方误展开）
    @Test
    fun `非折叠态 shouldExpand 恒为 false`() {
        listOf(
            input(iqoo),
            input(iqoo, savedW = 900, savedH = 1200),
            input(iqoo, contentNeededH = 1500),
        ).forEach {
            assertFalse("非折叠态不应要求展开", OverlayGeometryPolicy.decide(it).shouldExpand)
        }
    }

    // ────────────────────────────────────────────────────────────
    // ④ 五连报核心：保存值小于下限 → 必须抬到下限
    // ────────────────────────────────────────────────────────────
    @Test
    fun `保存值小于下限时抬到下限`() {
        // 用户历史 prefs 里躺着的小窗值（正是 39% 窄条量级）
        val d = OverlayGeometryPolicy.decide(input(iqoo, savedW = 424, savedH = 600))
        val (floorW, floorH) = OverlayGeometryPolicy.floorSize(1080, 2400, 2.75f)
        assertEquals(OverlayGeometryPolicy.Reason.FLOOR_RAISED, d.reason)
        assertEquals("宽度应抬到下限", floorW, d.width)
        assertTrue("高度应不低于下限", d.height >= floorH)
    }

    // ⑤ 保存值大于下限 → 尊重用户手拖（不擅自改小/改大）
    @Test
    fun `保存值大于下限时尊重用户`() {
        val (floorW, floorH) = OverlayGeometryPolicy.floorSize(1080, 2400, 2.75f)
        val bigW = floorW + 40
        val bigH = floorH + 80
        val d = OverlayGeometryPolicy.decide(input(iqoo, savedW = bigW, savedH = bigH))
        assertEquals(OverlayGeometryPolicy.Reason.SAVED, d.reason)
        assertEquals(bigW, d.width)
        assertEquals(bigH, d.height)
    }

    // ⑥ 无保存值 → 大窗默认（屏宽 80%，2026-09-18 缩小少挡题）
    @Test
    fun `无保存值时取大窗默认`() {
        val d = OverlayGeometryPolicy.decide(input(iqoo))
        assertEquals(OverlayGeometryPolicy.Reason.DEFAULT, d.reason)
        // 屏宽 80% = 864px（1080×0.80），下限更高则取下限
        val expectW = maxOf((1080 * 0.80f).toInt(), OverlayGeometryPolicy.floorSize(1080, 2400, 2.75f).first)
        assertEquals(expectW, d.width)
    }

    // ⑦ 脏值（超过屏幕）必须夹回屏幕内，绝不溢出
    @Test
    fun `保存值超过屏幕时夹回屏幕`() {
        val d = OverlayGeometryPolicy.decide(input(iqoo, savedW = 99999, savedH = 99999))
        assertEquals(1080, d.width)
        assertEquals(2400, d.height)
    }

    // ⑧ 负值 / 0 等脏值不得让窗口变成非法尺寸
    @Test
    fun `保存值为零或负时退回默认而非非法尺寸`() {
        listOf(-100, 0).forEach { bad ->
            val d = OverlayGeometryPolicy.decide(input(iqoo, savedW = bad, savedH = bad))
            assertTrue("宽度必须为正，输入 $bad 得到 ${d.width}", d.width > 0)
            assertTrue("高度必须为正，输入 $bad 得到 ${d.height}", d.height > 0)
            assertFalse("不得退化成 WRAP_CONTENT", d.isWrapContent)
        }
    }

    // ────────────────────────────────────────────────────────────
    // ⑨ 内容自适应
    // ────────────────────────────────────────────────────────────
    @Test
    fun `内容超高时撑开但不超过屏高上限`() {
        val d = OverlayGeometryPolicy.decide(input(iqoo, contentNeededH = 99999))
        assertEquals(OverlayGeometryPolicy.Reason.CONTENT_FIT, d.reason)
        val maxH = (2400 * 0.92f).toInt()
        assertEquals("高度应被屏高 92% 封顶", maxH, d.height)
    }

    @Test
    fun `内容很矮时不低于下限`() {
        val d = OverlayGeometryPolicy.decide(input(iqoo, contentNeededH = 10))
        val (_, floorH) = OverlayGeometryPolicy.floorSize(1080, 2400, 2.75f)
        assertTrue("高度不得低于下限 $floorH，实际 ${d.height}", d.height >= floorH)
    }

    // ────────────────────────────────────────────────────────────
    // ⑩ 考试模式：独立口径，不受折叠/保存值干扰
    // ────────────────────────────────────────────────────────────
    @Test
    fun `考试模式使用专属尺寸且不受保存值影响`() {
        val d = OverlayGeometryPolicy.decide(
            input(iqoo, examMode = true, examW = 500, examH = 460, savedW = 900, savedH = 1200)
        )
        assertEquals(OverlayGeometryPolicy.Reason.EXAM_MODE, d.reason)
        assertEquals(500, d.width)
        assertEquals(460, d.height)
    }

    @Test
    fun `考试模式即使折叠也不走折叠分支`() {
        val d = OverlayGeometryPolicy.decide(
            input(iqoo, examMode = true, collapsed = true, examW = 500, examH = 460)
        )
        assertEquals("考试模式优先级高于折叠", OverlayGeometryPolicy.Reason.EXAM_MODE, d.reason)
        assertFalse("考试模式不应触发折叠自动展开", d.shouldExpand)
    }

    @Test
    fun `考试模式未给尺寸时退回大窗下限`() {
        val d = OverlayGeometryPolicy.decide(input(iqoo, examMode = true))
        val (floorW, floorH) = OverlayGeometryPolicy.floorSize(1080, 2400, 2.75f)
        assertEquals(floorW, d.width)
        assertEquals(floorH, d.height)
    }

    // ────────────────────────────────────────────────────────────
    // ⑪ 跨机型：下限公式不得写出硬化像素值
    //     （历史坑：0.52f 系数配 280/480px 硬边界 → 高密度机窗口只 137dp）
    // ────────────────────────────────────────────────────────────
    @Test
    fun `三种机型的大窗默认都占屏宽约 80 且不溢出`() {
        listOf(iqoo, redmi, hiDpi).forEach { s ->
            val (w, _) = OverlayGeometryPolicy.defaultSize(s.first, s.second, s.third)
            val ratio = w.toFloat() / s.first
            assertTrue("${s.first}px 机型宽度占比应 ≥0.78，实际 $ratio", ratio >= 0.78f)
            assertTrue("宽度不得溢出屏幕", w <= s.first)
        }
    }

    @Test
    fun `密度为零等非法输入不得崩溃`() {
        val d = OverlayGeometryPolicy.decide(
            OverlayGeometryPolicy.Input(screenW = 1080, screenH = 2400, density = 0f)
        )
        assertTrue("不得返回非法尺寸", d.width > 0 && d.height > 0)
    }

    @Test
    fun `极窄屏下下限自动夹到屏幕宽而非溢出`() {
        // 320×480 的老设备：屏幕宽 320 < 240dp×density(1.0)=240 的极限情况
        val d = OverlayGeometryPolicy.decide(
            OverlayGeometryPolicy.Input(320, 480, 1.0f, savedW = 3000, savedH = 4000)
        )
        assertTrue("宽度必须 ≤ 屏宽 320，实际 ${d.width}", d.width <= 320)
        assertTrue("高度必须 ≤ 屏高 480，实际 ${d.height}", d.height <= 480)
    }

    // ────────────────────────────────────────────────────────────
    //  决策 3「允许收敛」：短内容必须能收回，且绝不小于下限
    //  （2026-09-15 用户拍板。原「只增高不缩小」会让长答案撑开后
    //   短答案仍留一大片空白 → 用户当成 bug 报。）
    // ────────────────────────────────────────────────────────────
    @Test
    fun `短内容会把窗口收回而不是保留上次的大高度`() {
        // 场景：先被长内容撑到 1600（并保存），随后内容只有 900。
        val tall = OverlayGeometryPolicy.decide(
            OverlayGeometryPolicy.Input(
                iqoo.first, iqoo.second, iqoo.third,
                savedW = null, savedH = 1600, contentNeededH = 1600,
            )
        )
        val short = OverlayGeometryPolicy.decide(
            OverlayGeometryPolicy.Input(
                iqoo.first, iqoo.second, iqoo.third,
                savedW = null, savedH = 1600, contentNeededH = 900,
            )
        )
        assertTrue(
            "短内容必须比长内容矮（允许收敛），实际 tall=${tall.height} short=${short.height}",
            short.height < tall.height,
        )
    }

    @Test
    fun `收敛不得突破下限（否则退回小窗这一历史缺陷）`() {
        // 内容极小（300px），但下限必须兜住 —— 用户连报五次「太小」的修复成果。
        val d = OverlayGeometryPolicy.decide(
            OverlayGeometryPolicy.Input(
                iqoo.first, iqoo.second, iqoo.third,
                savedW = null, savedH = 1600, contentNeededH = 300,
            )
        )
        val (_, floorH) = OverlayGeometryPolicy.floorSize(
            iqoo.first, iqoo.second, iqoo.third
        )
        assertTrue(
            "收敛后高度 ${d.height} 不得小于下限 $floorH",
            d.height >= floorH,
        )
    }

    @Test
    fun `内容超出屏高上限时被夹住而不是溢出`() {
        val d = OverlayGeometryPolicy.decide(
            OverlayGeometryPolicy.Input(
                iqoo.first, iqoo.second, iqoo.third,
                savedW = null, savedH = 1600, contentNeededH = 99999,
            )
        )
        assertTrue("高度必须 ≤ 屏高，实际 ${d.height}", d.height <= iqoo.second)
    }

    /**
     * 真机日志回归（用户 2026-09-15，32 行诊断原文）。
     *
     * 日志里尺寸决策是正确的：
     *   overlay.default screen=1260x2800px density=3.5 -> 1184x1540px (338x440dp)
     * 但用户截图里窗口只有 ~500px、贴右上角、文字被底边裁断。
     *
     * 500px + 右上角 = **考试模式** 的特征（0.46*1260=580 夹到 [300,500] → 500）。
     * 本用例把「考试模式会无视内容需求」这一行为**显式钉住**，
     * 防止将来有人以为普通路径的修复能覆盖考试窗。
     */
    @Test
    fun `真机回归——考试模式会无视内容需求并返回专属小窗（即卡住时的 500px）`() {
        // iQOO PD2352B: 1260x2800 @3.5
        val screenW = 1260
        val screenH = 2800
        val density = 3.5f
        // examOverlayDimensions() else 分支：0.46*1260=579 → coerceIn(300,500) = 500
        val examW = 500
        val examH = 460
        val d = OverlayGeometryPolicy.decide(
            OverlayGeometryPolicy.Input(
                screenW, screenH, density,
                collapsed = false,
                examMode = true,
                examW = examW,
                examH = examH,
                // 即使内容需要很高，考试模式也不理会 —— 这正是文字被裁断的原因
                contentNeededH = 2000,
            )
        )
        assertEquals(OverlayGeometryPolicy.Reason.EXAM_MODE, d.reason)
        // 500/1260 = 39.7% —— 与用户截图的 ~40% 屏宽吻合
        assertEquals(500, d.width)
        assertTrue(
            "考试窗只占屏宽约 40%，这就是用户看到的「小窗」",
            d.width.toFloat() / screenW < 0.45f,
        )
    }

    /**
     * 普通模式（非考试）在同一台机器上必须给出 80% 屏宽的大窗（2026-09-18 缩小）——
     * 证明「小窗」不是普通路径的锅，而是考试模式短路。
     */
    @Test
    fun `真机回归——同一台机器非考试模式必须是 80 屏宽大窗`() {
        val d = OverlayGeometryPolicy.decide(
            OverlayGeometryPolicy.Input(1260, 2800, 3.5f, collapsed = false)
        )
        assertFalse("非考试模式不得返回 EXAM_MODE", d.reason == OverlayGeometryPolicy.Reason.EXAM_MODE)
        assertEquals(
            "1008px 正是 0.80 口径下 overlay.default 的值（1260×0.80）",
            1008,
            d.width,
        )
    }

    // ═══════════════════════════════════════════════════════════
    // 考试模式尺寸：px/dp 混淆回归（2026-09-16 用户报「一直小窗」）
    // ═══════════════════════════════════════════════════════════
    //
    // 真机 iQOO：screen=1260x2800px, density=3.5 → configDp=360x800。
    private val phoneW = 1260
    private val phoneH = 2800
    private val phoneD = 3.5f

    /**
     * 红灯回归：考试窗宽度必须以 **dp 域比例** 产出。
     *
     * 旧实现 `(widthPixels * 0.46).toInt().coerceIn(300, 500)` 在 px 域算出 579，
     * 却被 dp 直觉的 500 夹住 → 500px = 143dp，只占屏宽 40%。
     * 本用例锁死「按比例、按 dp」的新口径。
     */
    @Test
    fun `考试窗宽度不能再用固定 px 上限夹 -- standard 档`() {
        val (w, _) = OverlayGeometryPolicy.examSize(phoneW, phoneH, phoneD, "standard")
        // 旧实现给出 500px；新实现按 0.58 屏宽 → 731px
        assertTrue(
            "考试窗标准档必须 > 旧 px 上限 500，实际 $w；说明仍在用固定 px 夹",
            w > 500,
        )
        assertEquals("0.58 * 360dp = 208.8dp → 730px", 730, w)
    }

    /**
     * 「大」档是用户选来「要更宽」的 —— 它必须比标准档更宽，
     * 且**必须能容纳标题栏全部按钮（204dp + 余量 = 220dp）**。
     */
    @Test
    fun `考试窗大档必须放得下标题栏全部按钮`() {
        val (w, _) = OverlayGeometryPolicy.examSize(phoneW, phoneH, phoneD, "large")
        val requiredPx = OverlayGeometryPolicy.TITLE_BAR_REQUIRED_DP * phoneD
        assertTrue(
            "大档宽 $w px 不足以容纳标题栏 $requiredPx px(=220dp) —— 按钮仍会被裁",
            w - 16 * phoneD >= requiredPx,
        )
        assertTrue("大档必须比标准档宽", w > 730)
    }

    /** 三档必须严格递增（用户能感知到「调大真的变大」）。 */
    @Test
    fun `考试窗三档宽度必须严格递增`() {
        val s = OverlayGeometryPolicy.examSize(phoneW, phoneH, phoneD, "small").first
        val m = OverlayGeometryPolicy.examSize(phoneW, phoneH, phoneD, "standard").first
        val l = OverlayGeometryPolicy.examSize(phoneW, phoneH, phoneD, "large").first
        assertTrue("小($s) < 标准($m) < 大($l) 必须成立", s < m && m < l)
    }

    /**
     * 旧 bug 的直接反证：三档**都**曾被夹到 390/500/590 px，
     * 对应 dz 111/143/169dp —— 全部装不下 204dp 的按钮。
     * 现在任何一档都不得小于 EXAM_MIN_WIDTH_DP。
     */
    @Test
    fun `考试窗任何档位都不得小于最小可读宽度`() {
        for (pref in listOf("small", "standard", "large", null, "bogus", "")) {
            val (w, h) = OverlayGeometryPolicy.examSize(phoneW, phoneH, phoneD, pref)
            assertTrue("档 '$pref' 宽 $w 小于最小 ${120 * phoneD}", w >= 120 * phoneD)
            assertTrue("档 '$pref' 高 $h 小于最小 ${120 * phoneD}", h >= 120 * phoneD)
        }
    }

    /** 未知/空档位必须回落 standard，绝不 crash。 */
    @Test
    fun `未知档位回落标准档`() {
        val std = OverlayGeometryPolicy.examSize(phoneW, phoneH, phoneD, "standard")
        for (bad in listOf(null, "", "bogus", "SMALL", "grande")) {
            assertEquals("档位 '$bad' 应回落标准档", std, OverlayGeometryPolicy.examSize(phoneW, phoneH, phoneD, bad))
        }
    }

    /** 考试窗绝不超出屏幕（含极端小屏 / 超大 density）。 */
    @Test
    fun `考试窗在任何屏幕上都不得超出屏幕`() {
        val screens = listOf(
            Triple(1260, 2800, 3.5f),
            Triple(1080, 1920, 2.75f),
            Triple(720, 1280, 2.0f),
            Triple(480, 800, 1.5f),
        )
        for ((sw, sh, d) in screens) {
            for (pref in listOf("small", "standard", "large")) {
                val (w, h) = OverlayGeometryPolicy.examSize(sw, sh, d, pref)
                assertTrue("屏 ${sw}x${sh}@$d 档 $pref: 宽 $w 超屏", w <= sw)
                assertTrue("屏 ${sw}x${sh}@$d 档 $pref: 高 $h 超屏", h <= sh)
            }
        }
    }

    /** density<=0 时不得除零，原样返回屏幕尺寸。 */
    @Test
    fun `density 非正时考试窗退化为屏幕尺寸`() {
        assertEquals(phoneW to phoneH, OverlayGeometryPolicy.examSize(phoneW, phoneH, 0f, "standard"))
        assertEquals(phoneW to phoneH, OverlayGeometryPolicy.examSize(phoneW, phoneH, -1f, "large"))
    }

    // ── 标题栏平铺判定（方案 B：够宽平铺，不够收进更多菜单） ──

    @Test
    fun `大档宽度下标题栏应判定为可平铺`() {
        val (w, _) = OverlayGeometryPolicy.examSize(phoneW, phoneH, phoneD, "large")
        assertTrue(
            "大档宽 $w px 应判定可平铺（需 ${OverlayGeometryPolicy.TITLE_BAR_REQUIRED_DP}dp）",
            OverlayGeometryPolicy.titleBarFits(w, phoneD),
        )
    }

    @Test
    fun `小档宽度下标题栏应判定为放不下`() {
        val (w, _) = OverlayGeometryPolicy.examSize(phoneW, phoneH, phoneD, "small")
        assertEquals("0.36 * 360dp = 129.6dp → 453px（低于旧 px 上限 500）", 453, w)
        assertFalse(
            "小档宽 $w px 装不下 ${OverlayGeometryPolicy.TITLE_BAR_REQUIRED_DP}dp，必须判定 false 以走收拢",
            OverlayGeometryPolicy.titleBarFits(w, phoneD),
        )
    }

    @Test
    fun `titleBarFits 阈值按 dp 而非 px 换算`() {
        // 220dp @3.5 = 770px
        assertTrue("769px 应差一点不够", !OverlayGeometryPolicy.titleBarFits(769, phoneD))
        assertTrue("770px 刚好够", OverlayGeometryPolicy.titleBarFits(770, phoneD))
        assertTrue("density<=0 视为够用，不得崩", OverlayGeometryPolicy.titleBarFits(1, 0f))
    }
    // ═══════════════════════════════════════════════════════════
    // 接线回归：service 必须**委托** policy，不得自己再算尺寸
    // ═══════════════════════════════════════════════════════════

    /**
     * 结构回归：`examOverlayDimensions()` 不得再出现固定 px 的 coerceIn。
     *
     * 原 bug 就是 service 自己算 `(widthPixels*0.46f).coerceIn(300,500)`。
     * 本用例直接读源码文本断言它已改为委托 —— 防止有人「顺手」把算式搬回来。
     */
    @Test
    fun `service 的考试窗尺寸必须委托 policy 而非自算`() {
        val src = java.io.File(
            "src/main/kotlin/top/hpa888/box/QuizAccessibilityService.kt",
        )
        assertTrue("找不到 QuizAccessibilityService.kt: ${src.absolutePath}", src.exists())
        val text = src.readText()

        // 定位 examOverlayDimensions 函数体
        val start = text.indexOf("private fun examOverlayDimensions()")
        assertTrue("examOverlayDimensions 函数不见了", start >= 0)
        val body = text.substring(start, minOf(start + 900, text.length))
        val end = body.indexOf("\n    }")
        val fn = if (end > 0) body.substring(0, end) else body

        assertTrue(
            "examOverlayDimensions 必须委托 OverlayGeometryPolicy.examSize；函数体现在是：\n$fn",
            fn.contains("OverlayGeometryPolicy.examSize"),
        )
        for (bad in listOf("coerceIn(300, 500)", "coerceIn(250, 390)", "coerceIn(360, 590)")) {
            assertFalse(
                "发现残留的固定 px 上限 $bad —— 这正是「考试模式一直小窗」的原 bug",
                fn.contains(bad),
            )
        }
    }

    // ───────────────── P1-1：考试窗位置记忆（2026-09-16） ─────────────────

    private val SW = 1260   // 真机 iQOO 屏宽 px
    private val SH = 2800
    private val EW = 730    // 标准档考试窗宽 px
    private val EH = 720

    @Test
    fun `无记忆时回退右上锚点，且与旧硬编码逐位等价`() {
        val (x, y) = OverlayGeometryPolicy.examPosition(null, SW, SH, EW, EH)
        // 旧实现：(1260 - 730 - 1260*0.03f).toInt() = 492 ; (2800*0.08f).toInt() = 224
        assertEquals(492, x)
        assertEquals(224, y)
    }

    @Test
    fun `有记忆时尊重用户位置，不再弹回右上角`() {
        val (x, y) = OverlayGeometryPolicy.examPosition("100,1500", SW, SH, EW, EH)
        assertEquals(100, x)
        assertEquals(1500, y)
    }

    @Test
    fun `记忆位置超界时夹回屏内，而不是丢弃`() {
        // 旋转屏幕 / 窗变大后，旧坐标可能超界
        val (x, y) = OverlayGeometryPolicy.parsePosition("9999,9999", SW, SH, EW, EH)!!
        assertEquals(SW - EW, x)   // 夹到 maxX
        assertEquals(SH - EH, y)   // 夹到 maxY
    }

    @Test
    fun `脏记忆串返回 null 走锚点，不崩`() {
        for (bad in listOf(null, "", "   ", "abc", "12", "1,2,3,4")) {
            val r = OverlayGeometryPolicy.parsePosition(bad, SW, SH, EW, EH)
            if (bad == "1,2,3,4") {
                assertEquals("多余字段应忽略前两位", 1 to 2, r)
            } else {
                assertNull("脏串 [$bad] 应返回 null", r)
            }
        }
    }

    @Test
    fun `窗口比屏还大时锚点不产生负坐标`() {
        val (x, y) = OverlayGeometryPolicy.examAnchor(600, 800, 900, 900)
        assertTrue("x 不得为负，实为 $x", x >= 0)
        assertTrue("y 不得为负，实为 $y", y >= 0)
    }

    @Test
    fun `考试窗位置决策必须走 policy：service 不得再硬编码右上锚点`() {
        val text = File(
            "src/main/kotlin/top/hpa888/box/QuizAccessibilityService.kt",
        ).readText()
        assertTrue(
            "考试窗定位必须委托 OverlayGeometryPolicy.examPosition",
            text.contains("OverlayGeometryPolicy.examPosition"),
        )
        assertFalse(
            "发现残留的硬编码右上锚点 —— 会让用户拖走的考试窗每次弹回右上角",
            Regex("""params\.x = \(dm\.widthPixels - \w+ - dm\.widthPixels \* 0\.03f\)""")
                .containsMatchIn(text),
        )
        assertTrue(
            "重置悬浮窗大小必须一并清掉考试位置，否则用户无法自救",
            Regex("""remove\(KEY_EXAM_GEOMETRY\)""").containsMatchIn(text),
        )
    }

    // ═══════════════════════════════════════════════════════════
    // P1/P2：手动 vs 自动考试模式 + 高频键宽度收口（2026-09-17）
    // ═══════════════════════════════════════════════════════════

    /**
     * P1：启动迁移只清「自动进入」的残留 examMode，保留「手动开关」。
     *
     * 结构回归：service 必须出现 KEY_EXAM_MODE_MANUAL，且迁移块的条件是
     * `examMode && !manual`（而非 e7382f5 的无条件清）。
     */
    @Test
    fun `启动迁移保留手动开的考试模式，只清自动残留`() {
        val text = File(
            "src/main/kotlin/top/hpa888/box/QuizAccessibilityService.kt",
        ).readText()
        assertTrue(
            "必须有 KEY_EXAM_MODE_MANUAL 区分手动/自动",
            text.contains("KEY_EXAM_MODE_MANUAL"),
        )
        assertTrue(
            "迁移条件必须是 examMode && !manual（否则又会误清手动开的）",
            Regex("""if\s*\(\s*p\.getBoolean\(KEY_EXAM_MODE,\s*false\)\s*&&\s*!manual\)""")
                .containsMatchIn(text),
        )
        assertTrue(
            "手动开关路径必须置 manual=true",
            Regex("""setExamMode\(!examMode,\s*manual\s*=\s*true\)""").containsMatchIn(text),
        )
        assertFalse(
            "不得残留无条件清 examMode 的旧迁移块",
            Regex("""if\s*\(\s*p\.getBoolean\(KEY_EXAM_MODE,\s*false\)\s*\)\s*\{[\s\S]*clear stale exam mode""")
                .containsMatchIn(text),
        )
    }

    /**
     * P2：高频三键宽度（92dp）收进 policy 单一事实源。
     *
     * 结构回归：service 不得再出现字面量 `val highFreqDp = 92`。
     */
    @Test
    fun `高频键宽度必须走 policy，service 不得再硬编码 92`() {
        assertEquals("policy 里高频三键基准值", 92, OverlayGeometryPolicy.TITLE_BAR_HIGH_FREQ_DP)
        val text = File(
            "src/main/kotlin/top/hpa888/box/QuizAccessibilityService.kt",
        ).readText()
        // 1. 收拢判定必须引用 policy 常量（单一事实源）
        assertTrue(
            "收拢判定必须引用 OverlayGeometryPolicy.TITLE_BAR_HIGH_FREQ_DP",
            text.contains("OverlayGeometryPolicy.TITLE_BAR_HIGH_FREQ_DP"),
        )
        // 2. 不得再有「字面量 92 直接参与算术运算」的残留（旧 bug 形态：
        //    `val highFreqDp = 92` 后接 `highFreqDp * d`）。
        //    注意：KDoc 注释里允许保留该字面量作「原 bug」记录，故只匹配
        //    `= 92` 且同一行内再出现算术使用（乘号）的形态，排除纯注释/文档。
        assertFalse(
            "发现残留的字面量 92 直接参与收拢算术 —— 真机校准时会漏改",
            Regex("""val\s+highFreqDp\s*=\s*92\b""").let {
                text.lines().any { line ->
                    !line.trimStart().startsWith("//") &&
                        !line.trimStart().startsWith("*") &&
                        it.matches(line.trim())
                }
            },
        )
    }

    /**
     * 结构回归（2026-09-17 ②-B）：标题栏左右内边距必须走 policy，且**对齐 layout 真值 12dp**。
     *
     * 背景：`quiz_overlay.xml` 的 `title_bar` 是 `paddingStart=12dp + paddingEnd=0dp`，
     * 合计 12dp。service 旧字面量写的是 16（偏大 4dp）。收口进 policy 后校准到 12。
     * 本测试锁死「policy 值 = 12」，防止将来有人把它改回 16 或再散回 service。
     */
    @Test
    fun `标题栏左右内边距必须走 policy 且对齐 layout 真值 12`() {
        assertEquals(
            "policy 标题栏左右内边距合计 = 12dp（quiz_overlay.xml title_bar 真值）",
            12,
            OverlayGeometryPolicy.TITLE_BAR_SIDE_PADDING_DP,
        )
        val text = File(
            "src/main/kotlin/top/hpa888/box/QuizAccessibilityService.kt",
        ).readText()
        // 1. 收拢判定必须引用 policy 常量（单一事实源）
        assertTrue(
            "收拢判定必须引用 OverlayGeometryPolicy.TITLE_BAR_SIDE_PADDING_DP",
            text.contains("OverlayGeometryPolicy.TITLE_BAR_SIDE_PADDING_DP"),
        )
        // 2. service 不得再出现「字面量 16 * d」或「- 16」参与可用宽度算术
        assertFalse(
            "发现残留的字面量 16 参与可用宽度算术（旧 bug 形态：dm.widthPixels - 16 * d）",
            Regex("""-\s*16\s*\*\s*d""").containsMatchIn(text),
        )
    }

    // ── 2026-09-18：miss 态正文去重回归（用户截图定位）──────────────────────
    // 根因：Dart 侧 visionMissHint 推送完整句「未搜到答案。点右上角紫色 AI 按钮…」，
    // 旧内联逻辑走 else 拼成「完整句 + \n\n + 后半句」，applyAnswerStyle 又把首行染紫，
    // 用户看到「紫色一行 + 黑色一行，内容重复」。修复：firstLine 已含后缀时不再追加。
    // 行为断言（直接调用顶层纯函数 missDisplayAnswer），不走正则文本断言。

    @Test
    fun `miss body - full hint sent by Dart returns single line without duplicate suffix`() {
        // Dart _pushOverlay(answers: "未搜到答案。点右上角紫色 AI 按钮，用 AI 联网搜题。")
        val input = "未搜到答案。点右上角紫色 AI 按钮，用 AI 联网搜题。"
        val result = missDisplayAnswer(input)
        assertEquals(
            "完整 hint 句应原样返回，不再追加后缀",
            input,
            result,
        )
        // 关键：结果里后缀只出现一次
        val suffix = "点右上角紫色 AI 按钮，用 AI 联网搜题。"
        assertEquals(1, result.split(suffix).size - 1)
    }

    @Test
    fun `miss body - empty input falls back to full hint sentence`() {
        val result = missDisplayAnswer("")
        assertEquals("未搜到答案。点右上角紫色 AI 按钮，用 AI 联网搜题。", result)
    }

    @Test
    fun `miss body - bare unhit label falls back to full hint sentence`() {
        val result = missDisplayAnswer("未命中")
        assertEquals("未搜到答案。点右上角紫色 AI 按钮，用 AI 联网搜题。", result)
    }

    @Test
    fun `miss body - arbitrary first line appends suffix once`() {
        // 普通题面（非 hint 句）：首行 + 空行 + 指路后缀，后缀仅出现一次
        val input = "1. 下列哪个是哺乳动物？\nA. 蛇 B. 虎 C. 鱼 D. 蛙"
        val result = missDisplayAnswer(input)
        val suffix = "点右上角紫色 AI 按钮，用 AI 联网搜题。"
        assertTrue("应包含首行", result.contains("1. 下列哪个是哺乳动物？"))
        assertEquals("后缀只能出现一次", 1, result.split(suffix).size - 1)
        assertTrue("后缀在首行之后", result.indexOf(suffix) > result.indexOf("哺乳动物"))
    }

    @Test
    fun `miss body - marker-stripped bare 未命中 label falls back to full hint sentence`() {
        // 调用方 updateAccessibilityOverlayView 传入前已 strip SIM marker
        // （rawAnswer.replace(SIM_REGEX)），函数收到的实际是纯文本。
        // "未命中" 单独作为答案行 → 走兜底句。
        val result = missDisplayAnswer("未命中")
        assertEquals("未搜到答案。点右上角紫色 AI 按钮，用 AI 联网搜题。", result)
    }

    // ── badgeState：标题栏相似度胶囊文案+配色（2026-09-18 截图定位的 hit 无相似度矛盾）──
    // 行为断言：直接调顶层纯函数 badgeState，覆盖 hit/miss/ambiguous/searching × 有/无相似度 全组合。

    @Test
    fun `badge - hit with null similarity shows 命中 green, NOT 未命中`() {
        // 截图实锤：AI 读屏答出「答案：C」（confidence=0 → sim=null）
        // 旧逻辑落 sim==null → 灰「未命中」，与正文紫色命中自相矛盾。
        val badge = badgeState(
            isSearchingNow = false,
            status = "hit",
            matchCount = 1,
            matchIndex = 0,
            sim = null,
        )
        assertEquals("命中", badge.text)
        assertEquals(0xFF12B76A.toInt(), badge.colorArgb)
    }

    @Test
    fun `badge - hit with similarity shows percentage with threshold color`() {
        val high = badgeState(false, "hit", 1, 0, 95)
        assertEquals("95%", high.text)
        assertEquals("≥90 应绿", 0xFF12B76A.toInt(), high.colorArgb)

        val mid = badgeState(false, "hit", 1, 0, 75)
        assertEquals("75%", mid.text)
        assertEquals("≥70 应琥珀", 0xFFF59E0B.toInt(), mid.colorArgb)

        val low = badgeState(false, "hit", 1, 0, 50)
        assertEquals("50%", low.text)
        assertEquals("<70 应灰", 0xFF98A2B3.toInt(), low.colorArgb)
    }

    @Test
    fun `badge - miss status shows 未命中 gray`() {
        val badge = badgeState(false, "miss", 0, 0, null)
        assertEquals("未命中", badge.text)
        assertEquals(0xFF98A2B3.toInt(), badge.colorArgb)
    }

    @Test
    fun `badge - ambiguous single shows 请确认 amber`() {
        val badge = badgeState(false, "ambiguous", 1, 0, 80)
        assertEquals("请确认", badge.text)
        assertEquals(0xFFF59E0B.toInt(), badge.colorArgb)
    }

    @Test
    fun `badge - ambiguous multi shows 确认 N of M amber`() {
        val badge = badgeState(false, "ambiguous", 3, 1, 80)
        assertEquals("确认 2/3", badge.text)
        assertEquals(0xFFF59E0B.toInt(), badge.colorArgb)
    }

    @Test
    fun `badge - searching shows 读屏中 amber`() {
        val badge = badgeState(true, "searching", 0, 0, null)
        assertEquals("读屏中", badge.text)
        assertEquals(0xFFF59E0B.toInt(), badge.colorArgb)
    }

    @Test
    fun `badge - legacy no-status with sim falls back to percentage`() {
        // 未携带结构化 status 的旧调用路径（status=""）
        val badge = badgeState(false, "", 0, 0, 92)
        assertEquals("92%", badge.text)
        assertEquals(0xFF12B76A.toInt(), badge.colorArgb)
    }

    @Test
    fun `badge - legacy no-status without sim shows 未命中`() {
        val badge = badgeState(false, "", 0, 0, null)
        assertEquals("未命中", badge.text)
        assertEquals(0xFF98A2B3.toInt(), badge.colorArgb)
    }

}
