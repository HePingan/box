package top.hpa888.box

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 网络类型上报（287 P1）。
 *
 * 只读不决策：策略（仅 Wi-Fi / 先问 / 不限）全在 Dart 侧，原生这里只回答
 * "现在是什么网络"并在变化时推一条消息。传输队列的闸门因此可以纯逻辑可测。
 *
 * 注意：注释里不要出现 image/星号 之类的片段 —— Kotlin 块注释**可嵌套**，
 * 那会让外层注释永不闭合、assembleRelease 直接失败（286 P3 踩过一次）。
 */
object NetworkStatusProvider {
    private const val CHANNEL = "top.hpa888.box/network_status"

    private var channel: MethodChannel? = null
    private var manager: ConnectivityManager? = null
    private var callback: ConnectivityManager.NetworkCallback? = null

    fun attach(context: Context, messenger: BinaryMessenger) {
        val appContext = context.applicationContext
        channel = MethodChannel(messenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "currentNetworkType" -> result.success(currentType(appContext))
                    else -> result.notImplemented()
                }
            }
        }
        manager = appContext.getSystemService(Context.CONNECTIVITY_SERVICE)
            as? ConnectivityManager
        register(appContext)
    }

    private fun register(context: Context) {
        val cm = manager ?: return
        if (callback != null) return
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = push(context)
            override fun onLost(network: Network) = push(context)
            override fun onCapabilitiesChanged(
                network: Network,
                caps: NetworkCapabilities,
            ) = push(context)
        }
        // 请求"任意可用网络"的回调，只用来感知变化，不会真的去建立连接。
        val request = NetworkRequest.Builder().build()
        try {
            cm.registerNetworkCallback(request, cb)
            callback = cb
        } catch (_: Exception) {
            // 拿不到回调也不致命：Dart 侧进传输面板时会主动问一次类型。
        }
    }

    /** 原生回调在 binder 线程，invokeMethod 必须回主线程。 */
    private fun push(context: Context) {
        val type = currentType(context)
        Handler(Looper.getMainLooper()).post {
            try {
                channel?.invokeMethod("networkChanged", type)
            } catch (_: Exception) {
            }
        }
    }

    /** wifi / mobile / ethernet / none / other —— 认不出来的一律 other。 */
    fun currentType(context: Context): String {
        val cm = (context.getSystemService(Context.CONNECTIVITY_SERVICE)
            as? ConnectivityManager) ?: return "other"
        val network = try {
            cm.activeNetwork
        } catch (_: Exception) {
            null
        } ?: return "none"
        val caps = try {
            cm.getNetworkCapabilities(network)
        } catch (_: Exception) {
            null
        } ?: return "none"
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
            else -> "other"
        }
    }
}
