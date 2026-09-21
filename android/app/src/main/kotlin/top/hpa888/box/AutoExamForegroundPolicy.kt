package top.hpa888.box

/**
 * E1/E3（2026-09-19）：离开 App 自动考试态的**纯**前台决策。
 *
 * 把 [QuizAccessibilityService.handleForegroundPackage] 里"进/出考试态"的
 * 状态机抽成无副作用的纯函数，便于单测锁定语义（服务侧只负责执行副作用：
 * setExamMode / loadRegion）。
 *
 * 语义（2026-09-19 用户拍板"修 E1+E3"）：
 *  - 回到 box（pkg == self）：**自动**进的考试态退出；**手动**开的保留。
 *  - 切到白名单 App 且当前非考试态：自动进入考试态。
 *  - E3：切到「不在白名单 / 配置已关」的 App 且当前处于考试态 —— 无论
 *    自动进的还是手动开的，都对称退出（旧版手动开的切出白名单不退出，
 *    用户感知"出不来"）。
 *  - 其余情况：状态不变。
 */
object AutoExamForegroundPolicy {

    data class Decision(
        /** 是否应把 examMode 置为 true（自动进入）。 */
        val enterExamMode: Boolean,
        /** 是否应把 examMode 置为 false（退出，含手动态对称退出）。 */
        val exitExamMode: Boolean,
        /** 退出后 autoExamByForeground 是否应复位 false。 */
        val resetAutoFlag: Boolean,
    ) {
        val noChange: Boolean get() = !enterExamMode && !exitExamMode
    }

    /**
     * @param isSelf 前台是否 box 自己。
     * @param inWhitelist 该前台 App 是否命中自动考试白名单（配置开启且在名单）。
     * @param examMode 当前考试态。
     * @param autoExamByForeground 当前是否"自动"进的考试态（false 可能是手动开的）。
     */
    fun decide(
        isSelf: Boolean,
        inWhitelist: Boolean,
        examMode: Boolean,
        autoExamByForeground: Boolean,
    ): Decision {
        return when {
            // 回到 box：自动进的退出；手动开的保留。
            isSelf -> {
                if (autoExamByForeground && examMode) {
                    Decision(enterExamMode = false, exitExamMode = true, resetAutoFlag = true)
                } else {
                    Decision(false, false, false)
                }
            }
            // 白名单 App 且当前非考试态：自动进入。
            inWhitelist && !examMode ->
                Decision(enterExamMode = true, exitExamMode = false, resetAutoFlag = false)
            // E3 收窄（2026-09-19）：切出白名单且「**自动**进的考试态」退出。
            // 手动开的考试态（autoExamByForeground=false）**不受切 App 影响**，
            // 只在用户手动关闭或明确意图（回 box 的自动态分支不适用）时退出。
            // 旧版 E3 全对称（手动态也退）会导致"手动态切到微信被误退"，用户要求收窄。
            !inWhitelist && examMode && autoExamByForeground ->
                Decision(enterExamMode = false, exitExamMode = true, resetAutoFlag = true)
            // 其余：不变。
            else -> Decision(false, false, false)
        }
    }

    /**
     * E1（2026-09-19）：内容/滚动事件的前台包重算是否该放行（节流门）。
     *
     * 窗口状态事件是切 App 的最强信号（[QuizAccessibilityService] 传
     * [nowMs] 与 [lastRecheckMs] 恒 0 模拟即时执行），不做节流；
     * 内容/滚动事件连发，需间隔 ≥ [minIntervalMs] 才放行一条重算，避免
     * 同题动画导致考试态抖动。
     *
     * @return true = 应执行一次前台包重算；false = 节流丢弃。
     */
    fun shouldRecheck(
        nowMs: Long,
        lastRecheckMs: Long,
        minIntervalMs: Long = 200,
    ): Boolean = nowMs - lastRecheckMs >= minIntervalMs
}
