package top.hpa888.box

/**
 * 手动 AI 读屏「运行态 UI」的保护策略（2026-09-19 报障修复，纯 Kotlin 可 JVM 单测）。
 *
 * ## 背景（真机截图证据：img_8920e96fae97）
 *
 * 手动点 AI 按钮触发读屏后：
 * - 按钮文字变成「AI…」（[QuizAccessibilityService.markVisionRunning] 已生效）；
 * - 但左上角胶囊停在上一题的灰「未命中」、进度横幅从不出现、
 *   正文停留在旧 miss 文案。
 *
 * 真因：Dart `_tryVisionFallback` 在读屏开始时会先推一条 `status="searching"`
 * 的内容（「新题 · AI 读屏中…」）。这条推送穿过
 * `showOrUpdateAccessibilityOverlay` 汇聚点时，旧实现无条件调用
 * `resetVisionButton()` → `stopVisionTicker()` → 运行态横幅被 GONE、
 * 每秒 ticker 停转；而 `resetVisionButton` 只恢复可点/透明度，
 * **不还原按钮文字**，「AI…」就此永久残留。
 *
 * ## 设计（三态意图的姊妹篇，与 [AiProcessPanelPolicy] 同惯例）
 *
 * 「读屏已结束」的唯一信号是**终态**推送（hit / miss / ambiguous），
 * 不是「有推送就结束」。决策收口为本对象的纯函数：
 * - [shouldPreserveRunningUi]：手动读屏运行中收到 searching 推送 →
 *   跳过 `resetVisionButton`（保留 ticker、横幅、按钮运行态）。
 * - [endsVisionRun]：终态判定，汇聚点据此真正复位。
 *
 * 状态本身由 service 持有（`visionRunning` 由 markVisionRunning(true/false) 维护）。
 */
object VisionRunningStatePolicy {

    /** 归一化：Dart 侧恒小写，防御性容忍大小写/空白差异。 */
    private fun normalize(status: String): String = status.trim().lowercase()

    /**
     * incoming 推送是否代表「本次读屏已结束」（终态）。
     *
     * `searching` 是过程态（可能来自手动读屏自身的 Dart 回推），
     * `idle`/空串是待机占位，都不算结束。
     */
    fun endsVisionRun(status: String): Boolean {
        return when (normalize(status)) {
            "hit", "miss", "ambiguous" -> true
            else -> false
        }
    }

    /**
     * 收到 incoming 推送时是否应保护「手动读屏运行态 UI」
     * （跳过 resetVisionButton / stopVisionTicker）。
     *
     * @param incomingStatus 本次推送携带的 status（空串=未携带，按 searching 处理——
     *   聚合通道历史调用多为刷新内容而非状态切换，误杀运行态代价高、
     *   误保留代价低：终态推送必然携带显式 status）
     * @param visionRunning 手动读屏当前是否在运行（markVisionRunning(true) 置位）
     */
    fun shouldPreserveRunningUi(incomingStatus: String, visionRunning: Boolean): Boolean {
        if (!visionRunning) return false
        val s = normalize(incomingStatus)
        // 空状态 = 内容刷新类推送（如过程文案），绝不能代表读屏结束
        if (s.isEmpty()) return true
        return !endsVisionRun(s)
    }
}
