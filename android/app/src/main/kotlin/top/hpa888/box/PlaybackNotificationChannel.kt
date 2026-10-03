package top.hpa888.box

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 后台播放（⑥B）的 Dart ↔ 原生通道。
 *
 * 分工：Dart 只说「现在播的是谁、在不在播」（[PlaybackKeepAliveService.start] /
 * [update] / [stop]），通知长什么样、按钮怎么走，全在原生侧 ——
 * 系统杀进程时，只有原生那一层还活着。
 *
 * 反过来，通知按钮与音频焦点事件从 [PlaybackKeepAliveService.onCommand]
 * 推回 Dart（`onCommand` 方法 + 命令字符串）。
 *
 * 失败一律静默：桌面 / 测试环境没有这个通道。
 */
object PlaybackNotificationChannel {
    private const val CHANNEL = "top.hpa888.box/video_playback"

    const val COMMAND_TOGGLE = "toggle"
    const val COMMAND_PREVIOUS = "previous"
    const val COMMAND_NEXT = "next"
    const val COMMAND_AUDIO_FOCUS_LOST = "audioFocusLost"

    @Volatile
    private var channel: MethodChannel? = null

    fun attach(context: Context, messenger: BinaryMessenger) {
        val appContext = context.applicationContext
        // 服务里的命令 → Dart。
        PlaybackKeepAliveService.onCommand = { command -> push(command) }

        channel = MethodChannel(messenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                val title = call.argument<String>("title") ?: "正在播放"
                val text = call.argument<String>("text") ?: "正在后台播放"
                val playing = call.argument<Boolean>("playing") ?: true
                when (call.method) {
                    "start" -> {
                        PlaybackKeepAliveService.start(appContext, title, text, playing)
                        result.success(true)
                    }
                    "update" -> {
                        PlaybackKeepAliveService.update(appContext, title, text, playing)
                        result.success(true)
                    }
                    "stop" -> {
                        PlaybackKeepAliveService.stop(appContext)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun push(command: String) {
        Handler(Looper.getMainLooper()).post {
            try {
                channel?.invokeMethod("onCommand", command)
            } catch (_: Throwable) {
                // 通道没建好：丢一条命令不影响播放。
            }
        }
    }
}
