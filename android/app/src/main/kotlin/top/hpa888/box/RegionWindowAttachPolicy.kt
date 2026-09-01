package top.hpa888.box

/**
 * 区域选择窗 addView 的重试与失败恢复决策。
 *
 * 抽成纯函数的原因：这段逻辑原先内联在
 * QuizAccessibilityService.enterRegionMode 里，依赖 WindowManager，纯 JVM
 * 单测碰不到。此前 P0FixLogicTest 声称验证它，实际是在测试方法里 throw
 * 两个自造异常再断言自己的局部变量——生产代码改坏了照样绿。
 *
 * 决策本身的由来：
 *  - 尝试 1 用不带 FLAG_LAYOUT_IN_SCREEN 的参数。部分 ROM 上
 *    TYPE_ACCESSIBILITY_OVERLAY + 该 flag 会抛 BadTokenException。
 *  - 尝试 1 失败再用带 FLAG_LAYOUT_IN_SCREEN + cutout mode 的参数重试，
 *    兼容确实需要全屏的 ROM。
 *  - 两次都失败必须恢复答案窗并 toast 真实错误，否则用户看到的是
 *    「点了框选，答案窗消失了，什么也没出现」。
 *  - 上报的错误必须是最后一次尝试的，不是第一次——第一次往往是
 *    BadTokenException，掩盖了重试后真正的权限问题。
 */
object RegionWindowAttachPolicy {

    /** 一次 addView 尝试的结果。 */
    sealed interface AttemptResult {
        object Success : AttemptResult
        data class Failure(val error: String) : AttemptResult
    }

    /** 整个附着流程的结论。 */
    sealed interface Outcome {
        /** 成功附着，第几次尝试成功（1 基）。 */
        data class Attached(val attempt: Int) : Outcome

        /** 全部失败，需恢复答案窗并上报最后一次的错误。 */
        data class Failed(val lastError: String) : Outcome
    }

    /**
     * 按顺序消费各次尝试，返回最终结论。
     *
     * @param attempts 依次执行的 addView 尝试；懒序列，成功后不再消费后续项
     */
    fun attach(attempts: Sequence<AttemptResult>): Outcome {
        var lastError = "unknown"
        var index = 0
        for (r in attempts) {
            index++
            when (r) {
                is AttemptResult.Success -> return Outcome.Attached(index)
                is AttemptResult.Failure -> lastError = r.error
            }
        }
        return Outcome.Failed(lastError)
    }
}
