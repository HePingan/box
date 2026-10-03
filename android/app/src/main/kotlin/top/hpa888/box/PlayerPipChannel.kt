package top.hpa888.box

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Rational
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 画中画（PiP）的底座（⑥A）。
 *
 * 为什么只能在**全屏播放态**用：PiP 缩的是**整个 Activity**，不是某一个 widget。
 * 在详情页内嵌播放时进小窗，用户看到的是整个详情页被压进小窗，没有意义。
 * Dart 侧因此把「进小窗」与「自动进小窗」都开在 chewie 全屏路由里。
 *
 * 两个 API 分水岭：
 *  - `enterPictureInPictureMode` 需要 API 26（minSdk 24 要判版本）；
 *  - `setAutoEnterEnabled`（播放中上滑回桌面自动进小窗）需要 API 31，老系统回退到按钮触发。
 *
 * 失败一律返回 false，不抛 —— 画中画是锦上添花。
 *
 * 注意：注释里不要出现斜杠加星号的片段 —— Kotlin 块注释可嵌套，会让构建失败（286 P3）。
 */
object PlayerPipChannel {
    private const val CHANNEL = "top.hpa888.box/player_pip"

    /** 小窗宽高比，Android 只接受 [1/2.39, 2.39] 之间的值。 */
    private const val MIN_RATIO = 0.41841004f
    private const val MAX_RATIO = 2.39f

    @Volatile
    private var channel: MethodChannel? = null

    fun attach(activity: Activity, messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(isSupported(activity))
                    "enter" -> {
                        val w = call.argument<Int>("width") ?: 16
                        val h = call.argument<Int>("height") ?: 9
                        result.success(enter(activity, w, h))
                    }
                    "setAutoEnter" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val w = call.argument<Int>("width") ?: 16
                        val h = call.argument<Int>("height") ?: 9
                        result.success(setAutoEnter(activity, enabled, w, h))
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /**
     * MainActivity.onPictureInPictureModeChanged 转发到这里，告诉 Dart
     * 「现在在小窗里」/「从小窗回来了」—— Dart 侧据此收起控件。
     */
    fun onModeChanged(isInPip: Boolean) {
        Handler(Looper.getMainLooper()).post {
            try {
                channel?.invokeMethod("pipModeChanged", isInPip)
            } catch (_: Throwable) {
                // 通道还没建（极少见）：丢了这条通知也不会影响播放。
            }
        }
    }

    fun isSupported(context: Context): Boolean = try {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            context.packageManager.hasSystemFeature(
                PackageManager.FEATURE_PICTURE_IN_PICTURE,
            )
    } catch (_: Throwable) {
        false
    }

    /** 应用到当前 Activity 上。参数只接受宽高比。 */
    private fun params(width: Int, height: Int): PictureInPictureParams {
        val ratio = safeRatio(width, height)
        return PictureInPictureParams.Builder()
            .setAspectRatio(ratio)
            .build()
    }

    private fun safeRatio(width: Int, height: Int): Rational {
        val w = if (width <= 0) 16 else width
        val h = if (height <= 0) 9 else height
        val value = w.toFloat() / h.toFloat()
        return when {
            value < MIN_RATIO -> Rational(419, 1000)
            value > MAX_RATIO -> Rational(239, 100)
            else -> Rational(w, h)
        }
    }

    private fun enter(activity: Activity, width: Int, height: Int): Boolean = try {
        if (!isSupported(activity) || activity.isFinishing) {
            false
        } else {
            activity.enterPictureInPictureMode(params(width, height))
        }
    } catch (_: Throwable) {
        false
    }

    /**
     * 播放中自动进小窗（API 31+）。开启后用户上滑回桌面就自动缩成小窗，
     * 不用再点按钮；关掉则恢复普通行为（切后台按 Dart 侧的后台播放策略处理）。
     */
    private fun setAutoEnter(
        activity: Activity,
        enabled: Boolean,
        width: Int,
        height: Int,
    ): Boolean = try {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            false
        } else {
            val builder = PictureInPictureParams.Builder()
                .setAspectRatio(safeRatio(width, height))
                .setAutoEnterEnabled(enabled)
            activity.setPictureInPictureParams(builder.build())
            true
        }
    } catch (_: Throwable) {
        false
    }
}
