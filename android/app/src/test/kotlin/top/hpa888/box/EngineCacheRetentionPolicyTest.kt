package top.hpa888.box

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 替换原 P0FixLogicTest 中的自证式断言：那个测试在方法体里重写了一遍
 * if 再断言自己的局部变量，生产代码改坏了它照样绿。这里调真实实现。
 */
class EngineCacheRetentionPolicyTest {

    @Test
    fun `无障碍服务仍在运行时必须保留引擎缓存`() {
        assertFalse(
            "服务在跑却清缓存，resolveChannel 会拿不到 FlutterEngine，抓题回调静默丢失",
            EngineCacheRetentionPolicy.shouldEvictEngineCache(accessibilityServiceRunning = true),
        )
    }

    @Test
    fun `无障碍服务已停止时可以移除引擎缓存`() {
        assertTrue(
            EngineCacheRetentionPolicy.shouldEvictEngineCache(accessibilityServiceRunning = false),
        )
    }
}
