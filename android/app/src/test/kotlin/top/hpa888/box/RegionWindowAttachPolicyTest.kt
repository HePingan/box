package top.hpa888.box

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 替换原 P0FixLogicTest 中的自证式断言：那个测试自己 throw 两个异常再
 * 断言自己的局部变量，从不碰生产代码。这里调真实实现。
 */
class RegionWindowAttachPolicyTest {

    private fun ok() = RegionWindowAttachPolicy.AttemptResult.Success
    private fun fail(e: String) = RegionWindowAttachPolicy.AttemptResult.Failure(e)

    @Test
    fun `第一次就成功时不再尝试第二次`() {
        var consumed = 0
        val attempts = sequence {
            consumed++; yield(ok())
            consumed++; yield(ok())
        }
        val outcome = RegionWindowAttachPolicy.attach(attempts)
        assertEquals(RegionWindowAttachPolicy.Outcome.Attached(1), outcome)
        assertEquals("成功后不该继续消费后续尝试（会重复 addView）", 1, consumed)
    }

    @Test
    fun `第一次失败第二次成功算附着成功`() {
        val outcome = RegionWindowAttachPolicy.attach(
            sequenceOf(fail("BadTokenException: Permission denied"), ok())
        )
        assertEquals(RegionWindowAttachPolicy.Outcome.Attached(2), outcome)
    }

    @Test
    fun `两次都失败时上报最后一次的错误而不是第一次`() {
        val outcome = RegionWindowAttachPolicy.attach(
            sequenceOf(
                fail("BadTokenException: Permission denied"),
                fail("SecurityException: Cannot add window"),
            )
        )
        assertTrue(outcome is RegionWindowAttachPolicy.Outcome.Failed)
        assertEquals(
            "第一次通常是 BadTokenException，会掩盖重试后真正的权限问题",
            "SecurityException: Cannot add window",
            (outcome as RegionWindowAttachPolicy.Outcome.Failed).lastError,
        )
    }

    @Test
    fun `一次尝试都没有时也要给出失败结论而不是崩`() {
        val outcome = RegionWindowAttachPolicy.attach(emptySequence())
        assertTrue(outcome is RegionWindowAttachPolicy.Outcome.Failed)
    }
}
