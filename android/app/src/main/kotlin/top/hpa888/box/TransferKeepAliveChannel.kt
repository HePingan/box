package top.hpa888.box

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 传输保活的 MethodChannel（284 P1）：Dart 侧 [TransferKeepAlive] 对应实现。
 *
 * 三个方法都是"尽力而为"：起不来/停不掉都不该让传输失败，所以一律回 success，
 * 把失败降级成一条日志（Dart 侧也就不用为平台差异写分支）。
 */
object TransferKeepAliveChannel {
    const val CHANNEL = "top.hpa888.box/remote_storage_transfer_service"
    const val METHOD_START = "start"
    const val METHOD_UPDATE = "update"
    const val METHOD_STOP = "stop"

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                METHOD_START -> {
                    TransferKeepAliveService.start(
                        context,
                        call.argument<String>("title") ?: "Box 传输中",
                        call.argument<String>("text") ?: "正在传输…",
                    )
                    result.success(null)
                }
                METHOD_UPDATE -> {
                    TransferKeepAliveService.update(
                        context,
                        call.argument<String>("text") ?: "正在传输…",
                    )
                    result.success(null)
                }
                METHOD_STOP -> {
                    TransferKeepAliveService.stop(context)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
