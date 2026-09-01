package top.hpa888.box

/**
 * 批量录入等待 OCR 回填时，每个轮询 tick 该做什么。
 *
 * 抽出来的原因是原先内联写法在等待窗口边界上会丢题：
 * 判定顺序把「已抓到题干」和「还没到上限」用 && 绑在一起，
 * 于是 checks == maxChecks 那一 tick 即使题干已经回填，
 * 也会掉进超时分支被记为失败并跳过。
 *
 * 正确的优先级是：先看有没有抓到内容，再看要不要超时。
 */
object BatchProbeWaitPolicy {

    enum class Action {
        /** 已抓到题干，进入保存流程。 */
        SAVE,

        /** 还没抓到，继续等下一 tick。 */
        WAIT,

        /** 等待窗口用尽仍未抓到，记失败并翻下一题。 */
        TIMEOUT,
    }

    /**
     * @param questionFilled 题干输入框当前是否已有非空内容
     * @param checks 已经等过的 tick 数
     * @param maxChecks 允许的最大 tick 数
     */
    fun decide(questionFilled: Boolean, checks: Int, maxChecks: Int): Action = when {
        // 抓到内容优先，无论等了多久都不该丢弃已识别的题目。
        questionFilled -> Action.SAVE
        checks >= maxChecks -> Action.TIMEOUT
        else -> Action.WAIT
    }
}
