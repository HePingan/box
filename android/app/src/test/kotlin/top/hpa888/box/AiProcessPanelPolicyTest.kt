package top.hpa888.box

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [AiProcessPanelPolicy] 决策测试。
 *
 * 直接调用生产代码断言输出值（非源码文本断言——吸取 254「测试绿而真机坏」教训）。
 * 状态机：NONE（默认）→ 用户展开/收起 → 新一轮搜题重置。
 */
class AiProcessPanelPolicyTest {

    // ── 决策 1.B 前半：新内容到达时是否自动展开 ──────────────────

    /** 默认（用户没碰过）：自动展开——用户 0914「显示只有一半」反馈的修复。 */
    @Test
    fun `默认态新内容自动展开`() {
        assertTrue(AiProcessPanelPolicy.shouldAutoExpandOnContent(AiProcessPanelPolicy.UserIntent.NONE))
    }

    /** 用户手动收起过：尊重用户，不再弹开（既有行为，防回归）。 */
    @Test
    fun `手动收起后新内容不自动弹开`() {
        assertFalse(AiProcessPanelPolicy.shouldAutoExpandOnContent(AiProcessPanelPolicy.UserIntent.COLLAPSED))
    }

    // ── 决策 1.B 后半：答案就绪是否自动收起（2026-09-19 报障核心） ──

    /** 默认态：答案就绪自动收起，把首屏让给答案（既有行为，防回归）。 */
    @Test
    fun `默认态答案就绪自动收起`() {
        assertTrue(AiProcessPanelPolicy.shouldAutoCollapseOnAnswerReady(AiProcessPanelPolicy.UserIntent.NONE))
    }

    /** 核心修复：用户手动展开后，同题重复渲染**不得**收回面板。 */
    @Test
    fun `手动展开后答案就绪不自动收起`() {
        assertFalse(AiProcessPanelPolicy.shouldAutoCollapseOnAnswerReady(AiProcessPanelPolicy.UserIntent.EXPANDED))
    }

    /** 手动收起态答案就绪无须再收（视图已收起，策略层面幂等）。 */
    @Test
    fun `手动收起后答案就绪决策仍为收起`() {
        assertTrue(AiProcessPanelPolicy.shouldAutoCollapseOnAnswerReady(AiProcessPanelPolicy.UserIntent.COLLAPSED))
    }

    // ── 新一轮搜题重置 ──────────────────────────────────────────

    /** 新一轮搜题：用户意图清零，自动化重新接管。 */
    @Test
    fun `新一轮搜题重置用户意图`() {
        assertTrue(AiProcessPanelPolicy.resetForNewSearch() == AiProcessPanelPolicy.UserIntent.NONE)
    }

    /** 重置后：新内容自动展开恢复（上一题手动收起不永久压制后续题目）。 */
    @Test
    fun `重置后恢复默认自动展开`() {
        val reset = AiProcessPanelPolicy.resetForNewSearch()
        assertTrue(AiProcessPanelPolicy.shouldAutoExpandOnContent(reset))
    }

    /** 重置后：答案就绪自动收起恢复（上一题手动展开不永久豁免后续题目）。 */
    @Test
    fun `重置后恢复答案就绪自动收起`() {
        val reset = AiProcessPanelPolicy.resetForNewSearch()
        assertTrue(AiProcessPanelPolicy.shouldAutoCollapseOnAnswerReady(reset))
    }
}
