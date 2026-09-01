package top.hpa888.box

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NestedTextScrollArbiterTest {

    @Test
    fun `输入框内容不足一屏时手势必须交给面板`() {
        // 这是用户报的「录入窗滑不动」：短内容输入框吃掉手势，面板不动。
        assertTrue(
            NestedTextScrollArbiter.shouldParentScroll(
                canScrollUp = false,
                canScrollDown = false,
                dy = -40f,
            ),
        )
        assertTrue(
            NestedTextScrollArbiter.shouldParentScroll(
                canScrollUp = false,
                canScrollDown = false,
                dy = 40f,
            ),
        )
    }

    @Test
    fun `输入框还能继续滚动时由输入框消费`() {
        // 手指上移（dy<0）= 想看下面的内容，输入框底部还有内容则自己吃。
        assertFalse(
            NestedTextScrollArbiter.shouldParentScroll(
                canScrollUp = true,
                canScrollDown = true,
                dy = -40f,
            ),
        )
    }

    @Test
    fun `滚到底部后继续上滑应把手势交回面板`() {
        assertTrue(
            NestedTextScrollArbiter.shouldParentScroll(
                canScrollUp = true,
                canScrollDown = false,
                dy = -40f,
            ),
        )
    }

    @Test
    fun `滚到顶部后继续下滑应把手势交回面板`() {
        assertTrue(
            NestedTextScrollArbiter.shouldParentScroll(
                canScrollUp = false,
                canScrollDown = true,
                dy = 40f,
            ),
        )
    }

    @Test
    fun `顶部下滑但内部仍可上滚时由输入框消费`() {
        assertFalse(
            NestedTextScrollArbiter.shouldParentScroll(
                canScrollUp = true,
                canScrollDown = true,
                dy = 40f,
            ),
        )
    }

    @Test
    fun `方向未成形时不抢手势`() {
        assertFalse(
            NestedTextScrollArbiter.shouldParentScroll(
                canScrollUp = true,
                canScrollDown = true,
                dy = 0f,
            ),
        )
    }
}
