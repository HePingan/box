package top.hpa888.box

import android.content.Context
import android.webkit.WebViewDatabase
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 清掉 WebView 缓存的 HTTP Basic 凭据（296）。
 *
 * 为什么需要它：Android WebView 会把 Basic 凭据按 (源 + realm) 缓存，**缓存命中时
 * WebView 直接带上旧凭据重发，`onReceivedHttpAuthRequest` 根本不会被调用** ——
 * 于是"在设置里把通道口令换成设备凭据之后，终端页还在用旧口令"，表现是终端 401 或者
 * 一直用旧身份在工作。
 *
 * 服务端那边还可以用"升 realm"让所有客户端重新问一次（换 realm = 换保护空间），
 * 但那是运维动作；这一条是让 App 自己能立刻生效：换过凭据再进终端页，先清一次缓存。
 *
 * 尽力而为：平台调不到（老系统 / 单测）就回 false，由调用方按"清不掉也照常加载"处理。
 */
object WebViewAuthCacheChannel {
    const val CHANNEL = "top.hpa888.box/webview_auth_cache"
    const val METHOD_CLEAR = "clear"

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                METHOD_CLEAR -> result.success(clear(context))
                else -> result.notImplemented()
            }
        }
    }

    /** 返回是否真的清了一次；异常不往外抛（凭据缓存不是功能正确性的前提）。 */
    private fun clear(context: Context): Boolean = try {
        WebViewDatabase.getInstance(context).clearHttpAuthUsernamePassword()
        true
    } catch (e: Throwable) {
        false
    }
}
