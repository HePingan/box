package top.hpa888.box

import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 打开外部链接（插件 `openUrl` 动作）。
 *
 * 为什么不用 url_launcher：这个仓库一直没有它（announcement_popup / about /
 * monitor 三处注释都明确写过"项目没有 url_launcher 依赖，所以给复制按钮"），
 * 加上会新拉 `url_launcher` + `url_launcher_android` 两个包 —— 为一个
 * ACTION_VIEW 不值得再冒一次依赖漂移。原生二十行就够。
 *
 * 安全边界：只接受 https。
 * 插件是别人写的，不能让一个 payload 直接拉起任意 scheme —— `tel:` / `sms:` /
 * `intent:` / `file:` 都能被拿去做坏事（例如 intent: 可以构造内部页面跳转）。
 * Dart 侧在调用前还会弹确认框显示域名。
 */
object ExternalLinkBridge {

    const val CHANNEL = "top.hpa888.box/external_link"

    private var channel: MethodChannel? = null
    private var appContext: Context? = null

    fun register(messenger: BinaryMessenger, context: Context) {
        appContext = context.applicationContext
        val ch = MethodChannel(messenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "openUrl" -> {
                    val url = call.argument<String>("url")?.trim().orEmpty()
                    result.success(open(url))
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Activity 销毁时解绑，避免重建后投向失效 channel。 */
    fun detach() {
        channel = null
    }

    private fun open(url: String): Boolean {
        val ctx = appContext ?: return false
        val uri = try {
            Uri.parse(url)
        } catch (_: Throwable) {
            return false
        }
        if (!"https".equals(uri.scheme, ignoreCase = true)) return false
        if (uri.host.isNullOrEmpty()) return false
        return try {
            ctx.startActivity(
                Intent(Intent.ACTION_VIEW, uri)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            true
        } catch (_: Throwable) {
            // 没有浏览器 / 无 activity 可处理 → 交给 Dart 侧提示"没有可用的浏览器"。
            false
        }
    }
}
