package top.hpa888.box

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
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
        private const val CHANNEL = "top.hpa888.box/quiz_plugin"
        private const val TAG = "QuizAccessibility"
        private const val PREFS_NAME = "quiz_plugin_prefs"
        private const val KEY_REGION = "quiz_region"
        /** 题图区域：仅框住题图本身，用于 dHash 消歧，与 OCR 区域独立。 */
        private const val KEY_IMAGE_REGION = "quiz_image_region"
        private const val KEY_OVERLAY_GEOMETRY = "quiz_overlay_geometry"
        private const val KEY_OVERLAY_COMPACT_MIGRATED = "quiz_overlay_compact_migrated_v4"
        // v5：修复 defaultOverlaySize() 的 px/dp 混用（旧窗仅 137dp，标题栏放不下）。
        // 记录已迁移的尺寸 schema 版本，避免每次启动都重算覆盖用户手动缩放的尺寸。
        private const val KEY_OVERLAY_SIZE_SCHEMA = "quiz_overlay_size_schema"
        // 折叠卡死修复的一次性迁移标记（见 loadPersistedState 里的说明）。
        private const val KEY_OVERLAY_COLLAPSE_SCHEMA = "quiz_overlay_collapse_schema"
        private const val KEY_OVERLAY_OPACITY = "quiz_overlay_opacity"
        private const val KEY_OVERLAY_FONT_SCALE = "quiz_overlay_font_scale"
        private const val KEY_HIDDEN_DOT = "quiz_overlay_hidden_dot"
        private const val KEY_EXAM_MODE = "quiz_exam_mode"
        private const val KEY_ANSWER_ONLY = "quiz_answer_only"
        private const val KEY_ANSWER_ONLY_BEFORE_EXAM = "quiz_answer_only_before_exam"
        private const val KEY_PRE_EXAM_GEOMETRY = "quiz_pre_exam_geometry"
        /** 考试窗记忆位置 "x,y"（P1-1：与普通模式位置分离，互不污染）。 */
        private const val KEY_EXAM_GEOMETRY = "quiz_exam_geometry"
        private const val KEY_EXAM_OVERLAY_SIZE = "quiz_exam_overlay_size"
        /**
         * 手动开关考试模式的持久化标志。
         *
         * 2026-09-17 P1：区分「⋯ 菜单手动开」与「前台 App 自动进入」。
         * 只有前者跨服务重启存活；后者是会话级状态，启动时清除，
         * 避免 e7382f5 的「残留 examMode」stuck-state 复发。
         */
        private const val KEY_EXAM_MODE_MANUAL = "quiz_exam_mode_manual"
        private const val KEY_CLICK_THROUGH = "quiz_click_through_collapsed"
        private const val KEY_THEME_COLOR = "quiz_theme_color"
        private const val KEY_COLLAPSED = "quiz_overlay_collapsed"
        private const val CONFIG_PREFS_NAME = "FlutterSharedPreferences"
        private const val CONFIG_KEY = "flutter.quiz_plugin_config"
        const val ACTION_UPDATE_REGION = "top.hpa888.box.UPDATE_QUIZ_REGION"

        // 悬浮窗尺寸/字号约束（默认更宽，避免标题按钮挤压与文字被截断）
        private const val OVERLAY_MIN_WIDTH_DP = 240
        private const val OVERLAY_MIN_HEIGHT_DP = 140

        /**
         * 内容自适应时预留的竖向余量（dp）：覆盖 padding 与区块间距。
         *
         * 少了它会「刚好差几行」把过程框最后一行裁掉 —— 用户看到的就是
         * 「AI 作答过程只显示一半」。调大 = 留更多余量（窗口略高）；调小反之。
         */
        private const val OVERLAY_VERTICAL_SLACK_DP = 28
        // 用户 2026-09-13 明确要求「扩大长宽高，扩大 1.5 倍」。
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
            svc.mainHandler.post {
                svc.regionMode = "ocr"
                svc.enterRegionMode()
            }
            return true
        }

        /** 进入「题图区域」框选模式，保存后写入 KEY_IMAGE_REGION 而非 OCR 区域。 */
        fun enterImageRegionModeIfRunning(): Boolean {
            val svc = runningService ?: return false
            svc.mainHandler.post {
                svc.regionMode = "image"
                svc.enterRegionMode()
            }
            return true
        }

        /** 更新 AI 作答过程（供 Flutter 侧在搜题各阶段推送，显示在答案下方）。 */
        fun updateAiProcessIfRunning(text: String?): Boolean {
            val svc = runningService ?: return false
            svc.updateAiProcess(text)
            return true
        }

        /** 用题图区域截图并计算 dHash（供 Flutter 侧消歧用）。 */
        fun captureImageRegionIfRunning(
            requestId: Int,
            callback: (ByteArray?) -> Unit,
        ): Boolean {
            val svc = runningService ?: return false
            svc.captureImageRegionScreenshotWithRequestId(requestId, callback)
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

        @JvmStatic
        fun computeDHashFromPng(pngBytes: ByteArray): String? {
            val svc = runningService
            if (svc != null) return svc.computeDHash(pngBytes)
            return null
        }
    }

    val mainHandler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var isActive = false
    private var screenRegion: RectF? = null
    /** 题图区域：仅框住题图本身，独立于 OCR 识别区域。 */
    private var imageRegion: RectF? = null
    private var windowManager: WindowManager? = null
    private var accessibilityOverlayView: View? = null
    private var overlayParams: WindowManager.LayoutParams? = null
    private var overlayQuestion = ""
    private var overlayAnswers = ""
    private var overlayStatus = "idle"
    private var overlayAnswerKey: String? = null

    // 读屏进度 ticker（2026-09-13）：每秒刷新徽章倒计时/阶段文案/进度条。
    // 最坏要等满 45s，静态文案会让用户以为卡死。
    private val visionTickerHandler = Handler(Looper.getMainLooper())
    private var visionTickerRunnable: Runnable? = null
    private var visionStartedAt = 0L
    /** 手动 AI 读屏是否在运行（markVisionRunning 维护；汇聚点按 VisionRunningStatePolicy 消费）。 */
    @Volatile private var visionRunning = false
    private var overlaySimilarity: Int? = null
    private var overlayMatchIndex = 0
    private var overlayMatchCount = 1
    private var overlayAnswersList: List<String> = emptyList()
    private var lastProbeSearchText: String = ""
    /** 无区域时点试捕：先框选，保存后自动继续。entry=录入填表；answer=答题搜题 */
    private var pendingProbeAfterRegion: String? = null
    /** 区域选择模式：ocr=识别区域（默认），image=题图区域。 */
    private var regionMode: String = "ocr"
    private var commandReceiver: BroadcastReceiver? = null

    // 悬浮窗几何 / 外观状态
    private var overlayFontScaleIndex = 1 // 默认中号（FONT_SCALE_STEPS[1] = 1.0）
    private var overlayCollapsed = false
    private var overlayHiddenDot = false
    @Volatile private var hiddenDotDragging = false

    /**
     * 用户此刻是否正在滑动/拖动我们自己的浮层。
     * 抓题扫描与浮层渲染共用主线程，滑动期间必须让路，松手后再恢复。
     */
    @Volatile private var ownOverlayInteracting = false

    /** 最后一次操作自己浮层的时间（触摸或滚动均算），用于抓题扫描静默判定。 */
    @Volatile private var lastOwnOverlayActivityAt = 0L

    /** 在途的扫描恢复回调，重排时需先撤销，避免叠加成多次扫描。 */
    private var scanResumeRunnable: Runnable? = null
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
    // D4（2026-09-19）：双击计时跨 attachDragHandler 保留（旧版是闭包局部，
    // 重建视图后清零，导致跨重建的双击被误判）。lastTitleTapInTitleArea 记录
    // "上一次 tap 是否落在标题区"，配合 D2 放宽判据。
    private var lastTitleTapTime = 0L
    private var lastTitleTapInTitleArea = false
    // E1（2026-09-19）：前台包重算节流时间戳。TYPE_WINDOW_CONTENT_CHANGED /
    // TYPE_VIEW_SCROLLED 可能在一秒内连发几十条（同题动画/滚动），但其中
    // 携带的前台包名变化才是切题信号。用固定间隔节流，去重后仅当包名真的
    // 变了才走 handleForegroundPackage（自动进/出考试态），避免动画连发
    // 导致考试态反复抖动。
    private var lastAutoExamRecheckAt = 0L

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
        // ⚠️ 用户 2026-09-15 第 N+1 次反馈「答题悬浮窗大小还是没有变化」，并附真机日志。
        //
        // ## 真因（本次由日志闭环实证，非推测）
        // 日志显示尺寸决策**完全正确**：
        //   overlay.default  screen=1260x2800px density=3.5 -> 1184x1540px (338x440dp)
        //   overlay.result(no-prefs) 1184x1540px (338x440dp)   ← 94% 屏宽，正是期望值
        // 但真机截图里窗口只有 ~500px（40% 屏宽），且**贴右上角、文字被底边裁断**。
        //
        // 500px + 右上角 + 内容返回 0 —— 三者同时出现只对应一条路径：
        // **考试模式**（examOverlayDimensions() 的 else 分支 = 0.46*屏宽 夹到 [300,500]，
        //   定位 x = 屏宽 - w - 3%、y = 8%）。且 decideOverlayGeometry() 的
        //   ① if (input.examMode) 分支在**最前面**直接返回考试尺寸，绕过所有宽高/下限逻辑；
        //   currentContentNeededHeight() 又因 `if (examMode || answerOnlyMode) return 0`
        //   恒返回 0 → 过程/答案框永远只放得下一行 → 「只显示一半」。
        // 这就是为什么此前每一次「尺寸修复」在真机上都像没生效 —— 修复压根不在被执行的路径上。
        //
        // ## 为什么会卡住（与 KEY_COLLAPSED 同型的 stuck-state bug）
        // 考试模式由**前台 App 自动进入**（handleForegroundPackage → autoExamByForeground），
        // 而 autoExamByForeground 是**内存标志**，examMode 却**持久化**。
        // 服务被杀/重启后 autoExamByForeground 归 false、examMode 从 prefs 恢复 true，
        // 两个退出条件（:676 / :684）都要求 autoExamByForeground == true → **永不触发**。
        // 用户从此永久卡在考试小窗，且 UI 上没有任何「已进入考试模式」的提示。
        //
        // ## 修法
        // 自动进入的考试模式**本质上是会话级状态**，跨重启存活没有任何合法语义
        // （真正的考试模式有独立开关，重启后会重新进入）。故启动时无条件清掉持久化的
        // examMode，让它回到普通大窗；用户若确实在考试，前台切换会立刻重新进入。
        // 与 KEY_COLLAPSED 的一次性迁移同理，但这里**每次启动都清**——
        // 因为「残留的 examMode」永远是 bug，不存在需要保留的场景。
        // ⚠️ 2026-09-17 P1：只清除「自动进入」的残留考试态，保留「手动开关」的。
        //
        // 背景（e7382f5 的 stuck-state 修复）：考试模式可**自动进入**（前台 App
        // 触发 → autoExamByForeground，内存标志）也可**手动开关**（⋯ 菜单）。
        // 自动进入是会话级状态，服务重启后 autoExamByForeground 归 false 而
        // examMode 从 prefs 恢复 true，两个退出条件都要求 autoExamByForeground==true
        // → 永不触发 → 用户永久卡在考试小窗。
        //
        // 但 e7382f5 的做法是**无条件**清 examMode，把手动开的也一并清掉了 ——
        // 手动是用户明确意图，跨重启应存活。现用 KEY_EXAM_MODE_MANUAL 区分：
        // 手动路径 setExamMode 时置 true，自动路径（handleForegroundPackage /
        // reapplyAutoExamFromConfig）不置。启动时只清「非手动」的残留。
        run {
            val p = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val manual = p.getBoolean(KEY_EXAM_MODE_MANUAL, false)
            if (p.getBoolean(KEY_EXAM_MODE, false) && !manual) {
                logDebug("migrate: clear auto-entered stale exam mode (stuck small-window fix)")
                p.edit()
                    .putBoolean(KEY_EXAM_MODE, false)
                    .apply()
            }
        }
        examMode = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_EXAM_MODE, false)
        answerOnlyMode = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_ANSWER_ONLY, false)
        clickThroughWhenCollapsed = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_CLICK_THROUGH, false)
        // ⚠️ 用户 2026-09-15 第 N 次反馈「答题悬浮窗还是没有变化，ai搜题显示也没有优化」。
        // 真因之一：折叠态是**持久化**的（KEY_COLLAPSED），而折叠时窗口是
        // WRAP_CONTENT 窄条（真机实测仅 39% 屏宽）。用户折叠过一次后，除手动点
        // 「重置悬浮窗大小」外无任何清除点 → 跨重启、跨升级永久卡在小窗，
        // 于是每次升级用户都说「还是没变化」——其实新版的大窗逻辑根本没机会生效。
        //
        // 一次性 schema：升级到含本次修复的版本时，无条件清掉历史折叠态。
        // 与 :3345 那段「别做一次性迁移」的告诫不冲突 —— 那条针对的是**尺寸**
        // 迁移（改的是「已保存值 ×N」，跑过即作废且会被手拖值覆盖）；这里清的是
        // 一个**卡死的布尔状态**，且只在升级当次需要（用户之后再折叠仍被尊重）。
        run {
            val p = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            if (p.getInt(KEY_OVERLAY_COLLAPSE_SCHEMA, 0) < 1) {
                if (p.getBoolean(KEY_COLLAPSED, false)) {
                    logDebug("migrate: clear stale collapsed state (stuck-sliver fix)")
                }
                p.edit()
                    .putBoolean(KEY_COLLAPSED, false)
                    .putInt(KEY_OVERLAY_COLLAPSE_SCHEMA, 1)
                    .apply()
            }
        }
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

        // 抓题扫描跑在主线程（渲染悬浮窗的同一条线程），且每次都是几百次 binder 调用。
        // 自身浮层滚动产生的事件既是无用功又直接吃掉滑动帧率，必须在入口挡掉。
        if (!QuizCaptureScanGate.shouldScan(
                eventPackage = event.packageName?.toString().orEmpty(),
                selfPackage = packageName,
                ownOverlayInteracting = ownOverlayInteracting,
            )
        ) {
            return
        }

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                // 前台包名感知：离开 box 自动考试模式，回到 box 恢复
                // （E1：窗口状态是切 App 的**最强**信号，不走节流，立即重算。）
                recheckForegroundForAutoExam(event, /*throttled=*/false)
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
                // E1（2026-09-19）：切题 App 常**不发** WINDOW_STATE_CHANGED
                // （单 Activity + 内部 Fragment/WebView 切题），只发 content/
                // scroll。旧版这些事件只抓题、不重算前台包 → 离开 box 时
                // 自动考试态"进不去/出不来"，用户感知"不灵敏"。此处补一次
                // **节流 + 去重**的前台包重算（仅包名真变才走 handleForeground
                // Package），不影响抓题节流。
                recheckForegroundForAutoExam(event, /*throttled=*/true)
            }
        }
    }

    /**
     * E1（2026-09-19）：统一的前台包重算入口，供 WINDOW_STATE_CHANGED（即时）
     * 与 WINDOW_CONTENT_CHANGED / VIEW_SCROLLED（节流）共用，保证"进/出考试
     * 态"只有**一条**判定路径（单一事实源）。
     *
     * @param throttled 为 true 时按 [lastAutoExamRecheckAt] 节流（同题动画
     *   一秒几十条事件里只放行一条重算），避免考试态反复抖动；窗口状态事件
     *   是强信号，传 false 立即执行。
     * @return 是否真正执行了一次重算（包名有变化）。
     */
    private fun recheckForegroundForAutoExam(event: AccessibilityEvent, throttled: Boolean): Boolean {
        if (throttled) {
            val now = System.currentTimeMillis()
            // E1：节流门委托纯函数（单一事实源），仅放行一条重算。
            if (!AutoExamForegroundPolicy.shouldRecheck(now, lastAutoExamRecheckAt)) return false
            lastAutoExamRecheckAt = now
        } else {
            lastAutoExamRecheckAt = System.currentTimeMillis()
        }
        val eventPkg = event.packageName?.toString().orEmpty()
        val pkg = resolveForegroundPackageForAutoExam(eventPkg)
        if (pkg.isBlank() || pkg == lastForegroundPkg) return false
        lastForegroundPkg = pkg
        handleForegroundPackage(pkg)
        return true
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
        // E1/E3（2026-09-19）：进/出考试态的决策抽成纯函数
        // AutoExamForegroundPolicy.decide（单一事实源，可单测）。服务只负责
        // 执行副作用（setExamMode / loadRegion）。
        val decision = AutoExamForegroundPolicy.decide(
            isSelf = pkg == self,
            inWhitelist = pkg.isNotBlank() && pkg != self && shouldAutoExamForPackage(pkg),
            examMode = examMode,
            autoExamByForeground = autoExamByForeground,
        )
        when {
            decision.enterExamMode -> {
                autoExamByForeground = true
                setExamMode(true)
            }
            decision.exitExamMode -> {
                if (decision.resetAutoFlag) autoExamByForeground = false
                setExamMode(false)
            }
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
     * 考试窗尺寸（px）——**委托** [OverlayGeometryPolicy.examSize]。
     *
     * ⚠️ 2026-09-16 修复：本函数原先在此处**自己算**，且写成：
     *
     * ```kotlin
     * val w = (dm.widthPixels * 0.46f).toInt().coerceIn(300, 500)
     * ```
     *
     * 在 px 域算出 579，却用**照 dp 直觉写的** 300/500 去夹 →
     * `LayoutParams.width` 单位是 px，真机（1260px / density 3.5）被夹成
     * `500px = 143dp`（只占屏宽 40%）。三档固定上限 390/500/590 全部中招，
     * **连「大」档都只有 169dp** —— 而标题栏需 204dp，于是按钮必然被裁、
     * 用户看到的永远是「小窗」。这就是用户报的「开启考试模式就一直是小窗」。
     *
     * 现改为单一事实源：比例与 dp 口径都在 policy 里，本函数只做数据搬运。
     * 尺寸决策散落在 service 内正是该 bug 得以长期存活的原因。
     */
    private fun examOverlayDimensions(): Pair<Int, Int> {
        val dm = resources.displayMetrics
        return OverlayGeometryPolicy.examSize(
            screenW = dm.widthPixels,
            screenH = dm.heightPixels,
            density = dm.density,
            preference = examOverlaySizePreference(),
        )
    }

    private fun applyExamOverlayDimensions(
        params: WindowManager.LayoutParams,
        view: View,
        updatePosition: Boolean = false,
    ) {
        val (w, h) = examOverlayDimensions()
        params.width = w
        params.height = h
        // 考试模式：位置记忆优先（用户拖过就尊重），否则靠右上、少挡题干。
        // 决策委托 OverlayGeometryPolicy —— 与普通模式口径统一，且可 JVM 单测。
        val dm = resources.displayMetrics
        val (px, py) = OverlayGeometryPolicy.examPosition(
            loadExamPosition(),
            dm.widthPixels,
            dm.heightPixels,
            w,
            h,
        )
        params.x = px
        params.y = py
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
            if (status == "ambiguous") {
                overlayAnswerKey = null
            } else if (answerKey != null) {
                overlayAnswerKey = answerKey
            }
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
        // 任何一次「终态」渲染结果都是「读屏已结束」的信号：把手动读屏键恢复可点。
        // 放在这个唯一汇聚点，避免 Dart 侧每条 return 路径都要显式复位（漏一条就锁死按钮）。
        // 2026-09-19 修复：searching 推送（手动读屏开始时 Dart _tryVisionFallback 必推
        // 「新题 · AI 读屏中…」）不再是结束信号——旧实现这里无条件 resetVisionButton()
        // → stopVisionTicker()，横幅被 GONE、ticker 停转、按钮「AI…」永不还原
        //（真机截图 img_8920e96fae97：AI… 在转而胶囊/正文全是旧 miss 渲染）。
        if (VisionRunningStatePolicy.endsVisionRun(status)) {
            visionRunning = false
            resetVisionButton()
        }
        if (status == "ambiguous") {
            overlayAnswerKey = null
        } else if (answerKey != null) {
            overlayAnswerKey = answerKey
        }
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
        // 决策 1.B：答案就绪 → 自动收起 AI 过程，把首屏让给答案。
        // 放在这个**唯一汇聚点**（每次答案渲染都过这里），避免 Dart 侧每条
        // return 路径各自调用（漏一条就不会收起）。
        if (isAnswerReadyStatus(status)) {
            accessibilityOverlayView?.let { autoCollapseAiProcessOnAnswerReady(it) }
        }
        return true
    }

    /**
     * 该状态是否表示「答案已就绪」（决策 1.B 的自动收起触发条件）。
     *
     * `searching` = 还在搜，**不该**收起过程（用户正要看 AI 干活）；
     * `ambiguous` = 需人工确认，也保留过程（用户要据此判断）。
     */
    private fun isAnswerReadyStatus(status: String): Boolean {
        val s = status.trim().lowercase()
        if (s.isEmpty()) return false
        return s != "searching" && s != "ambiguous" && s != "idle"
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
                regionMode = "ocr"
                enterRegionMode()
            }
            view.findViewById<View>(R.id.btn_area)?.setOnLongClickListener {
                showRegionQuickMenu(it)
                true
            }
            view.findViewById<View>(R.id.btn_quiz_entry)?.setOnClickListener {
                val ch = resolveChannel()
                if (ch == null) {
                    toast("请先打开 box 应用")
                } else {
                    ch.invokeMethod("examQuickEntry", null)
                }
            }
            refreshRegionButtonState(view)
            view.findViewById<View>(R.id.btn_probe)?.setOnClickListener {
                probeFromSavedRegionForAnswer()
            }
            view.findViewById<View>(R.id.btn_search)?.setOnClickListener {
                resolveChannel()?.invokeMethod("manualSearch", mapOf("question" to overlayQuestion))
            }
            // AI 读屏：手动按键，绕过自动流程直接让大模型读屏作答。
            // 与 btn_search 的区别：search 走「题干 → 本地/外部题库」，
            // 本键走「截图 → 大模型直接给答案」，能处理读图题。
            view.findViewById<View>(R.id.btn_ai_vision)?.setOnClickListener {
                val ch = resolveChannel()
                if (ch == null) {
                    toast("请先打开 box 应用")
                } else {
                    // 立即进入「读屏中」态：大模型最坏要走 45s 重试窗口，
                    // 不给反馈的话用户会以为按钮没反应，然后反复点。
                    markVisionRunning(view, true)
                    ch.invokeMethod("visionSearch", mapOf("question" to overlayQuestion))
                }
            }
            view.findViewById<View>(R.id.btn_close)?.setOnClickListener { hideAccessibilityOverlay() }
            view.findViewById<View>(R.id.btn_font)?.setOnClickListener { cycleFontScale(view) }
            view.findViewById<View>(R.id.btn_collapse)?.setOnClickListener { toggleCollapse(view) }
            view.findViewById<View>(R.id.btn_hide_overlay)?.setOnClickListener { toggleHiddenDot(view) }
            view.findViewById<View>(R.id.btn_expand)?.setOnClickListener { toggleCollapse(view) }
            view.findViewById<View>(R.id.btn_more)?.setOnClickListener { showMoreMenu(it, view) }
            // 框选识别范围：用户 2026-09-13 第五次反馈「帮框选识别范围的按钮
            // 也加回来」——此前被收进 ⋯ 菜单，用户找不到。现标题栏常驻。
            // 进 OCR 框选（含题干+选项），保存后自动继续搜题。
            view.findViewById<View>(R.id.btn_region_entry)?.setOnClickListener {
                regionMode = "ocr"
                pendingProbeAfterRegion = "answer"
                enterRegionMode()
            }
            // AI 作答过程折叠开关（默认收起，不挤占答案首屏）。
            view.findViewById<View>(R.id.ai_process_header)?.setOnClickListener {
                toggleAiProcessExpanded(it)
            }
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
            // FLAG_HARDWARE_ACCELERATED：Manifest 的 hardwareAccelerated 只覆盖 Activity，
            // WindowManager 直加的浮层默认软件渲染，答案区滚动会掉帧。
            val params = WindowManager.LayoutParams(
                w,
                h,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
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
                val (px, py) = OverlayGeometryPolicy.examPosition(
                    loadExamPosition(),
                    dm.widthPixels,
                    dm.heightPixels,
                    examW,
                    examH,
                )
                params.x = px
                params.y = py
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
                            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
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
        // A1'（2026-09-19）：11f → 12f。原 11f 与静态默认 13sp（quiz_overlay.xml +
        // applyAnswerStyle）口径分裂：用户按一次字号循环，答案骤缩 2sp 观感像 bug。
        // 12f = 「略小于题干但可读」，与 13f 静态默认只差 1 档，切换不再跳变。
        // 考试模式 16.5f 大卡口径在 applyAnswerStyle 内独立，不经本函数。
        val baseA = 12f
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

    /** AI 作答过程：展开/收起（默认收起，避免挤占答案首屏）。 */
    private fun toggleAiProcessExpanded(anyView: View) {
        val root = accessibilityOverlayView ?: return
        val scroll = root.findViewById<View>(R.id.scroll_ai_process) ?: return
        val expanding = scroll.visibility != View.VISIBLE
        scroll.visibility = if (expanding) View.VISIBLE else View.GONE
        root.findViewById<TextView>(R.id.tv_ai_process_toggle)?.text =
            if (expanding) "收起" else "展开"
        // 记住用户意图（三态策略，见 AiProcessPanelPolicy）：手动展开后
        // 答案就绪不再自动收起（2026-09-19 报障：展开 <1s 被同题重复渲染收回）。
        if (expanding) {
            aiProcessIntent = AiProcessPanelPolicy.UserIntent.EXPANDED
            root.findViewById<TextView>(R.id.tv_ai_process_title)?.text = "AI 作答过程"
            // 优化显示：展开后内容占位变了，重算窗口高度避免底边裁切
            //（与 updateAiProcess 同一条 ensure 路径，不新开第二套尺寸逻辑）。
            ensureAnswerOverlayFitsContent(root)
        } else {
            aiProcessIntent = AiProcessPanelPolicy.UserIntent.COLLAPSED
            // 折叠态时把内容摘要放进标题右侧，让用户不展开也能看到关键一步。
            val full = root.findViewById<TextView>(R.id.tv_ai_process)?.text?.toString().orEmpty()
            val firstLine = full.lineSequence().firstOrNull { it.isNotBlank() }.orEmpty()
            root.findViewById<TextView>(R.id.tv_ai_process_title)?.text =
                if (firstLine.isBlank()) "AI 作答过程" else "AI 作答过程 · $firstLine"
        }
    }

    /**
     * 更新 AI 作答过程文本（在答题悬浮窗下方显示）。
     *
     * 用户 2026-09-13 第五次反馈「ai回答时在答题悬浮窗下面显示作答过程」。
     * 由 Flutter 侧在搜题各阶段经 `aiProcess` 方法调用推过来；传入空串表示
     * 本次不是 AI 作答（如本地题库命中），此时整块隐藏，保持界面干净。
     */
    fun updateAiProcess(text: String?) {
        val root = accessibilityOverlayView ?: return
        mainHandler.post {
            val box = root.findViewById<View>(R.id.ai_process_box) ?: return@post
            val body = text?.trim().orEmpty()
            if (body.isEmpty()) {
                box.visibility = View.GONE
                // 新一轮搜题：用户意图清零，自动化重新接管（AiProcessPanelPolicy）。
                aiProcessIntent = AiProcessPanelPolicy.resetForNewSearch()
                root.findViewById<TextView>(R.id.tv_ai_process)?.text = ""
                return@post
            }
            // ⚠️ 用户 2026-09-15 第 N 次反馈「答题悬浮窗还是没有变化，ai搜题显示也没有优化」。
            // 真因：窗口被**持久化**成折叠态（KEY_COLLAPSED），折叠时参数是
            // WRAP_CONTENT（窄条），而 ensureAnswerOverlayFitsContent 又在折叠态直接
            // return → 过程框只放得下一行，看起来就是「没变化 + 只显示一半」。
            // 新的过程内容 = 新一轮搜题的明确信号 → 必须保证窗口处于展开态。
            // 走 toggleCollapse 的既有路径（它会应用 flooredExpandedSize() 下限），
            // 不新开第二套尺寸逻辑。
            if (overlayCollapsed) {
                logDebug("aiProcess: auto-expand overlay (was collapsed, stuck-sliver fix)")
                toggleCollapse(root)
            }
            root.findViewById<TextView>(R.id.tv_ai_process)?.text = body
            root.findViewById<TextView>(R.id.tv_ai_process_title)?.text = "AI 作答过程"
            box.visibility = View.VISIBLE
            // 首次出现过程内容时**自动展开**（决策 1.B：默认展开）。
            // 用户 2026-09-14 反馈「显示只有一半，我看不完全」——默认收起时
            // 用户只能看到一个标题条，以为内容丢了。用户一旦手动点过「收起」，
            // 就不再自动弹开（尊重用户选择）。
            if (AiProcessPanelPolicy.shouldAutoExpandOnContent(aiProcessIntent)) {
                root.findViewById<View>(R.id.scroll_ai_process)?.visibility = View.VISIBLE
                root.findViewById<TextView>(R.id.tv_ai_process_toggle)?.text = "收起"
            } else if (root.findViewById<View>(R.id.scroll_ai_process)?.visibility != View.VISIBLE) {
                // 保持用户的手动收起态，但把最新摘要放进标题，不展开也能看到进展。
                val latest = body.lineSequence().lastOrNull { it.isNotBlank() }.orEmpty()
                root.findViewById<TextView>(R.id.tv_ai_process_title)?.text =
                    if (latest.isBlank()) "AI 作答过程" else "AI 作答过程 · $latest"
            }
            // 自适应：过程框占位后重算窗口高度，保证它不被窗口底边裁掉。
            // 走 ensureAnswerOverlayFitsContent 这一条既有路径，避免第二套尺寸
            // 计算逻辑（单一事实源）；它会把过程框计入 needed。
            ensureAnswerOverlayFitsContent(root)
        }
    }

    /**
     * 答案已就绪 → 自动收起 AI 过程（决策 1.B：默认展开，出答案后自动收起）。
     *
     * ## 为什么需要这一步
     *
     * 决策 1.B 的完整语义是「过程默认展开（让用户看到 AI 在干活）**且**答案出来
     * 后自动收起（把首屏让给答案）」。只做前半段会让答案与过程抢首屏，
     * 出现用户已明确抱怨过的「拥挤」。
     *
     * 与 [aiProcessIntent] 的关系：这里是**系统自动**收起，不动用户意图；
     * 但用户本轮手动展开（[AiProcessPanelPolicy.UserIntent.EXPANDED]）时跳过——
     * 否则同题重复渲染会把用户刚展开的面板收回去（2026-09-19 报障）。
     */
    private fun autoCollapseAiProcessOnAnswerReady(root: View) {
        val scroll = root.findViewById<View>(R.id.scroll_ai_process) ?: return
        if (scroll.visibility != View.VISIBLE) return
        // 用户本轮手动展开过 → 不收（2026-09-19 报障：手动展开 <1s 被同题
        // 重复渲染收回）。决策 1.B 只管默认态，不凌驾用户当前意图。
        if (!AiProcessPanelPolicy.shouldAutoCollapseOnAnswerReady(aiProcessIntent)) {
            logDebug("aiProcess: skip auto-collapse (user expanded this round)")
            return
        }
        scroll.visibility = View.GONE
        root.findViewById<TextView>(R.id.tv_ai_process_toggle)?.text = "展开"
        // 收起后标题右侧保留关键一步摘要，用户不展开也能看到结论。
        val full = root.findViewById<TextView>(R.id.tv_ai_process)?.text?.toString().orEmpty()
        val firstLine = full.lineSequence().firstOrNull { it.isNotBlank() }.orEmpty()
        root.findViewById<TextView>(R.id.tv_ai_process_title)?.text =
            if (firstLine.isBlank()) "AI 作答过程" else "AI 作答过程 · $firstLine"
        logDebug("aiProcess: auto-collapsed on answer ready (decision 1.B)")
    }

    /** 用户对过程面板的最近一次手动操作意图（三态策略，见 AiProcessPanelPolicy）。 */
    private var aiProcessIntent = AiProcessPanelPolicy.UserIntent.NONE

    private fun showMoreMenu(anchor: View, root: View) {
        try {
            val popup = android.widget.PopupMenu(this, anchor)
            popup.menu.add(0, 1, 0, "字号")
            popup.menu.add(0, 2, 1, "识别区域")
            popup.menu.add(0, 10, 9, "一键录入")
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
                    2 -> { regionMode = "ocr"; enterRegionMode(); true }
                    3 -> { copyAnswerToClipboard(); true }
                    4 -> { toggleAnswerOnly(root); true }
                    5 -> { setExamMode(!examMode, manual = true); true }
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
                    // 一键录入：原标题栏按钮迁入溢出菜单（2026-09-13 排版调整）
                    10 -> {
                        val ch = resolveChannel()
                        if (ch == null) {
                            toast("请先打开 box 应用")
                        } else {
                            ch.invokeMethod("examQuickEntry", null)
                        }
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
            // 先退出考试模式（会恢复备份）；再强制默认大窗。
            // 重置 = 手动清理，清掉手动标志，避免重启后又残留。
            setExamMode(false, manual = true)
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
            .remove(KEY_EXAM_GEOMETRY)
            .remove(KEY_EXAM_MODE_MANUAL)
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

    /**
     * 手动 AI 读屏的运行态反馈。
     *
     * 大模型读屏最坏要等满 45s 重试窗口（截图 → 压缩 → 退避重试）。
     * 期间若界面毫无变化，用户会以为「按了没反应」并反复点击，
     * 反而把请求打散。这里做两件事：置 searching 态（标题徽章显示「检索中」），
     * 以及禁用按钮防止重复触发。结果回来时由 Dart 侧 updateOverlay 复位。
     */
    private fun markVisionRunning(root: View, running: Boolean) {
        // 运行态标志：汇聚点（showOrUpdateAccessibilityOverlay）据此判定
        // searching 推送是「过程态」而非「结束信号」（VisionRunningStatePolicy）。
        visionRunning = running
        if (running) overlayStatus = "searching"
        val btn = root.findViewById<View>(R.id.btn_ai_vision)
        btn?.isEnabled = !running
        btn?.alpha = if (running) 0.45f else 0.95f
        // 用户 2026-09-13 第三次反馈「ai搜索时没有看到提示与进度」：
        // 仅把按钮变淡 + 一个小进度条，用户感知不到。这里把按钮**文字本身**
        // 改成进行中态，配合每秒倒计时，一按下去就能看到画面在动。
        val label = root.findViewById<View>(R.id.tv_ai_vision_label) as? TextView
        if (label != null) {
            label.text = if (running) "AI…" else "AI"
        }
        root.findViewById<View>(R.id.status_bar)?.setBackgroundColor(0xFFF59E0B.toInt())
        if (running) {
            visionStartedAt = System.currentTimeMillis()
            startVisionTicker(root)
        } else {
            stopVisionTicker(root)
        }
    }

    /**
     * 读屏进度：每秒刷新徽章倒计时 + 正文阶段文案 + 不定型进度条。
     *
     * 静态一句「最长约 45 秒」用户会以为卡死（最坏要等满 45s：截图 + 压缩 +
     * 2s/5s/10s/15s 退避重试）。阶段文案口径与 Dart 侧
     * `QuizPluginEntry.visionProgressText` 保持一致（改一处需改两处）。
     */
    private fun startVisionTicker(root: View) {
        stopVisionTicker(root)
        val answer = root.findViewById<View>(R.id.tv_answer) as? TextView
        // 进度展示改为**独立横幅**（vision_progress_box + tv_vision_progress +
        // vision_progress），不再写进相似度胶囊 —— 胶囊在窄窗下会被自适应收起，
        // 写进去等于没提示（用户 2026-09-13 反馈「看不到进度」的真因之一）。
        root.findViewById<View>(R.id.vision_progress_box)?.visibility = View.VISIBLE
        val progressBar = root.findViewById<View>(R.id.vision_progress) as? android.widget.ProgressBar
        val label = root.findViewById<View>(R.id.tv_vision_progress) as? TextView
        val tick = object : Runnable {
            override fun run() {
                val elapsedMs = System.currentTimeMillis() - visionStartedAt
                val s = (elapsedMs / 1000).toInt().coerceAtLeast(0)
                label?.text = visionPhaseText(s)
                answer?.text = visionPhaseText(s)
                // 进度条按 45s 总超时推进，封顶 95% 留出等待余量，避免「满格却没结果」
                progressBar?.progress = ((s * 100 / 45).coerceIn(0, 95))
                // 超过 45s 硬超时后停止 ticker：旧实现会一直每秒刷新下去，
                // 用户看到「还在转」以为没反应（而底层其实已经失败返回了）。
                if (s >= 45) {
                    // 先停 ticker（会隐藏进度横幅），再把横幅重新显示成「超时」终态，
                    // 否则刚写进去的文案会被 stopVisionTicker 的 GONE 一起藏掉。
                    stopVisionTicker(root)
                    // 超时即本次读屏终止：对称还原运行态（visionRunning + 按钮 label），
                    // 不等 Dart 侧迟到的终态推送（其间用户看到的是「AI…」+超时提示的矛盾态）。
                    visionRunning = false
                    (root.findViewById<View>(R.id.tv_ai_vision_label) as? TextView)?.text = "AI"
                    root.findViewById<View>(R.id.vision_progress_box)
                        ?.visibility = View.VISIBLE
                    label?.text = "AI 读屏已超时，可重新点击 AI 重试。"
                    return
                }
                visionTickerHandler.postDelayed(this, 1000)
            }
        }
        visionTickerRunnable = tick
        visionTickerHandler.post(tick)
    }

    private fun stopVisionTicker(root: View) {
        visionTickerRunnable?.let { visionTickerHandler.removeCallbacks(it) }
        visionTickerRunnable = null
        root.findViewById<View>(R.id.vision_progress_box)?.visibility = View.GONE
    }

    /** 分阶段文案：与 Dart 侧 visionProgressText 同口径。 */
    private fun visionPhaseText(s: Int): String = when {
        s < 3 -> "正在识别题目…"
        s < 15 -> "正在请求大模型（首次较慢，请稍候）…"
        s < 45 -> "仍在重试（网络波动，最长约 45 秒）…"
        else -> "等待超时，可重新点击 AI 读屏重试。"
    }

    /** 供 Dart 侧在收到读屏结果/失败后复位按钮。结果内容由 updateOverlay 统一重绘。 */
    private fun resetVisionButton() {
        accessibilityOverlayView?.let { stopVisionTicker(it) }
        accessibilityOverlayView
            ?.findViewById<View>(R.id.btn_ai_vision)
            ?.let { btn ->
                btn.isEnabled = true
                btn.alpha = 0.95f
                // 2026-09-19 修复：markVisionRunning(true) 把按钮文字改成「AI…」，
                // 这里必须对称还原成「AI」，否则结束后「AI…」永久残留
                //（真机截图证据：搜索早已 miss 返回，按钮仍显示 AI…）。
                (btn.findViewById<View>(R.id.tv_ai_vision_label) as? TextView)
                    ?.text = "AI"
            }
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

    /**
     * 切换考试模式。
     *
     * @param manual true = 用户经 ⋯ 菜单**手动**开关（跨服务重启存活）；
     *               false = 前台 App **自动**进入/退出（会话级，重启清除）。
     *               2026-09-17 P1：用 KEY_EXAM_MODE_MANUAL 区分，启动时只清自动残留。
     */
    private fun setExamMode(enabled: Boolean, manual: Boolean = false) {
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
            // 手动标志：手动开→true；手动关→false；自动路径保持原值（不改这个键）。
            .putBoolean(KEY_EXAM_MODE_MANUAL, if (manual) examMode else prefs.getBoolean(KEY_EXAM_MODE_MANUAL, false))
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
        // 中间摘要条已移除；相似度在状态行徽章，答案只在正文。
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
        // 相似度已并入标题栏胶囊（2026-09-13 第二轮优化）：status_row 恒隐藏，
        // 不要在此恢复 VISIBLE，否则空行会把卡片撑出一条白带。
        view.findViewById<View>(R.id.status_row)?.visibility = View.GONE
        // AI 联网搜题是**核心功能**（答题搜不出答案时唯一的联网出路），不是低频
        // 装饰入口 —— 考试模式下也必须可见。用户 2026-09-13 报障：驾考 App 触发
        // autoExam 后 AI 按钮消失，正文却还在指路「点右上角 AI 按钮」，
        // 指路指向一个被自己藏起来的按钮。此处显式保活，且严禁再收进 hideIds。
        view.findViewById<View>(R.id.btn_ai_vision)?.visibility = View.VISIBLE
        // 考试态极简：隐藏低频入口，但 AI搜题/眼睛/录入 三键必须常驻
        // （用户 2026-09-13 第三次拍板：删掉关闭，保留这三键）。
        view.findViewById<View>(R.id.btn_hide_overlay)?.visibility = View.VISIBLE
        view.findViewById<View>(R.id.btn_quiz_entry)?.visibility = View.VISIBLE
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
        // 按可用宽度重排标题栏（窄窗让位，AI 优先保位）。放在 chrome 之后，
        // 保证模式切换完成后按最终可见集合重新分配宽度。
        applyTitleBarAdaptive(view)
    }

    /**
     * 标题栏按**可用宽度**自适应。
     *
     * 为什么需要：`defaultOverlaySize()` 用 `(widthPixels*0.52).coerceIn(280,480)`
     * 把 480 当成 **px** 上限，iQOO 1440px/密度3.5 上窗实际只有 137dp，
     * 而标题栏静态需求 193~224dp → 横向溢出，右侧按钮被裁掉（用户截图里
     * AI 联网搜题 + 更多 正好消失，正文却还在指路「点右上角 AI 按钮」）。
     *
     * 用户 2026-09-13 第三次拍板：
     *   · 关闭(✕) 没必要 → 已从布局移除；
     *   · 标题栏只保留 **AI / 眼睛 / 录入题目** 三键，三键都必须常驻；
     *   · AI 按钮过大挤掉相似度胶囊 → 收窄（去图标 + 缩 padding）。
     *
     * 因此这里不再有 close、也不再让眼睛/录入参与让位：三键恒可见。
     * 只有「相似度胶囊」和低频「更多」按剩余宽度伸缩。
     */
    private fun applyTitleBarAdaptive(view: View) {
        val badge = view.findViewById<View>(R.id.tv_similarity_badge)
        val more = view.findViewById<View>(R.id.btn_more)
        val ai = view.findViewById<View>(R.id.btn_ai_vision)
        val eye = view.findViewById<View>(R.id.btn_hide_overlay)
        val entry = view.findViewById<View>(R.id.btn_quiz_entry)
        val region = view.findViewById<View>(R.id.btn_region_entry)

        // 用户指定的三键 + 低频更多：全部常驻，不因宽度让位。
        ai?.visibility = View.VISIBLE
        eye?.visibility = View.VISIBLE
        entry?.visibility = View.VISIBLE
        // 框选识别范围：用户第 5 次反馈要求「加回来」→ 也常驻。
        // （窗口已按新下限放大到约 94% 屏宽，容纳得住第六个按钮。）
        region?.visibility = View.VISIBLE

        // 相似度胶囊在左侧拖动区常驻，不参与让位。
        view.findViewById<View>(R.id.tv_similarity_badge)?.visibility = View.VISIBLE

        // ===== 方案 A（用户 2026-09-15 拍板）：按钮区横向可滑动 =====
        // 原来的宽度预算裁剪逻辑（budget -= ... 按顺序把 ⋯ / 胶囊 GONE 掉）
        // 在引入 HorizontalScrollView 后已成为**有害**逻辑：
        //   - 按钮滑得动，就不该因为「一屏放不下」而隐藏；
        //   - 隐藏反而让用户以为功能没了（用户第 5 次反馈「框选按钮找不到」即此因）。
        // 故此处不再按宽度隐藏任何按钮，溢出部分交给横向滑动。
        more?.visibility = View.VISIBLE

        // ===== 方案 B（用户 2026-09-16 拍板）：空间不足时收拢低频按钮 =====
        // 滑动能解决「按钮被裁」，但**滑动手势是隐式的** —— 用户不知道右边还有东西，
        // 于是仍会认为「框选按钮不见了」（与第 5 次反馈同源）。所以：
        //   够宽 → 全部平铺（最优，零学习成本）；
        //   不够宽 → 把最低频的「框选识别区域」「题库」收进既有 ⋯ 菜单，
        //            给 AI / 眼睛这两个高频键让位。菜单项**本来就有**
        //            （识别区域 / 一键录入），故这是复用而非新建。
        //
        // 阈值走 policy（单一事实源），不在 service 里写死。
        if (TITLE_ACTIONS_SCROLL_ENABLED) {
            applyTitleBarCollapseIfNeeded(view, more, region, entry, ai, eye)
        } else {
            applyTitleBarBudgetLegacy(view, more, badge)
        }
    }

    /**
     * 方案 B：按**实测宽度**决定是否把低频按钮收进 ⋯ 菜单。
     *
     * 判定经 [OverlayGeometryPolicy.titleBarFits]（dp 口径，单一事实源）。
     * 收拢只隐藏**低频两键**（框选 / 题库），AI、眼睛、⋯ 三键恒常驻 ——
     * 它们是用户 2026-09-13 拍板点名保底的功能入口。
     *
     * 代价（如实标注）：收拢后框选/题库需多点一次 ⋯。这是有意的取舍 ——
     * 窄窗下「按钮可见但被裁掉一半」比「多点一次」糟糕得多。
     */
    private fun applyTitleBarCollapseIfNeeded(
        view: View,
        more: View?,
        region: View?,
        entry: View?,
        ai: View?,
        eye: View?,
    ) {
        val dm = resources.displayMetrics
        val d = if (dm.density > 0f) dm.density else 1f

        // 高频三键宽度（dp）：⋯26 + AI40 + 眼睛26。
        // 2026-09-17：数值收进 OverlayGeometryPolicy.TITLE_BAR_HIGH_FREQ_DP（单一事实源）。
        // ⚠️ 仍为估算值，真机（如红米 K80 density 4.0）校准时只改 policy，不动此处。
        val highFreqDp = OverlayGeometryPolicy.TITLE_BAR_HIGH_FREQ_DP
        // 标题栏左右内边距合计（dp）：收进 policy，与高频三键同口径。
        val availPx = (dm.widthPixels - OverlayGeometryPolicy.TITLE_BAR_SIDE_PADDING_DP * d).toInt()

        // 先假定全部平铺，用它判断放不放得下。
        val fullFits = OverlayGeometryPolicy.titleBarFits(availPx, d)

        // 已收拢时的高频部分是否放得下（收拢后宽度需求 = highFreqDp + 余量）。
        val collapsedFits = availPx >= highFreqDp * d

        val shouldCollapse = !fullFits

        if (shouldCollapse && collapsedFits) {
            // 收拢：低频两键进 ⋯ 菜单（菜单项已存在：识别区域 / 一键录入）。
            region?.visibility = View.GONE
            entry?.visibility = View.GONE
            ai?.visibility = View.VISIBLE
            eye?.visibility = View.VISIBLE
            more?.visibility = View.VISIBLE
            logDebug(
                "titlebar.collapse low-freq→more avail=${availPx}px(${availPx / d}dp) " +
                    "need=${OverlayGeometryPolicy.TITLE_BAR_REQUIRED_DP}dp",
            )
        } else if (shouldCollapse) {
            // 极端窄窗：连高频三键都放不下 → 只留 ⋯（菜单里含全部功能，永不丢入口）。
            region?.visibility = View.GONE
            entry?.visibility = View.GONE
            ai?.visibility = View.GONE
            eye?.visibility = View.GONE
            more?.visibility = View.VISIBLE
            logDebug("titlebar.collapse all→more avail=${availPx}px (extremely narrow)")
        } else {
            // 放得下：全部平铺，零学习成本。
            region?.visibility = View.VISIBLE
            entry?.visibility = View.VISIBLE
            ai?.visibility = View.VISIBLE
            eye?.visibility = View.VISIBLE
            more?.visibility = View.VISIBLE
        }
    }

    /** 方案 A 开关：true = 按钮区横向可滑动（不再按宽度隐藏按钮）。 */
    private val TITLE_ACTIONS_SCROLL_ENABLED = true

    /**
     * 历史「宽度预算裁剪」逻辑（方案 A 之前的实现），仅在
     * [TITLE_ACTIONS_SCROLL_ENABLED] = false 时启用，供快速回退。
     */
    private fun applyTitleBarBudgetLegacy(view: View, more: View?, badge: View?) {
        val dm = resources.displayMetrics
        val d = if (dm.density > 0f) dm.density else 1f
        val bar = view.findViewById<View>(R.id.title_bar)
        var availPx = bar?.width ?: 0
        if (availPx <= 0) availPx = defaultOverlaySize().first
        val padPx = (12 + 12) * d
        var budget = availPx - padPx

        val morePx = (26 + 5) * d
        val aiPx = (26 + 4) * d   // 纯「AI」胶囊：9+13+9 文字 + marginEnd4，收窄后约 30dp
        val eyePx = (26 + 3) * d
        val entryPx = (26 + 3) * d
        val regionPx = (26 + 3) * d

        // 1) 三键 + 更多恒占位（用户指定保留，不参与让位）。
        budget -= (aiPx + eyePx + entryPx + regionPx)
        val showMore = budget >= morePx
        more?.visibility = if (showMore) View.VISIBLE else View.GONE
        if (showMore) budget -= morePx
        // 2) 相似度胶囊：此时剩余全部给它，够就正常显示，勉强够就缩窄，实在不够才隐。
        // 注意：只调 maxWidth（配合布局里的 wrap_content + ellipsize=end），
        // 不要写死 layoutParams.width —— 那会把胶囊撑成固定宽度，短文案
        // （如「90%」）反而被拉长，破坏「内容自适应」的观感。
        if (badge is TextView) {
            val minBadge = 22 * d
            when {
                budget < minBadge -> badge.visibility = View.GONE
                else -> {
                    badge.visibility = View.VISIBLE
                    badge.maxWidth = minOf(44 * d, budget).toInt()
                }
            }
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
            // 展开消费点：统一走 flooredExpandedSize()，确保历史小值/WRAP_CONTENT
            // 污染不会让窗口退回小窗（用户「没变化」真因）。
            val (ew, eh) = flooredExpandedSize()
            params.width = ew
            params.height = eh
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
            // P0-1b 反转（2026-09-19 D1）：折叠**一律成功**。
            // 旧逻辑：此刻若有 AI 作答过程/内容（decideOverlayGeometry 返回
            // shouldExpand），双击折叠会被自动弹回展开——用户点折叠没反应。
            // 现改为：折叠方向只看用户意图（forceCollapsed），有内容也折成小窗；
            // 再双击展开时下方 else 分支仍走 decideOverlayGeometry()，会自动
            // 按内容高度撑回（不会丢内容）。这样"有内容也能折"且展开仍可复现。
            params.width = WindowManager.LayoutParams.WRAP_CONTENT
            params.height = WindowManager.LayoutParams.WRAP_CONTENT
        } else {
            // 展开消费点：统一走 decideOverlayGeometry()（与 applyHiddenDotUi 同口径）。
            val decision = decideOverlayGeometry(
                collapsed = false,
                contentNeededH = currentContentNeededHeight(view),
            )
            params.width = decision.width
            params.height = decision.height
            resizeHandle?.visibility = View.VISIBLE
            collapseBtn?.setImageResource(R.drawable.ic_chevron_up)
            container?.visibility = View.VISIBLE
            pill?.visibility = View.GONE
            clampParamsToScreen(params)
            logDebug("overlay.expand reason=" + decision.reason + " applied=" + params.width + "x" + params.height + "px")
        }
        try { wm.updateViewLayout(view, params) } catch (_: Throwable) {}
        // 诊断：记录最终真正生效的窗口尺寸（关于页 → 调试日志可查），
        // 与 overlay.load/default 对照可立刻判断「改了没变化」卡在哪一环。
        logDebug(
            "overlay.apply collapsed=" + overlayCollapsed + " expandedField=" +
                overlayExpandedWidth + "x" + overlayExpandedHeight +
                " applied=" + params.width + "x" + params.height + "px"
        )
        applyClickThroughFlags()
    }

    private var overlayExpandedWidth = 0

    /**
     * 缩放门闸缓存。resizeHandleTouch 每个事件都会被调用，若在函数内新建门闸，
     * 同帧合并状态就会随事件丢失，等于没做合并。
     */
    private var resizeCommitterCache: OverlayLayoutCommitter? = null
    private var resizeCommitterView: View? = null

    private fun resizeCommitter(
        view: View,
        wm: WindowManager,
        params: WindowManager.LayoutParams,
    ): OverlayLayoutCommitter {
        val cached = resizeCommitterCache
        if (cached != null && resizeCommitterView === view) return cached
        val created = OverlayLayoutCommitter(ChoreographerFrameScheduler()) { g ->
            params.x = g.x
            params.y = g.y
            params.width = g.width
            params.height = g.height
            try { wm.updateViewLayout(view, params) } catch (_: Throwable) {}
        }
        resizeCommitterCache = created
        resizeCommitterView = view
        return created
    }

    /**
     * 浮层被触摸期间暂停抓题扫描。由浮层的 touch 分发在按下时置位、抬起时清位。
     * 松手后补一次扫描，避免滑动期间刚好切题被漏掉。
     */
    fun setOwnOverlayInteracting(interacting: Boolean) {
        // 触摸本身就是一次「活动」，无论置位还是清位都要刷新静默计时。
        lastOwnOverlayActivityAt = SystemClock.uptimeMillis()
        if (ownOverlayInteracting == interacting) return
        ownOverlayInteracting = interacting
        if (!interacting) scheduleScanResume(OverlayScanResumePolicy.QUIET_WINDOW_MS)
    }

    /**
     * 浮层内部发生滚动（含抬手后的 fling 惯性）时刷新静默计时。
     *
     * 只看触摸不够：ACTION_UP 之后 ScrollView 还在跑减速动画，
     * 此时开扫会把全树遍历插进动画中段，表现为松手瞬间顿一下。
     */
    fun notifyOwnOverlayScrolled() {
        lastOwnOverlayActivityAt = SystemClock.uptimeMillis()
    }

    /** 静默期结束后才补一次扫描，避免漏掉滑动期间的切题。 */
    private fun scheduleScanResume(delayMs: Long) {
        scanResumeRunnable?.let { mainHandler.removeCallbacks(it) }
        val r = Runnable {
            scanResumeRunnable = null
            if (!isActive) return@Runnable
            val decision = OverlayScanResumePolicy.decide(
                now = SystemClock.uptimeMillis(),
                touchActive = ownOverlayInteracting,
                lastActivityAt = lastOwnOverlayActivityAt,
            )
            when (decision) {
                is OverlayScanResumePolicy.Decision.Resume ->
                    extractAndSend(bestCaptureRoot(null))
                is OverlayScanResumePolicy.Decision.Recheck ->
                    scheduleScanResume(decision.delayMs)
            }
        }
        scanResumeRunnable = r
        mainHandler.postDelayed(r, delayMs)
    }

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
                // 与拖动一致：同帧合并，避免逐采样跨进程布局造成缩放发涩。
                resizeCommitter(view, wm, params).request(
                    OverlayGeometry(params.x, params.y, params.width, params.height),
                )
                true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                resizeCommitter(view, wm, params).flush(
                    OverlayGeometry(params.x, params.y, params.width, params.height),
                )
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
        val dragHandle = view.findViewById<View>(R.id.title_drag_handle)
        val pill = view.findViewById<View>(R.id.collapsed_pill)
        // 用户 2026-09-15 拍板方案 A：标题栏右侧按钮区改为横向可滑动。
        //
        // ## 为什么拖动目标不能再是整个 title_bar
        // 现在 title_bar 内含一个 HorizontalScrollView（btn_more/AI/框选/眼睛/题库）。
        // 若仍把 title_bar 当拖动目标，DOWN 时返回 true 会把横向手势全吃掉，
        // 导致按钮区**永远滑不动**；反之若让 ScrollView 先接，窗口又拖不动。
        // 两者只能二选一，因此把「拖动」收窄到左侧专用热区：
        //   tv_similarity_badge（相似度胶囊）+ title_drag_handle（28dp 死区）
        // 滑动区内不再挂拖动监听 —— 横滑归按钮，拖动归左侧，互不抢。
        //
        // 代价（如实记录）：拖动热区从「整条标题栏」缩小为「左侧约 90dp」。
        // 双击折叠同理，只在拖动区生效；按钮区双击不再折叠。
        // 拖动目标 = 左侧「非滑动区」的全部元素 + 折叠态胶囊：
        //   title_drag_handle（28dp 死区）+ tv_similarity_badge（相似度胶囊）
        //   + collapsed_pill（折叠成小圆点时的整卡，必须还能拖）
        // 显式包含胶囊，是因为 attachDragToTarget 用的是「目标自身」的
        // OnTouchListener（非拦截式）—— 只挂 handle 的话，手指按在胶囊上
        // 不会拖动窗口。前两者都在 ScrollView 之外，不会抢按钮的横滑手势。
        // 兜底：若布局被改回旧版（无 handle），退回整个 titleBar 作拖动目标。
        val badge = view.findViewById<View>(R.id.tv_similarity_badge)
        val dragTargets = if (dragHandle != null || badge != null) {
            listOfNotNull(dragHandle, badge, pill)
        } else {
            listOfNotNull(titleBar, pill)
        }
        val dragRoot = view
        if (dragTargets.isEmpty()) {
            // minimal view fallback
            attachDragToTarget(dragRoot, view, params, wm, slop)
            return
        }
        for (target in dragTargets) {
            attachDragToTarget(dragRoot, target, params, wm, slop)
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
                        // D5（2026-09-19）：拖动不再突变半透明（旧版写死 0.55f，
                        // 与用户自己设的透明度不一致、观感突兀）。改为只轻微降 0.9，
                        // 松手时恢复 loadOverlayOpacity()。
                        root.findViewById<View>(R.id.answer_container)?.alpha = baseAlpha() * 0.9f
                        root.findViewById<View>(R.id.collapsed_pill)?.alpha = baseAlpha() * 0.9f
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
                        // 考试模式拖拽**不写**「正常大窗」持久化（否则污染普通态位置），
                        // 但写入**考试窗自己的**记忆位置：用户把考试窗挪开过，下次应还在这儿。
                        if (examMode) {
                            saveExamPosition(params.x, params.y)
                        } else {
                            saveOverlayPosition(params.x, params.y)
                        }
                    } else {
                        val now = System.currentTimeMillis()
                        // D2+D3+D4（2026-09-19）：双击判据放宽。
                        //  旧版要求「第二次松手仍停在标题区」才折叠，第二次点
                        //  到按钮上就失效；且计时窗口 280ms 偏短、lastTapTime
                        //  是闭包局部（跨 attach 清零）。
                        //  现改为：两次 tap 都发生在标题区（lastTitleTapInTitleArea
                        //  记录上一次）且间隔 < 350ms 才折叠；计时/标记存成员
                        //  字段跨 attach 保留。
                        val isTitleArea = v.id == R.id.title_bar ||
                            v.id == R.id.title_drag_handle ||
                            v.id == R.id.tv_similarity_badge
                        if (isTitleArea && lastTitleTapInTitleArea && now - lastTitleTapTime < 350) {
                            toggleCollapse(root)
                            lastTitleTapTime = 0L
                            lastTitleTapInTitleArea = false
                        } else if (v.id == R.id.collapsed_pill && !wasDragging) {
                            // 单击 pill 展开
                            if (overlayCollapsed) toggleCollapse(root)
                            lastTitleTapTime = now
                            lastTitleTapInTitleArea = false
                        } else {
                            lastTitleTapTime = now
                            lastTitleTapInTitleArea = isTitleArea
                            // 让子按钮还能收到点击：未拖动时不拦截 UP 给 click
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

    /**
     * 标题栏区域按钮状态：
     * - alpha 表示 OCR 识别区域是否已配置（已配置不透明，未配置半透明）
     * - tint 表示题图区域是否已配置（已配置显琥珀色，未配置显常规浅色）
     *
     * 题图区域直接决定图片指纹的区分度：未配置时图片指纹取自整题截图，
     * 「同题干同选项仅题图不同」的题会因 dHash 区分度不足而误配。
     * 这里用颜色把该状态暴露在悬浮窗上，避免用户不知道自己漏配了。
     */
    private fun refreshRegionButtonState(root: View? = accessibilityOverlayView) {
        val btn = root?.findViewById<View>(R.id.btn_area) ?: return
        val hasOcrRegion = loadSavedRegionOnly() != null || screenRegion != null
        btn.alpha = if (hasOcrRegion) 0.95f else 0.62f

        val hasImageRegion = loadImageRegion() != null
        (btn as? ImageButton)?.setColorFilter(
            if (hasImageRegion) 0xFFFBBF24.toInt() else 0xFFF8FAFC.toInt()
        )
        btn.contentDescription = when {
            hasImageRegion && hasOcrRegion -> "设置识别区域（识别区域、题图区域均已配置）"
            hasImageRegion -> "设置识别区域（题图区域已配置，识别区域未配置）"
            hasOcrRegion -> "设置识别区域（识别区域已配置，题图区域未配置）"
            else -> "设置识别区域（识别区域、题图区域均未配置）"
        }
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
            val imgSet = loadImageRegion() != null
            popup.menu.add(0, 6, 5, if (imgSet) "重设题图区域…" else "框选题图区域…")
            if (imgSet) popup.menu.add(0, 7, 6, "清除题图区域")
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
                    6 -> {
                        // 框选题图区域
                        regionMode = "image"
                        enterRegionMode()
                        true
                    }
                    7 -> {
                        // 清除题图区域
                        imageRegion = null
                        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                        prefs.remove(KEY_IMAGE_REGION)
                        val pkg = lastForegroundPkg
                        if (pkg.isNotBlank()) prefs.remove("${KEY_IMAGE_REGION}_$pkg")
                        prefs.apply()
                        toast("题图区域已清除")
                        // C1: 清除后立即刷新按钮颜色（琥珀→白）
                        mainHandler.post { refreshRegionButtonState() }
                        true
                    }
                    else -> false
                }
            }
            popup.show()
        } catch (e: Throwable) {
            Log.w(TAG, "showRegionQuickMenu failed", e)
            pendingProbeAfterRegion = "answer"
            regionMode = "ocr"
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
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
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

        // 题图模式：面板文案/按钮按用途自适应，避免和 OCR 识别区域混淆。
        val isImageMode = regionMode == "image"
        view.findViewById<TextView>(R.id.tv_region_hint)?.text = if (isImageMode) {
            "框选「题图区域」：只框住题目里的图片本身，不要包含题干和选项文字，" +
                "否则文字会稀释图片指纹，导致同题干不同题图被误判为同一题。"
        } else {
            "框选「识别区域」：包含题干和选项的范围，用于取题和 OCR。"
        }
        (view.findViewById<View>(R.id.btn_region_save) as? android.widget.Button)?.text =
            if (isImageMode) "保存题图区域" else "保存"
        // 题图模式下试捕/OCR试识/搜题都不适用，隐藏避免误触。
        view.findViewById<View>(R.id.btn_region_probe)?.visibility =
            if (isImageMode) View.GONE else View.VISIBLE
        view.findViewById<View>(R.id.btn_region_ocr)?.visibility =
            if (isImageMode) View.GONE else View.VISIBLE

        // 优先当前前台 App 专属区域，否则全局/默认上 55%
        val pkg = lastForegroundPkg.ifBlank { null }
        val initial = if (isImageMode) {
            loadImageRegion()
        } else {
            (pkg?.let { loadRegionForPackage(it) }) ?: loadRegion()
        }
        if (initial != null) {
            selector?.setRegion(initial)
        } else if (isImageMode) {
            // 题图常见位置：题干下方居中偏上的一块，给个比 OCR 区更小的起始框。
            selector?.applyPreset(0.12f, 0.22f, 0.88f, 0.55f)
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
            // 题图模式：仅保存，不触发任何探测
            if (regionMode == "image") {
                regionMode = "ocr"
                pendingProbeAfterRegion = null
                exitRegionMode()
                return@setOnClickListener
            }
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
            if (regionMode == "image") {
                regionMode = "ocr"
                pendingProbeAfterRegion = null
                exitRegionMode()
                return@setOnRegionConfirmedListener
            }
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
            val last = if (regionMode == "image") loadImageRegion() else loadSavedRegionOnly()
            if (last != null) {
                selector?.setRegion(last)
                toast(if (regionMode == "image") "已恢复上次题图区域" else "已恢复上次区域")
            } else {
                toast(if (regionMode == "image") "尚无已保存题图区域" else "尚无已保存区域")
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

        // 两次尝试的差异只在 params，重试/失败恢复的判定交给
        // RegionWindowAttachPolicy（可单测），这里只负责真实的 addView 副作用。
        val attempts = sequenceOf(
            {
                // 尝试 1：正常参数（无 FLAG_LAYOUT_IN_SCREEN）
            },
            {
                // 尝试 2：加 FLAG_LAYOUT_IN_SCREEN + cutout mode（兼容部分需要全屏的 ROM）
                params.flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    params.layoutInDisplayCutoutMode =
                        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                }
            },
        ).mapIndexed { i, prepare ->
            try {
                prepare()
                wm.addView(view, params)
                RegionWindowAttachPolicy.AttemptResult.Success
            } catch (e: Throwable) {
                val err = "${e.javaClass.simpleName}: ${e.message}"
                Log.w(TAG, "region window addView attempt ${i + 1} failed: $err", e)
                try { wm.removeView(view) } catch (_: Throwable) {}
                RegionWindowAttachPolicy.AttemptResult.Failure(err)
            }
        }

        val outcome = RegionWindowAttachPolicy.attach(attempts)
        if (outcome is RegionWindowAttachPolicy.Outcome.Attached) {
            if (outcome.attempt > 1) {
                Log.i(TAG, "region window add succeeded with FLAG_LAYOUT_IN_SCREEN retry")
            }
            regionWindowView = view
            regionWindowParams = params
        } else {
            val lastError = (outcome as RegionWindowAttachPolicy.Outcome.Failed).lastError
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
        // 题图模式：只写题图区域，不污染 OCR 识别区域
        if (regionMode == "image") {
            saveImageRegion(region)
            if (showToast) toast("题图区域已保存")
            // C1: 题图区域保存后立即刷新按钮颜色指示
            mainHandler.post { refreshRegionButtonState() }
            return
        }
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
        root.findViewById<View>(R.id.btn_probe_copy)?.setOnClickListener {
            copyProbePanelToClipboard(title, body)
        }
    }

    /**
     * 复制框选页试捕面板结果。
     *
     * 面板只有预览文本，没有解析后的题干/选项，所以这里把去前缀后的
     * 可搜文本作为「读屏原文」，其余段落留空并如实标注，避免复制出
     * 看起来完整但其实没有解析结果的假快照。
     */
    private fun copyProbePanelToClipboard(title: String, body: String) {
        val payload = QuizProbeCopyFormatter.build(
            status = title,
            raw = lastProbeSearchText.ifBlank { body },
            question = "",
            options = "",
            answer = "",
            analysis = "",
            timestamp = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US)
                .format(java.util.Date()),
        )
        try {
            val cm = getSystemService(Context.CLIPBOARD_SERVICE)
                as android.content.ClipboardManager
            cm.setPrimaryClip(android.content.ClipData.newPlainText("box-probe", payload))
            toast("已复制试捕结果")
        } catch (e: Throwable) {
            Log.w(TAG, "copy probe panel failed", e)
            toast("复制失败：${e.message ?: e.javaClass.simpleName}")
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

    /**
     * 把原生侧诊断写入 Flutter 调试日志库（LogChannel.quiz）。
     *
     * 为什么需要它：悬浮窗尺寸/dp 计算全在原生侧，而用户能看到的调试日志
     * （抽屉→更多→调试日志）在 Flutter 侧。用户 2026-09-13 反复反馈
     * 「悬浮窗大小没有变化」，没有原生真实 density/取值就无法判断是
     * 迁移没命中、还是设备密度假设错了 —— 这里把事实直接送进日志。
     */
    private fun logDebug(message: String) {
        try {
            resolveChannel()?.invokeMethod("nativeDebugLog", mapOf("message" to message))
        } catch (_: Throwable) {
            // 日志失败绝不影响主流程
        }
    }

    private fun loadOverlayPosition(): Pair<Int, Int> {
        val (w, h) = loadOverlaySize()
        return loadOverlayPosition(w, h)
    }

    /**
     * 悬浮窗几何**一行式快照**（P1-2），把报障定位从「猜」变成「读一行」。
     *
     * ## 为什么需要
     *
     * 用户 2026-09-13 起连续五次报尺寸问题，每次都要来回追问：机型？折叠态？
     * prefs 里的值？实际生效值？是否被下限夹过？—— 因为这些信息分散在
     * 8 个写点里，没有任何一处能一次说清。
     *
     * 本函数把这些全部拼成一行，在每次决策后由 [logDebug] 打进既有的
     * 「调试日志」页（无 adb 的普通用户可直接复制），**不新建悬浮按钮**。
     *
     * 典型输出：
     * `geom snapshot | screen=1080x2400 d=2.75 | collapsed=false exam=false |
     *  floor=825x1200 | saved=825x1620 | applied=825x1620 | contentNeed=1480`
     *
     * @param decision 本次决策（可空 = 只快照当前状态）
     * @param contentNeededH 内容需要高度，便于判断是否该继续长高
     */
    private fun describeGeometry(
        decision: OverlayGeometryPolicy.Decision? = null,
        contentNeededH: Int = 0,
    ): String {
        val dm = resources.displayMetrics
        val (floorW, floorH) = overlaySizeFloor()
        val applied = overlayParams?.let { it.width.toString() + "x" + it.height } ?: "null"
        val sb = StringBuilder()
        sb.append("geom snapshot | screen=").append(dm.widthPixels).append('x').append(dm.heightPixels)
        sb.append(" d=").append(dm.density)
        sb.append(" | collapsed=").append(overlayCollapsed)
        sb.append(" exam=").append(examMode)
        sb.append(" answerOnly=").append(answerOnlyMode)
        sb.append(" | floor=").append(floorW).append('x').append(floorH)
        sb.append(" | saved=").append(overlayExpandedWidth).append('x').append(overlayExpandedHeight)
        sb.append(" | applied=").append(applied)
        if (decision != null) {
            sb.append(" | decision=").append(decision.width).append('x').append(decision.height)
            sb.append(" reason=").append(decision.reason)
            if (decision.shouldExpand) sb.append(" shouldExpand=true")
        }
        if (contentNeededH > 0) sb.append(" | contentNeed=").append(contentNeededH)
        return sb.toString()
    }

    /**
     * 组装 [OverlayGeometryPolicy.Input] 并调用唯一权威决策（P0-1b 的收口点）。
     *
     * 所有需要「窗口该多大 / 该不该自动展开」的地方都走这里，
     * 不再各自 `coerceIn` —— 这是「同一现象五连报」的结构性修复。
     *
     * @param contentNeededH 内容需要的高度（px）；0 表示无内容需求。
     */
    private fun decideOverlayGeometry(
        savedW: Int? = null,
        savedH: Int? = null,
        collapsed: Boolean = overlayCollapsed,
        contentNeededH: Int = 0,
    ): OverlayGeometryPolicy.Decision {
        val dm = resources.displayMetrics
        val (examW, examH) = if (examMode) examOverlayDimensions() else (0 to 0)
        val decision = OverlayGeometryPolicy.decide(
            OverlayGeometryPolicy.Input(
                screenW = dm.widthPixels,
                screenH = dm.heightPixels,
                density = dm.density,
                savedW = savedW,
                savedH = savedH,
                collapsed = collapsed,
                examMode = examMode,
                examW = examW,
                examH = examH,
                contentNeededH = contentNeededH,
            )
        )
        // 每次决策都留一行完整快照：下次报障只需用户复制这一行。
        logDebug(describeGeometry(decision, contentNeededH))
        return decision
    }

    /**
     * 大窗默认尺寸（px）。
     *
     * P0-1b：公式已迁到 [OverlayGeometryPolicy.defaultSize]（单一事实源），
     * 这里只做委托与日志 —— 保留本函数是因为历史调用点很多，改动调用点风险更大。
     */
    private fun defaultOverlaySize(): Pair<Int, Int> {
        val dm = resources.displayMetrics
        val (wPx, hPx) = OverlayGeometryPolicy.defaultSize(
            dm.widthPixels, dm.heightPixels, dm.density,
        )
        logDebug(
            "overlay.default screen=" + dm.widthPixels + "x" + dm.heightPixels + "px " +
                "density=" + dm.density + " -> " + wPx + "x" + hPx + "px " +
                "(" + (wPx / dm.density).toInt() + "x" + (hPx / dm.density).toInt() + "dp)"
        )
        return wPx to hPx
    }

    /**
     * 悬浮窗「大窗下限」的**单一事实源**：(floorW, floorH)，单位 px。
     *
     * P0-1b：公式已迁到 [OverlayGeometryPolicy.floorSize]，这里只做委托。
     * 历史教训（保留原文以免回退）：下限逻辑一旦散落多处（loadOverlaySize 一套、
     * 展开路径另一套），就会出现「改了 prefs 下限却没变化」——因为渲染走的是另一条路。
     */
    private fun overlaySizeFloor(): Pair<Int, Int> {
        val dm = resources.displayMetrics
        return OverlayGeometryPolicy.floorSize(dm.widthPixels, dm.heightPixels, dm.density)
    }

    /**
     * 产出**已施加下限**的展开尺寸。
     *
     * 真因：`overlayExpandedWidth/Height` 是与 prefs 脱钩的内存字段，折叠/恢复等场景
     * 会把当时的（可能很小的、甚至是 WRAP_CONTENT 的）尺寸捕获进去，展开时又原样
     * 消费 → 窗口永远回不到大窗，用户看到的仍是「没变化」。所有展开路径都必须走这里。
     */
    private fun flooredExpandedSize(): Pair<Int, Int> {
        val dm = resources.displayMetrics
        val (floorW, floorH) = overlaySizeFloor()
        return OverlayGeometryPolicy.expandedSize(
            OverlayGeometryPolicy.Input(
                screenW = dm.widthPixels,
                screenH = dm.heightPixels,
                density = dm.density,
                savedW = if (overlayExpandedWidth > 0) overlayExpandedWidth else null,
                savedH = if (overlayExpandedHeight > 0) overlayExpandedHeight else null,
            ),
            floorW,
            floorH,
        )
    }

    private fun saveOverlayPosition(x: Int, y: Int) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString(KEY_OVERLAY_GEOMETRY, "$x,$y")
            .apply()
    }

    /**
     * 考试窗位置独立持久化。
     *
     * 2026-09-16 P1-1：此前考试窗位置**硬编码右上角**，用户拖走后下次进入必被弹回；
     * 而普通模式位置有记忆 → 同一件事两套口径。现改为独立记忆键：
     * 与普通模式位置互不污染（考试窗尺寸/位置本就与普通大窗是两套语义）。
     */
    private fun saveExamPosition(x: Int, y: Int) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString(KEY_EXAM_GEOMETRY, "$x,$y")
            .apply()
    }

    /** 读取考试窗记忆位置；无记录返回 null → policy 回退右上锚点。 */
    private fun loadExamPosition(): String? =
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_EXAM_GEOMETRY, null)

    private fun loadOverlaySize(): Pair<Int, Int> {
        val dm = resources.displayMetrics
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString("${KEY_OVERLAY_GEOMETRY}_size", null)
        // 大窗下限：用户 2026-09-13 起连续五次反馈「悬浮窗太小 / 还很拥挤 /
        // 扩大 1.5 倍 / 大小没有变化 / 还是没有变化」。
        //
        // 历史教训（务必别回退成一次性 schema 迁移）：
        //   v4/v5/v6 都是「schema < N 时改一次并置位」的一次性迁移。一次性
        //   迁移有三个致命缺陷：①升级后只要跑过一次就再也不生效（用户下一次
        //   反馈时它已经作废）；②它改的是「已保存值 ×1.5」，若保存值本身就
        //   很小，乘完依然很小；③用户手拖过窗口后保存值会把它盖掉。
        //   结果就是用户反复报「没有变化」。
        //
        // 现方案：改成**每次启动无条件施加的 dp 下限**（不是一次性迁移）。
        //   用户保存的尺寸仍被尊重（比下限大就用手拖的值），但只要比下限小，
        //   就会被抬到下限。这样无论 prefs 里躺着什么历史值、无论升级多少次，
        //   窗口都不会再退回小窗。用户想变小仍可用右下角手柄拖动（拖动值若
        //   大于下限则保留）。
        val minW = (OVERLAY_MIN_WIDTH_DP * dm.density).toInt()
        val minH = (OVERLAY_MIN_HEIGHT_DP * dm.density).toInt()
        // 大窗下限：走单一事实源 overlaySizeFloor()。
        val (floorW, floorH) = overlaySizeFloor()
        logDebug(
            "overlay.load raw=" + raw + " schema=" +
                prefs.getInt(KEY_OVERLAY_SIZE_SCHEMA, 0) + " compactMigrated=" +
                prefs.getBoolean(KEY_OVERLAY_COMPACT_MIGRATED, false) +
                " density=" + dm.density +
                " screen=" + dm.widthPixels + "x" + dm.heightPixels + "px" +
                " floor=" + floorW + "x" + floorH + "px (" +
                (floorW / dm.density).toInt() + "x" + (floorH / dm.density).toInt() + "dp)"
        )
        if (raw != null) {
            // 2026-09-19 紧凑迁移（schema v8）：0.80 新默认（ab80376）长期被旧 SAVED
            // 尺寸顶住（Reason.SAVED 优先级高于 Reason.DEFAULT，新默认永远轮不到），
            // 且 254 的 floor 抬升会把抬升值写回 prefs 永久固化。低于 v8 的历史
            // 保存值清除一次让新默认落地；此后用户手拖照常记忆（schema ≥ 8 不再清）。
            val savedSchema = prefs.getInt(KEY_OVERLAY_SIZE_SCHEMA, 0)
            if (OverlayGeometryPolicy.shouldDropSavedSizeForCompact(savedSchema)) {
                logDebug(
                    "overlay.compact-migrate drop saved=$raw schema=$savedSchema" +
                        " -> default(" + (floorW / dm.density).toInt() + "x" +
                        (floorH / dm.density).toInt() + "dp)"
                )
                prefs.edit()
                    .remove("${KEY_OVERLAY_GEOMETRY}_size")
                    .putInt(KEY_OVERLAY_SIZE_SCHEMA, OverlayGeometryPolicy.COMPACT_SIZE_SCHEMA)
                    .apply()
                logDebug("overlay.result(no-prefs) " + floorW + "x" + floorH + "px (" +
                    (floorW / dm.density).toInt() + "x" + (floorH / dm.density).toInt() + "dp)")
                return floorW to floorH
            }
            val p = raw.split(',').mapNotNull { it.toIntOrNull() }
            if (p.size >= 2) {
                var w = p[0].coerceIn(minW, dm.widthPixels)
                var h = p[1].coerceIn(minH, dm.heightPixels)
                // 若保存值小于大窗下限 → 抬到下限（真机上报「没变化」的正面修复）。
                if (w < floorW || h < floorH) {
                    logDebug("overlay.floor raise " + w + "x" + h + " -> " + floorW + "x" + floorH)
                    w = w.coerceAtLeast(floorW)
                    h = h.coerceAtLeast(floorH)
                    prefs.edit()
                        .putInt(KEY_OVERLAY_SIZE_SCHEMA, OverlayGeometryPolicy.COMPACT_SIZE_SCHEMA)
                        .putString("${KEY_OVERLAY_GEOMETRY}_size", "$w,$h")
                        .apply()
                }
                logDebug("overlay.result " + w + "x" + h + "px (" +
                    (w / dm.density).toInt() + "x" + (h / dm.density).toInt() + "dp)")
                return w to h
            }
        }
        logDebug("overlay.result(no-prefs) " + floorW + "x" + floorH + "px (" +
            (floorW / dm.density).toInt() + "x" + (floorH / dm.density).toInt() + "dp)")
        return floorW to floorH
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

    /**
     * 当前内容**实际需要**的高度（px），供 [decideOverlayGeometry] 决策。
     *
     * ## 为什么不用 `answer.height`（P1-1 的根因）
     *
     * 原先 `ensureAnswerOverlayFitsContent` 用 `answer.height` 求和，但那是
     * ScrollView 在**窗口被夹过之后**的高度 —— 是滞后测量：窗口小 → 测得小 →
     * 决定不长大 → 窗口还是小，形成死锁，用户永远看不到「长大」。
     * 这里改用**内容固有高度**（`measuredHeight` 兜底 `height`），并显式加上
     * 过程框需要的高度，避免滞后。
     *
     * @return 内容需要的高度（px）；无内容需求返回 0。
     */
    private fun currentContentNeededHeight(view: View): Int {
        // 注意：这里**不再**因 examMode 直接 return 0。
        // 旧版 `if (examMode || answerOnlyMode) return 0` 与真机观察矛盾：用户截图里
        // 考试小窗的文字被底边裁断（说明内容确实有高度需求，只是没被计入）。
        // answerOnlyMode 早期退出同理 —— 仅答案模式下答案文本依然需要高度。
        // 保留一个真正的空数据守卫即可：无内容时返回 0。
        val answer = view.findViewById<View>(R.id.scroll_answer)
        val processBox = view.findViewById<View>(R.id.ai_process_box)
        val hasProcess = hasPendingAiProcess(view)
        if (answer == null && !hasProcess) return 0

        // 标题栏 + 答案区 + 过程区 + 内边距，逐块用固有高度累加。
        val titleBar = view.findViewById<View>(R.id.title_bar)
        var total = 0
        total += intrinsicHeight(titleBar)
        total += intrinsicHeight(answer)
        if (hasProcess) total += intrinsicHeight(processBox)
        // 竖向 padding + 区块间距余量（避免刚好差几 px 又被裁一行）。
        total += (OVERLAY_VERTICAL_SLACK_DP * resources.displayMetrics.density).toInt()
        return total.coerceAtLeast(0)
    }

    /**
     * 取视图的**固有高度**（px）——优先 `measuredHeight`，退回 `height`。
     *
     * 不用 `height` 优先，是因为窗口被夹时 `height` 会跟着缩水，
     * 用它做决策会形成「越小越不涨」的死锁（P1-1）。
     */
    private fun intrinsicHeight(v: View?): Int {
        if (v == null || v.visibility == View.GONE) return 0
        return if (v.measuredHeight > 0) v.measuredHeight else v.height.coerceAtLeast(0)
    }

    /**
     * 折叠态下判断是否该自动展开：折叠是用户选择，不能一见内容就弹开，
     * 但过程框一旦有可见内容且窗口是 WRAP_CONTENT 窄条，就必然被裁 →
     * 这时才展开。与 updateAiProcess 的 box 可见性同口径（单一事实源）。
     */
    private fun hasPendingAiProcess(view: View): Boolean {
        val box = view.findViewById<View>(R.id.ai_process_box) ?: return false
        if (box.visibility != View.VISIBLE) return false
        // CharSequence?.orEmpty() 不存在（.trim() 后仍是 CharSequence）→ 先 toString()。
        val text = view.findViewById<TextView>(R.id.tv_ai_process)?.text?.toString()?.trim().orEmpty()
        return text.isNotEmpty()
    }

    /**
     * 构建 miss 态正文（纯函数，可单测调用，不依赖 View）。
     *
     * @param rawAnswer 去掉 SIM marker 后的 overlayAnswers 文本（已 trim）。
     * @return 应展示在 tv_answer 的内容：
     *   - 空 / 仅"未命中" → 兜底句「未搜到答案。点右上角紫色 AI 按钮…」
     *   - 首行已含完整 hint（endsWith 或 contains 后缀）→ 直接展示首行，
     *     **不**再追加后缀（2026-09-18 去重：Dart 侧 visionMissHint 推送的
     *     就是完整 hint 句，旧逻辑会拼成「完整句 + 换行 + 后半句」造成
     *     紫色首行与黑色正文视觉重复）。
     *   - 其他内容 → "首行 + 空行 + 指路后缀"。
     */
    @JvmOverloads
    fun buildMissDisplayAnswer(rawAnswer: String): String =
        missDisplayAnswer(rawAnswer)

    private fun ensureAnswerOverlayFitsContent(view: View) {
        if (examMode || answerOnlyMode) return
        // ⚠️ 用户 2026-09-15 反馈「答题悬浮窗还是没有变化，ai搜题显示也没有优化」。
        // 原先这里对 overlayCollapsed 也直接 return → 折叠态下按内容自适应**完全不跑**，
        // 窗口保持 WRAP_CONTENT，AI 过程框只能显示一行（用户看到的就是「没优化」）。
        // 折叠是用户主动选择，不该被无声取消；但**内容确实需要按需增高**时，
        // 说明用户正在看新一轮结果 → 先退出折叠态，再正常走自适应。
        if (overlayCollapsed) {
            val needsMore = hasPendingAiProcess(view)
            if (!needsMore) return
            logDebug("ensureFits: expand from collapsed (content needs full height)")
            toggleCollapse(view)
        }
        val answer = view.findViewById<View>(R.id.scroll_answer) ?: return
        // ⚠️ 历史坑（用户 2026-09-14 报障「ai搜题这个显示咋只有一半，我看不完全」
        // 的真因）：旧实现写成 `needed = title + status + divider + question +
        // answer.height`，**完全没算下方 ai_process_box**。于是 AI 作答过程一出现，
        // 它就落在窗口底边之外被裁掉 —— 用户只能看到一半。
        //
        // P1-1 修复：改用 currentContentNeededHeight()（固有高度，非滞后 height）
        // 并统一走 OverlayGeometryPolicy.decide()，同时**允许收敛**（此前是
        // `if (needed > current.height)` 单向棘轮：窗口一旦被夹小，测得的
        // 内容高度也跟着小，于是永远不涨 —— 用户看到「没变化」的死锁）。
        answer.post {
            val current = overlayParams ?: return@post
            val needed = currentContentNeededHeight(view)
            if (needed <= 0) return@post
            val decision = decideOverlayGeometry(
                collapsed = false,
                contentNeededH = needed,
            )
            val targetH = decision.height
            // 收敛：过高过低都调（下限由 policy 保证），不再只增不减。
            if (targetH != current.height || decision.width != current.width) {
                current.width = decision.width
                current.height = targetH
                clampParamsToScreen(current)
                if (!examMode) {
                    overlayExpandedWidth = current.width
                    overlayExpandedHeight = current.height
                }
                try { windowManager?.updateViewLayout(view, current) } catch (_: Throwable) {}
                // 诊断：把「决定」与「实际生效」都打出来，报障时一眼定位。
                logDebug(
                    "ensureFits reason=" + decision.reason + " needed=" + needed +
                        " target=" + decision.width + "x" + targetH +
                        " applied=" + current.width + "x" + current.height + "px"
                )
            }
        }
    }

    private fun updateAccessibilityOverlayView() {
        val view = accessibilityOverlayView ?: return
        val qTv = view.findViewById<TextView>(R.id.tv_question)
        val aTv = view.findViewById<TextView>(R.id.tv_answer)
        val status = view.findViewById<View>(R.id.status_bar)
        val pillLabel = view.findViewById<TextView>(R.id.tv_pill_label)
        // 相似度徽章已从标题栏迁到状态行（2026-09-13），不再与功能按钮抢宽度。
        val title = view.findViewById<TextView>(R.id.tv_similarity_badge)

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
            overlayStatus == "miss" -> buildMissDisplayAnswer(a)
            overlayStatus == "ambiguous" -> a.ifBlank { "存在多个候选，请手动确认" }
            else -> compactAnswerForExam(a, includeSimilarity = false)
        }
        qTv?.text = q
        // A3 占位弱化（2026-09-19）：无真实题时（占位文案）整行半透明 + 灰色，
        // 与真实题干（全不透明 + 深色）在视觉上区分「还没出题 / 已出题」。
        // 占位判定复用 updateAccessibilityOverlayView 本地的 q 常量兜底值。
        val isPlaceholderQuestion = overlayQuestion.isBlank()
        qTv?.alpha = if (isPlaceholderQuestion) 0.55f else 1.0f
        qTv?.setTextColor(if (isPlaceholderQuestion) 0xFF94A3B8.toInt() else 0xFF101828.toInt())
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
            "ambiguous" -> 0xFFF59E0B.toInt()
            "hit" -> 0xFF22C55E.toInt()
            else -> themeColor
        }
        status?.setBackgroundColor(color)

        val key = overlayAnswerKey
        val sim = overlaySimilarity ?: simFromMarker ?: extractSimilarity(a)

        // 相似度胶囊现内联在标题栏（2026-09-13 第二轮优化：原独立 status_row
        // 白底+蓝条横贯整卡视觉割裂）。配色与 Dart 侧 similarityPillColor 同口径：
        // 绿=命中 / 琥珀=检索中 / 灰=未命中。改一处需改两处。
        // 命中态（hit）无相似度（AI 读屏 confidence=0）时绝不能落「未命中」，
        // 否则会正文「答案：C」紫色命中 + 徽章「未命中」灰 的自相矛盾（2026-09-18 截图）。
        val (badgeText, badgeColor) = badgeState(
            isSearchingNow = isSearchingNow,
            status = overlayStatus,
            matchCount = overlayMatchCount,
            matchIndex = overlayMatchIndex,
            sim = sim,
        )
        title?.text = badgeText
        title?.backgroundTintList = android.content.res.ColorStateList.valueOf(badgeColor)
        // 多匹配的切换仍可从正文长按/更多入口完成；相似度标签仅承担状态展示。
        title?.setOnClickListener(null)
        view.findViewById<View>(R.id.answer_container)?.alpha = loadOverlayOpacity()
        // B4 合成提示（2026-09-19）：elevation 阴影 + 圆角背景交给 GPU 硬件层合成，
        // 国产 ROM 上滚动/重排时阴影重绘更顺。视图未失效时系统直接复用层级位图。
        // LAYER_TYPE_NONE 还原默认行为（调透明度动画等场景不再需要时可改回）。
        view.findViewById<View>(R.id.answer_container)?.setLayerType(View.LAYER_TYPE_HARDWARE, null)
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
    /**
     * 用题图区域（imageRegion）截图，仅裁题图部分，用于 dHash 消歧。
     * 题图区域未配置时回传 null（Flutter 侧降级跳过图片筛选）。
     */
    fun captureImageRegionScreenshotWithRequestId(
        requestId: Int,
        callback: (ByteArray?) -> Unit,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) { callback(null); return }
        imageRegion = imageRegion ?: loadImageRegion()
        val region = imageRegion
        if (region == null || region.isEmpty) { callback(null); return }

        Companion.currentRequestId = requestId
        try {
            takeScreenshot(
                android.view.Display.DEFAULT_DISPLAY,
                { it.run() },
                object : AccessibilityService.TakeScreenshotCallback {
                    override fun onSuccess(screenshot: AccessibilityService.ScreenshotResult) {
                        val bytes = runCatching { encodePngWithRegion(screenshot, region) }.getOrNull()
                        try { screenshot.hardwareBuffer.close() } catch (_: Throwable) {}
                        if (Companion.currentRequestId == requestId) callback(bytes)
                    }
                    override fun onFailure(errorCode: Int) {
                        Log.w(TAG, "captureImageRegion failed code=$errorCode")
                        if (Companion.currentRequestId == requestId) callback(null)
                    }
                }
            )
        } catch (e: Throwable) {
            Log.w(TAG, "captureImageRegion exception", e)
            if (Companion.currentRequestId == requestId) callback(null)
        }
    }

    /** 截全屏后按指定 region 裁剪并编码为 PNG。 */
    private fun encodePngWithRegion(screenshot: ScreenshotResult, region: RectF): ByteArray? {
        val buffer = screenshot.hardwareBuffer
        val full = Bitmap.wrapHardwareBuffer(buffer, screenshot.colorSpace) ?: return null
        val software = full.copy(Bitmap.Config.ARGB_8888, false) ?: return null
        full.recycle()
        val left = region.left.toInt().coerceIn(0, software.width - 1)
        val top = region.top.toInt().coerceIn(0, software.height - 1)
        val right = region.right.toInt().coerceIn(left + 1, software.width)
        val bottom = region.bottom.toInt().coerceIn(top + 1, software.height)
        val cropped = Bitmap.createBitmap(software, left, top, right - left, bottom - top)
        val out = ByteArrayOutputStream()
        cropped.compress(Bitmap.CompressFormat.PNG, 100, out)
        if (cropped !== software) cropped.recycle()
        software.recycle()
        return out.toByteArray()
    }

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

    /**
     * 计算题图的 dHash（差异哈希）。
     *
     * 算法：
     * 1. 缩放到 9×8（宽 9，高 8）
     * 2. 转灰度
     * 3. 每行比较左右相邻像素：左 > 右则 bit=1，否则 bit=0
     * 4. 8 行 × 8 比较 = 64 位 → 16 字符 hex
     */
    fun computeDHash(pngBytes: ByteArray): String? {
        if (pngBytes.isEmpty()) return null
        val original = android.graphics.BitmapFactory.decodeByteArray(pngBytes, 0, pngBytes.size)
            ?: return null
        if (original.width < 2 || original.height < 2) {
            original.recycle()
            return null
        }
        // 缩放到 9×8
        val resized = Bitmap.createScaledBitmap(original, 9, 8, true)
        original.recycle()
        // 转灰度
        val gray = Bitmap.createBitmap(9, 8, Bitmap.Config.ARGB_8888)
        val paint = Paint()
        val canvas = Canvas(gray)
        canvas.drawBitmap(resized, 0f, 0f, paint)
        resized.recycle()
        // 计算哈希
        val sb = StringBuilder()
        for (y in 0 until 8) {
            for (x in 0 until 8) {
                val left = Color.red(gray.getPixel(x, y)) * 0.299 +
                    Color.green(gray.getPixel(x, y)) * 0.587 +
                    Color.blue(gray.getPixel(x, y)) * 0.114
                val right = Color.red(gray.getPixel(x + 1, y)) * 0.299 +
                    Color.green(gray.getPixel(x + 1, y)) * 0.587 +
                    Color.blue(gray.getPixel(x + 1, y)) * 0.114
                sb.append(if (left > right) '1' else '0')
            }
        }
        gray.recycle()
        // 转为 16 字符 hex
        val hash = sb.toString()
        val result = StringBuilder()
        for (i in 0 until 16) {
            val nibble = hash.substring(i * 4, (i + 1) * 4).toInt(2)
            result.append(String.format("%01x", nibble))
        }
        return result.toString()
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
            ?: getSharedPreferences("top.hpa888.box_preferences", Context.MODE_PRIVATE)
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

    /** 保存题图区域（独立于 OCR 识别区域），同样按前台包记忆。 */
    private fun saveImageRegion(region: RectF) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
        val raw = "${region.left},${region.top},${region.right},${region.bottom}"
        prefs.putString(KEY_IMAGE_REGION, raw)
        val pkg = lastForegroundPkg
        if (pkg.isNotBlank() && pkg != packageName && !pkg.startsWith("com.android")) {
            prefs.putString("${KEY_IMAGE_REGION}_$pkg", raw)
        }
        prefs.apply()
        imageRegion = region
    }

    private fun parseRegionRaw(raw: String?): RectF? {
        if (raw == null) return null
        val parts = raw.split(',').mapNotNull { it.toFloatOrNull() }
        if (parts.size != 4) return null
        val rect = RectF(parts[0], parts[1], parts[2], parts[3])
        return if (rect.isEmpty) null else rect
    }

    /** 读取题图区域：优先当前前台包专属，回退全局。 */
    private fun loadImageRegion(): RectF? {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val pkg = lastForegroundPkg
        if (pkg.isNotBlank() && pkg != packageName) {
            parseRegionRaw(prefs.getString("${KEY_IMAGE_REGION}_$pkg", null))?.let { return it }
        }
        return parseRegionRaw(prefs.getString(KEY_IMAGE_REGION, null))
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

/**
 * miss 态悬浮窗正文拼接（纯函数，可单测，不依赖 Service 实例）。
 *
 * 根因（2026-09-18 用户截图定位）：
 * Dart 侧 [visionMissHint] 推送的是完整句「未搜到答案。点右上角紫色 AI 按钮…」，
 * 旧内联逻辑走 else 分支拼成「完整句 + \n\n + 后半句」，
 * [applyAnswerStyle] 又把首行（含「答案」二字）染成主题色加粗，
 * 黑色后半行保留默认色 → 用户看到「紫色一行 + 黑色一行，内容重复」。
 *
 * 修复：当 firstLine 已包含指路后缀时，直接展示 firstLine，不再追加。
 *
 * @param rawAnswer 去掉 SIM marker 后的 overlayAnswers 文本（已 trim）。
 */
internal fun missDisplayAnswer(rawAnswer: String): String {
    val suffix = "点右上角紫色 AI 按钮，用 AI 联网搜题。"
    val firstLine = rawAnswer.lineSequence()
        .map { it.trim() }
        .firstOrNull { it.isNotEmpty() && !it.contains("相似度") }
    return if (firstLine.isNullOrBlank() || firstLine == "未命中") {
        "未搜到答案。$suffix"
    } else if (firstLine.endsWith(suffix) || firstLine.contains(suffix)) {
        firstLine
    } else {
        "$firstLine\n\n$suffix"
    }
}

/** 标题栏相似度胶囊（徽章）的文案 + 配色（纯函数，可单测，不依赖 Service 实例）。 */
internal data class OverlayBadge(
    val text: String,
    /** @hide */
    val colorArgb: Int,
)

/**
 * 计算标题栏相似度胶囊（徽章）的文案与配色。
 *
 * 口径（与 Dart 侧 similarityPillColor 同口径，改一处需改两处）：
 * - 检索中 / 歧义 / 未命中 → 琥珀 / 琥珀 / 灰
 * - 命中（hit）有相似度 → 显示「X%」，配色按阈值（≥90 绿 / ≥70 琥珀 / 其余灰）
 * - 命中（hit）无相似度（AI 读屏 confidence=0）→ 显示「命中」（绿），
 *   绝不能落「未命中」灰 —— 否则正文命中 + 徽章「未命中」自相矛盾
 *   （2026-09-18 用户截图：「答案：C」紫色命中，徽章却灰「未命中」）。
 */
internal fun badgeState(
    isSearchingNow: Boolean,
    status: String,
    matchCount: Int,
    matchIndex: Int,
    sim: Int?,
): OverlayBadge = when {
    isSearchingNow -> OverlayBadge("读屏中", 0xFFF59E0B.toInt())
    status == "ambiguous" && matchCount > 1 ->
        OverlayBadge("确认 ${matchIndex + 1}/$matchCount", 0xFFF59E0B.toInt())
    status == "ambiguous" -> OverlayBadge("请确认", 0xFFF59E0B.toInt())
    status == "miss" -> OverlayBadge("未命中", 0xFF98A2B3.toInt())
    // 命中态：有相似度显示百分比；无相似度（AI 读屏）显示「命中」绿底，不再误判未命中。
    status == "hit" ->
        if (sim == null) OverlayBadge("命中", 0xFF12B76A.toInt())
        else OverlayBadge("$sim%", hitSimilarityColor(sim))
    // 未携带结构化 status 的旧调用路径：按相似度兜底，无相似度才算未命中。
    sim == null -> OverlayBadge("未命中", 0xFF98A2B3.toInt())
    else -> OverlayBadge("$sim%", hitSimilarityColor(sim))
}

/** 命中态相似度配色：≥90 绿 / ≥70 琥珀 / 其余灰。 */
private fun hitSimilarityColor(sim: Int): Int = when {
    sim >= 90 -> 0xFF12B76A.toInt()
    sim >= 70 -> 0xFFF59E0B.toInt()
    else -> 0xFF98A2B3.toInt()
}
