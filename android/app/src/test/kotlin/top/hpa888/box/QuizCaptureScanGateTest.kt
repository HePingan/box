package top.hpa888.box

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 无障碍抓题扫描门闸。
 *
 * onAccessibilityEvent 跑在 App 主线程，也就是渲染 OCR 录入窗的那条线程。
 * 一次 extractAndSend 会枚举所有交互窗口再递归遍历目标 App 节点树
 * （每个 getChild / getBoundsInScreen 都是 binder 跨进程调用），
 * 几百次 IPC 全压在主线程上。
 *
 * 在录入窗里上下滑内容、左右滑功能按钮时，我们自己的窗口会持续发
 * TYPE_VIEW_SCROLLED，把这条重扫描按 500ms 节流反复触发 —— 滑动期间掉帧。
 * 这些扫描还全是无用功：题目来自目标 App，我们自己滚动不代表目标页面变了。
 */
class QuizCaptureScanGateTest {

    private val self = "com.example.box"

    @Test
    fun `自己窗口发出的事件不得触发抓题扫描`() {
        // 这就是用户报的卡顿来源：录入窗滚动 → 自身 TYPE_VIEW_SCROLLED → 全树重扫。
        assertFalse(
            QuizCaptureScanGate.shouldScan(
                eventPackage = self,
                selfPackage = self,
                ownOverlayInteracting = false,
            ),
        )
    }

    @Test
    fun `目标 App 的事件正常触发扫描`() {
        assertTrue(
            QuizCaptureScanGate.shouldScan(
                eventPackage = "com.jiakaobaodian.app",
                selfPackage = self,
                ownOverlayInteracting = false,
            ),
        )
    }

    @Test
    fun `手指正在操作自己的浮层时一律不扫描`() {
        // 滑动/拖动期间即使目标 App 在后台连发事件，也要先保住我们的帧率。
        assertFalse(
            QuizCaptureScanGate.shouldScan(
                eventPackage = "com.jiakaobaodian.app",
                selfPackage = self,
                ownOverlayInteracting = true,
            ),
        )
    }

    @Test
    fun `松手后恢复扫描`() {
        assertTrue(
            QuizCaptureScanGate.shouldScan(
                eventPackage = "com.jiakaobaodian.app",
                selfPackage = self,
                ownOverlayInteracting = false,
            ),
        )
    }

    @Test
    fun `包名为空时不误杀，保持原有抓题能力`() {
        // 部分 ROM 对浮层事件不报包名；宁可多扫一次也不能漏题。
        assertTrue(
            QuizCaptureScanGate.shouldScan(
                eventPackage = "",
                selfPackage = self,
                ownOverlayInteracting = false,
            ),
        )
    }

    @Test
    fun `系统 UI 事件不触发扫描`() {
        // 状态栏/通知栏动画会连发事件，扫描同样是无用功。
        assertFalse(
            QuizCaptureScanGate.shouldScan(
                eventPackage = "com.android.systemui",
                selfPackage = self,
                ownOverlayInteracting = false,
            ),
        )
    }
}
