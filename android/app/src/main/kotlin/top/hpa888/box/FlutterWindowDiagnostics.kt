package top.hpa888.box

import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * 自由小窗/多窗口诊断日志的出口。
 *
 * 两个 sink 同时写，缺一不可：
 *
 *  - **logcat**（tag [tag]）：Dart 侧彻底卡死时唯一还能出数的通道。
 *  - **Dart 侧 AppLogger**：普通用户拿不到 adb，只能在 App 内「调试日志」页复制给我们。
 *
 * 为什么需要缓冲：`onResume` / `onWindowFocusChanged` 会在 FlutterEngine 配好、
 * Dart 侧注册 handler **之前**就触发，而白屏现场最有价值的恰恰是最早那几条。
 * 所以 Dart 未就绪时先攒在 [pending]，等 [onDartReady] 再按序回放。
 *
 * 缓冲上限 [MAX_BUFFERED] 条，超出丢最旧的——诊断日志不值得为它 OOM。
 */
object FlutterWindowDiagnostics {
    /** 统一的 logcat 标签，方便从真机反馈中精确筛选自由小窗生命周期。 */
    const val tag = "BoxFlutterWindow"

    const val CHANNEL = "top.hpa888.box/window_diagnostics"

    /** 原生 → Dart 的单条事件推送方法名。 */
    const val METHOD_ON_EVENT = "onWindowEvent"

    /** Dart → 原生的「handler 已注册，可以回放」信号。 */
    const val METHOD_READY = "ready"

    private const val MAX_BUFFERED = 200

    private val lock = Any()
    private val pending = ArrayDeque<String>()
    private var channel: MethodChannel? = null
    private var dartReady = false
    private var lastMessage: String? = null

    /** 供测试与诊断读取当前缓冲深度。 */
    val bufferedCount: Int
        get() = synchronized(lock) { pending.size }

    fun attachChannel(target: MethodChannel) {
        synchronized(lock) { channel = target }
    }

    /**
     * Activity 销毁时解绑。
     *
     * 必须把 [dartReady] 一起复位：换了 engine 之后旧的 ready 状态不再成立，
     * 否则重建后的事件会被投向一个已经失效的 channel 而静默丢掉。
     */
    fun detachChannel() {
        synchronized(lock) {
            channel = null
            dartReady = false
        }
    }

    /** Dart 侧 handler 就绪，回放缓冲中的历史事件。 */
    fun onDartReady() {
        val drained: List<String>
        synchronized(lock) {
            dartReady = true
            drained = pending.toList()
            pending.clear()
        }
        drained.forEach { deliver(it) }
    }

    /**
     * 记录一条窗口事件。必须在主线程调用（生命周期回调本来就是主线程）。
     *
     * 连续重复的同一条消息会被折叠：内容完全相同意味着窗口状态没变化，
     * 留着只会把 AppLogger 那 1000 行的环形缓冲挤满、把真正有用的上下文顶掉。
     */
    fun record(message: String) {
        Log.i(tag, message)

        val ready: Boolean
        synchronized(lock) {
            if (message == lastMessage) return
            lastMessage = message

            ready = dartReady && channel != null
            if (!ready) {
                if (pending.size >= MAX_BUFFERED) pending.removeFirst()
                pending.addLast(message)
            }
        }

        if (ready) deliver(message)
    }

    private fun deliver(message: String) {
        val target = synchronized(lock) { channel } ?: return
        try {
            target.invokeMethod(METHOD_ON_EVENT, mapOf("message" to message))
        } catch (e: Throwable) {
            // 诊断通道不能反过来拖垮 App：投递失败只在 logcat 留痕。
            Log.w(tag, "deliver failed: ${e.message}")
        }
    }
}
