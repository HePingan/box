package top.hpa888.box

/**
 * 决定一个无障碍事件是否值得触发全树抓题扫描。
 *
 * 扫描代价很高：枚举交互窗口 + 递归遍历目标 App 节点树，每次 getChild /
 * getBoundsInScreen 都是 binder 跨进程调用，且全部发生在 App 主线程 ——
 * 正是渲染悬浮窗的那条线程。
 *
 * 我们自己的浮层滚动时会持续发 TYPE_VIEW_SCROLLED，把这条重扫描反复唤起，
 * 于是滑动掉帧。而这些扫描本身毫无意义：题目在目标 App 里，
 * 我们自己滚动不代表目标页面变了。
 */
object QuizCaptureScanGate {

    /**
     * @param eventPackage 事件来源包名，可能为空（部分 ROM 不上报）
     * @param selfPackage 本应用包名
     * @param ownOverlayInteracting 用户此刻是否正在滑动/拖动我们自己的浮层
     */
    fun shouldScan(
        eventPackage: String,
        selfPackage: String,
        ownOverlayInteracting: Boolean,
    ): Boolean {
        // 操作自己的浮层期间优先保帧率，扫描一律推迟到松手之后。
        if (ownOverlayInteracting) return false
        // 包名为空时不敢误杀，宁可多扫一次也不能漏题。
        if (eventPackage.isBlank()) return true
        // 自身浮层事件：纯无用功，直接挡掉。
        if (eventPackage == selfPackage) return false
        // 系统 UI（状态栏/通知栏动画）同样不会带来新题。
        if (eventPackage == "com.android.systemui" ||
            eventPackage.startsWith("com.android.systemui")
        ) {
            return false
        }
        return true
    }
}
