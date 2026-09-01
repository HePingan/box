package top.hpa888.box

/**
 * 决定「操作完自己的浮层之后，什么时候可以恢复抓题扫描」。
 *
 * 为什么需要它：抓题扫描是全树遍历（枚举交互窗口 + 递归节点树，数百次 binder
 * 跨进程调用），且跑在 App 主线程 —— 正是渲染悬浮窗的那条线程。
 *
 * 触摸期间的扫描已被 [QuizCaptureScanGate] 挡住，但松手并不等于滚动结束：
 * HorizontalScrollView / ScrollView 抬手后还有 fling 惯性动画要跑几百毫秒。
 * 按固定延迟（原实现 220ms）补扫，扫描正好插进减速动画中段，
 * 表现就是「手指离开后画面顿一下」，用户感知为左右滑按钮卡顿。
 *
 * 策略：维护「最后一次活动时间」（触摸或滚动都算活动），
 * 只有静默超过 [QUIET_WINDOW_MS] 才真正开扫，否则继续推迟到静默期结束。
 */
object OverlayScanResumePolicy {

    /**
     * 静默窗口。需覆盖典型 fling 减速尾段，又不能长到让用户等答案。
     * 350ms 是这两者的折中。
     */
    const val QUIET_WINDOW_MS = 350L

    sealed interface Decision {
        /** 可以扫描了。 */
        data object Resume : Decision

        /** 还不能扫，[delayMs] 之后再判断一次。 */
        data class Recheck(val delayMs: Long) : Decision
    }

    /**
     * @param now 当前时间（调用方传 SystemClock.uptimeMillis()）
     * @param touchActive 手指此刻是否还按在浮层上
     * @param lastActivityAt 最后一次触摸或滚动的时间戳
     */
    fun decide(now: Long, touchActive: Boolean, lastActivityAt: Long): Decision {
        if (touchActive) return Decision.Recheck(QUIET_WINDOW_MS)
        val quietFor = now - lastActivityAt
        if (quietFor >= QUIET_WINDOW_MS) return Decision.Resume
        // 时钟回拨或时间戳在未来时 quietFor 可能为负，
        // 直接用差值会算出超长延迟把扫描饿死；统一夹到静默窗口内。
        val remaining = (QUIET_WINDOW_MS - quietFor).coerceIn(1L, QUIET_WINDOW_MS)
        return Decision.Recheck(remaining)
    }
}
