package top.hpa888.box

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * 悬浮窗几何提交门闸。
 *
 * 触摸事件频率远高于显示刷新率，每个 ACTION_MOVE 都调用 updateViewLayout
 * 会让 WindowManager 在一帧内做多次跨进程布局，表现为拖动/缩放发涩。
 * 门闸负责把同一帧内的多次请求合并成一次，并丢弃几何未变化的提交。
 */
class OverlayLayoutCommitterTest {

    /** 可控帧调度器：手动触发帧回调，避免依赖 Choreographer。 */
    private class FakeFrameScheduler : FrameScheduler {
        private var pending: (() -> Unit)? = null
        var postCount = 0
            private set

        override fun post(action: () -> Unit) {
            pending = action
            postCount++
        }

        override fun cancel() {
            pending = null
        }

        fun hasPending(): Boolean = pending != null

        fun tick() {
            val action = pending ?: return
            pending = null
            action()
        }
    }

    private fun committerWithLog(): Triple<OverlayLayoutCommitter, FakeFrameScheduler, MutableList<OverlayGeometry>> {
        val scheduler = FakeFrameScheduler()
        val committed = mutableListOf<OverlayGeometry>()
        val committer = OverlayLayoutCommitter(scheduler) { committed.add(it) }
        return Triple(committer, scheduler, committed)
    }

    @Test
    fun `同一帧内的多次请求合并为一次提交且采用最后几何`() {
        val (committer, scheduler, committed) = committerWithLog()

        committer.request(OverlayGeometry(10, 20, 300, 400))
        committer.request(OverlayGeometry(11, 22, 300, 400))
        committer.request(OverlayGeometry(15, 30, 300, 400))

        assertEquals("帧回调只应注册一次", 1, scheduler.postCount)
        assertEquals("帧到来前不得提交", 0, committed.size)

        scheduler.tick()

        assertEquals(1, committed.size)
        assertEquals(OverlayGeometry(15, 30, 300, 400), committed[0])
    }

    @Test
    fun `几何未变化时不产生重复提交`() {
        val (committer, scheduler, committed) = committerWithLog()
        val g = OverlayGeometry(10, 20, 300, 400)

        committer.request(g)
        scheduler.tick()
        committer.request(g)
        scheduler.tick()

        assertEquals("相同几何只提交一次", 1, committed.size)
    }

    @Test
    fun `flush 立即提交待处理几何并取消帧回调`() {
        val (committer, scheduler, committed) = committerWithLog()

        committer.request(OverlayGeometry(10, 20, 300, 400))
        committer.flush(OverlayGeometry(80, 90, 300, 400))

        assertEquals("松手时最后一段位移必须落地", 1, committed.size)
        assertEquals(OverlayGeometry(80, 90, 300, 400), committed[0])
        assertEquals("待处理帧回调必须取消，避免回跳到旧坐标", false, scheduler.hasPending())

        scheduler.tick()
        assertEquals("取消后帧回调不得再提交", 1, committed.size)
    }

    @Test
    fun `flush 时几何与上次提交相同则不重复提交`() {
        val (committer, scheduler, committed) = committerWithLog()
        val g = OverlayGeometry(10, 20, 300, 400)

        committer.request(g)
        scheduler.tick()
        committer.flush(g)

        assertEquals(1, committed.size)
    }

    @Test
    fun `宽高变化同样参与去重，缩放共用同一门闸`() {
        val (committer, scheduler, committed) = committerWithLog()

        committer.request(OverlayGeometry(0, 0, 300, 400))
        scheduler.tick()
        committer.request(OverlayGeometry(0, 0, 300, 401))
        scheduler.tick()

        assertEquals("仅高度变化也必须提交", 2, committed.size)
        assertEquals(OverlayGeometry(0, 0, 300, 401), committed[1])
    }

    @Test
    fun `未请求时 flush 不提交任何内容`() {
        val (committer, _, committed) = committerWithLog()
        committer.flush(OverlayGeometry(5, 5, 100, 100))
        assertEquals("首次 flush 应提交一次以保证状态一致", 1, committed.size)
    }
}
