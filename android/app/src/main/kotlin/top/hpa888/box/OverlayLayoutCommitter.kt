package top.hpa888.box

/** 悬浮窗几何快照。位置与尺寸共用一个值对象，让拖动和缩放复用同一条提交门闸。 */
data class OverlayGeometry(val x: Int, val y: Int, val width: Int, val height: Int)

/** 帧调度抽象，便于单测替换 Choreographer。 */
interface FrameScheduler {
    fun post(action: () -> Unit)
    fun cancel()
}

/** 真机实现：绑定到显示刷新节奏。 */
class ChoreographerFrameScheduler : FrameScheduler {
    private var callback: android.view.Choreographer.FrameCallback? = null

    override fun post(action: () -> Unit) {
        cancel()
        val cb = android.view.Choreographer.FrameCallback {
            callback = null
            action()
        }
        callback = cb
        android.view.Choreographer.getInstance().postFrameCallback(cb)
    }

    override fun cancel() {
        callback?.let { android.view.Choreographer.getInstance().removeFrameCallback(it) }
        callback = null
    }
}

/**
 * 把高频几何变更合并到每个显示帧最多一次 `updateViewLayout`。
 *
 * 触摸采样率通常高于刷新率，逐事件提交会让 WindowManager 在一帧内反复跨进程
 * 布局，用户手感就是拖动发涩、跟手迟滞。这里做两件事：
 * 同帧合并（只保留最后一次几何），以及几何未变化时直接跳过提交。
 */
class OverlayLayoutCommitter(
    private val scheduler: FrameScheduler,
    private val commit: (OverlayGeometry) -> Unit,
) {
    private var pending: OverlayGeometry? = null
    private var lastCommitted: OverlayGeometry? = null
    private var scheduled = false

    fun request(geometry: OverlayGeometry) {
        pending = geometry
        // 已有帧回调在途时不得重复注册：重复 post 会退化成逐事件提交，
        // 同帧合并也就失效了。
        if (scheduled) return
        scheduled = true
        scheduler.post {
            scheduled = false
            val next = pending ?: return@post
            pending = null
            applyIfChanged(next)
        }
    }

    /**
     * 立即提交，用于 ACTION_UP：否则最后一段位移会停在未到达的帧回调里，
     * 表现为松手时少移动一截。
     */
    fun flush(geometry: OverlayGeometry) {
        scheduler.cancel()
        scheduled = false
        pending = null
        applyIfChanged(geometry)
    }

    private fun applyIfChanged(geometry: OverlayGeometry) {
        if (geometry == lastCommitted) return
        lastCommitted = geometry
        commit(geometry)
    }
}
