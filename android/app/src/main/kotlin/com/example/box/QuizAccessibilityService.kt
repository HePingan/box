package com.example.box

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.PixelFormat
import android.os.Build
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.TextView
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class QuizAccessibilityService : AccessibilityService() {

    companion object {
        private const val CHANNEL = "com.example.box/quiz_plugin"
        private const val TAG = "QuizAccessibility"
        private const val PREFS_NAME = "quiz_plugin_prefs"
        private const val KEY_REGION = "quiz_region"
        private const val CONFIG_PREFS_NAME = "FlutterSharedPreferences"
        private const val CONFIG_KEY = "flutter.quiz_plugin_config"
        const val ACTION_UPDATE_REGION = "com.example.box.UPDATE_QUIZ_REGION"
        const val ACTION_SHOW_ACCESSIBILITY_OVERLAY = "com.example.box.SHOW_ACCESSIBILITY_OVERLAY"
        const val ACTION_HIDE_ACCESSIBILITY_OVERLAY = "com.example.box.HIDE_ACCESSIBILITY_OVERLAY"
        const val EXTRA_QUESTION = "question"
        const val EXTRA_ANSWERS = "answers"

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

        private var lastSendTime = 0L
        private var lastQuestion = ""
        @Volatile private var runningService: QuizAccessibilityService? = null

        fun isRunning(): Boolean = runningService != null
    }

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
        Toast.makeText(applicationContext, "无障碍服务已连接", Toast.LENGTH_SHORT).show()
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
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> {
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
        val filter = IntentFilter().apply {
            addAction(ACTION_UPDATE_REGION)
            addAction(ACTION_SHOW_ACCESSIBILITY_OVERLAY)
            addAction(ACTION_HIDE_ACCESSIBILITY_OVERLAY)
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
                    Toast.makeText(applicationContext, "识别区域已更新", Toast.LENGTH_SHORT).show()
                }
            }
            ACTION_SHOW_ACCESSIBILITY_OVERLAY -> {
                val question = intent.getStringExtra(EXTRA_QUESTION).orEmpty()
                val answers = intent.getStringExtra(EXTRA_ANSWERS).orEmpty()
                showOrUpdateAccessibilityOverlay(question, answers)
            }
            ACTION_HIDE_ACCESSIBILITY_OVERLAY -> hideAccessibilityOverlay()
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
        val wm = windowManager ?: (getSystemService(Context.WINDOW_SERVICE) as? WindowManager).also { windowManager = it } ?: return false
        val inflater = getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
        val view = inflater.inflate(R.layout.quiz_overlay, null)
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

    private fun extractAndSend(root: AccessibilityNodeInfo?) {
        if (root == null) return
        val candidates = mutableListOf<String>()
        screenRegion = screenRegion ?: loadRegion()
        collectText(root, candidates)

        val config = readCaptureConfig()
        val cleaned = normalizeQuizText(candidates, config)
        val debugCapture = isDebugCaptureEnabled()
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

    private fun isDebugCaptureEnabled(): Boolean {
        return readCaptureConfig().debugCapture
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

    private fun collectText(node: AccessibilityNodeInfo, out: MutableList<String>) {
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
                collectText(child, out)
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
