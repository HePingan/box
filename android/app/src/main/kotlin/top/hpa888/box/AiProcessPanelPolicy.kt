package top.hpa888.box

/**
 * AI 作答过程面板的用户意图策略（2026-09-19 报障：点展开后 <1s 被自动收回）。
 *
 * ## 背景
 *
 * 决策 1.B 的完整语义是「过程默认展开、答案就绪后自动收起」。但它此前
 * **不区分用户意图**：用户手动点「展开」后，同题的下一次答案渲染
 * （倒计时/进度刷新引起重复捕获，真机截图两次渲染相差 15s）会在
 * [QuizAccessibilityService.updateAnswerOverlay] 汇聚点再次触发自动收起，
 * 把用户刚展开的面板收回去。
 *
 * 旧实现只有一个布尔 [QuizAccessibilityService] `aiProcessUserCollapsed`
 * （防「自动展开」），没有对称的「防自动收起」标志。
 *
 * ## 设计
 *
 * 把用户意图从布尔升级为三态，决策全部收口为本对象的纯函数（可 JVM 单测）：
 * - [UserIntent.NONE]：用户没碰过 → 决策 1.B 完整生效（自动展开 + 答案就绪自动收起）
 * - [UserIntent.COLLAPSED]：用户手动收起过 → 新内容不再自动弹开
 * - [UserIntent.EXPANDED]：用户手动展开过 → 答案就绪**不再自动收起**（本次修复）
 *
 * 状态本身由 service 持有（`aiProcessIntent`）；新一轮搜题（过程内容被清空）
 * 时重置回 [UserIntent.NONE]，自动化重新接管——上一题的「想看过程」不应当
 * 永久顶掉后续题目的「答案优先」默认体验。
 */
object AiProcessPanelPolicy {

    /** 用户对 AI 作答过程面板的最近一次手动操作意图。 */
    enum class UserIntent { NONE, COLLAPSED, EXPANDED }

    /**
     * 新的过程内容到达时是否自动展开（决策 1.B 前半，原 `!aiProcessUserCollapsed`）。
     */
    fun shouldAutoExpandOnContent(intent: UserIntent): Boolean =
        intent != UserIntent.COLLAPSED

    /**
     * 答案就绪渲染时是否自动收起（决策 1.B 后半）。
     *
     * [UserIntent.EXPANDED]（用户本轮手动展开过）→ false：**尊重用户意图**，
     * 同题重复渲染不得收回面板（2026-09-19 报障根因）。
     */
    fun shouldAutoCollapseOnAnswerReady(intent: UserIntent): Boolean =
        intent != UserIntent.EXPANDED

    /**
     * 新一轮搜题开始（过程内容被清空）：用户意图清零，自动化重新接管。
     */
    fun resetForNewSearch(): UserIntent = UserIntent.NONE
}
