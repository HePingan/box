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
import java.io.ByteArrayOutputStream
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.TextView
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
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
        private const val CONFIG_PREFS_NAME = "FlutterSharedPreferences"
        private const val CONFIG_KEY = "flutter.quiz_plugin_config"
        const val ACTION_UPDATE_REGION = "com.example.box.UPDATE_QUIZ_REGION"

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

        private var lastSendTime = 0L
        private var lastQuestion = ""
        @Volatile private var runningService: QuizAccessibilityService? = null

        fun isRunning(): Boolean = runningService != null

        /** 显示 / 更新无障碍悬浮窗。返回 false 表示服务未运行（调用方应降级为通知栏）。 */
        fun showOverlayIfRunning(question: String, answers: String): Boolean {
            val svc = runningService ?: return false
            svc.mainHandler.post { svc.showOrUpdateAccessibilityOverlay(question, answers) }
            return true
        }

        /** 隐藏无障碍悬浮窗。 */
        fun hideOverlayIfRunning() {
            val svc = runningService ?: return
            svc.mainHandler.post { svc.hideAccessibilityOverlay() }
        }

        /**
         * 截取当前屏幕并裁剪到识别区域，回调返回 PNG 字节（失败返回 null）。
         * 依赖 AccessibilityService.takeScreenshot（API 30+）。对设了 FLAG_SECURE 的
         * 页面截屏会是黑屏/失败，属预期限制。
         */
        fun captureRegionIfRunning(callback: (ByteArray?) -> Unit): Boolean {
            val svc = runningService ?: return false
            svc.captureRegionScreenshot(callback)
            return true
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var isActive = false
    private var screenRegion: RectF? = null
    private var windowManager: WindowManager? = null
    private var accessibilityOverlayView: View? = null
    private var overlayParams: WindowManager.LayoutParams? = null
    private var overlayQuestion = ""
    private var overlayAnswers = ""
    private var commandReceiver: BroadcastReceiver? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                    AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED or
                    AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED or
                    AccessibilityEvent.TYPE_VIEW_SCROLLED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            notificationTimeout = 600
            flags = AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                    AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
        }
        serviceInfo = info
        channel = resolveChannel()
        screenRegion = loadRegion()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        registerCommandReceiver()
        runningService = this
        isActive = true
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (!isActive) return

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED -> {
                val now = System.currentTimeMillis()
                if (now - lastSendTime < 900) return
                extractAndSend(event.source)
                lastSendTime = now
            }
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED,
            AccessibilityEvent.TYPE_VIEW_SCROLLED -> {
                // 内容变化 / 滚动更频繁，用更长节流避免频繁遍历节点树。
                val now = System.currentTimeMillis()
                if (now - lastSendTime < 1800) return
                extractAndSend(event.source)
                lastSendTime = now
            }
        }
    }

    override fun onInterrupt() {
        // ignore
    }

    override fun onDestroy() {
        runningService = null
        unregisterCommandReceiver()
        hideAccessibilityOverlay()
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

    private fun showOrUpdateAccessibilityOverlay(question: String, answers: String) {
        overlayQuestion = question.ifBlank { overlayQuestion }
        overlayAnswers = answers.ifBlank { overlayAnswers }
        if (accessibilityOverlayView == null) {
            val created = runCatching { createAccessibilityOverlay() }.getOrDefault(false)
            if (!created) {
                Log.w(TAG, "TYPE_ACCESSIBILITY_OVERLAY create failed")
                return
            }
        }
        updateAccessibilityOverlayView()
    }

    private fun createAccessibilityOverlay(): Boolean {
        val wm = windowManager
            ?: (getSystemService(Context.WINDOW_SERVICE) as? WindowManager).also { windowManager = it }
            ?: return false
        val inflater = getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
        val view = inflater.inflate(R.layout.quiz_overlay, null)
        // 无障碍悬浮窗中不提供区域选择（区域设置走应用内 + 临时普通悬浮）。
        view.findViewById<View>(R.id.btn_area)?.visibility = View.GONE
        view.findViewById<View>(R.id.btn_search)?.setOnClickListener {
            resolveChannel()?.invokeMethod("manualSearch", mapOf("question" to overlayQuestion))
        }
        view.findViewById<View>(R.id.btn_close)?.setOnClickListener { hideAccessibilityOverlay() }

        val width = (resources.displayMetrics.widthPixels * 0.86f).toInt()
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            width,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 50
            y = 200
        }

        attachDragHandler(view, params, wm)

        return try {
            wm.addView(view, params)
            accessibilityOverlayView = view
            overlayParams = params
            true
        } catch (e: Throwable) {
            Log.w(TAG, "add accessibility overlay failed", e)
            accessibilityOverlayView = null
            overlayParams = null
            false
        }
    }

    /**
     * 给悬浮窗加拖动：记录 DOWN 时窗口坐标与触点偏移，MOVE 用增量，避免旧实现里
     * 把窗口中心直接怼到手指坐标导致的跳变。仅当移动超过 touch slop 才判定为拖动，
     * 从而不影响关闭/搜题按钮的点击。
     */
    private fun attachDragHandler(view: View, params: WindowManager.LayoutParams, wm: WindowManager) {
        val slop = ViewConfiguration.get(this).scaledTouchSlop
        var initialX = 0
        var initialY = 0
        var touchX = 0f
        var touchY = 0f
        var dragging = false
        view.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    dragging = false
                    false
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - touchX
                    val dy = event.rawY - touchY
                    if (!dragging && hypot(dx, dy) > slop) dragging = true
                    if (dragging) {
                        params.x = initialX + dx.toInt()
                        params.y = initialY + dy.toInt()
                        try { wm.updateViewLayout(view, params) } catch (_: Throwable) {}
                    }
                    dragging
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    val wasDragging = dragging
                    dragging = false
                    wasDragging
                }
                else -> false
            }
        }
    }

    private fun updateAccessibilityOverlayView() {
        accessibilityOverlayView?.findViewById<TextView>(R.id.tv_question)?.text =
            overlayQuestion.ifEmpty { "等待捕获题目…" }
        accessibilityOverlayView?.findViewById<TextView>(R.id.tv_answer)?.text =
            overlayAnswers.ifEmpty { "等待搜题结果…" }
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
        if (payload == lastQuestion) return
        if (!debugCapture && config.filterNoise && !QUIZ_KEYWORDS.any { cleaned.contains(it, ignoreCase = true) }) return

        val activeChannel = resolveChannel()
        if (activeChannel == null) {
            Log.w(TAG, "Flutter channel is not ready; skip captured question")
            return
        }

        lastQuestion = payload
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

        val text = node.text?.toString()?.trim() ?: node.contentDescription?.toString()?.trim()
        if (!text.isNullOrEmpty()) {
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
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_REGION, "${region.left},${region.top},${region.right},${region.bottom}")
            .apply()
    }

    private fun loadRegion(): RectF? {
        val raw = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).getString(KEY_REGION, null) ?: return null
        val parts = raw.split(',').mapNotNull { it.toFloatOrNull() }
        if (parts.size != 4) return null
        return RectF(parts[0], parts[1], parts[2], parts[3])
    }
}
