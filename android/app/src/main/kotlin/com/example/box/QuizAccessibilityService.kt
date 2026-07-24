package com.example.box

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.PixelFormat
import android.hardware.HardwareBuffer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.accessibilityservice.GestureDescription
import android.os.SystemClock
import android.graphics.Path
import java.io.ByteArrayOutputStream
import kotlin.math.max
import android.view.ContextThemeWrapper
import android.view.Gravity
import android.view.LayoutInflater
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import kotlin.math.hypot

/**
 * 答题插件无障碍服务。
 *
 * 职责（P0 重构后）：
 *  1. 捕获：通过 AccessibilityNodeInfo 读取目标 App 屏幕文本（不受 FLAG_SECURE 影响）。
 *  2. 显示：唯一使用 TYPE_ACCESSIBILITY_OVERLAY 承载答案悬浮窗。该窗口类型属于系统
 *     无障碍层，不计入普通悬浮窗检测，不需要 SYSTEM_ALERT_WINDOW 权限，可绕过
 *     驾考宝典等 App 的悬浮窗屏蔽 / 考试模式限制。
 *  3. 与 MainActivity 的交互改为直接静态方法调用（持有 runningService 单例），
 *     不再依赖易丢失/有延迟的广播来驱动显示。
 */
class QuizAccessibilityService : AccessibilityService() {

    companion object {
        private const val CHANNEL = "com.example.box/quiz_plugin"
        private const val TAG = "QuizAccessibility"
        private const val PREFS_NAME = "quiz_plugin_prefs"
        private const val KEY_REGION = "quiz_region"
        private const val KEY_OVERLAY_GEOMETRY = "quiz_overlay_geometry"
        private const val KEY_OVERLAY_COMPACT_MIGRATED = "quiz_overlay_compact_migrated_v4"
        private const val KEY_OVERLAY_OPACITY = "quiz_overlay_opacity"
        private const val KEY_OVERLAY_FONT_SCALE = "quiz_overlay_font_scale"
        private const val KEY_HIDDEN_DOT = "quiz_overlay_hidden_dot"
        private const val KEY_EXAM_MODE = "quiz_exam_mode"
        private const val KEY_ANSWER_ONLY = "quiz_answer_only"
        private const val KEY_ANSWER_ONLY_BEFORE_EXAM = "quiz_answer_only_before_exam"
        private const val KEY_PRE_EXAM_GEOMETRY = "quiz_pre_exam_geometry"
        private const val KEY_EXAM_OVERLAY_SIZE = "quiz_exam_overlay_size"
        private const val KEY_CLICK_THROUGH = "quiz_click_through_collapsed"
        private const val KEY_THEME_COLOR = "quiz_theme_color"
        private const val KEY_COLLAPSED = "quiz_overlay_collapsed"
        private const val CONFIG_PREFS_NAME = "FlutterSharedPreferences"
        private const val CONFIG_KEY = "flutter.quiz_plugin_config"
        const val ACTION_UPDATE_REGION = "com.example.box.UPDATE_QUIZ_REGION"

        // 悬浮窗尺寸/字号约束（默认更宽，避免标题按钮挤压与文字被截断）
        private const val OVERLAY_MIN_WIDTH_DP = 240
        private const val OVERLAY_MIN_HEIGHT_DP = 140
        private val FONT_SCALE_STEPS = floatArrayOf(0.85f, 1.0f, 1.2f, 1.45f)
        private val THEME_COLORS = intArrayOf(
            0xFF4F46E5.toInt(), // 靛蓝
            0xFF059669.toInt(), // 翠绿
            0xFFDC2626.toInt(), // 红
            0xFF7C3AED.toInt(), // 紫
            0xFF0891B2.toInt(), // 青
        )

        private val NOISE_LINES = setOf(
            "设置", "返回", "取消", "确定", "确认", "保存", "删除",
            "编辑", "搜索", "加载中", "暂无", "请输入", "请选择",
            "点击", "打开", "关闭", "Android", "WLAN", "蓝牙",
            "移动网络", "通知", "电池", "存储", "安全", "应用"
        )

        private val NOISE_CONTAINS = setOf(
            "上一题", "下一题", "收藏", "查看解析", "提交答案", "交卷",
            "广告", "会员", "分享", "反馈", "继续练习", "重新答题",
            "正确答案", "我的答案", "答题卡", "考试记录"
        )

        private val QUIZ_KEYWORDS = setOf(
            "题", "A.", "B.", "C.", "D.", "A、", "B、", "C、", "D、",
            "单选", "多选", "判断", "选择", "答案", "题目", "解析",
            "1.", "2.", "3.", "4.", "①", "②", "③", "④",
            "以下", "关于", "下列", "正确", "错误", "不是",
            "?", "？", "___", "____"
        )

        private const val MAX_TREE_DEPTH = 40

        private var lastWindowCaptureAt = 0L
        private var lastTextCaptureAt = 0L
        private var lastContentCaptureAt = 0L
        private var lastQuestion = ""
        private var lastQuestionSentAt = 0L
        @Volatile private var runningService: QuizAccessibilityService? = null
        // 无障碍悬浮窗最近一次创建是否失败（供诊断用）
        @Volatile var accessibilityOverlayCreateFailed: Boolean = false
            private set
        // 截屏结果缓存（takeScreenshot 回调异步返回，Dart 侧轮询读取）
        @Volatile var lastScreenshotBytes: ByteArray? = null
        // 当前活跃截图请求的 requestId，用于丢弃过期回调
        @Volatile var currentRequestId: Int = 0

        fun isRunning(): Boolean = runningService != null

        /**
         * 仅当无障碍悬浮窗已真正添加到 WindowManager 时才返回 true。
         *
         * 创建操作在主线程异步执行；此前返回 true 会让 Flutter 误报“已显示”，
         * 即使 addView() 随后失败，普通悬浮窗/通知栏的兜底也不会触发。
         */
        fun showOverlayIfRunning(
            question: String,
            answers: String,
            status: String = "idle",
            answerKey: String? = null,
            similarity: Int? = null,
            matchIndex: Int = 0,
            matchCount: Int = 1,
            answersList: List<String> = emptyList(),
        ): Boolean {
            val svc = runningService ?: return false
            if (Looper.myLooper() == svc.mainHandler.looper) {
                return svc.showOrUpdateAccessibilityOverlay(
                    question, answers, status, answerKey, similarity, matchIndex, matchCount, answersList
                )
            }
            val shown = java.util.concurrent.atomic.AtomicBoolean(false)
            val completed = java.util.concurrent.CountDownLatch(1)
            svc.mainHandler.post {
                try {
                    shown.set(
                        svc.showOrUpdateAccessibilityOverlay(
                            question, answers, status, answerKey, similarity, matchIndex, matchCount, answersList
                        )
                    )
                } finally {
                    completed.countDown()
                }
            }
            return try {
                // 主线程可能被 Flutter 首帧/布局占满；1s 过短会误判失败并跳过 a11y 窗。
                completed.await(3, java.util.concurrent.TimeUnit.SECONDS) && shown.get()
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                false
            }
        }

        /** 无障碍悬浮窗当前是否已添加（用于可见性判断）。 */
        fun hasOverlayView(): Boolean {
            val svc = runningService ?: return false
            return svc.accessibilityOverlayView != null
        }

        /** 隐藏无障碍悬浮窗。 */
        fun hideOverlayIfRunning() {
            val svc = runningService ?: return
            svc.mainHandler.post { svc.hideAccessibilityOverlay() }
        }

        /** 重新显示无障碍悬浮窗（用服务内缓存的题目/答案）。关闭助手时不恢复。 */
        fun restoreOverlayIfRunning() {
            val svc = runningService ?: return
            svc.mainHandler.post {
                if (!svc.isPluginEnabledInConfig()) {
                    svc.hideAccessibilityOverlay()
                    return@post
                }
                if (QuizOcrEntryOverlay.isShowing()) return@post
                svc.showOrUpdateAccessibilityOverlay("", "")
            }
        }

        /**
         * 截屏并裁剪到识别区域，回调返回 PNG 字节（失败返回 null）。
         * 依赖 AccessibilityService.takeScreenshot（API 30+）。
         */
        fun captureRegionIfRunning(callback: (ByteArray?) -> Unit): Boolean {
            val svc = runningService ?: return false
            svc.captureRegionScreenshot(callback)
            return true
        }

        /**
         * 带 requestId 的截屏：Dart 侧用 [QuizCaptureSessionCoordinator] 校验请求归属，
         * 防止并发 OCR/录入/试识串图。
         */
        fun captureRegionIfRunningWithRequestId(
            requestId: Int,
            callback: (ByteArray?) -> Unit,
        ): Boolean {
            val svc = runningService ?: return false
            svc.captureRegionScreenshotWithRequestId(requestId, callback)
            return true
        }

        /**
         * 设置无障碍悬浮窗整体透明度（0.3~1.0）。
         */
        fun setOverlayOpacityIfRunning(opacity: Float): Boolean {
            val svc = runningService ?: return false
            svc.mainHandler.post { svc.setOverlayOpacity(opacity) }
            return true
        }

        /** 设置普通答题悬浮窗的宽高（dp），实时应用并持久化。 */
        fun setOverlaySizeIfRunning(widthDp: Float, heightDp: Float): Boolean {
            val svc = runningService ?: return false
            svc.mainHandler.post { svc.setOverlaySizeFromDp(widthDp, heightDp) }
            return true
        }

        /** 恢复推荐紧凑卡片尺寸并清除历史手动几何。 */
        fun resetOverlaySizeIfRunning(): Boolean {
            val svc = runningService ?: return false
            svc.mainHandler.post { svc.resetOverlayGeometry(svc.accessibilityOverlayView ?: return@post) }
            return true
        }

        /** 进入识别区域调节（服务自建全屏无障碍浮层，有权限）。 */
        fun enterRegionModeIfRunning(): Boolean {
            val svc = runningService ?: return false
            svc.mainHandler.post { svc.enterRegionMode() }
            return true
        }

        /** 录入窗发起框选：保存区域后走录入试捕，而不是答题搜题。 */
        fun requestEntryProbeAfterRegionIfRunning(): Boolean {
            val svc = runningService ?: return false
            svc.mainHandler.post { svc.pendingProbeAfterRegion = "entry" }
            return true
        }

        /**
         * 用当前已框选/已保存的识别区域直接「试捕」读屏填表，
         * 无需重新进入区域调节。供 OCR 录入窗的「试捕」按钮调用。
         * delayMs：录入窗刚 minimize 后给系统一点时间把 active window 切回目标 App。
         */
        fun probeFromSavedRegionIfRunning(delayMs: Long = 0L): Boolean {
            val svc = runningService ?: return false
            if (delayMs > 0L) {
                svc.mainHandler.postDelayed({ svc.probeNodesFromSavedRegion() }, delayMs)
            } else {
                svc.mainHandler.post { svc.probeNodesFromSavedRegion() }
            }
            return true
        }

        /** 将 Flutter 侧预设实时同步到服务自建的区域选择器。 */
        fun applyRegionPresetIfRunning(left: Float, top: Float, right: Float, bottom: Float): Boolean {
            val svc = runningService ?: return false
            svc.mainHandler.post { svc.applyRegionPreset(left, top, right, bottom) }
            return true
        }

        /** 退出识别区域调节，恢复答案悬浮窗。 */
        fun exitRegionModeIfRunning(): Boolean {
            val svc = runningService ?: return false
            svc.mainHandler.post { svc.exitRegionMode() }
            return true
        }

        /**
         * Flutter 配置保存后调用：按当前前台包 + autoExamOnLeaveApp 重算考试模式，
         * 避免「关掉离开App自动考试」后悬浮窗仍停在考试态。
         */
        fun onConfigChangedIfRunning(): Boolean {
            val svc = runningService ?: return false
            svc.mainHandler.post { svc.reapplyAutoExamFromConfig() }
            return true
        }

        /** Dart OCR 试识结果回写到区域调节预览面板。 */
        fun setProbeResultIfRunning(title: String, body: String): Boolean {
            val svc = runningService ?: return false
            svc.mainHandler.post { svc.showProbePanel(title, body) }
            return true
        }

        /** 供外部类（如 OCR 录入窗）取当前服务实例。 */
        fun runningServiceOrNull(): QuizAccessibilityService? = runningService

        /** 检查当前是否已有已保存的识别区域 */
        fun hasRegionIfRunning(): Boolean {
            val svc = runningService ?: return false
            return svc.screenRegion != null
        }

        /**
         * 批量翻到下一题：优先点击有语义的「下一题」节点，找不到时回退左滑。
         * 回调为 true 表示导航动作已被系统接受，不代表页面已渲染完成。
         */
        fun navigateToNextQuestion(
            svc: QuizAccessibilityService,
            onComplete: (Boolean, String) -> Unit,
        ) {
            // 手势能力由 service xml 的 canPerformGestures 授予；不能用节点点击
            // 作为前置条件，否则不少 WebView/Canvas 题库会误判“已导航”却完全没翻页。
            dispatchBatchSwipeLeft(svc) { accepted -> onComplete(accepted, "左滑") }
        }

        /** 批量录入时发送左滑手势（从屏幕右侧向左侧滑动）。
         * 回调发生在手势结束/取消后，供调用方只在真正完成滑动后继续试捕。
         */
        fun dispatchBatchSwipeLeft(
            svc: QuizAccessibilityService,
            onComplete: (Boolean) -> Unit,
        ) {
            val dm = svc.resources.displayMetrics
            val startX = dm.widthPixels * 0.88f
            val endX = dm.widthPixels * 0.12f
            // 中间略偏下，避开多数题目卡片中的可点击控件，也减少状态栏/手势区干扰。
            val y = dm.heightPixels * 0.58f
            val path = Path().apply {
                moveTo(startX, y)
                lineTo(endX, y)
            }
            val gesture = GestureDescription.Builder()
                .addStroke(GestureDescription.StrokeDescription(path, 60L, 550L))
                .build()
            try {
                val accepted = svc.dispatchGesture(
                    gesture,
                    object : AccessibilityService.GestureResultCallback() {
                        override fun onCompleted(gestureDescription: GestureDescription?) {
                            onComplete(true)
                        }

                        override fun onCancelled(gestureDescription: GestureDescription?) {
                            Log.w(TAG, "batch left swipe cancelled")
                            onComplete(false)
                        }
                    },
                    svc.mainHandler,
                )
                if (!accepted) {
                    Log.w(TAG, "batch left swipe was rejected; accessibility service may need re-enable")
                    onComplete(false)
                }
            } catch (e: Throwable) {
                Log.w(TAG, "batch left swipe failed", e)
                onComplete(false)
            }
        }

        /** 打开 OCR 悬浮录入窗（需无障碍服务运行）。 */
        fun showOcrEntryOverlayIfRunning(): Boolean {
            val svc = runningService ?: return false
            svc.mainHandler.post {
                // 清理区域调节后的试捕待处理标记，避免 OCR 录入打开后区域确认误路由
                svc.pendingProbeAfterRegion = null
                // 录入期间压制答案窗，避免叠层干扰
                svc.hideAccessibilityOverlay()
                // 若正处于区域调节，先退出，避免两窗叠加
                if (svc.regionWindowView != null) svc.exitRegionMode()
                QuizOcrEntryOverlay.showOn(svc)
            }
            return true
        }

        fun hideOcrEntryOverlay() {
            Handler(Looper.getMainLooper()).post {
                QuizOcrEntryOverlay.hideIfShowing()
            }
        }
    }

    val mainHandler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var isActive = false
    private var screenRegion: RectF? = null
    private var windowManager: WindowManager? = null
    private var accessibilityOverlayView: View? = null
    private var overlayParams: WindowManager.LayoutParams? = null
    private var overlayQuestion = ""
    private var overlayAnswers = ""
    private var overlayStatus = "idle"
    private var overlayAnswerKey: String? = null
    private var overlaySimilarity: Int? = null
    private var overlayMatchIndex = 0
    private var overlayMatchCount = 1
    private var overlayAnswersList: List<String> = emptyList()
    private var lastProbeSearchText: String = ""
    /** 无区域时点试捕：先框选，保存后自动继续。entry=录入填表；answer=答题搜题 */
    private var pendingProbeAfterRegion: String? = null
    private var commandReceiver: BroadcastReceiver? = null

    // 悬浮窗几何 / 外观状态
    private var overlayFontScaleIndex = 1 // 默认中号（FONT_SCALE_STEPS[1] = 1.0）
    private var overlayCollapsed = false
    private var overlayHiddenDot = false
    @Volatile private var hiddenDotDragging = false
    private var deferredCaptureAfterDotDrag: Runnable? = null
    private var overlayExpandedHeight = 0 // 展开时的窗口高度（px），折叠时暂存
    private var examMode = false
    private var clickThroughWhenCollapsed = false
    private var themeColor = THEME_COLORS[0]
    private var lastForegroundPkg = ""
    private var autoExamByForeground = false
    private var preExamGeometry: String? = null // "x,y,w,h"
    private var lastVolumeDownAt = 0L
    private var volumeDownTapPending = false
    private var volumeDownResetTask: Runnable? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                    AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED or
                    AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED or
                    AccessibilityEvent.TYPE_VIEW_SCROLLED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            notificationTimeout = 600
            // 必须保留 FLAG_RETRIEVE_INTERACTIVE_WINDOWS，否则 windows 列表不可用，
            // 直接点悬浮窗「试捕」时 rootInActiveWindow 常为 null（前台焦点刚在我们自己的浮层上）。
            flags = AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                    AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                    AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                    AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
        }
        serviceInfo = info
        channel = resolveChannel()
        screenRegion = loadRegion()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        registerCommandReceiver()
        runningService = this
        isActive = true
        // 恢复持久化外观
        examMode = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_EXAM_MODE, false)
        answerOnlyMode = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_ANSWER_ONLY, false)
        clickThroughWhenCollapsed = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_CLICK_THROUGH, false)
        overlayCollapsed = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_COLLAPSED, false)
        overlayHiddenDot = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_HIDDEN_DOT, false)
        themeColor = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getInt(KEY_THEME_COLOR, THEME_COLORS[0])
        applyThemeFromFlutterConfig()
        // 服务被杀恢复：仅当配置 enabled 且 OCR 录入未打开时自动显示答案窗
        if (isPluginEnabledInConfig() && !QuizOcrEntryOverlay.isShowing()) {
            mainHandler.post {
                showOrUpdateAccessibilityOverlay(
                    overlayQuestion.ifBlank { "等待捕获题目…" },
                    overlayAnswers.ifBlank { "等待搜题结果…" },
                    overlayStatus,
                    overlayAnswerKey,
                    overlaySimilarity,
                    overlayMatchIndex,
                    overlayMatchCount,
                )
            }
        }
    }

    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        val params = overlayParams ?: return
        val view = accessibilityOverlayView ?: return
        clampParamsToScreen(params)
        try { windowManager?.updateViewLayout(view, params) } catch (_: Throwable) {}
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        // 只监听批量录入期间的音量下键双击；返回 false，不吞系统原本的音量调节。
        if (event.keyCode != KeyEvent.KEYCODE_VOLUME_DOWN ||
            event.action != KeyEvent.ACTION_DOWN ||
            event.repeatCount != 0 ||
            !QuizOcrEntryOverlay.isBatchRunning()) {
            return false
        }
        val now = SystemClock.uptimeMillis()
        if (volumeDownTapPending && now - lastVolumeDownAt <= 550L) {
            volumeDownTapPending = false
            volumeDownResetTask?.let { mainHandler.removeCallbacks(it) }
            volumeDownResetTask = null
            QuizOcrEntryOverlay.stopBatchEntryIfRunning("音量下键双击")
        } else {
            volumeDownTapPending = true
            lastVolumeDownAt = now
            volumeDownResetTask?.let { mainHandler.removeCallbacks(it) }
            val reset = Runnable { volumeDownTapPending = false }
            volumeDownResetTask = reset
            mainHandler.postDelayed(reset, 550L)
        }
        return false
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (!isActive) return
        // 驾考宝典页面滚动/动画会高频发节点事件；圆点拖动优先，扫描延后到松手后。
        if (hiddenDotDragging) return

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                // 前台包名感知：离开 box 自动考试模式，回到 box 恢复
                val eventPkg = event.packageName?.toString().orEmpty()
                val pkg = resolveForegroundPackageForAutoExam(eventPkg)
                if (pkg.isNotBlank() && pkg != lastForegroundPkg) {
                    lastForegroundPkg = pkg
                    handleForegroundPackage(pkg)
                }
                val now = System.currentTimeMillis()
                // 窗口切换是新题强信号；仅按窗口事件独立限流。
                if (now - lastWindowCaptureAt < 300) return
                extractAndSend(bestCaptureRoot(event.source))
                lastWindowCaptureAt = now
            }
            AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED -> {
                val now = System.currentTimeMillis()
                // 文本变化易在动画中连发，独立限流，避免阻塞真正窗口切题。
                if (now - lastTextCaptureAt < 750) return
                extractAndSend(bestCaptureRoot(event.source))
                lastTextCaptureAt = now
            }
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED,
            AccessibilityEvent.TYPE_VIEW_SCROLLED -> {
                // 内容/滚动可能是同题 UI 动画，但翻题 App 也常只发该事件；
                // 使用较短节流，Dart 指纹/命中锁负责进一步防重。
                val now = System.currentTimeMillis()
                if (now - lastContentCaptureAt < 500) return
                extractAndSend(bestCaptureRoot(event.source))
                lastContentCaptureAt = now
            }
        }
    }

    /**
     * 无障碍浮层自身也会发 WINDOW_STATE_CHANGED；不能把它误当成回到 box，
     * 否则自动考试模式刚进入就会被自己的 overlay 事件退出。
     */
    private fun resolveForegroundPackageForAutoExam(eventPkg: String): String {
        if (eventPkg != packageName) return eventPkg
        val rootPkg = try { rootInActiveWindow?.packageName?.toString().orEmpty() } catch (_: Throwable) { "" }
        return rootPkg.takeIf { it.isNotBlank() && it != packageName } ?: eventPkg
    }

    private fun handleForegroundPackage(pkg: String) {
        val self = packageName
        if (pkg == self) {
            if (autoExamByForeground && examMode) {
                autoExamByForeground = false
                setExamMode(false)
            }
        } else if (shouldAutoExamForPackage(pkg) && !examMode) {
            // 切到第三方 App：按配置自动考试模式（少挡题）
            autoExamByForeground = true
            setExamMode(true)
        } else if (!shouldAutoExamForPackage(pkg) && autoExamByForeground && examMode) {
            // 配置已关 / 不在白名单：若当前是自动进的考试模式则退出
            autoExamByForeground = false
            setExamMode(false)
        }
        // 按 App 切换识别区域（不在区域调节中时）
        if (regionWindowView == null && pkg.isNotBlank() && pkg != self) {
            val perApp = loadRegionForPackage(pkg)
            if (perApp != null) {
                screenRegion = perApp
            }
        }
    }

    /** 配置变更后：用 lastForegroundPkg 重新套用自动考试规则。 */
    private fun reapplyAutoExamFromConfig() {
        val pkg = lastForegroundPkg.ifBlank {
            // 尽量从根窗口猜前台
            try {
                rootInActiveWindow?.packageName?.toString().orEmpty()
            } catch (_: Throwable) {
                ""
            }
        }
        if (pkg.isBlank()) {
            // 无前台信息：若自动考试已关且当前是自动进的考试态，退出
            if (!isAutoExamConfigEnabled() && autoExamByForeground && examMode) {
                autoExamByForeground = false
                setExamMode(false)
            } else {
                // 仍刷新考试 chrome（按钮显隐）
                accessibilityOverlayView?.let { applyExamChrome(it) }
                updateAccessibilityOverlayView()
            }
            return
        }
        handleForegroundPackage(pkg)
        accessibilityOverlayView?.let {
            applyExamChrome(it)
            applyAnswerOnlyVisibility(it)
            if (examMode && overlayParams != null && !overlayCollapsed) {
                // 修改小/标准/大后，当前考试窗立即换尺寸，无需切换 App。
                applyExamOverlayDimensions(overlayParams!!, it)
            }
        }
        updateAccessibilityOverlayView()
    }

    private fun isAutoExamConfigEnabled(): Boolean {
        val raw = getSharedPreferences(CONFIG_PREFS_NAME, Context.MODE_PRIVATE)
            .getString(CONFIG_KEY, null) ?: return true
        return !Regex("\"autoExamOnLeaveApp\"\\s*:\\s*false").containsMatchIn(raw)
    }

    /** 读取 Flutter 的考试窗尺寸偏好，兼容老版本默认 standard。 */
    private fun examOverlaySizePreference(): String {
        val raw = getSharedPreferences(CONFIG_PREFS_NAME, Context.MODE_PRIVATE)
            .getString(CONFIG_KEY, null) ?: return "standard"
        val value = Regex("\"examOverlaySize\"\\s*:\\s*\"([^\"]+)\"")
            .find(raw)?.groupValues?.getOrNull(1)
        return when (value) {
            "small", "standard", "large" -> value
            else -> "standard"
        }
    }

    /**
     * 考试窗尺寸：按答案卡片设计（接近方形），不沿用普通窗或历史手动尺寸。
     * 高度直接由宽度推导，避免不同长屏设备上再次退化成横向长条。
     */
    private fun examOverlayDimensions(): Pair<Int, Int> {
        val dm = resources.displayMetrics
        return when (examOverlaySizePreference()) {
            "small" -> {
                val w = (dm.widthPixels * 0.36f).toInt().coerceIn(250, 390)
                w to (w * 0.90f).toInt().coerceIn(225, 350)
            }
            "large" -> {
                val w = (dm.widthPixels * 0.54f).toInt().coerceIn(360, 590)
                w to (w * 0.92f).toInt().coerceIn(330, 540)
            }
            else -> {
                val w = (dm.widthPixels * 0.46f).toInt().coerceIn(300, 500)
                w to (w * 0.92f).toInt().coerceIn(275, 460)
            }
        }
    }

    private fun applyExamOverlayDimensions(
        params: WindowManager.LayoutParams,
        view: View,
        updatePosition: Boolean = false,
    ) {
        val (w, h) = examOverlayDimensions()
        params.width = w
        params.height = h
        // 考试模式必须突破普通窗的历史几何；统一靠右上定位并立即更新。
        val dm = resources.displayMetrics
        params.x = (dm.widthPixels - w - dm.widthPixels * 0.03f).toInt().coerceAtLeast(0)
        params.y = (dm.heightPixels * 0.08f).toInt()
        clampParamsToScreen(params)
        try { windowManager?.updateViewLayout(view, params) } catch (e: Throwable) {
            Log.w(TAG, "apply exam overlay geometry failed: ${e.javaClass.simpleName}", e)
        }
    }

    /** 是否应对该包自动考试模式（读 Flutter 配置）。 */
    private fun shouldAutoExamForPackage(pkg: String): Boolean {
        if (pkg.isBlank() || pkg == packageName) return false
        if (pkg.startsWith("com.android") || pkg == "com.android.systemui") return false
        if (!isAutoExamConfigEnabled()) return false
        val raw = getSharedPreferences(CONFIG_PREFS_NAME, Context.MODE_PRIVATE)
            .getString(CONFIG_KEY, null) ?: return true
        val m = Regex("\"autoExamPackages\"\\s*:\\s*\"([^\"]*)\"").find(raw)
        val listRaw = m?.groupValues?.getOrNull(1)?.replace("\\n", "\n")?.replace("\\r", "") ?: ""
        val packages = listRaw.split(',', '\n', ';', ' ')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        if (packages.isEmpty()) return true // 空白名单 = 全部第三方
        return packages.any { pkg == it || pkg.startsWith("$it.") }
    }

    override fun onInterrupt() {
        // ignore
    }

    override fun onDestroy() {
        runningService = null
        unregisterCommandReceiver()
        hideAccessibilityOverlay()
        QuizOcrEntryOverlay.hideIfShowing()
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        handleCommand(intent)
        return START_NOT_STICKY
    }

    private fun registerCommandReceiver() {
        if (commandReceiver != null) return
        commandReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                handleCommand(intent)
            }
        }
        // 仅识别区域更新仍走广播（低频、非关键路径）；显示/隐藏改为直接静态调用。
        val filter = IntentFilter().apply {
            addAction(ACTION_UPDATE_REGION)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(commandReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(commandReceiver, filter)
        }
    }

    private fun unregisterCommandReceiver() {
        val receiver = commandReceiver ?: return
        try {
            unregisterReceiver(receiver)
        } catch (_: Throwable) {}
        commandReceiver = null
    }

    private fun handleCommand(intent: Intent?) {
        when (intent?.action) {
            ACTION_UPDATE_REGION -> {
                val left = intent.getIntExtra("left", -1)
                val top = intent.getIntExtra("top", -1)
                val right = intent.getIntExtra("right", -1)
                val bottom = intent.getIntExtra("bottom", -1)
                if (left >= 0 && top >= 0 && right > left && bottom > top) {
                    val region = RectF(left.toFloat(), top.toFloat(), right.toFloat(), bottom.toFloat())
                    saveRegion(region)
                    screenRegion = region
                }
            }
        }
    }

    /**
     * 显示或刷新无障碍悬浮窗。
     *
     * 返回值必须反映 addView 的真实结果，供调用方决定是否切到普通悬浮窗/通知栏兜底。
     * 若用户已关闭答题助手（config.enabled=false），则拒绝创建/刷新，避免录入时仍弹答案窗。
     */
    private fun showOrUpdateAccessibilityOverlay(
        question: String,
        answers: String,
        status: String = "idle",
        answerKey: String? = null,
        similarity: Int? = null,
        matchIndex: Int = 0,
        matchCount: Int = 1,
        answersList: List<String> = emptyList(),
    ): Boolean {
        // 关闭答题助手后：不创建、不刷新答案悬浮窗（OCR 录入场景尤其需要）
        if (!isPluginEnabledInConfig()) {
            if (accessibilityOverlayView != null) {
                hideAccessibilityOverlay()
            }
            return false
        }
        // OCR 录入窗打开时，不抢占/盖住录入窗
        if (QuizOcrEntryOverlay.isShowing()) {
            // 仍更新缓存，便于关闭录入后恢复
            overlayQuestion = question.ifBlank { overlayQuestion }
            overlayAnswers = answers.ifBlank { overlayAnswers }
            if (status.isNotBlank()) overlayStatus = status
            if (answerKey != null) overlayAnswerKey = answerKey
            if (answersList.isNotEmpty()) {
                overlayAnswersList = answersList
                overlayMatchCount = answersList.size
                overlayMatchIndex = matchIndex.coerceIn(0, answersList.lastIndex)
                overlayAnswers = answersList[overlayMatchIndex]
            }
            return false
        }
        overlayQuestion = question.ifBlank { overlayQuestion }
        // 新题检索中：明确清空旧匹配列表，不能让上一题 answersList 残留。
        if (status == "searching") {
            overlayAnswersList = emptyList()
            overlayMatchIndex = 0
            overlayMatchCount = 1
            overlayAnswerKey = answerKey
            if (similarity != null && similarity > 0) overlaySimilarity = similarity
        }
        overlayAnswers = answers
        if (status.isNotBlank()) overlayStatus = status
        if (answerKey != null) overlayAnswerKey = answerKey
        // 相似度为 0 时不覆盖已有值，让 Native 回退到 SIM marker/正则提取
        if (similarity != null && similarity > 0) overlaySimilarity = similarity
        if (answersList.isNotEmpty()) {
            overlayAnswersList = answersList
            overlayMatchCount = answersList.size
            overlayMatchIndex = matchIndex.coerceIn(0, answersList.lastIndex)
            overlayAnswers = answersList[overlayMatchIndex]
        } else {
            overlayMatchIndex = matchIndex
            overlayMatchCount = matchCount.coerceAtLeast(1)
        }
        if (accessibilityOverlayView == null) {
            if (!createAccessibilityOverlay()) {
                Log.w(TAG, "TYPE_ACCESSIBILITY_OVERLAY create failed")
                accessibilityOverlayCreateFailed = true
                return false
            }
        }
        accessibilityOverlayCreateFailed = false
        updateAccessibilityOverlayView()
        return true
    }

    /**
     * AccessibilityService 默认主题不含 AppCompat attr。
     * 布局若引用 ?attr/xxx 会在 inflate 时 InflateException，必须用系统主题包装。
     */
    private fun themedInflater(): LayoutInflater {
        val themed = ContextThemeWrapper(this, android.R.style.Theme_DeviceDefault_Light)
        return LayoutInflater.from(themed)
    }

    /** inflate 失败时的最小答案窗（纯代码，不依赖 XML 主题 attr）。 */
    private fun createMinimalAnswerView(): View {
        val density = resources.displayMetrics.density
        val pad = (12 * density).toInt()
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(0xFFFFFFFF.toInt())
            setPadding(pad, pad, pad, pad)
            elevation = 10f * density
        }
        val title = TextView(this).apply {
            text = "答题助手"
            setTextColor(0xFF4F46E5.toInt())
            textSize = 15f
            setPadding(0, 0, 0, pad / 2)
        }
        val q = TextView(this).apply {
            id = R.id.tv_question
            text = "等待捕获题目…"
            setTextColor(0xFF101828.toInt())
            textSize = 14f
        }
        val a = TextView(this).apply {
            id = R.id.tv_answer
            text = "等待搜题结果…"
            setTextColor(0xFF344054.toInt())
            textSize = 13f
            setPadding(0, pad / 2, 0, 0)
        }
        root.addView(title)
        root.addView(q)
        root.addView(a)
        root.setOnClickListener { /* 占位，拖动由 attachDragHandler 处理 */ }
        return root
    }

    private fun inflateOverlayView(): View {
        return try {
            themedInflater().inflate(R.layout.quiz_overlay, null)
        } catch (e: Throwable) {
            Log.w(TAG, "inflate quiz_overlay failed, using minimal view: ${e.message}", e)
            createMinimalAnswerView()
        }
    }

    private fun createAccessibilityOverlay(): Boolean {
        return try {
            val wm = windowManager
                ?: (getSystemService(Context.WINDOW_SERVICE) as? WindowManager).also { windowManager = it }
                ?: return false
            val view = inflateOverlayView()
            // 无障碍悬浮窗中按钮（若是 minimal view 则 findViewById 为 null，安全跳过）
            view.findViewById<View>(R.id.btn_area)?.setOnClickListener {
                // 从答案窗进区域模式：保存后默认自动试捕并搜题
                pendingProbeAfterRegion = "answer"
                enterRegionMode()
            }
            view.findViewById<View>(R.id.btn_area)?.setOnLongClickListener {
                showRegionQuickMenu(it)
                true
            }
            refreshRegionButtonState(view)
            view.findViewById<View>(R.id.btn_probe)?.setOnClickListener {
                probeFromSavedRegionForAnswer()
            }
            view.findViewById<View>(R.id.btn_search)?.setOnClickListener {
                resolveChannel()?.invokeMethod("manualSearch", mapOf("question" to overlayQuestion))
            }
            view.findViewById<View>(R.id.btn_close)?.setOnClickListener { hideAccessibilityOverlay() }
            view.findViewById<View>(R.id.btn_font)?.setOnClickListener { cycleFontScale(view) }
            view.findViewById<View>(R.id.btn_collapse)?.setOnClickListener { toggleCollapse(view) }
            view.findViewById<View>(R.id.btn_hide_overlay)?.setOnClickListener { toggleHiddenDot(view) }
            view.findViewById<View>(R.id.btn_expand)?.setOnClickListener { toggleCollapse(view) }
            view.findViewById<View>(R.id.btn_more)?.setOnClickListener { showMoreMenu(it, view) }
            view.findViewById<View>(R.id.tv_answer)?.setOnLongClickListener {
                copyAnswerToClipboard()
                true
            }
            view.findViewById<View>(R.id.tv_question)?.setOnLongClickListener {
                copyAnswerToClipboard()
                true
            }
            view.findViewById<View>(R.id.resize_handle)?.setOnTouchListener { _, event ->
                resizeHandleTouch(view, event)
            }
            // hidden_dot 的触摸监听必须在 overlayParams 已就绪后绑定，见 addView 成功分支。

            val (w, h) = loadOverlaySize()
            val (x, y) = loadOverlayPosition(w, h)
            overlayFontScaleIndex = loadFontScaleIndex()
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }
            // 注意：部分 ROM 上 TYPE_ACCESSIBILITY_OVERLAY 配合 FLAG_LAYOUT_IN_SCREEN
            // 对非全屏小窗会抛 BadTokenException，这里去掉该 flag 以提升兼容性。
            val params = WindowManager.LayoutParams(
                w,
                h,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                this.x = x
                this.y = y
            }

            applyFontScale(view, fontScale())
            view.findViewById<View>(R.id.answer_container)?.alpha = loadOverlayOpacity()
            applyThemeToView(view)
            applyAnswerOnlyVisibility(view)
            applyExamChrome(view)
            // 若服务重启时仍标记为考试模式，补一次紧凑几何 + 内容
            if (examMode && !overlayCollapsed) {
                val (examW, examH) = examOverlayDimensions()
                params.width = examW
                params.height = examH
                val dm = resources.displayMetrics
                params.x = (dm.widthPixels - examW - dm.widthPixels * 0.03f).toInt().coerceAtLeast(0)
                params.y = (dm.heightPixels * 0.08f).toInt()
                clampParamsToScreen(params)
            }
            // 考试态从首次创建起强制卡片几何，绝不复用普通态的持久化长条尺寸。

            attachDragHandler(view, params, wm)

            try {
                wm.addView(view, params)
                accessibilityOverlayView = view
                overlayParams = params
                attachHiddenDotHandler(view)
                if (overlayHiddenDot) {
                    applyHiddenDotUi(view, params, forceHidden = true)
                } else if (overlayCollapsed) {
                    applyCollapsedUi(view, params, forceCollapsed = true)
                }
                true
            } catch (e: Throwable) {
                Log.w(TAG, "add accessibility overlay failed: ${e.javaClass.simpleName}: ${e.message}", e)
                try {
                    params.flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        params.layoutInDisplayCutoutMode =
                            WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                    }
                    wm.addView(view, params)
                    accessibilityOverlayView = view
                    overlayParams = params
                    attachHiddenDotHandler(view)
                    if (overlayHiddenDot) {
                        applyHiddenDotUi(view, params, forceHidden = true)
                    } else if (overlayCollapsed) {
                        applyCollapsedUi(view, params, forceCollapsed = true)
                    }
                    Log.i(TAG, "accessibility overlay add succeeded on retry")
                    true
                } catch (e2: Throwable) {
                    Log.w(TAG, "add accessibility overlay retry failed: ${e2.javaClass.simpleName}: ${e2.message}", e2)
                    accessibilityOverlayView = null
                    overlayParams = null
                    false
                }
            }
        } catch (e: Throwable) {
            Log.e(TAG, "createAccessibilityOverlay fatal: ${e.javaClass.simpleName}: ${e.message}", e)
            accessibilityOverlayView = null
            overlayParams = null
            false
        }
    }

    // ---- 悬浮窗可调外观 ----

    private fun fontScale(): Float = FONT_SCALE_STEPS.getOrElse(overlayFontScaleIndex) { 1.0f }

    private fun applyFontScale(view: View, scale: Float) {
        val q = view.findViewById<TextView>(R.id.tv_question)
        val a = view.findViewById<TextView>(R.id.tv_answer)
        val baseQ = 14f
        // 答案通常含完整选项/解析；默认缩小一档，窄屏长答案更紧凑且减少遮挡。
        val baseA = 11f
        q?.textSize = baseQ * scale
        a?.textSize = baseA * scale
    }

    private fun cycleFontScale(view: View) {
        overlayFontScaleIndex = (overlayFontScaleIndex + 1) % FONT_SCALE_STEPS.size
        saveFontScaleIndex(overlayFontScaleIndex)
        applyFontScale(view, fontScale())
        val pct = (FONT_SCALE_STEPS[overlayFontScaleIndex] * 100).toInt()
        try {
            android.widget.Toast.makeText(this, "字号 ${pct}%", android.widget.Toast.LENGTH_SHORT).show()
        } catch (_: Throwable) {}
    }

    private fun showMoreMenu(anchor: View, root: View) {
        try {
            val popup = android.widget.PopupMenu(this, anchor)
            popup.menu.add(0, 1, 0, "字号")
            popup.menu.add(0, 2, 1, "识别区域")
            popup.menu.add(0, 3, 2, "复制答案")
            popup.menu.add(0, 4, 3, if (answerOnlyMode) "显示题目+答案" else "仅显示答案")
            popup.menu.add(0, 5, 4, if (examMode) "退出考试模式" else "考试模式")
            popup.menu.add(0, 6, 5, if (clickThroughWhenCollapsed) "折叠可点击" else "折叠穿透点击")
            popup.menu.add(0, 7, 6, "切换主题色")
            popup.menu.add(0, 9, 8, "重置悬浮窗大小")
            if (overlayAnswersList.size > 1 || overlayMatchCount > 1) {
                val total = maxOf(overlayAnswersList.size, overlayMatchCount)
                popup.menu.add(0, 8, 7, "下一条匹配 ${overlayMatchIndex + 1}/$total")
            }
            popup.setOnMenuItemClickListener { item ->
                when (item.itemId) {
                    1 -> { cycleFontScale(root); true }
                    2 -> { enterRegionMode(); true }
                    3 -> { copyAnswerToClipboard(); true }
                    4 -> { toggleAnswerOnly(root); true }
                    5 -> { setExamMode(!examMode); true }
                    6 -> {
                        clickThroughWhenCollapsed = !clickThroughWhenCollapsed
                        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                            .putBoolean(KEY_CLICK_THROUGH, clickThroughWhenCollapsed).apply()
                        applyClickThroughFlags()
                        toast(if (clickThroughWhenCollapsed) "折叠穿透：开" else "折叠穿透：关")
                        true
                    }
                    7 -> {
                        cycleThemeColor(root)
                        true
                    }
                    8 -> {
                        cycleMatchAnswer()
                        true
                    }
                    9 -> {
                        resetOverlayGeometry(root)
                        true
                    }
                    else -> false
                }
            }
            popup.show()
        } catch (e: Throwable) {
            Log.w(TAG, "showMoreMenu failed", e)
            cycleFontScale(root)
        }
    }

    private fun cycleMatchAnswer() {
        val list = overlayAnswersList
        if (list.size > 1) {
            overlayMatchIndex = (overlayMatchIndex + 1) % list.size
            overlayMatchCount = list.size
            overlayAnswers = list[overlayMatchIndex]
        } else if (overlayMatchCount > 1) {
            overlayMatchIndex = (overlayMatchIndex + 1) % overlayMatchCount
        } else {
            toast("仅一条匹配")
            return
        }
        updateAccessibilityOverlayView()
        toast("匹配 ${overlayMatchIndex + 1}/$overlayMatchCount")
        resolveChannel()?.invokeMethod(
            "cycleMatch",
            mapOf("index" to overlayMatchIndex, "count" to overlayMatchCount)
        )
    }

    /** 一键恢复正常大窗尺寸，并退出折叠/考试小窗污染。 */
    private fun resetOverlayGeometry(root: View) {
        if (examMode) {
            // 先退出考试模式（会恢复备份）；再强制默认大窗
            setExamMode(false)
        }
        val (dw, dh) = defaultOverlaySize()
        val (dx, dy) = loadOverlayPosition()
        saveOverlaySize(dw, dh)
        saveOverlayPosition(dx, dy)
        overlayExpandedWidth = dw
        overlayExpandedHeight = dh
        overlayCollapsed = false
        overlayHiddenDot = false
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_COLLAPSED, false)
            .putBoolean(KEY_HIDDEN_DOT, false)
            .remove(KEY_PRE_EXAM_GEOMETRY)
            .apply()
        preExamGeometry = null
        val params = overlayParams
        val wm = windowManager
        if (params != null && wm != null) {
            params.width = dw
            params.height = dh
            params.x = dx
            params.y = dy
            clampParamsToScreen(params)
            // 恢复展开态 UI
            root.findViewById<View>(R.id.answer_container)?.visibility = View.VISIBLE
            root.findViewById<View>(R.id.collapsed_pill)?.visibility = View.GONE
            root.findViewById<View>(R.id.resize_handle)?.visibility = View.VISIBLE
            applyAnswerOnlyVisibility(root)
            try { wm.updateViewLayout(root, params) } catch (_: Throwable) {}
        }
        toast("已重置为正常大窗")
    }

    private fun toast(msg: String) {
        try {
            android.widget.Toast.makeText(this, msg, android.widget.Toast.LENGTH_SHORT).show()
        } catch (_: Throwable) {}
    }

    private fun cycleThemeColor(root: View) {
        val idx = THEME_COLORS.indexOf(themeColor).let { if (it < 0) 0 else (it + 1) % THEME_COLORS.size }
        themeColor = THEME_COLORS[idx]
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putInt(KEY_THEME_COLOR, themeColor).apply()
        applyThemeToView(root)
        toast("主题色 ${idx + 1}/${THEME_COLORS.size}")
    }

    private fun applyThemeToView(view: View) {
        view.findViewById<View>(R.id.title_bar)?.setBackgroundColor(themeColor)
        view.findViewById<View>(R.id.collapsed_pill)?.setBackgroundColor(themeColor)
        // status 待命色也用主题色
        if (overlayStatus == "idle") {
            view.findViewById<View>(R.id.status_bar)?.setBackgroundColor(themeColor)
        }
    }

    private fun setExamMode(enabled: Boolean) {
        val view = accessibilityOverlayView
        val params = overlayParams
        val wm = windowManager
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (enabled && !examMode) {
            // 备份进入前的几何 + 仅答案偏好（持久化，避免内存丢失后无法恢复）
            val backupGeo = if (params != null) {
                val w = if (params.width > 0) params.width else {
                    view?.width?.takeIf { it > 0 } ?: defaultOverlaySize().first
                }
                val h = if (params.height > 0) params.height else {
                    view?.height?.takeIf { it > 0 } ?: defaultOverlaySize().second
                }
                "${params.x},${params.y},$w,$h"
            } else {
                val (w, h) = loadOverlaySize()
                val (x, y) = loadOverlayPosition()
                "$x,$y,$w,$h"
            }
            preExamGeometry = backupGeo
            prefs.edit()
                .putString(KEY_PRE_EXAM_GEOMETRY, backupGeo)
                .putBoolean(KEY_ANSWER_ONLY_BEFORE_EXAM, answerOnlyMode)
                .apply()

            examMode = true
            answerOnlyMode = true // 考试模式强制仅答案（不覆盖用户 KEY_ANSWER_ONLY）
            if (view != null) {
                applyAnswerOnlyVisibility(view) // 含 applyExamChrome
                applyExamChrome(view)
            }
            if (params != null && wm != null && view != null) {
                applyExamOverlayDimensions(params, view, updatePosition = true)
                view.findViewById<View>(R.id.answer_container)?.alpha =
                    loadOverlayOpacity().coerceAtMost(0.96f)
            }
            updateAccessibilityOverlayView()
            toast("考试模式")
        } else if (!enabled && examMode) {
            examMode = false
            // 恢复进入考试前的「仅答案」偏好
            answerOnlyMode = prefs.getBoolean(
                KEY_ANSWER_ONLY_BEFORE_EXAM,
                prefs.getBoolean(KEY_ANSWER_ONLY, false)
            )
            if (view != null) {
                applyAnswerOnlyVisibility(view)
                applyExamChrome(view)
                view.findViewById<View>(R.id.answer_container)?.alpha = loadOverlayOpacity()
            }
            // 恢复几何：无论 answerOverlay 当前是否为 null，都先算好尺寸写回持久化，
            // 避免「关闭 APP 重建后」窗为 null 导致恢复被跳过、下次重建仍用小窗。
            val geo = preExamGeometry ?: prefs.getString(KEY_PRE_EXAM_GEOMETRY, null)
            val (size, pos) = if (geo != null) {
                val p = geo.split(',').mapNotNull { it.toIntOrNull() }
                if (p.size >= 4 && p[2] > 0 && p[3] > 0) {
                    val dm = resources.displayMetrics
                    val w = p[2].coerceIn((OVERLAY_MIN_WIDTH_DP * dm.density).toInt(), dm.widthPixels)
                    val h = p[3].coerceIn((OVERLAY_MIN_HEIGHT_DP * dm.density).toInt(), dm.heightPixels)
                    val x = p[0].coerceAtLeast(0)
                    val y = p[1].coerceAtLeast(0)
                    Pair(w to h, x to y)
                } else {
                    val d = defaultOverlaySize(); val pp = loadOverlayPosition()
                    Pair(d.first to d.second, pp.first to pp.second)
                }
            } else {
                val d = defaultOverlaySize(); val pp = loadOverlayPosition()
                Pair(d.first to d.second, pp.first to pp.second)
            }
            val restoredW = size.first
            val restoredH = size.second
            var rx = pos.first
            var ry = pos.second
            // 旋转/分屏后旧坐标可能已不适配新尺寸；按恢复后的宽高统一 clamp，
            // 即使当前 overlay 已被销毁，写回 prefs 的正常窗也不会跑出屏幕。
            val dm = resources.displayMetrics
            rx = rx.coerceIn(0, (dm.widthPixels - restoredW).coerceAtLeast(0))
            ry = ry.coerceIn(0, (dm.heightPixels - restoredH).coerceAtLeast(0))
            // 写回持久化（下次重建或当前窗都按此尺寸）
            saveOverlaySize(restoredW, restoredH)
            saveOverlayPosition(rx, ry)
            overlayExpandedWidth = restoredW
            overlayExpandedHeight = restoredH
            // 若当前窗与 params 仍在，立即应用
            if (view != null && overlayParams != null && wm != null) {
                // 无论折叠态与否，先恢复正常尺寸
                overlayParams!!.width = restoredW
                overlayParams!!.height = restoredH
                overlayParams!!.x = rx
                overlayParams!!.y = ry
                if (overlayCollapsed) {
                    applyCollapsedUi(view, overlayParams!!, forceCollapsed = false)
                } else {
                    clampParamsToScreen(overlayParams!!)
                    try { wm.updateViewLayout(view, overlayParams) } catch (_: Throwable) {}
                }
            }
            preExamGeometry = null
            prefs.edit().remove(KEY_PRE_EXAM_GEOMETRY).apply()
            // 退出考试后刷新 UI：重新按正常模式格式化题目/答案/标题。
            updateAccessibilityOverlayView()
            toast("已退出考试模式")
        }
        prefs.edit()
            .putBoolean(KEY_EXAM_MODE, examMode)
            .putBoolean(
                KEY_ANSWER_ONLY,
                if (examMode) {
                    prefs.getBoolean(KEY_ANSWER_ONLY_BEFORE_EXAM, false)
                } else {
                    answerOnlyMode
                }
            )
            .apply()
        if (view != null) applyAnswerOnlyVisibility(view)
    }

    /** 把 "x,y,w,h" 写回 params；成功返回 true。 */
    private fun restoreGeometryToParams(
        params: WindowManager.LayoutParams,
        geo: String?,
    ): Boolean {
        if (geo.isNullOrBlank()) return false
        val p = geo.split(',').mapNotNull { it.toIntOrNull() }
        if (p.size < 4) return false
        var w = p[2]
        var h = p[3]
        if (w <= 0 || h <= 0) {
            val d = defaultOverlaySize()
            w = d.first
            h = d.second
        }
        val dm = resources.displayMetrics
        w = w.coerceIn((OVERLAY_MIN_WIDTH_DP * dm.density).toInt(), dm.widthPixels)
        h = h.coerceIn((OVERLAY_MIN_HEIGHT_DP * dm.density).toInt(), dm.heightPixels)
        params.x = p[0]
        params.y = p[1]
        params.width = w
        params.height = h
        clampParamsToScreen(params)
        return true
    }

    private fun applyAnswerOnlyVisibility(view: View) {
        val scrollQ = view.findViewById<View>(R.id.scroll_question)
        val divider = view.findViewById<View>(R.id.answer_divider)
        // 中间摘要条已移除；相似度只在标题，答案只在正文。
        if (answerOnlyMode || examMode) {
            scrollQ?.visibility = View.GONE
            divider?.visibility = View.GONE
        } else {
            scrollQ?.visibility = View.VISIBLE
            divider?.visibility = View.VISIBLE
        }
        applyExamChrome(view)
    }

    /**
     * 考试模式 chrome：只留标题（答案+相似度）+ 关闭；
     * 隐藏试捕/搜索/更多/折叠/字号/调节柄等，界面更干净。
     */
    private fun applyExamChrome(view: View) {
        val exam = examMode
        val hideIds = intArrayOf(
            R.id.btn_probe,
            R.id.btn_search,
            R.id.btn_more,
            R.id.btn_collapse,
            R.id.btn_font,
            R.id.resize_handle,
        )
        for (id in hideIds) {
            view.findViewById<View>(id)?.visibility =
                if (exam) View.GONE else View.VISIBLE
        }
        // 关闭按钮考试态仍保留，方便关掉悬浮窗
        view.findViewById<View>(R.id.btn_close)?.visibility = View.VISIBLE
        // 考试态答案区保持紧凑内容高度；避免 weight=1 把卡片拉成空白长条。
        val scrollA = view.findViewById<View>(R.id.scroll_answer)
        if (scrollA != null) {
            val lp = scrollA.layoutParams
            if (lp is android.widget.LinearLayout.LayoutParams) {
                lp.height = if (exam) android.widget.LinearLayout.LayoutParams.WRAP_CONTENT else 0
                lp.weight = if (exam) 0f else 1f
                scrollA.layoutParams = lp
            }
        }
        // 标题栏统一 36dp（与布局一致）
        view.findViewById<View>(R.id.title_bar)?.let { bar ->
            val h = 36 * resources.displayMetrics.density
            bar.layoutParams = bar.layoutParams.apply { height = h.toInt() }
        }
    }

    private var answerOnlyMode = false

    private fun toggleAnswerOnly(view: View) {
        answerOnlyMode = !answerOnlyMode
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_ANSWER_ONLY, answerOnlyMode).apply()
        applyAnswerOnlyVisibility(view)
        toast(if (answerOnlyMode) "仅显示答案" else "显示题目+答案")
    }

    private fun applyClickThroughFlags() {
        val params = overlayParams ?: return
        val view = accessibilityOverlayView ?: return
        val wm = windowManager ?: return
        // 折叠 + 开启穿透：不接收触摸，纯展示
        if (overlayCollapsed && clickThroughWhenCollapsed) {
            params.flags = params.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        } else {
            params.flags = params.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
            params.flags = params.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
        }
        try { wm.updateViewLayout(view, params) } catch (_: Throwable) {}
    }

    private fun copyAnswerToClipboard() {
        val text = listOf(overlayQuestion, overlayAnswers)
            .filter { it.isNotBlank() }
            .joinToString("\n\n")
            .ifBlank { return }
        try {
            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
            cm.setPrimaryClip(android.content.ClipData.newPlainText("quiz", text))
            toast("已复制")
        } catch (_: Throwable) {}
    }

    private fun toggleCollapse(view: View) {
        applyCollapsedUi(view, overlayParams ?: return, forceCollapsed = !overlayCollapsed)
    }

    /** 眼睛按钮：完整悬浮窗隐藏为可拖动的极小半透明圆点，再点圆点恢复。 */
    private fun toggleHiddenDot(view: View) {
        applyHiddenDotUi(view, overlayParams ?: return, forceHidden = !overlayHiddenDot)
    }

    private fun applyHiddenDotUi(
        view: View,
        params: WindowManager.LayoutParams,
        forceHidden: Boolean,
    ) {
        val wm = windowManager ?: return
        val dot = view.findViewById<View>(R.id.hidden_dot) ?: return
        val container = view.findViewById<View>(R.id.answer_container)
        val pill = view.findViewById<View>(R.id.collapsed_pill)
        val resize = view.findViewById<View>(R.id.resize_handle)
        overlayHiddenDot = forceHidden
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_HIDDEN_DOT, overlayHiddenDot)
            .apply()
        if (overlayHiddenDot) {
            if (params.width > 0) overlayExpandedWidth = params.width
            if (params.height > 0) overlayExpandedHeight = params.height
            overlayCollapsed = false
            container?.visibility = View.GONE
            pill?.visibility = View.GONE
            resize?.visibility = View.GONE
            dot.visibility = View.VISIBLE
            val d = (32f * resources.displayMetrics.density).toInt()
            params.width = d
            params.height = d
            clampParamsToScreen(params)
        } else {
            params.width = if (overlayExpandedWidth > 0) overlayExpandedWidth else defaultOverlaySize().first
            params.height = if (overlayExpandedHeight > 0) overlayExpandedHeight else defaultOverlaySize().second
            container?.visibility = View.VISIBLE
            pill?.visibility = View.GONE
            resize?.visibility = if (examMode) View.GONE else View.VISIBLE
            dot.visibility = View.GONE
            clampParamsToScreen(params)
            applyAnswerOnlyVisibility(view)
            applyExamChrome(view)
        }
        try { wm.updateViewLayout(view, params) } catch (_: Throwable) {}
        applyClickThroughFlags()
    }

    /** 圆点松手后仅补一次捕获，避免拖动期间与驾考宝典节点扫描竞争主线程。 */
    private fun scheduleCaptureAfterHiddenDotDrag() {
        deferredCaptureAfterDotDrag?.let { mainHandler.removeCallbacks(it) }
        val task = Runnable {
            deferredCaptureAfterDotDrag = null
            if (!hiddenDotDragging && isActive) {
                extractAndSend(resolveProbeRoot())
            }
        }
        deferredCaptureAfterDotDrag = task
        mainHandler.postDelayed(task, 180L)
    }

    /** 隐身圆点点击恢复，超过触控阈值则作为拖动并记住位置。 */
    private fun attachHiddenDotHandler(root: View) {
        val dot = root.findViewById<View>(R.id.hidden_dot) ?: return
        val params = overlayParams ?: return
        val wm = windowManager ?: return
        val slop = ViewConfiguration.get(this).scaledTouchSlop
        var startX = 0
        var startY = 0
        var touchX = 0f
        var touchY = 0f
        var dragging = false
        var frameScheduled = false
        var pendingLayout = false
        var lastAppliedX = Int.MIN_VALUE
        var lastAppliedY = Int.MIN_VALUE
        val frameCallback = android.view.Choreographer.FrameCallback {
            frameScheduled = false
            if (!pendingLayout) return@FrameCallback
            pendingLayout = false
            if (params.x == lastAppliedX && params.y == lastAppliedY) return@FrameCallback
            try {
                wm.updateViewLayout(root, params)
                lastAppliedX = params.x
                lastAppliedY = params.y
            } catch (_: Throwable) {}
        }
        fun scheduleLayout() {
            pendingLayout = true
            if (!frameScheduled) {
                frameScheduled = true
                android.view.Choreographer.getInstance().postFrameCallback(frameCallback)
            }
        }
        fun flushLayout() {
            if (frameScheduled) {
                android.view.Choreographer.getInstance().removeFrameCallback(frameCallback)
                frameScheduled = false
            }
            pendingLayout = false
            try {
                wm.updateViewLayout(root, params)
                lastAppliedX = params.x
                lastAppliedY = params.y
            } catch (_: Throwable) {}
        }
        dot.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = params.x
                    startY = params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    dragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - touchX
                    val dy = event.rawY - touchY
                    if (!dragging && hypot(dx.toDouble(), dy.toDouble()) > slop) {
                        dragging = true
                        hiddenDotDragging = true
                        deferredCaptureAfterDotDrag?.let { mainHandler.removeCallbacks(it) }
                    }
                    if (dragging) {
                        params.x = startX + dx.toInt()
                        params.y = startY + dy.toInt()
                        clampParamsToScreen(params)
                        scheduleLayout()
                    }
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (dragging) {
                        flushLayout()
                        saveOverlayPosition(params.x, params.y)
                        hiddenDotDragging = false
                        scheduleCaptureAfterHiddenDotDrag()
                    } else if (event.actionMasked == MotionEvent.ACTION_UP) {
                        toggleHiddenDot(root)
                    }
                    dragging = false
                    true
                }
                else -> false
            }
        }
    }

    private fun applyCollapsedUi(
        view: View,
        params: WindowManager.LayoutParams,
        forceCollapsed: Boolean,
    ) {
        val wm = windowManager ?: return
        overlayCollapsed = forceCollapsed
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_COLLAPSED, overlayCollapsed).apply()
        val resizeHandle = view.findViewById<View>(R.id.resize_handle)
        val pill = view.findViewById<View>(R.id.collapsed_pill)
        val container = view.findViewById<View>(R.id.answer_container)
        val collapseBtn = view.findViewById<ImageButton>(R.id.btn_collapse)
        if (overlayCollapsed) {
            if (params.height > 0) overlayExpandedHeight = params.height
            if (params.width > 0) overlayExpandedWidth = params.width
            resizeHandle?.visibility = View.GONE
            collapseBtn?.setImageResource(R.drawable.ic_chevron_down)
            // 折叠小窗：仍显示答案区（含相似度），只收起题目（answerOnly 时题目本就 GONE）
            // 不隐藏 answer_container，避免小窗下看不到答案/相似度
            pill?.visibility = View.GONE
            params.width = WindowManager.LayoutParams.WRAP_CONTENT
            params.height = WindowManager.LayoutParams.WRAP_CONTENT
        } else {
            params.width = if (overlayExpandedWidth > 0) overlayExpandedWidth else defaultOverlaySize().first
            params.height = if (overlayExpandedHeight > 0) overlayExpandedHeight else defaultOverlaySize().second
            resizeHandle?.visibility = View.VISIBLE
            collapseBtn?.setImageResource(R.drawable.ic_chevron_up)
            container?.visibility = View.VISIBLE
            pill?.visibility = View.GONE
            clampParamsToScreen(params)
        }
        try { wm.updateViewLayout(view, params) } catch (_: Throwable) {}
        applyClickThroughFlags()
    }

    private var overlayExpandedWidth = 0

    private fun resizeHandleTouch(view: View, event: MotionEvent): Boolean {
        val wm = windowManager ?: return false
        val params = overlayParams ?: return false
        val dm = resources.displayMetrics
        val minW = (OVERLAY_MIN_WIDTH_DP * dm.density).toInt()
        val minH = (OVERLAY_MIN_HEIGHT_DP * dm.density).toInt()
        val maxW = dm.widthPixels
        val maxH = (dm.heightPixels * 0.9f).toInt()
        return when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                resizeStartW = params.width
                resizeStartH = params.height
                resizeStartX = event.rawX
                resizeStartY = event.rawY
                true
            }
            MotionEvent.ACTION_MOVE -> {
                val nw = (resizeStartW + (event.rawX - resizeStartX)).toInt().coerceIn(minW, maxW)
                val nh = (resizeStartH + (event.rawY - resizeStartY)).toInt().coerceIn(minH, maxH)
                params.width = nw
                params.height = nh
                overlayExpandedHeight = nh
                overlayExpandedWidth = nw
                clampParamsToScreen(params)
                try { wm.updateViewLayout(view, params) } catch (_: Throwable) {}
                true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                // 考试模式拖拽不写坏「正常大窗」持久化；退出考试时用 preExamGeometry 恢复
                if (!examMode) {
                    saveOverlaySize(params.width, params.height)
                    saveOverlayPosition(params.x, params.y)
                }
                false
            }
            else -> false
        }
    }

    private var resizeStartW = 0
    private var resizeStartH = 0
    private var resizeStartX = 0f
    private var resizeStartY = 0f

    private fun clampParamsToScreen(params: WindowManager.LayoutParams) {
        val dm = resources.displayMetrics
        val w = if (params.width > 0) params.width else (dm.widthPixels * 0.5f).toInt()
        val h = if (params.height > 0) params.height else (dm.heightPixels * 0.35f).toInt()
        params.x = params.x.coerceIn(0, (dm.widthPixels - w).coerceAtLeast(0))
        params.y = params.y.coerceIn(0, (dm.heightPixels - h).coerceAtLeast(0))
    }

    private fun snapToEdge(params: WindowManager.LayoutParams, view: View? = accessibilityOverlayView) {
        val dm = resources.displayMetrics
        val density = dm.density
        val threshold = (24 * density).toInt()
        val w = if (params.width > 0) params.width else (dm.widthPixels * 0.5f).toInt()
        val centerX = params.x + w / 2
        val targetX = if (centerX < dm.widthPixels / 2) {
            if (params.x < threshold) 0 else params.x
        } else {
            val right = dm.widthPixels - w
            if (params.x > right - threshold) right.coerceAtLeast(0) else params.x
        }
        val startX = params.x
        if (targetX == startX || view == null) {
            params.x = targetX
            clampParamsToScreen(params)
            return
        }
        // 90ms 快速吸边，避免松手后动画拖尾造成“卡一下”的错觉。
        val anim = android.animation.ValueAnimator.ofInt(startX, targetX)
        anim.duration = 90
        anim.interpolator = android.view.animation.DecelerateInterpolator()
        anim.addUpdateListener { a ->
            params.x = a.animatedValue as Int
            clampParamsToScreen(params)
            try { windowManager?.updateViewLayout(view, params) } catch (_: Throwable) {}
        }
        anim.start()
    }

    /**
     * 仅标题栏/折叠 pill 可拖动；正文留给滚动。
     * 增量坐标 + 边界 clamp + 松手贴边 + 拖动半透明 + 双击折叠。
     */
    private fun attachDragHandler(view: View, params: WindowManager.LayoutParams, wm: WindowManager) {
        val slop = ViewConfiguration.get(this).scaledTouchSlop
        val titleBar = view.findViewById<View>(R.id.title_bar)
        val pill = view.findViewById<View>(R.id.collapsed_pill)
        val dragTargets = listOfNotNull(titleBar, pill)
        if (dragTargets.isEmpty()) {
            // minimal view fallback
            attachDragToTarget(view, view, params, wm, slop)
            return
        }
        for (target in dragTargets) {
            attachDragToTarget(view, target, params, wm, slop)
        }
        // pill 整卡点击展开（未拖动时）
        pill?.setOnClickListener {
            if (!overlayCollapsed) return@setOnClickListener
            toggleCollapse(view)
        }
    }

    private fun attachDragToTarget(
        root: View,
        target: View,
        params: WindowManager.LayoutParams,
        wm: WindowManager,
        slop: Int,
    ) {
        var initialX = 0
        var initialY = 0
        var touchX = 0f
        var touchY = 0f
        var dragging = false
        var downTime = 0L
        var lastTapTime = 0L
        var frameScheduled = false
        var pendingLayout = false
        var lastAppliedX = Int.MIN_VALUE
        var lastAppliedY = Int.MIN_VALUE
        val frameCallback = android.view.Choreographer.FrameCallback {
            frameScheduled = false
            if (!pendingLayout) return@FrameCallback
            pendingLayout = false
            // 同一显示帧内合并多个 MOVE，并跳过坐标未变的提交，避免系统浮层拖动卡顿。
            if (params.x == lastAppliedX && params.y == lastAppliedY) return@FrameCallback
            try {
                wm.updateViewLayout(root, params)
                lastAppliedX = params.x
                lastAppliedY = params.y
            } catch (_: Throwable) {}
        }
        val scheduleLayout = {
            pendingLayout = true
            if (!frameScheduled) {
                frameScheduled = true
                android.view.Choreographer.getInstance().postFrameCallback(frameCallback)
            }
        }
        val flushLayout = {
            if (frameScheduled) {
                android.view.Choreographer.getInstance().removeFrameCallback(frameCallback)
                frameScheduled = false
            }
            pendingLayout = false
            try {
                wm.updateViewLayout(root, params)
                lastAppliedX = params.x
                lastAppliedY = params.y
            } catch (_: Throwable) {}
        }
        val baseAlpha = { loadOverlayOpacity() }

        target.setOnTouchListener { v, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    if (event.getPointerId(event.actionIndex) != 0 && event.pointerCount > 1) {
                        return@setOnTouchListener false
                    }
                    initialX = params.x
                    initialY = params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    dragging = false
                    downTime = System.currentTimeMillis()
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    if (event.actionIndex != 0) return@setOnTouchListener dragging
                    val dx = event.rawX - touchX
                    val dy = event.rawY - touchY
                    if (!dragging && hypot(dx.toDouble(), dy.toDouble()) > slop) {
                        dragging = true
                        // 拖动中半透明
                        root.findViewById<View>(R.id.answer_container)?.alpha = 0.55f
                        root.findViewById<View>(R.id.collapsed_pill)?.alpha = 0.55f
                    }
                    if (dragging) {
                        params.x = initialX + dx.toInt()
                        params.y = initialY + dy.toInt()
                        clampParamsToScreen(params)
                        // Choreographer 合帧：MOVE 再密集也一帧最多 updateViewLayout 一次。
                        scheduleLayout()
                    }
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    val wasDragging = dragging
                    root.findViewById<View>(R.id.answer_container)?.alpha = baseAlpha()
                    root.findViewById<View>(R.id.collapsed_pill)?.alpha = 1f
                    if (wasDragging) {
                        // 将最后一个尚未到帧回调的位置立即落盘，避免松手少移动一截。
                        flushLayout()
                        snapToEdge(params, root)
                        // 考试模式只挪位置也不污染「正常态」持久化（备份在 preExamGeometry）
                        if (!examMode) {
                            saveOverlayPosition(params.x, params.y)
                        }
                    } else {
                        val now = System.currentTimeMillis()
                        // 双击标题栏折叠/展开
                        if (v.id == R.id.title_bar && now - lastTapTime < 280) {
                            toggleCollapse(root)
                            lastTapTime = 0L
                        } else if (v.id == R.id.collapsed_pill && !wasDragging) {
                            // 单击 pill 展开
                            if (overlayCollapsed) toggleCollapse(root)
                            lastTapTime = now
                        } else {
                            lastTapTime = now
                            // 让子按钮还能收到点击：未拖动时不拦截 UP 给 click
                            if (v.id == R.id.title_bar) {
                                // 标题栏空白区单击：不做事；子 ImageButton 有自己的 listener
                            }
                        }
                    }
                    dragging = false
                    // 若点在按钮上，需要返回 false 让 click 生效——但我们在 DOWN 返回了 true。
                    // 按钮有独立 click，title_bar 的 touch 不会抢按钮（子 View 优先）。
                    wasDragging
                }
                else -> false
            }
        }
    }

    // ---- 识别区域调节（服务自建全屏无障碍浮层）----

    /** 标题栏区域按钮：已保存区域时不透明，未设置时半透明提示。 */
    private fun refreshRegionButtonState(root: View? = accessibilityOverlayView) {
        val btn = root?.findViewById<View>(R.id.btn_area) ?: return
        val has = loadSavedRegionOnly() != null || screenRegion != null
        btn.alpha = if (has) 0.95f else 0.62f
    }

    /** 长按区域按钮：快捷预设，不进全屏框选。 */
    private fun showRegionQuickMenu(anchor: View) {
        try {
            val popup = android.widget.PopupMenu(this, anchor)
            popup.menu.add(0, 1, 0, "题干带")
            popup.menu.add(0, 2, 1, "中部")
            popup.menu.add(0, 3, 2, "全屏")
            popup.menu.add(0, 4, 3, "恢复上次")
            popup.menu.add(0, 5, 4, "打开框选…")
            popup.setOnMenuItemClickListener { item ->
                when (item.itemId) {
                    1 -> {
                        applyRegionPresetToSaved(0.02f, 0.04f, 0.98f, 0.55f, "题干带")
                        true
                    }
                    2 -> {
                        applyRegionPresetToSaved(0.04f, 0.28f, 0.96f, 0.72f, "中部")
                        true
                    }
                    3 -> {
                        // 长按菜单「全屏」：直接存近似整屏像素区（状态栏下到导航栏上）。
                        val dm = resources.displayMetrics
                        val sbId = resources.getIdentifier("status_bar_height", "dimen", "android")
                        val sb = if (sbId > 0) resources.getDimensionPixelSize(sbId).toFloat() else 0f
                        val nbId = resources.getIdentifier("navigation_bar_height", "dimen", "android")
                        val nb = if (nbId > 0) resources.getDimensionPixelSize(nbId).toFloat() else 0f
                        val w = dm.widthPixels.toFloat()
                        val h = dm.heightPixels.toFloat()
                        val full = RectF(0f, sb, w, (h - nb).coerceAtLeast(sb + 80f))
                        saveRegion(full)
                        screenRegion = full
                        toast("已设为全屏区域")
                        refreshRegionButtonState()
                        true
                    }
                    4 -> {
                        val last = loadSavedRegionOnly()
                        if (last != null) {
                            saveRegion(last)
                            screenRegion = last
                            toast("已恢复上次区域")
                            refreshRegionButtonState()
                        } else {
                            toast("尚无已保存区域")
                        }
                        true
                    }
                    5 -> {
                        pendingProbeAfterRegion = "answer"
                        enterRegionMode()
                        true
                    }
                    else -> false
                }
            }
            popup.show()
        } catch (e: Throwable) {
            Log.w(TAG, "showRegionQuickMenu failed", e)
            pendingProbeAfterRegion = "answer"
            enterRegionMode()
        }
    }

    private fun applyRegionPresetToSaved(
        left: Float,
        top: Float,
        right: Float,
        bottom: Float,
        label: String,
    ) {
        val dm = resources.displayMetrics
        val w = dm.widthPixels.toFloat()
        val h = dm.heightPixels.toFloat()
        val region = android.graphics.RectF(left * w, top * h, right * w, bottom * h)
        saveRegion(region)
        screenRegion = region
        toast("已设为$label")
        refreshRegionButtonState()
    }

    private var regionWindowView: View? = null
    private var regionWindowParams: WindowManager.LayoutParams? = null

    private fun enterRegionMode() {
        if (regionWindowView != null) return
        val wm = windowManager ?: return

        // Phase 1 — 先准备好 view + params（此时答案窗还在，不丢失 UI）
        val view = try {
            inflateOverlayView()
        } catch (e: Throwable) {
            Log.w(TAG, "enterRegionMode inflate failed", e)
            toast("区域选择器创建失败：${e.javaClass.simpleName}: ${e.message}")
            QuizOcrEntryOverlay.restoreAfterRegionIfNeeded()
            if (!QuizOcrEntryOverlay.isShowing() && isPluginEnabledInConfig()) {
                showOrUpdateAccessibilityOverlay("", "")
            }
            return
        }
        view.findViewById<View>(R.id.answer_container)?.visibility = View.GONE
        view.findViewById<View>(R.id.collapsed_pill)?.visibility = View.GONE
        view.findViewById<View>(R.id.resize_handle)?.visibility = View.GONE

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        // 移除 FLAG_LAYOUT_IN_SCREEN：部分 ROM 上 TYPE_ACCESSIBILITY_OVERLAY + 该 flag 会抛 BadTokenException
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }

        val selector = view.findViewById<View>(R.id.region_selector) as? RegionSelectorView
        val toolbar = view.findViewById<View>(R.id.region_toolbar)
        selector?.visibility = View.VISIBLE
        toolbar?.visibility = View.VISIBLE
        view.findViewById<View>(R.id.region_probe_panel)?.visibility = View.GONE

        // 工具栏贴底：按实测高度预留安全区，禁止写死 120/200dp（会把全屏夹到约 2/3）。
        val dens = resources.displayMetrics.density
        fun applyToolbarSafeInsets(selectorView: RegionSelectorView?, toolbarView: View?) {
            val sbIdLocal = resources.getIdentifier("status_bar_height", "dimen", "android")
            val sbLocal =
                if (sbIdLocal > 0) resources.getDimensionPixelSize(sbIdLocal).toFloat() else 0f
            val nbIdLocal = resources.getIdentifier("navigation_bar_height", "dimen", "android")
            val nbLocal =
                if (nbIdLocal > 0) resources.getDimensionPixelSize(nbIdLocal).toFloat() else 0f
            val measured = toolbarView?.height?.toFloat() ?: 0f
            // 未 layout 时用主操作行估算（约 88dp）；展开更多后再 post 实测。
            val fallback = 88f * dens
            val toolbarH = if (measured > 0f) measured else fallback
            // 仅预留工具栏本身 + 8dp 手柄余量，不再额外灌水。
            val bottom = max(toolbarH + 8f * dens, nbLocal)
            selectorView?.setSafeInsets(
                left = 0f,
                top = sbLocal,
                right = 0f,
                bottom = bottom,
            )
        }
        applyToolbarSafeInsets(selector, toolbar)
        toolbar?.post { applyToolbarSafeInsets(selector, toolbar) }

        // 优先当前前台 App 专属区域，否则全局/默认上 55%
        val pkg = lastForegroundPkg.ifBlank { null }
        val initial = (pkg?.let { loadRegionForPackage(it) }) ?: loadRegion()
        if (initial != null) {
            selector?.setRegion(initial)
        } else {
            selector?.applyPreset(0.02f, 0.04f, 0.98f, 0.55f)
        }
        selector?.setOnRegionChangedListener { rectF ->
            resolveChannel()?.invokeMethod(
                "onRegionPreview",
                mapOf(
                    "left" to rectF.left.toDouble(),
                    "top" to rectF.top.toDouble(),
                    "right" to rectF.right.toDouble(),
                    "bottom" to rectF.bottom.toDouble(),
                ),
            )
        }
        view.findViewById<View>(R.id.btn_region_cancel)?.setOnClickListener {
            pendingProbeAfterRegion = null
            exitRegionMode()
        }
        view.findViewById<View>(R.id.btn_region_save)?.setOnClickListener {
            saveRegionFromSelector(selector, showToast = true)
            // 录入窗在场（含 minimize）时默认录入试捕；否则答题搜题
            val pending = pendingProbeAfterRegion
                ?: if (QuizOcrEntryOverlay.isShowing() || QuizOcrEntryOverlay.isMinimizedForRegion()) "entry" else "answer"
            pendingProbeAfterRegion = null
            exitRegionMode()
            mainHandler.postDelayed({
                when (pending) {
                    "entry" -> probeNodesFromSavedRegion()
                    else -> probeFromSavedRegionForAnswer()
                }
            }, 200L)
        }
        selector?.setOnRegionConfirmedListener {
            saveRegionFromSelector(selector, showToast = true)
            val pending = pendingProbeAfterRegion
                ?: if (QuizOcrEntryOverlay.isShowing() || QuizOcrEntryOverlay.isMinimizedForRegion()) "entry" else "answer"
            pendingProbeAfterRegion = null
            exitRegionMode()
            mainHandler.postDelayed({
                when (pending) {
                    "entry" -> probeNodesFromSavedRegion()
                    else -> probeFromSavedRegionForAnswer()
                }
            }, 200L)
        }
        val morePanel = view.findViewById<View>(R.id.region_more_panel)
        morePanel?.visibility = View.GONE
        view.findViewById<View>(R.id.btn_region_more)?.setOnClickListener {
            val open = morePanel?.visibility != View.VISIBLE
            morePanel?.visibility = if (open) View.VISIBLE else View.GONE
            (it as? android.widget.Button)?.text = if (open) "收起" else "更多"
            // 展开/收起后按实测高度更新底部 inset，禁止写死 200dp。
            toolbar?.post { applyToolbarSafeInsets(selector, toolbar) }
        }
        view.findViewById<View>(R.id.btn_preset_top)?.setOnClickListener {
            selector?.applyPreset(0.02f, 0.04f, 0.98f, 0.55f)
        }
        view.findViewById<View>(R.id.btn_preset_mid)?.setOnClickListener {
            selector?.applyPreset(0.04f, 0.28f, 0.96f, 0.72f)
        }
        view.findViewById<View>(R.id.btn_preset_full)?.setOnClickListener {
            // 点「全屏」：先收起更多面板，按实测工具栏高度铺满可用区。
            morePanel?.visibility = View.GONE
            (view.findViewById<View>(R.id.btn_region_more) as? android.widget.Button)?.text = "更多"
            toolbar?.post {
                applyToolbarSafeInsets(selector, toolbar)
                selector?.applyMaxRegion()
                toast("已设为全屏区域")
            } ?: run {
                applyToolbarSafeInsets(selector, toolbar)
                selector?.applyMaxRegion()
                toast("已设为全屏区域")
            }
        }
        view.findViewById<View>(R.id.btn_preset_last)?.setOnClickListener {
            val last = loadSavedRegionOnly()
            if (last != null) {
                selector?.setRegion(last)
                toast("已恢复上次区域")
            } else {
                toast("尚无已保存区域")
            }
        }
        // R2：试捕 / OCR / 比例
        view.findViewById<View>(R.id.btn_region_probe)?.setOnClickListener {
            probeNodesInRegion(selector)
        }
        view.findViewById<View>(R.id.btn_region_ocr)?.setOnClickListener {
            probeOcrInRegion(selector)
        }
        val aspectBtn = view.findViewById<android.widget.Button>(R.id.btn_region_aspect)
        aspectBtn?.setOnClickListener {
            val label = selector?.cycleAspectRatio() ?: "自由"
            aspectBtn.text = "比例:$label"
            toast("比例 $label")
        }
        view.findViewById<View>(R.id.btn_probe_search)?.setOnClickListener {
            searchWithProbeText()
        }

        // Phase 2 — 准备就绪后，再隐藏答案窗并尝试 addView
        hideAccessibilityOverlay()
        QuizOcrEntryOverlay.minimizeForRegionIfShowing()

        var addSuccess = false
        var lastError: String? = null

        // 尝试 1：正常参数（无 FLAG_LAYOUT_IN_SCREEN）
        try {
            wm.addView(view, params)
            addSuccess = true
        } catch (e: Throwable) {
            lastError = "${e.javaClass.simpleName}: ${e.message}"
            Log.w(TAG, "region window addView attempt 1 failed: $lastError", e)
            try { wm.removeView(view) } catch (_: Throwable) {}
        }

        // 尝试 2：加 FLAG_LAYOUT_IN_SCREEN + cutout mode（兼容部分需要全屏的 ROM）
        if (!addSuccess) {
            try {
                params.flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    params.layoutInDisplayCutoutMode =
                        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                }
                wm.addView(view, params)
                addSuccess = true
                Log.i(TAG, "region window add succeeded with FLAG_LAYOUT_IN_SCREEN retry")
            } catch (e2: Throwable) {
                lastError = "${e2.javaClass.simpleName}: ${e2.message}"
                Log.w(TAG, "region window addView attempt 2 failed: $lastError", e2)
                try { wm.removeView(view) } catch (_: Throwable) {}
            }
        }

        if (addSuccess) {
            regionWindowView = view
            regionWindowParams = params
        } else {
            // 失败恢复：必须恢复答案窗，toast 真实错误信息
            Log.e(TAG, "enterRegionMode: all addView attempts failed, restoring overlay. Error: $lastError")
            regionWindowView = null
            regionWindowParams = null
            QuizOcrEntryOverlay.restoreAfterRegionIfNeeded()
            toast("区域选择器打开失败：$lastError")
            if (!QuizOcrEntryOverlay.isShowing() && isPluginEnabledInConfig()) {
                showOrUpdateAccessibilityOverlay("", "")
            }
        }
    }

    private fun applyRegionPreset(left: Float, top: Float, right: Float, bottom: Float) {
        val selector = regionWindowView?.findViewById<View>(R.id.region_selector) as? RegionSelectorView
            ?: return
        selector.applyPreset(left, top, right, bottom)
    }

    private fun exitRegionMode() {
        val view = regionWindowView ?: return
        try { windowManager?.removeView(view) } catch (_: Throwable) {}
        regionWindowView = null
        regionWindowParams = null
        // OCR 录入优先恢复；关闭助手不弹答案窗
        if (QuizOcrEntryOverlay.isShowing()) {
            QuizOcrEntryOverlay.restoreAfterRegionIfNeeded()
            QuizOcrEntryOverlay.setStatus("区域已更新，可继续 OCR 识别")
            return
        }
        if (isPluginEnabledInConfig()) {
            showOrUpdateAccessibilityOverlay("", "")
            mainHandler.post { refreshRegionButtonState() }
        }
    }

    private fun saveRegionFromSelector(selector: RegionSelectorView?, showToast: Boolean = false) {
        val region = selector?.getRegion() ?: return
        saveRegion(region)
        screenRegion = region
        if (showToast) {
            val pkg = lastForegroundPkg
            val tip = if (pkg.isNotBlank() && pkg != packageName) {
                "已保存（$pkg）"
            } else {
                "已保存，可返回搜题"
            }
            toast(tip)
        }
    }

    private fun showProbePanel(title: String, body: String) {
        val root = regionWindowView ?: return
        val panel = root.findViewById<View>(R.id.region_probe_panel)
        val t = root.findViewById<TextView>(R.id.tv_probe_title)
        val b = root.findViewById<TextView>(R.id.tv_probe_body)
        panel?.visibility = View.VISIBLE
        t?.text = title
        b?.text = body.ifBlank { "（空）" }
        // 从正文提取可搜题文本（去掉「· 」前缀列表行）
        lastProbeSearchText = body.lineSequence()
            .map { it.trim().removePrefix("· ").trim() }
            .filter { it.isNotBlank() && !it.startsWith("共 ") && !it.startsWith("区域内") && !it.startsWith("截图") }
            .joinToString("\n")
            .ifBlank { body.trim() }
        root.findViewById<View>(R.id.btn_probe_search)?.setOnClickListener {
            searchWithProbeText()
        }
    }

    private fun searchWithProbeText() {
        val text = lastProbeSearchText.trim()
        if (text.isBlank()) {
            toast("没有可搜文本")
            return
        }
        // 取前几行作为题目，避免过长
        val question = text.lineSequence()
            .filter { it.isNotBlank() }
            .take(8)
            .joinToString("\n")
        val ch = resolveChannel()
        if (ch == null) {
            toast("请先打开 box 应用")
            return
        }
        try {
            ch.invokeMethod("searchWithProbeText", mapOf("text" to question))
            toast("已提交搜题")
            // 保存当前框并退出区域模式，露出答案窗
            (regionWindowView?.findViewById<View>(R.id.region_selector) as? RegionSelectorView)?.let {
                saveRegionFromSelector(it, showToast = false)
            }
            exitRegionMode()
        } catch (e: Throwable) {
            Log.w(TAG, "searchWithProbeText failed", e)
            toast("搜题失败：${e.message}")
        }
    }

    /** 节点试捕：不退出选择器，预览区域内无障碍文本。 */
    private fun probeNodesInRegion(selector: RegionSelectorView?) {
        val region = selector?.getRegion()
        if (region == null) {
            toast("请先框选区域")
            return
        }
        showProbePanel("试捕中…", "正在读取无障碍节点…")
        // 临时用选择框作为捕获区域
        val prev = screenRegion
        screenRegion = RectF(region)
        try {
            val root = resolveProbeRoot()
            if (root == null) {
                showProbePanel("试捕失败", "无法获取当前窗口节点（可能无障碍未覆盖该 App）")
                return
            }
            val candidates = mutableListOf<String>()
            collectText(root, candidates, 0)
            val preview = candidates
                .map { it.trim().replace(Regex("\\s+"), " ") }
                .filter { it.isNotBlank() }
                .distinct()
                .take(12)
            val body = if (preview.isEmpty()) {
                "区域内未读到文本。可试：放大框 / 换题干带 / 用 OCR 试识"
            } else {
                "共 ${candidates.size} 条节点，预览 ${preview.size} 条：\n" +
                    preview.joinToString("\n") { "· $it" }
            }
            showProbePanel("试捕预览", body)
            // 仅在 OCR 录入窗发起的试捕才进入填表链路。答案窗的试捕只做预览/搜题，
            // 否则用户只是验证读屏也会被突然切走并打开 OCR 录入窗。
            val full = candidates
                .map { it.trim().replace(Regex("\\s+"), " ") }
                .filter { it.isNotBlank() }
                .distinct()
                .joinToString("\n")
            if (full.isNotBlank()) {
                val inOcrEntryMode = QuizOcrEntryOverlay.isMinimizedForRegion()
                val ch = resolveChannel()
                if (ch != null) {
                    try {
                        if (inOcrEntryMode) {
                            ch.invokeMethod("ocrEntryParse", mapOf("raw" to full))
                        } else {
                            ch.invokeMethod("searchWithProbeText", mapOf("text" to full))
                        }
                    } catch (e: Throwable) {
                        Log.w(TAG, "probe routing failed", e)
                    }
                }
            }
        } catch (e: Throwable) {
            Log.w(TAG, "probeNodes failed", e)
            showProbePanel("试捕失败", e.message ?: e.javaClass.simpleName)
        } finally {
            screenRegion = prev
        }
    }

    /**
     * 解析读屏根节点。
     *
     * 直接点悬浮窗「试捕」时，焦点刚落在我们自己的 TYPE_ACCESSIBILITY_OVERLAY 上，
     * [rootInActiveWindow] 常为 null 或指向我们自己的包，导致提示
     * 「无法获取当前窗口节点」。框选页试捕时前台仍是目标 App，所以能成功。
     *
     * 策略：active 优先（且非自身包）→ 遍历 windows 找 TYPE_APPLICATION 非自身包
     * → 任意非自身包 → active 兜底。
     * 依赖 [AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS]。
     */
    private fun resolveProbeRoot(): AccessibilityNodeInfo? {
        fun isSelfOrSystem(pkg: String): Boolean {
            if (pkg.isBlank()) return true
            if (pkg == packageName) return true
            if (pkg == "com.android.systemui") return true
            if (pkg.startsWith("com.android.systemui")) return true
            return false
        }

        // 1) active window：若是目标 App 直接用
        rootInActiveWindow?.let { root ->
            val pkg = root.packageName?.toString().orEmpty()
            if (!isSelfOrSystem(pkg)) return root
        }

        // 2) 遍历交互窗口（需 FLAG_RETRIEVE_INTERACTIVE_WINDOWS）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val wins = try { windows } catch (_: Throwable) { null } ?: emptyList()
            // 优先 application + active/focused
            val ranked = wins.sortedByDescending { w ->
                var score = 0
                try {
                    if (w.type == AccessibilityWindowInfo.TYPE_APPLICATION) score += 100
                    if (w.isActive) score += 20
                    if (w.isFocused) score += 10
                } catch (_: Throwable) {}
                score
            }
            for (w in ranked) {
                val root = try { w.root } catch (_: Throwable) { null } ?: continue
                val pkg = root.packageName?.toString().orEmpty()
                if (!isSelfOrSystem(pkg)) return root
            }
        }

        // 3) 兜底：仍返回 active（可能 null）
        return rootInActiveWindow
    }

    /**
     * 用已保存/已框选区域（screenRegion）直接读屏 → 解析填表。
     * 供 OCR 录入窗的「试捕」按钮调用，无需重新进入区域调节。
     * @param attempt 重试次数：录入窗刚 hide 后 active window 可能短暂为空，最多重试 3 次。
     */
    /** 尝试点击当前目标 App 中的「下一题」或 Next；允许点其可点击祖先。 */
    private fun clickNextQuestionNode(root: AccessibilityNodeInfo): Boolean {
        val nextLabels = listOf("下一题", "下一", "下题", "next")
        fun visit(node: AccessibilityNodeInfo?, depth: Int): Boolean {
            if (node == null || depth > 40) return false
            try {
                val label = listOf(node.text, node.contentDescription).joinToString(" ") { it?.toString().orEmpty() }.trim().lowercase()
                if (nextLabels.any { label == it || label.contains(it) }) {
                    var target: AccessibilityNodeInfo? = node
                    repeat(6) {
                        val current = target ?: return@repeat
                        if (current.isClickable && current.isEnabled && current.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true
                        target = current.parent
                    }
                }
                for (i in 0 until node.childCount) if (visit(node.getChild(i), depth + 1)) return true
            } catch (e: Throwable) { Log.w(TAG, "clickNextQuestionNode traversal failed", e) }
            return false
        }
        return visit(root, 0)
    }

        private fun probeNodesFromSavedRegion(attempt: Int = 0) {
        // 优先内存区域，否则从持久化恢复（冷启动/服务重建后 screenRegion 可能为空）
        var region = screenRegion ?: loadRegion()
        if (region != null) screenRegion = region
        if (region == null) {
            // 无区域：自动进框选，保存后继续试捕填表
            pendingProbeAfterRegion = "entry"
            toast("请先框选识别区域，保存后自动试捕")
            QuizOcrEntryOverlay.minimizeForRegionIfShowing()
            enterRegionMode()
            return
        }
        val prev = screenRegion
        try {
            val root = resolveProbeRoot()
            if (root == null) {
                if (attempt < 5) {
                    mainHandler.postDelayed({ probeNodesFromSavedRegion(attempt + 1) }, 220L)
                    return
                }
                toast("读屏失败：未覆盖该 App / 焦点在浮层上，可重试或先进「框选」")
                QuizOcrEntryOverlay.ensureVisibleAfterProbeIfNeeded("试捕失败：读不到前台窗口")
                return
            }
            val candidates = mutableListOf<String>()
            collectText(root, candidates, 0)
            val full = candidates
                .map { it.trim().replace(Regex("\\s+"), " ") }
                .filter { it.isNotBlank() }
                .distinct()
                .joinToString("\n")
            if (full.isBlank()) {
                if (attempt < 3) {
                    mainHandler.postDelayed({ probeNodesFromSavedRegion(attempt + 1) }, 220L)
                    return
                }
                // 读屏空 → OCR 兜底（截图可用时）
                toast("读屏无文本，尝试 OCR 兜底…")
                QuizOcrEntryOverlay.ensureVisibleAfterProbeIfNeeded("读屏无文本，OCR 兜底中…")
                fallbackOcrProbeForEntry()
                return
            }
            val ch = resolveChannel()
            if (ch == null) {
                toast("Flutter 通道未就绪：请打开 box 应用后再试")
                QuizOcrEntryOverlay.ensureVisibleAfterProbeIfNeeded("试捕失败：Flutter 通道未就绪")
                return
            }
            try {
                ch.invokeMethod("ocrEntryParse", mapOf("raw" to full))
                // Dart 侧会 showOcrEntryOverlay + fill；这里再兜底显示，避免仍 GONE
                mainHandler.postDelayed({
                    QuizOcrEntryOverlay.ensureVisibleAfterProbeIfNeeded("试捕完成，请核对后保存")
                }, 120L)
            } catch (e: Throwable) {
                Log.w(TAG, "probeFromSaved→ocrEntryParse failed", e)
                toast("试捕回填失败：${e.message}")
                QuizOcrEntryOverlay.ensureVisibleAfterProbeIfNeeded("试捕回填失败：${e.message}")
            }
        } catch (e: Throwable) {
            Log.w(TAG, "probeFromSaved failed", e)
            toast("试捕失败：${e.message}")
            QuizOcrEntryOverlay.ensureVisibleAfterProbeIfNeeded("试捕失败：${e.message}")
        } finally {
            screenRegion = prev ?: region
        }
    }

    /**
     * 答题悬浮窗「试捕」：用已框选/已保存区域读屏，把文本作为题目触发搜题。
     * 与 OCR 录入侧的试捕复用同一读屏逻辑，只是结果走 searchWithProbeText。
     */
private fun probeFromSavedRegionForAnswer(attempt: Int = 0) {
        val region = screenRegion
        if (region == null) {
            pendingProbeAfterRegion = "answer"
            toast("请先框选识别区域，保存后自动试捕搜题")
            enterRegionMode()
            return
        }
        val prev = screenRegion
        try {
            val root = resolveProbeRoot()
            if (root == null) {
                if (attempt < 3) {
                    mainHandler.postDelayed({ probeFromSavedRegionForAnswer(attempt + 1) }, 150L)
                    return
                }
                toast("读屏失败：未覆盖该 App / 焦点在浮层上，可重试或点「识别区域」")
                return
            }
            val candidates = mutableListOf<String>()
            collectText(root, candidates, 0)
            val full = candidates
                .map { it.trim().replace(Regex("\\s+"), " ") }
                .filter { it.isNotBlank() }
                .distinct()
                .joinToString("\n")
            if (full.isBlank()) {
                if (attempt < 2) {
                    mainHandler.postDelayed({ probeFromSavedRegionForAnswer(attempt + 1) }, 150L)
                    return
                }
                toast("读屏无文本，尝试 OCR 兜底…")
                fallbackOcrProbeForAnswer()
                return
            }
            val ch = resolveChannel()
            if (ch == null) {
                toast("Flutter 通道未就绪：请打开 box 应用后再试")
                return
            }
            try {
                ch.invokeMethod("searchWithProbeText", mapOf("text" to full))
            } catch (e: Throwable) {
                Log.w(TAG, "probeForAnswer→searchWithProbeText failed", e)
                toast("试捕搜题失败：${e.message}")
            }
        } catch (e: Throwable) {
            Log.w(TAG, "probeFromSavedRegionForAnswer failed", e)
            toast("试捕失败：${e.message}")
        } finally {
            screenRegion = prev
        }
    }

    /** 录入侧：读屏空时用已存区域截图 → OCR → ocrEntryParse */
    private fun fallbackOcrProbeForEntry() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            toast("读屏无文本且系统不支持截图 OCR（需 Android 11+）")
            return
        }
        if (screenRegion == null) {
            toast("无识别区域，无法 OCR 兜底")
            return
        }
        lastScreenshotBytes = null
        captureRegionScreenshot { bytes ->
            mainHandler.post {
                if (bytes == null || bytes.isEmpty()) {
                    toast("OCR 兜底失败：截图失败（可能 FLAG_SECURE）")
                    return@post
                }
                lastScreenshotBytes = bytes
                val ch = resolveChannel()
                if (ch == null) {
                    toast("OCR 兜底失败：Flutter 通道未就绪")
                    return@post
                }
                try {
                    // 复用录入 OCR 识别链路
                    ch.invokeMethod(
                        "ocrEntryRecognize",
                        mapOf("bytes" to bytes),
                    )
                } catch (e: Throwable) {
                    Log.w(TAG, "fallbackOcr entry failed", e)
                    toast("OCR 兜底失败：${e.message}")
                }
            }
        }
    }

    /** 答题侧：读屏空时截图 → regionOcrProbe 预览；并尽量 searchWithProbeText */
    private fun fallbackOcrProbeForAnswer() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            toast("读屏无文本且系统不支持截图 OCR（需 Android 11+）")
            return
        }
        if (screenRegion == null) {
            toast("无识别区域，无法 OCR 兜底")
            return
        }
        lastScreenshotBytes = null
        captureRegionScreenshot { bytes ->
            mainHandler.post {
                if (bytes == null || bytes.isEmpty()) {
                    toast("OCR 兜底失败：截图失败（可能 FLAG_SECURE）")
                    return@post
                }
                lastScreenshotBytes = bytes
                val ch = resolveChannel()
                if (ch == null) {
                    toast("OCR 兜底失败：Flutter 通道未就绪")
                    return@post
                }
                try {
                    // 走区域 OCR 预览 + 自动搜题（答题侧 OCR 兜底）
                    ch.invokeMethod(
                        "regionOcrProbe",
                        mapOf("bytes" to bytes, "bytesLen" to bytes.size, "autoSearch" to true),
                    )
                    toast("已 OCR 兜底并尝试搜题")
                } catch (e: Throwable) {
                    Log.w(TAG, "fallbackOcr answer failed", e)
                    toast("OCR 兜底失败：${e.message}")
                }
            }
        }
    }

    /** OCR 试识：截当前框 → Dart OCR → setProbeResult 回写。 */
    private fun probeOcrInRegion(selector: RegionSelectorView?) {
        val region = selector?.getRegion()
        if (region == null) {
            toast("请先框选区域")
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            showProbePanel("OCR 不可用", "需要 Android 11+ 的 takeScreenshot")
            return
        }
        showProbePanel("OCR 试识…", "正在截图识别区域…")
        val prev = screenRegion
        // 下面保留原有 OCR 截图逻辑（region 已校验）
        // NOTE: 原函数体从 screenRegion=RectF(region) 开始
        screenRegion = RectF(region)
        lastScreenshotBytes = null
        captureRegionScreenshot { bytes ->
            mainHandler.post {
                screenRegion = prev
                if (bytes == null || bytes.isEmpty()) {
                    showProbePanel("OCR 失败", "截图失败（可能 FLAG_SECURE 或权限不足）")
                    return@post
                }
                lastScreenshotBytes = bytes
                val ch = resolveChannel()
                if (ch == null) {
                    showProbePanel("OCR 失败", "Flutter 通道未就绪，请打开 box 应用后再试")
                    return@post
                }
                showProbePanel("OCR 试识…", "截图成功，正在识别…")
                try {
                    ch.invokeMethod(
                        "regionOcrProbe",
                        mapOf("bytes" to bytes, "bytesLen" to bytes.size),
                    )
                } catch (e: Throwable) {
                    Log.w(TAG, "invoke regionOcrProbe failed", e)
                    showProbePanel("OCR 失败", e.message ?: "通道调用失败")
                }
            }
        }
    }

    /** 仅读用户显式保存的区域，不含默认上 55% 推导。 */
    private fun loadSavedRegionOnly(): RectF? {
        val pkg = lastForegroundPkg
        if (pkg.isNotBlank() && pkg != packageName) {
            loadRegionForPackage(pkg)?.let { return it }
        }
        val raw = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).getString(KEY_REGION, null)
            ?: return null
        val parts = raw.split(',').mapNotNull { it.toFloatOrNull() }
        if (parts.size != 4) return null
        return RectF(parts[0], parts[1], parts[2], parts[3])
    }

    private fun loadRegionForPackage(pkg: String): RectF? {
        val raw = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString("${KEY_REGION}_$pkg", null) ?: return null
        val parts = raw.split(',').mapNotNull { it.toFloatOrNull() }
        if (parts.size != 4) return null
        return RectF(parts[0], parts[1], parts[2], parts[3])
    }

    // ---- 持久化 ----

    private fun loadOverlayPosition(width: Int, height: Int): Pair<Int, Int> {
        val dm = resources.displayMetrics
        val maxX = (dm.widthPixels - width).coerceAtLeast(0)
        val maxY = (dm.heightPixels - height).coerceAtLeast(0)
        val raw = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).getString(KEY_OVERLAY_GEOMETRY, null)
        if (raw != null) {
            val p = raw.split(',').mapNotNull { it.toIntOrNull() }
            if (p.size >= 2) {
                return p[0].coerceIn(0, maxX) to p[1].coerceIn(0, maxY)
            }
        }
        // 默认靠右上，少挡左侧题干
        val x = (dm.widthPixels - width - dm.widthPixels * 0.04f).toInt().coerceIn(0, maxX)
        val y = (dm.heightPixels * 0.10f).toInt().coerceIn(0, maxY)
        return x to y
    }

    private fun loadOverlayPosition(): Pair<Int, Int> {
        val (w, h) = loadOverlaySize()
        return loadOverlayPosition(w, h)
    }

    private fun defaultOverlaySize(): Pair<Int, Int> {
        val dm = resources.displayMetrics
        // 普通答题窗使用紧凑 5:4 卡片，避免覆盖题图/选项并消除横向长条感。
        val w = (dm.widthPixels * 0.52f).toInt().coerceIn(280, 480)
        val h = (w * 0.80f).toInt().coerceIn(230, 390)
        return w to h
    }

    private fun saveOverlayPosition(x: Int, y: Int) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString(KEY_OVERLAY_GEOMETRY, "$x,$y")
            .apply()
    }

    private fun loadOverlaySize(): Pair<Int, Int> {
        val dm = resources.displayMetrics
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString("${KEY_OVERLAY_GEOMETRY}_size", null)
        if (raw != null) {
            val p = raw.split(',').mapNotNull { it.toIntOrNull() }
            if (p.size >= 2) {
                val minW = (OVERLAY_MIN_WIDTH_DP * dm.density).toInt()
                val minH = (OVERLAY_MIN_HEIGHT_DP * dm.density).toInt()
                var w = p[0].coerceIn(minW, dm.widthPixels)
                var h = p[1].coerceIn(minH, dm.heightPixels)
                // v4 强制把历史宽窗（含手动遗留的 88% 宽长条）迁移为紧凑卡片；
                // 后续用户通过缩放手柄调整的卡片尺寸会保留。
                val isLegacyWide = w > (dm.widthPixels * 0.62f).toInt() ||
                    h * 100 < w * 70
                if (!prefs.getBoolean(KEY_OVERLAY_COMPACT_MIGRATED, false) && isLegacyWide) {
                    val compact = defaultOverlaySize()
                    w = compact.first
                    h = compact.second
                    prefs.edit()
                        .putBoolean(KEY_OVERLAY_COMPACT_MIGRATED, true)
                        .putString("${KEY_OVERLAY_GEOMETRY}_size", "$w,$h")
                        .apply()
                }
                return w to h
            }
        }
        return defaultOverlaySize()
    }

    private fun saveOverlaySize(w: Int, h: Int) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString("${KEY_OVERLAY_GEOMETRY}_size", "$w,$h")
            .apply()
    }

    private fun loadFontScaleIndex(): Int {
        val v = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).getInt(KEY_OVERLAY_FONT_SCALE, 1)
        return v.coerceIn(0, FONT_SCALE_STEPS.size - 1)
    }

    private fun saveFontScaleIndex(i: Int) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putInt(KEY_OVERLAY_FONT_SCALE, i)
            .apply()
    }

    private fun loadOverlayOpacity(): Float {
        val v = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getFloat(KEY_OVERLAY_OPACITY, 1.0f)
        return v.coerceIn(0.3f, 1.0f)
    }

    private fun saveOverlayOpacity(o: Float) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putFloat(KEY_OVERLAY_OPACITY, o)
            .apply()
    }

    private fun setOverlayOpacity(opacity: Float) {
        val view = accessibilityOverlayView ?: return
        val clamped = opacity.coerceIn(0.3f, 1.0f)
        view.findViewById<View>(R.id.answer_container)?.alpha = clamped
        saveOverlayOpacity(clamped)
    }

    private fun setOverlaySizeFromDp(widthDp: Float, heightDp: Float) {
        if (examMode || overlayHiddenDot) return
        val view = accessibilityOverlayView ?: return
        val params = overlayParams ?: return
        val density = resources.displayMetrics.density
        val dm = resources.displayMetrics
        val minW = (OVERLAY_MIN_WIDTH_DP * density).toInt()
        val minH = (OVERLAY_MIN_HEIGHT_DP * density).toInt()
        params.width = (widthDp * density).toInt().coerceIn(minW, dm.widthPixels)
        params.height = (heightDp * density).toInt().coerceIn(minH, (dm.heightPixels * 0.82f).toInt())
        overlayExpandedWidth = params.width
        overlayExpandedHeight = params.height
        clampParamsToScreen(params)
        try { windowManager?.updateViewLayout(view, params) } catch (_: Throwable) {}
        saveOverlaySize(params.width, params.height)
        saveOverlayPosition(params.x, params.y)
    }

    private fun ensureAnswerOverlayFitsContent(view: View) {
        if (examMode || answerOnlyMode || overlayCollapsed) return
        val answer = view.findViewById<TextView>(R.id.tv_answer) ?: return
        // TextView 在本次赋值后的真实换行数决定最小内容高度；避免失败文案变两三行后
        // 被旧的手动窗口高度裁掉。只增高，不破坏用户主动缩小后的宽度/位置。
        answer.post {
            val current = overlayParams ?: return@post
            val content = view.findViewById<View>(R.id.answer_container) ?: return@post
            val titleH = view.findViewById<View>(R.id.title_bar)?.height ?: 0
            val statusH = view.findViewById<View>(R.id.status_bar)?.height ?: 0
            val dividerH = view.findViewById<View>(R.id.answer_divider)?.height ?: 0
            val questionH = view.findViewById<View>(R.id.scroll_question)?.height ?: 0
            val needed = titleH + statusH + dividerH + questionH + answer.height
            if (needed > current.height) {
                current.height = needed.coerceAtMost((resources.displayMetrics.heightPixels * 0.82f).toInt())
                clampParamsToScreen(current)
                try { windowManager?.updateViewLayout(view, current) } catch (_: Throwable) {}
            }
        }
    }

    private fun updateAccessibilityOverlayView() {
        val view = accessibilityOverlayView ?: return
        val qTv = view.findViewById<TextView>(R.id.tv_question)
        val aTv = view.findViewById<TextView>(R.id.tv_answer)
        val status = view.findViewById<View>(R.id.status_bar)
        val pillLabel = view.findViewById<TextView>(R.id.tv_pill_label)
        val title = view.findViewById<TextView>(R.id.tv_title)

        val q = overlayQuestion.ifEmpty { "等待捕获题目…" }
        val rawAnswer = overlayAnswers.ifEmpty { "等待搜题结果…" }
        // Dart 写入隐藏 SIM marker，供标题/摘要条稳定显示相似度；正文必须移除该内部标记。
        val simFromMarker = Regex("\\[\\[SIM:(\\d{1,3})]]").find(rawAnswer)
            ?.groupValues?.getOrNull(1)?.toIntOrNull()
        val a = rawAnswer.replace(Regex("\\s*\\[\\[SIM:\\d{1,3}]]"), "").trim()
        val isSearchingNow = overlayStatus == "searching"
        // 标题/摘要条已展示状态与相似度；内容区命中时只显示答案本身。
        // 检索中：标题已有「新题 · 检索中」，正文与摘要条不再重复。
        val displayAnswer = when {
            isSearchingNow -> ""
            overlayStatus == "miss" -> a.lineSequence()
                .map { it.trim() }
                .firstOrNull { it.isNotEmpty() && !it.contains("相似度") }
                ?: a.ifBlank { "未命中" }
            else -> compactAnswerForExam(a, includeSimilarity = false)
        }
        qTv?.text = q
        // 检索中清空正文，避免与标题三重复
        if (isSearchingNow) {
            aTv?.text = ""
        } else {
            applyAnswerStyle(aTv, displayAnswer)
        }
        ensureAnswerOverlayFitsContent(view)
        applyAnswerOnlyVisibility(view)
        applyThemeToView(view)
        clampQuestionScrollMaxHeight(view)

        // 结构化状态色（优先 status 字段）
        val color = when (overlayStatus) {
            "searching" -> 0xFFF59E0B.toInt()
            "miss" -> 0xFFEF4444.toInt()
            "hit" -> 0xFF22C55E.toInt()
            else -> themeColor
        }
        status?.setBackgroundColor(color)

        val key = overlayAnswerKey
        val sim = overlaySimilarity ?: simFromMarker ?: extractSimilarity(a)

        // 标题栏只显示固定相似度标签：进一步缩短文案，给眼睛与关闭按钮保留固定空间。
        val badgeText = when {
            isSearchingNow -> "检索中"
            sim == null -> "待匹配"
            sim >= 90 -> "$sim%"
            sim >= 70 -> "$sim%"
            else -> "$sim%"
        }
        val badgeColor = when {
            isSearchingNow -> 0xFFB45309.toInt()
            sim == null -> 0xFF475467.toInt()
            sim >= 90 -> 0xFF15803D.toInt()
            sim >= 70 -> 0xFFB45309.toInt()
            else -> 0xFFB91C1C.toInt()
        }
        title?.text = badgeText
        title?.backgroundTintList = android.content.res.ColorStateList.valueOf(badgeColor)
        // 多匹配的切换仍可从正文长按/更多入口完成；相似度标签仅承担状态展示。
        title?.setOnClickListener(null)
        view.findViewById<View>(R.id.answer_container)?.alpha = loadOverlayOpacity()
    }

    /** 题目区限高：长题干区内自滚，避免挤掉答案/相似度首屏。 */
    private fun clampQuestionScrollMaxHeight(view: View) {
        val scrollQ = view.findViewById<View>(R.id.scroll_question) ?: return
        if (examMode || answerOnlyMode) return
        val maxH = (96f * resources.displayMetrics.density).toInt()
        scrollQ.post {
            if (scrollQ.height > maxH) {
                val lp = scrollQ.layoutParams
                lp.height = maxH
                scrollQ.layoutParams = lp
            }
        }
    }

    /** 考试/仅答案模式：只保留「答案…」；相似度只在标题，避免重复占用空间。 */
    private fun compactAnswerForExam(raw: String, includeSimilarity: Boolean = false): String {
        if (raw.isBlank()) return raw
        val lines = raw.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.toList()
        if (lines.isEmpty()) return raw

        // 答案：优先「答案：…」行；否则首个像 A./B. 的选项答案
        var answerLine = lines.firstOrNull {
            it.startsWith("答案") && !it.startsWith("答案区")
        }
        if (answerLine == null) {
            answerLine = lines.firstOrNull {
                it.matches(Regex("^[A-DＡ-Ｄ][.、．:：)].+")) ||
                    it.matches(Regex("^[A-DＡ-Ｄ]$")) ||
                    ((it.contains("正确") || it.contains("错误")) && it.length <= 12)
            }
        }
        // 去掉前缀「匹配题目」等误伤
        if (answerLine != null &&
            (answerLine.startsWith("匹配题目") || answerLine.startsWith("选项") || answerLine.startsWith("解析"))
        ) {
            answerLine = null
        }

        val keep = mutableListOf<String>()
        if (answerLine != null) {
            // 统一成「答案：…」
            val cleaned = if (answerLine.startsWith("答案")) {
                answerLine
            } else {
                "答案：$answerLine"
            }
            keep.add(cleaned)
        } else {
            // 兜底：首行非噪声
            lines.firstOrNull {
                !it.startsWith("匹配题目") &&
                    !it.startsWith("选项") &&
                    !it.startsWith("解析") &&
                    !it.contains("相似度")
            }?.let { keep.add(if (it.startsWith("答案")) it else "答案：$it") }
        }
        if (includeSimilarity) {
            val simLine = lines.firstOrNull { it.contains("相似度") }
            val simOnly = simLine?.let {
                Regex("""相似度\s*[:：]?\s*(\d{1,3})\s*%""").find(it)?.let { m ->
                    "相似度：${m.groupValues[1]}%"
                } ?: it
            }
            if (simOnly != null) keep.add(simOnly)
        }

        if (keep.isEmpty()) return lines.take(2).joinToString("\n")
        return keep.joinToString("\n")
    }

    private fun extractSimilarity(raw: String): Int? {
        val m = Regex("""相似度\s*[:：]?\s*(\d{1,3})\s*%""").find(raw) ?: return null
        return m.groupValues.getOrNull(1)?.toIntOrNull()
    }

    private fun applyAnswerStyle(tv: TextView?, text: String) {
        if (tv == null) return
        // 考试态优先可读性：答案两行使用更大的基础字号；普通态仍跟随字号设置。
        val baseSize = if (examMode) 16.5f else 13f
        tv.textSize = baseSize * if (examMode) 1.0f else fontScale()
        tv.setLineSpacing(
            (if (examMode) 5 else 3) * resources.displayMetrics.density,
            1.0f,
        )
        // 首行若像「答案：A」或「A. xxx」则加粗首行
        val firstLineEnd = text.indexOf('\n').let { if (it < 0) text.length else it }
        val first = text.substring(0, firstLineEnd)
        val looksLikeAnswer = first.contains("答案") ||
            first.matches(Regex("^[A-DＡ-Ｄ][.、．:].*")) ||
            first.matches(Regex("^[A-DＡ-Ｄ]$"))
        if (looksLikeAnswer && text.isNotBlank()) {
            val span = android.text.SpannableString(text)
            span.setSpan(
                android.text.style.StyleSpan(android.graphics.Typeface.BOLD),
                0,
                firstLineEnd,
                android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            span.setSpan(
                android.text.style.ForegroundColorSpan(themeColor),
                0,
                firstLineEnd,
                android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            // 多选项行也轻微强调 A./B.
            val lineRegex = Regex("(?m)^([A-DＡ-Ｄ])[.、．]")
            for (m in lineRegex.findAll(text)) {
                span.setSpan(
                    android.text.style.StyleSpan(android.graphics.Typeface.BOLD),
                    m.range.first,
                    m.range.last + 1,
                    android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
            tv.text = span
        } else {
            tv.text = text
        }
    }

    private fun hideAccessibilityOverlay() {
        val view = accessibilityOverlayView ?: return
        try {
            windowManager?.removeView(view)
        } catch (_: Throwable) {}
        accessibilityOverlayView = null
        overlayParams = null
    }

    /**
     * 截屏并裁剪到识别区域，PNG 编码后回调返回字节。
     * 需要 API 30+（takeScreenshot）；低版本或失败回调 null。
     */
    fun captureRegionScreenshot(callback: (ByteArray?) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            callback(null)
            return
        }
        screenRegion = screenRegion ?: loadRegion()
        try {
            takeScreenshot(
                android.view.Display.DEFAULT_DISPLAY,
                { it.run() },
                object : AccessibilityService.TakeScreenshotCallback {
                    override fun onSuccess(screenshot: AccessibilityService.ScreenshotResult) {
                        val bytes = runCatching { encodeCroppedPng(screenshot) }.getOrNull()
                        try {
                            screenshot.hardwareBuffer.close()
                        } catch (_: Throwable) {}
                        lastScreenshotBytes = bytes
                        callback(bytes)
                    }

                    override fun onFailure(errorCode: Int) {
                        Log.w(TAG, "takeScreenshot failed code=$errorCode")
                        callback(null)
                    }
                }
            )
        } catch (e: Throwable) {
            Log.w(TAG, "takeScreenshot exception", e)
            callback(null)
        }
    }

    /**
     * 带 requestId 的截屏：Dart 侧用 QuizCaptureSessionCoordinator 校验请求归属，
     * 防止并发 OCR/录入/试识串图。Native 端记录 requestId，回调时比对丢弃过期结果。
     */
    fun captureRegionScreenshotWithRequestId(
        requestId: Int,
        callback: (ByteArray?) -> Unit,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            callback(null)
            return
        }
        // 记录本次请求 ID，后续回调时比对
        Companion.currentRequestId = requestId
        screenRegion = screenRegion ?: loadRegion()
        try {
            takeScreenshot(
                android.view.Display.DEFAULT_DISPLAY,
                { it.run() },
                object : AccessibilityService.TakeScreenshotCallback {
                    override fun onSuccess(screenshot: AccessibilityService.ScreenshotResult) {
                        val bytes = runCatching { encodeCroppedPng(screenshot) }.getOrNull()
                        try {
                            screenshot.hardwareBuffer.close()
                        } catch (_: Throwable) {}
                        lastScreenshotBytes = bytes
                        // 仅当 requestId 未过期时才回传
                        if (Companion.currentRequestId == requestId) {
                            callback(bytes)
                        }
                    }

                    override fun onFailure(errorCode: Int) {
                        Log.w(TAG, "takeScreenshot failed code=$errorCode")
                        if (Companion.currentRequestId == requestId) {
                            callback(null)
                        }
                    }
                }
            )
        } catch (e: Throwable) {
            Log.w(TAG, "takeScreenshot exception", e)
            if (Companion.currentRequestId == requestId) {
                callback(null)
            }
        }
    }

    private fun encodeCroppedPng(screenshot: ScreenshotResult): ByteArray? {
        val buffer: HardwareBuffer = screenshot.hardwareBuffer
        val colorSpace = screenshot.colorSpace
        val full = Bitmap.wrapHardwareBuffer(buffer, colorSpace) ?: return null
        // 转成可裁剪的软件位图
        val software = full.copy(Bitmap.Config.ARGB_8888, false) ?: return null
        full.recycle()

        val region = screenRegion
        val cropped = if (region != null && !region.isEmpty) {
            val left = region.left.toInt().coerceIn(0, software.width - 1)
            val top = region.top.toInt().coerceIn(0, software.height - 1)
            val right = region.right.toInt().coerceIn(left + 1, software.width)
            val bottom = region.bottom.toInt().coerceIn(top + 1, software.height)
            Bitmap.createBitmap(software, left, top, right - left, bottom - top)
        } else {
            software
        }

        val out = ByteArrayOutputStream()
        cropped.compress(Bitmap.CompressFormat.PNG, 100, out)
        if (cropped !== software) cropped.recycle()
        software.recycle()
        return out.toByteArray()
    }

    private fun bestCaptureRoot(eventRoot: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        // 事件 source 常是某个选项/局部容器。优先取完整目标窗口，局部节点仅作兜底。
        val root = resolveProbeRoot()
        return root ?: eventRoot
    }

    private fun extractAndSend(root: AccessibilityNodeInfo?) {
        if (root == null) return
        val candidates = mutableListOf<String>()
        screenRegion = screenRegion ?: loadRegion()
        collectText(root, candidates, 0)

        val config = readCaptureConfig()
        val cleaned = normalizeQuizText(candidates, config)
        val debugCapture = config.debugCapture
        val payload = if (debugCapture) buildDebugPayload(candidates, cleaned) else cleaned

        if (payload.isBlank()) return
        // 仅在同一屏幕稳定期内抑制重复；题目 A → B → A 必须再次投递，
        // 否则 Dart 无法恢复 A 的答案。Dart 层已有指纹/命中锁防重复搜题。
        val now = System.currentTimeMillis()
        if (payload == lastQuestion && now - lastQuestionSentAt < 900L) return
        if (!debugCapture && config.filterNoise && !QUIZ_KEYWORDS.any { cleaned.contains(it, ignoreCase = true) }) return

        val activeChannel = resolveChannel()
        if (activeChannel == null) {
            Log.w(TAG, "Flutter channel is not ready; skip captured question")
            return
        }

        lastQuestion = payload
        lastQuestionSentAt = now
        Log.d(TAG, "捕获题目: $payload")
        activeChannel.invokeMethod("onQuestionCaptured", mapOf("question" to payload))
    }

    private fun resolveChannel(): MethodChannel? {
        val engine = FlutterEngineCache.getInstance().get("quiz_engine") ?: return null
        return channel ?: MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).also { channel = it }
    }

    private data class CaptureConfig(
        val filterNoise: Boolean = true,
        val maxCaptureLines: Int = 8,
        val debugCapture: Boolean = false,
    )

    private fun normalizeQuizText(candidates: List<String>, config: CaptureConfig): String {
        val lines = candidates
            .map { it.trim().replace(Regex("\\s+"), " ") }
            .filter { line ->
                line.isNotBlank() && line.length <= 180 &&
                        (!config.filterNoise ||
                                (!NOISE_LINES.contains(line) && NOISE_CONTAINS.none { noise -> line.contains(noise) }))
            }
            .distinct()
            .toMutableList()

        if (lines.isEmpty()) return ""

        val firstQuestionIndex = lines.indexOfFirst { line ->
            line.contains("题") ||
                    line.contains("？") ||
                    line.contains("?") ||
                    line.matches(Regex("^\\d+[.、].*")) ||
                    line.contains("以下") ||
                    line.contains("关于") ||
                    line.contains("下列")
        }.let { if (it < 0) 0 else it }

        val selected = lines.drop(firstQuestionIndex).take(config.maxCaptureLines.coerceIn(1, 20))
        return selected.joinToString("\n")
    }

    private fun buildDebugPayload(candidates: List<String>, cleaned: String): String {
        val rawPreview = candidates
            .map { it.trim().replace(Regex("\\s+"), " ") }
            .filter { it.isNotBlank() }
            .distinct()
            .take(12)
            .joinToString("\n")
        return listOf(
            "【无障碍调试】原始节点 ${candidates.size} 条",
            "【清洗后】",
            cleaned.ifBlank { "<空>" },
            "【原始预览】",
            rawPreview.ifBlank { "<空>" }
        ).joinToString("\n")
    }

    private fun readCaptureConfig(): CaptureConfig {
        val raw = getSharedPreferences(CONFIG_PREFS_NAME, Context.MODE_PRIVATE)
            .getString(CONFIG_KEY, null)
            ?: getSharedPreferences("com.example.box_preferences", Context.MODE_PRIVATE)
                .getString("quiz_plugin_config", null)
            ?: return CaptureConfig()
        return CaptureConfig(
            filterNoise = parseBooleanConfig(raw, "filterNoise", true),
            maxCaptureLines = parseIntConfig(raw, "maxCaptureLines", 8),
            debugCapture = parseBooleanConfig(raw, "debugCapture", false),
        )
    }

    private fun parseBooleanConfig(raw: String, key: String, fallback: Boolean): Boolean {
        val match = Regex("\\\"$key\\\"\\s*:\\s*(true|false)").find(raw) ?: return fallback
        return match.groupValues[1] == "true"
    }

    private fun parseIntConfig(raw: String, key: String, fallback: Int): Int {
        val match = Regex("\\\"$key\\\"\\s*:\\s*(\\d+)").find(raw) ?: return fallback
        return match.groupValues[1].toIntOrNull() ?: fallback
    }

    private fun collectText(node: AccessibilityNodeInfo, out: MutableList<String>, depth: Int) {
        if (depth > MAX_TREE_DEPTH) return
        if (!node.isVisibleToUser) return

        val bounds = Rect()
        node.getBoundsInScreen(bounds)
        if (!isNodeInsideSelectedRegion(bounds)) return

        // 跳过明显的图标/导航 chrome，但 Button 可能承载 A/B/C/D 选项，不能一刀切。
        val cls = node.className?.toString() ?: ""
        val isChrome = cls.contains("ImageView") || cls.contains("Image") ||
            cls.contains("FloatingAction") || cls.contains("Tab") || cls.contains("BottomNav")
        val text = node.text?.toString()?.trim() ?: node.contentDescription?.toString()?.trim()
        val looksLikeOption = !text.isNullOrEmpty() && (
            text.matches(Regex("^[A-HＡ-Ｈ][.、．:：)].+")) ||
                text.matches(Regex("^(正确|错误|对|错)$"))
            )
        if (!text.isNullOrEmpty() && (!isChrome || looksLikeOption) && text.length <= 120) {
            out.add(text)
        }

        for (i in 0 until node.childCount) {
            node.getChild(i)?.let { child ->
                collectText(child, out, depth + 1)
            }
        }
    }

    private fun isNodeInsideSelectedRegion(bounds: Rect): Boolean {
        val region = screenRegion ?: return true
        if (bounds.isEmpty) return true
        val nodeRect = RectF(bounds)
        return RectF.intersects(region, nodeRect) || region.contains(nodeRect.centerX(), nodeRect.centerY())
    }

    private fun saveRegion(region: RectF) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
        val raw = "${region.left},${region.top},${region.right},${region.bottom}"
        prefs.putString(KEY_REGION, raw)
        // 按当前前台 App 记忆（非本应用）
        val pkg = lastForegroundPkg
        if (pkg.isNotBlank() && pkg != packageName && !pkg.startsWith("com.android")) {
            prefs.putString("${KEY_REGION}_$pkg", raw)
        }
        prefs.apply()
    }

    private fun loadRegion(): RectF? {
        // 优先当前前台 App 专属
        val pkg = lastForegroundPkg
        if (pkg.isNotBlank() && pkg != packageName) {
            loadRegionForPackage(pkg)?.let { return it }
        }
        val raw = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).getString(KEY_REGION, null)
        if (raw != null) {
            val parts = raw.split(',').mapNotNull { it.toFloatOrNull() }
            if (parts.size == 4) return RectF(parts[0], parts[1], parts[2], parts[3])
        }
        // 默认上 55% 屏（少吃导航栏/底部按钮噪音）
        val dm = resources.displayMetrics
        return RectF(
            dm.widthPixels * 0.02f,
            dm.heightPixels * 0.04f,
            dm.widthPixels * 0.98f,
            dm.heightPixels * 0.55f,
        )
    }

    private fun isPluginEnabledInConfig(): Boolean {
        val raw = getSharedPreferences(CONFIG_PREFS_NAME, Context.MODE_PRIVATE)
            .getString(CONFIG_KEY, null)
            ?: return false
        return Regex("\"enabled\"\\s*:\\s*true").containsMatchIn(raw)
    }

    /** 供 companion / 外部查询：答题助手是否开启。 */
    fun isQuizAssistEnabled(): Boolean = isPluginEnabledInConfig()

    private fun applyThemeFromFlutterConfig() {
        val raw = getSharedPreferences(CONFIG_PREFS_NAME, Context.MODE_PRIVATE)
            .getString(CONFIG_KEY, null) ?: return
        val idxMatch = Regex("\"themeColorIndex\"\\s*:\\s*(\\d+)").find(raw)
        val idx = idxMatch?.groupValues?.getOrNull(1)?.toIntOrNull() ?: return
        if (idx in THEME_COLORS.indices) {
            themeColor = THEME_COLORS[idx]
            getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                .putInt(KEY_THEME_COLOR, themeColor).apply()
        }
        val opMatch = Regex("\"overlayOpacity\"\\s*:\\s*([0-9.]+)").find(raw)
        val op = opMatch?.groupValues?.getOrNull(1)?.toFloatOrNull()
        if (op != null) {
            saveOverlayOpacity(op.coerceIn(0.3f, 1.0f))
        }
    }
}
