package top.hpa888.box

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 漫画离线下载保活的 MethodChannel（2026-10-02）：Dart 侧 [ComicDownloadKeepAlive] 对应实现。
 *
 * 四个方法都是"尽力而为"：起不来/停不掉都不该让下载失败，所以一律回 success，
 * 把失败降级成一条日志（Dart 侧也就不用为平台差异写分支）。
 */
object ComicKeepAliveChannel {
    const val CHANNEL = "top.hpa888.box/comic_download_service"
    const val METHOD_START = "start"
    const val METHOD_UPDATE = "update"

    /** 下完收工，**留一条可划掉的通知**（"下载完成"）。 */
    const val METHOD_FINISH = "finish"
    const val METHOD_STOP = "stop"

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                METHOD_START -> {
                    ComicKeepAliveService.start(
                        context,
                        call.argument<String>("title") ?: "漫画下载中",
                        call.argument<String>("text") ?: "正在下载…",
                    )
                    result.success(null)
                }
                METHOD_UPDATE -> {
                    ComicKeepAliveService.update(
                        context,
                        call.argument<String>("text") ?: "正在下载…",
                    )
                    result.success(null)
                }
                METHOD_FINISH -> {
                    ComicKeepAliveService.finish(
                        context,
                        call.argument<String>("title") ?: "漫画下载完成",
                        call.argument<String>("text") ?: "已下载完成",
                    )
                    result.success(null)
                }
                METHOD_STOP -> {
                    ComicKeepAliveService.stop(context)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
