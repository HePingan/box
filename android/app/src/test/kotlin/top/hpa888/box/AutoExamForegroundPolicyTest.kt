package top.hpa888.box

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * E1/E3（2026-09-19）锁定 AutoExamForegroundPolicy 的进/出考试态语义，
 * 防止后续回归（尤其 E3 的"手动开考试态切出白名单也退出"对称路径）。
 */
class AutoExamForegroundPolicyTest {

    private fun d(
        isSelf: Boolean,
        inWhitelist: Boolean,
        examMode: Boolean,
        auto: Boolean,
    ) = AutoExamForegroundPolicy.decide(isSelf, inWhitelist, examMode, auto)

    @Test
    fun `回 box 自动进的考试态应退出`() {
        val r = d(isSelf = true, inWhitelist = false, examMode = true, auto = true)
        assertTrue("自动进考试态，回 box 须退出", r.exitExamMode)
        assertTrue("退出须复位 autoExamByForeground", r.resetAutoFlag)
        assertFalse(r.enterExamMode)
    }

    @Test
    fun `回 box 手动开的考试态应保留`() {
        val r = d(isSelf = true, inWhitelist = false, examMode = true, auto = false)
        assertFalse("手动开的考试态，回 box 不应被清掉（用户明确意图）", r.exitExamMode)
        assertFalse(r.enterExamMode)
    }

    @Test
    fun `切到白名单 App 且非考试态应自动进入`() {
        val r = d(isSelf = false, inWhitelist = true, examMode = false, auto = false)
        assertTrue(r.enterExamMode)
        assertFalse(r.exitExamMode)
    }

    @Test
    fun `切到白名单 App 已处考试态不应再动作`() {
        val r = d(isSelf = false, inWhitelist = true, examMode = true, auto = true)
        assertTrue("已在考试态，同白名单内切 App 不进也不出", r.noChange)
    }

    @Test
    fun `E3收窄 自动进考试态切出白名单应退出`() {
        val r = d(isSelf = false, inWhitelist = false, examMode = true, auto = true)
        assertTrue("自动进考试态切出白名单须退出", r.exitExamMode)
        assertTrue("退出须复位 autoExamByForeground", r.resetAutoFlag)
    }

    @Test
    fun `E3收窄 手动开考试态切出白名单不退出（不受切App影响）`() {
        val r = d(isSelf = false, inWhitelist = false, examMode = true, auto = false)
        assertTrue("手动态切出白名单不该被切App误退（收窄后保留）", r.noChange)
        assertFalse("手动态保留，不进入", r.enterExamMode)
    }

    @Test
    fun `切到白名单外且非考试态不动作`() {
        val r = d(isSelf = false, inWhitelist = false, examMode = false, auto = false)
        assertTrue("非考试态切到白名单外 App 不该进考试", r.noChange)
    }

    @Test
    fun `E1 节流门 间隔足够才放行`() {
        assertTrue("首条（间隔 1000>=200）须放行", AutoExamForegroundPolicy.shouldRecheck(nowMs = 1000, lastRecheckMs = 0))
        assertFalse("连发（间隔 150<200）须丢弃", AutoExamForegroundPolicy.shouldRecheck(nowMs = 250, lastRecheckMs = 100))
        assertTrue("间隔 200==min 须放行（>= 边界）", AutoExamForegroundPolicy.shouldRecheck(nowMs = 300, lastRecheckMs = 100))
    }
}
