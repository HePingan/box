package top.hpa888.box

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 批量录入「等 OCR 回填」轮询判定的纯逻辑测试。
 *
 * 原实现的 bug：轮询体写成
 *
 * ```
 * if (q.isNotEmpty() && checks < maxChecks) { save() }
 * else if (checks >= maxChecks) { timeout() }
 * else { checks++; postDelayed(this, 100) }
 * ```
 *
 * 当 checks 恰好走到 maxChecks(60) 时，即使题干这一刻已经回填好了，
 * 第一个分支因为 `checks < maxChecks` 为假而不成立，直接掉进超时分支，
 * 把一道本来抓到的题记成失败并跳过。等待窗口边界上会丢题。
 */
class BatchProbeWaitPolicyTest {

    @Test
    fun `题干已回填就该保存`() {
        val d = BatchProbeWaitPolicy.decide(
            questionFilled = true,
            checks = 3,
            maxChecks = 60,
        )
        assertEquals(BatchProbeWaitPolicy.Action.SAVE, d)
    }

    @Test
    fun `题干为空且未到上限则继续等`() {
        val d = BatchProbeWaitPolicy.decide(
            questionFilled = false,
            checks = 3,
            maxChecks = 60,
        )
        assertEquals(BatchProbeWaitPolicy.Action.WAIT, d)
    }

    @Test
    fun `题干为空且到上限则超时`() {
        val d = BatchProbeWaitPolicy.decide(
            questionFilled = false,
            checks = 60,
            maxChecks = 60,
        )
        assertEquals(BatchProbeWaitPolicy.Action.TIMEOUT, d)
    }

    @Test
    fun `边界上题干已回填必须保存而不是超时 — 原实现在此丢题`() {
        val d = BatchProbeWaitPolicy.decide(
            questionFilled = true,
            checks = 60,
            maxChecks = 60,
        )
        assertEquals(
            "checks==maxChecks 且已抓到题干时，应保存而非记失败",
            BatchProbeWaitPolicy.Action.SAVE,
            d,
        )
    }

    @Test
    fun `超过上限但已回填仍应保存`() {
        val d = BatchProbeWaitPolicy.decide(
            questionFilled = true,
            checks = 999,
            maxChecks = 60,
        )
        assertEquals(BatchProbeWaitPolicy.Action.SAVE, d)
    }

    @Test
    fun `已回填优先级高于超时 — 任何 checks 下都不该丢题`() {
        for (c in 0..80) {
            assertTrue(
                "checks=$c 时已回填却没判 SAVE",
                BatchProbeWaitPolicy.decide(true, c, 60) ==
                    BatchProbeWaitPolicy.Action.SAVE,
            )
        }
    }
}
