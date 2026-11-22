package top.hpa888.box

import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 插件分享码深链：`boxapp://plugin?c=CODE`。
 *
 * 为什么走原生而不是引 `app_links`：本项目已有 [ShareInboxReceiver] 这套
 * 「冷启动先攒着 / 热启动直接推」的模式，照抄它零依赖、零 pubspec 变更，
 * 也不用担心 lock 里的依赖漂移（上一次为加一个二维码就漂了 8 个包）。
 *
 * 生命周期与分享一致：
 *   * 冷启动：Intent 在 Dart handler 挂上之前就到了 → 先攒着，Dart 调 `takePending` 取；
 *   * 热启动：Dart 已就绪 → 直接 `onPluginCode` 推过去。
 *
 * 注意：这个 filter 只声明在 MainActivity 上，**没有**加到 CalculatorAlias。
 * 伪装开启时 MainActivity 被停用 → 深链一并失效，与「分享到极客匣」同一套心智：
 * 伪装期间不该有任何外部入口把真应用拉起来。
 */
object DeepLinkReceiver {

    const val CHANNEL = "top.hpa888.box/plugin_deeplink"

    /** Dart → 原生：handler 已挂好，可以推了。 */
    private const val METHOD_READY = "ready"

    /** Dart → 原生：取走冷启动时攒下的码。 */
    private const val METHOD_TAKE_PENDING = "takePending"

    /** 原生 → Dart：有一个码要处理。 */
    private const val METHOD_ON_CODE = "onPluginCode"

    /** Dart → 原生：深链自检（App Links 是否已验证、scheme 能不能解析）。 */
    private const val METHOD_DIAGNOSE = "diagnose"

    /** 分享链接所在的域名，必须与 manifest 里的 https filter 一致。 */
    private const val WEB_HOST = "box.hpa888.top"

    /**
     * 码长度上限：服务端现在是 6 位，留余量给以后加长。
     * 超长的不解析 —— 免得把一段奇怪字符串当码去请求。
     */
    private const val MAX_CODE_LEN = 32

    private var channel: MethodChannel? = null
    private var dartReady = false
    private var pendingCode: String? = null
    private var appContext: android.content.Context? = null

    fun register(messenger: BinaryMessenger, context: android.content.Context) {
        appContext = context.applicationContext
        val ch = MethodChannel(messenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                METHOD_READY -> {
                    dartReady = true
                    // 冷启动攒下的码在这里补推（Dart 侧刚挂上 handler）。
                    pendingCode?.let { pushToDart(it) }
                    result.success(true)
                }
                METHOD_TAKE_PENDING -> {
                    val code = pendingCode
                    pendingCode = null
                    result.success(code)
                }
                METHOD_DIAGNOSE -> result.success(diagnose())
                else -> result.notImplemented()
            }
        }
    }

    /**
     * 深链自检。
     *
     * 为什么需要它：App Links 校验是系统行为（装机后异步拉 assetlinks.json），
     * 失败时没有任何用户可见的报错 —— 链接只是悄悄变成"打开浏览器"。
     * 这里把系统的域名验证状态读出来，省得靠猜。
     */
    private fun diagnose(): Map<String, Any?> {
        val ctx = appContext
        val out = mutableMapOf<String, Any?>(
            "host" to WEB_HOST,
            "scheme" to "boxapp",
            "sdkInt" to android.os.Build.VERSION.SDK_INT,
            "webLinkState" to "unknown",
            "webLinkVerified" to false,
            "schemeResolvable" to false,
        )
        if (ctx == null) {
            out["error"] = "没有 context（通道未注册？）"
            return out
        }
        val pm = ctx.packageManager
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            try {
                // getDomainVerificationUserState 是 API 31+；更低的系统只能靠行为观察。
                val state = pm.getDomainVerificationUserState(ctx.packageName)
                val st = state?.hostToStateMap?.get(WEB_HOST)
                out["webLinkState"] = when (st) {
                    android.content.pm.PackageManager.DOMAIN_STATE_VERIFIED -> "verified"
                    android.content.pm.PackageManager.DOMAIN_STATE_SELECTED -> "selected"
                    android.content.pm.PackageManager.DOMAIN_STATE_NONE -> "none"
                    null -> "unlisted"
                    else -> "unknown"
                }
                out["webLinkVerified"] =
                    st == android.content.pm.PackageManager.DOMAIN_STATE_VERIFIED
            } catch (e: Throwable) {
                out["webLinkState"] = "error"
                out["error"] = e.message
            }
        } else {
            out["webLinkState"] = "apiBelow31"
        }
        // 查自己包的 scheme 能否解析：限定 packageName，不涉及其它应用的可见性。
        try {
            val probe = android.content.Intent(
                android.content.Intent.ACTION_VIEW,
                android.net.Uri.parse("boxapp://plugin?c=TEST"),
            )
            probe.setPackage(ctx.packageName)
            out["schemeResolvable"] = probe.resolveActivity(pm) != null
        } catch (e: Throwable) {
            out["error"] = (out["error"] as? String ?: "") + " scheme:${e.message}"
        }
        return out
    }

    /** Activity 销毁时解绑：否则重建后事件会投向失效 channel。 */
    fun detach() {
        channel = null
        dartReady = false
    }

    fun handleIntent(intent: Intent?) {
        val code = codeFromIntent(intent) ?: return
        if (dartReady) {
            pushToDart(code)
        } else {
            // 冷启动期间连点两个链接时以最后一次为准：用户当下的意图是后一个。
            pendingCode = code
        }
    }

    /**
     * 两种深链都认：
     *   * `boxapp://plugin?c=CODE` —— 自建 scheme（落地页按钮、手点链接）
     *   * `https://box.hpa888.top/p/CODE` —— App Links（扫码/系统打开，已验证域名时直接进 App）
     *
     * 为什么非要两条：扫码器把 `boxapp://` 当地址丢给浏览器时，
     * 微信/QQ/Chrome 都当未知协议 → 白屏（用户实测）。https 才能被所有扫码器正常处理。
     */
    private fun codeFromIntent(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return null
        val uri = intent.data ?: return null
        val scheme = uri.scheme?.lowercase() ?: return null
        val host = uri.host?.lowercase() ?: return null
        val candidate: String? = when {
            scheme == "boxapp" && host == "plugin" -> uri.getQueryParameter("c")
            scheme == "https" && host == "box.hpa888.top" &&
                (uri.path ?: "").startsWith("/p/") -> uri.lastPathSegment
            else -> null
        }
        val raw = candidate?.trim().orEmpty()
        if (raw.isEmpty() || raw.length > MAX_CODE_LEN) return null
        // 码表只有 [0-9A-Z]（服务端 _pluginShareAlphabet）；其它字符说明链接被改过。
        if (!raw.all { it.isLetterOrDigit() }) return null
        return raw.uppercase()
    }

    private fun pushToDart(code: String) {
        try {
            channel?.invokeMethod(METHOD_ON_CODE, mapOf("code" to code))
            pendingCode = null
        } catch (_: Throwable) {
            // 推失败就留着，等下一次 ready 或 takePending 再来拿。
            pendingCode = code
        }
    }
}
