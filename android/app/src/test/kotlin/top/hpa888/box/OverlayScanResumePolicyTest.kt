package top.hpa888.box

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * 抓题扫描恢复时机。
 *
 * 用户实测：左右滑功能按钮仍卡顿。根因不是滑动过程本身（已被门闸挡住），
 * 而是松手后固定 220ms 就补扫一次 —— 那一刻 HorizontalScrollView 的
 * fling 惯性还在跑，全树扫描（数百次 binder，主线程）正好插进减速动画里。
 */
class OverlayScanResumePolicyTest {

    @Test
    fun `手指仍按住时不恢复扫描`() {
        val d = OverlayScanResumePolicy.decide(
            now = 1000L,
            touchActive = true,
            lastActivityAt = 1000L,
        )
        assertEquals(OverlayScanResumePolicy.Decision.Recheck(OverlayScanResumePolicy.QUIET_WINDOW_MS), d)
    }

    @Test
    fun `松手且静默期已过才恢复扫描`() {
        val d = OverlayScanResumePolicy.decide(
            now = 1000L + OverlayScanResumePolicy.QUIET_WINDOW_MS,
            touchActive = false,
            lastActivityAt = 1000L,
        )
        assertEquals(OverlayScanResumePolicy.Decision.Resume, d)
    }

    @Test
    fun `松手后 fling 仍在滚动时必须继续推迟，不能按固定延迟硬扫`() {
        // 松手在 1000，fling 又在 1150 产生滚动 → 静默期从 1150 重新计时。
        // 旧实现固定 220ms 后开扫（1220），恰好撞在 fling 中段。
        val d = OverlayScanResumePolicy.decide(
            now = 1220L,
            touchActive = false,
            lastActivityAt = 1150L,
        )
        assertEquals(
            OverlayScanResumePolicy.Decision.Recheck(1150L + OverlayScanResumePolicy.QUIET_WINDOW_MS - 1220L),
            d,
        )
    }

    @Test
    fun `静默期边界视为已结束`() {
        val d = OverlayScanResumePolicy.decide(
            now = 1000L + OverlayScanResumePolicy.QUIET_WINDOW_MS,
            touchActive = false,
            lastActivityAt = 1000L,
        )
        assertEquals(OverlayScanResumePolicy.Decision.Resume, d)
    }

    @Test
    fun `重新检查的延迟不得为零或负数，避免空转刷屏`() {
        val d = OverlayScanResumePolicy.decide(
            now = 1000L,
            touchActive = false,
            lastActivityAt = 1000L,
        )
        val delay = (d as OverlayScanResumePolicy.Decision.Recheck).delayMs
        assert(delay > 0L) { "delay must be positive, got $delay" }
    }

    @Test
    fun `时钟回拨或活动时间在未来时不得算出超长延迟`() {
        val d = OverlayScanResumePolicy.decide(
            now = 1000L,
            touchActive = false,
            lastActivityAt = 5000L,
        )
        val delay = (d as OverlayScanResumePolicy.Decision.Recheck).delayMs
        assert(delay in 1L..OverlayScanResumePolicy.QUIET_WINDOW_MS) {
            "delay must be clamped to quiet window, got $delay"
        }
    }
}
