package top.hpa888.box

import android.app.Activity
import android.content.Context
import android.media.AudioManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 播放器亮度 / 音量手势的底座（④）。
 *
 * 亮度只改**当前窗口**（WindowManager.LayoutParams.screenBrightness），
 * 不动系统全局亮度 —— 后者要 WRITE_SETTINGS 授权，退出播放器还会留着，
 * 不是播放器该碰的东西。跟随系统时读回来是 -1。
 *
 * 音量走 AudioManager 的媒体流（STREAM_MUSIC），需要 MODIFY_AUDIO_SETTINGS，
 * 那是普通权限、装上就有，不用运行时申请。
 *
 * 约定：任何失败都返回 false / -1，不抛异常 —— 手势是锦上添花，
 * 不能因为拿不到亮度就把播放器搞崩。
 *
 * 注意：注释里不要出现斜杠加星号的片段 —— Kotlin 块注释可嵌套，
 * 那会让外层注释永不闭合、assembleRelease 直接失败（286 P3 踩过一次）。
 */
object PlayerGestureChannel {
    private const val CHANNEL = "top.hpa888.box/player_gesture"

    fun attach(activity: Activity, messenger: BinaryMessenger) {
        val appContext = activity.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getBrightness" -> result.success(currentBrightness(activity))
                "setBrightness" -> {
                    val value = call.argument<Double>("value") ?: -1.0
                    result.success(applyBrightness(activity, value.toFloat()))
                }
                "getVolume" -> result.success(volumeState(appContext))
                "setVolume" -> {
                    val value = call.argument<Double>("value") ?: -1.0
                    result.success(applyVolume(appContext, value.toFloat()))
                }
                else -> result.notImplemented()
            }
        }
    }

    /** 当前窗口亮度 0..1；-1 = 跟随系统。 */
    private fun currentBrightness(activity: Activity): Double = try {
        activity.window.attributes.screenBrightness.toDouble()
    } catch (_: Exception) {
        -1.0
    }

    /** value 0..1 = 设定；小于 0 = 交还系统。返回是否真的写进去了。 */
    private fun applyBrightness(activity: Activity, value: Float): Boolean = try {
        activity.runOnUiThread {
            val attrs = activity.window.attributes
            attrs.screenBrightness =
                if (value < 0f) -1f else value.coerceIn(0.01f, 1f)
            activity.window.attributes = attrs
        }
        true
    } catch (_: Exception) {
        false
    }

    /** 返回 current（0..1，取不到是 -1）与 max（最大档位）。 */
    private fun volumeState(context: Context): Map<String, Any> {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            ?: return mapOf("current" to -1.0, "max" to 0)
        return try {
            val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val cur = am.getStreamVolume(AudioManager.STREAM_MUSIC)
            mapOf(
                "current" to (if (max > 0) cur.toDouble() / max else 0.0),
                "max" to max,
            )
        } catch (_: Exception) {
            mapOf("current" to -1.0, "max" to 0)
        }
    }

    /** value 0..1（相对最大档位）；小于 0 视为无效。 */
    private fun applyVolume(context: Context, value: Float): Boolean = try {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (am == null || value < 0f) {
            false
        } else {
            val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val target = (value.coerceIn(0f, 1f) * max).toInt()
            am.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
            true
        }
    } catch (_: Exception) {
        false
    }
}
