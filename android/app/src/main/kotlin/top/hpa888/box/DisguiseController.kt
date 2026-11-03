package top.hpa888.box

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Process
import android.util.Log
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 「伪装成计算器」的原生侧。
 *
 * 为什么必须动原生：`android:label` 与 `android:icon` 是编译期资源，应用运行时
 * 改不了。唯一可靠的运行期切换方式是 manifest 里预置一枚 **activity-alias**
 * （[ALIAS_CLASS]），用 PackageManager 在「真身」与「别名」之间切换启用状态。
 *
 * ## 三个必须记住的坑
 *
 * 1. **一定要带 [PackageManager.DONT_KILL_APP]**。不带的话系统会为了应用组件
 *    变更直接杀掉本进程，用户点一下开关应用就闪退 —— 看着像崩溃。
 * 2. **覆盖安装会重置状态**。component 的 enabled 状态存在 PackageManager 里，
 *    OTA 替换安装后按 manifest 的 `android:enabled` 重建 —— 也就是「每次更新
 *    图标自己变回极客匣」。Dart 侧启动时用 `heal()` 重新对齐，本类只负责执行。
 * 3. **别在这里持久化业务状态**。本文件只存一个 `enabled` 标志给通知伪装用
 *    （[DisguiseNotifications] 在 Service 里被调用，拿不到 Dart 侧设置）；
 *    真正的用户意图以 Flutter 的 `SharedPreferences` 为准。
 */
object DisguiseController {

    const val CHANNEL = "top.hpa888.box/disguise"

    private const val TAG = "BoxDisguise"
    private const val ALIAS_CLASS = "top.hpa888.box.CalculatorAlias"
    private const val MAIN_CLASS = "top.hpa888.box.MainActivity"
    private const val PREFS = "box_disguise"
    private const val KEY_ENABLED = "enabled"

    fun attach(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isDisguised" -> result.success(isDisguised(activity))
                "setDisguised" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    result.success(apply(activity, enabled))
                }
                "setSecureFlag" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    applySecureFlag(activity, enabled)
                    result.success(true)
                }
                "isDuplicateApp" -> result.success(isDuplicateApp())
                else -> result.notImplemented()
            }
        }
    }

    /** 当前桌面图标是否为「计算器」。问 PackageManager，不看本地偏好。 */
    fun isDisguised(context: Context): Boolean {
        val alias = ComponentName(context.packageName, ALIAS_CLASS)
        return try {
            context.packageManager.getComponentEnabledSetting(alias) ==
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } catch (t: Throwable) {
            Log.w(TAG, "读不到 alias 状态", t)
            false
        }
    }

    /**
     * 切换桌面图标与名称。返回切换后系统的真实状态（不是"我请求了什么"）。
     */
    fun apply(context: Context, disguise: Boolean): Boolean {
        val pm = context.packageManager
        val alias = ComponentName(context.packageName, ALIAS_CLASS)
        val main = ComponentName(context.packageName, MAIN_CLASS)
        return try {
            if (disguise) {
                pm.setComponentEnabledSetting(
                    alias,
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    PackageManager.DONT_KILL_APP,
                )
                // 真身必须关掉，否则桌面上会同时出现「极客匣」和「计算器」两个图标，
                // 伪装立刻穿帮。代价是挂在 MainActivity 上的「分享到极客匣」
                // intent-filter 一起失效 —— 设置页已如实说明。
                pm.setComponentEnabledSetting(
                    main,
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP,
                )
            } else {
                pm.setComponentEnabledSetting(
                    main,
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    PackageManager.DONT_KILL_APP,
                )
                pm.setComponentEnabledSetting(
                    alias,
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP,
                )
            }
            prefs(context).edit().putBoolean(KEY_ENABLED, disguise).apply()
            isDisguised(context) == disguise
        } catch (t: Throwable) {
            Log.w(TAG, "切换伪装图标失败 disguise=$disguise", t)
            false
        }
    }

    /**
     * 用 FLAG_SECURE 遮住最近任务里的缩略图。
     *
     * 不遮的话，多任务界面那张卡片上直接就是真应用的画面 —— 桌面图标伪装得再好
     * 也一眼看穿。代价是截图也会被系统拦下（同一条 flag），所以 Dart 侧做成了
     * 可关的选项。
     */
    private fun applySecureFlag(activity: Activity, enabled: Boolean) {
        try {
            if (enabled) {
                activity.window.setFlags(
                    WindowManager.LayoutParams.FLAG_SECURE,
                    WindowManager.LayoutParams.FLAG_SECURE,
                )
            } else {
                activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "FLAG_SECURE 设置失败 enabled=$enabled", t)
        }
    }

    /**
     * 是否运行在分身 / 多用户身份下。
     *
     * 主用户 uid 形如 10xxxx（userId=0），分身/工作资料是 userId≠0。分身里是
     * **另一份应用数据**，图标与口令都独立 —— 设置页据此提示用户，否则他会以为
     * 「伪装在分身里失效了」。
     */
    private fun isDuplicateApp(): Boolean = Process.myUid() / 100000 != 0

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** 供通知伪装读取（Service 里拿不到 Dart 侧设置）。 */
    fun isEnabledForNotifications(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ENABLED, false)
}
