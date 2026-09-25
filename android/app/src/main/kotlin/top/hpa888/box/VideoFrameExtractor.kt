package top.hpa888.box

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * 远端存储插件：视频首帧抽取（284 D8）。
 *
 * 为什么必须在原生做：Flutter 侧没有视频解码器，`video_player` 只能播、抽不出帧。
 * [MediaMetadataRetriever] 可以**不解码整段视频**就取一帧（[MediaMetadataRetriever.OPTION_CLOSEST_SYNC]
 * 只解关键帧），而且能直接对 http(s) URL 工作——内部按需发 Range 请求，
 * 所以远端视频不必先整段下载。
 *
 * 三条硬约束：
 *  1. **绝不让调用方失败**：拿不到就回 null（Dart 侧回退通用图标）。远端不认识认证、
 *     服务端不支持 Range、编码不支持，这些都是"这张图没有"，不是错误。
 *  2. **不许卡主线程**：抽取放单线程池；抽完切回主线程回 result（Flutter 的要求）。
 *  3. **一定要 release**：MediaMetadataRetriever 持有解码器/文件描述符，
 *     不释放会泄漏 fd（列表滚动时会累积成"打不开更多文件"）。
 */
object VideoFrameExtractor {
    const val CHANNEL = "top.hpa888.box/remote_storage_video_frame"
    const val METHOD_FRAME_AT = "frameAt"
    const val tag = "BoxVideoFrame"

    private const val JPEG_QUALITY = 80

    /** 抽取用的单线程池：抽帧是 IO+解码密集，串行即可，也不该和 UI 抢线程。 */
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "box-video-frame").apply { isDaemon = true }
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != METHOD_FRAME_AT) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val url = call.argument<String>("url")
            if (url.isNullOrBlank()) {
                result.success(null)
                return@setMethodCallHandler
            }
            val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
            val positionMs = (call.argument<Number>("positionMs") ?: 0).toLong()
            val maxWidth = (call.argument<Number>("maxWidth") ?: 256).toInt()

            executor.execute {
                val bytes = try {
                    extract(url, headers, positionMs, maxWidth)
                } catch (t: Throwable) {
                    // 包括 IllegalArgumentException（url 不被支持）、
                    // RuntimeException（解码失败）、IOException 等：
                    // 一律当成"拿不到"，Dart 侧会回退图标。
                    Log.w(tag, "抽帧失败: ${t.javaClass.simpleName}: ${t.message}")
                    null
                }
                Handler(Looper.getMainLooper()).post { result.success(bytes) }
            }
        }
    }

    private fun extract(
        url: String,
        headers: Map<String, String>,
        positionMs: Long,
        maxWidth: Int,
    ): ByteArray? {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(url, headers)
            val frame = retriever.getFrameAtTime(
                positionMs * 1000L,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
            ) ?: return null
            val scaled = scaleToWidth(frame, maxWidth)
            val out = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)
            if (scaled !== frame) scaled.recycle()
            return out.toByteArray().takeIf { it.isNotEmpty() }
        } finally {
            try {
                retriever.release()
            } catch (t: Throwable) {
                Log.w(tag, "release 失败: ${t.message}")
            }
        }
    }

    /** 按宽度等比缩小；已经够小就原样返回（不复制位图）。 */
    private fun scaleToWidth(bitmap: Bitmap, maxWidth: Int): Bitmap {
        if (maxWidth <= 0 || bitmap.width <= maxWidth) return bitmap
        val ratio = maxWidth.toFloat() / bitmap.width.toFloat()
        val height = (bitmap.height * ratio).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bitmap, maxWidth, height, true)
    }
}
