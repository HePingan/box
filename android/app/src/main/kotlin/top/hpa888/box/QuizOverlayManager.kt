package top.hpa888.box

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.RectF
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.view.ContextThemeWrapper
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

private const val TAG = "QuizOverlayManager"

/**
 * 答题插件显示协调器（P0 重构后）。
 *
 * 显示层策略：
 *  - 答案展示统一走无障碍悬浮窗（QuizAccessibilityService，TYPE_ACCESSIBILITY_OVERLAY），
 *    可绕过驾考宝典等 App 的悬浮窗屏蔽；不可用时降级为通知栏。
 *  - 普通系统悬浮窗（TYPE_APPLICATION_OVERLAY）仅保留给「识别区域选择器」这类临时
 *    应用内交互，不再用于展示答案。
 *
 * displayMode:
 *  - accessibility：无障碍悬浮（默认，抗屏蔽）
 *  - notification：通知栏兜底
 *  - manual：仅应用内手动
 */
class QuizOverlayManager(private val context: Context) {

    companion object {
        private const val CHANNEL = "top.hpa888.box/quiz_plugin"
        private const val PREFS_NAME = "quiz_plugin_prefs"
        private const val KEY_REGION = "quiz_region"
        private const val NOTIFICATION_ID = 0x2024_11_07
    }

    // 区域选择器专用的临时普通悬浮窗
    private var regionOverlayView: View? = null
    private var windowManager: WindowManager? = null
    private var regionParams: WindowManager.LayoutParams? = null

    // 无障碍服务未运行时的普通悬浮窗兜底（TYPE_APPLICATION_OVERLAY，需悬浮窗权限）
    private var normalOverlayView: View? = null
    private var normalOverlayParams: WindowManager.LayoutParams? = null

    private var channel: MethodChannel? = null
    private var currentQuestion = ""
    private var currentAnswers = ""
    private var displayMode = "accessibility"

    init {
        try {
            // 必须用 applicationContext：TYPE_APPLICATION_OVERLAY 绑 Activity 时，
            // 切到目标 App 导致 MainActivity destroy 后窗口会一起消失。
            val app = context.applicationContext
            windowManager = app.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
            val engine = FlutterEngineCache.getInstance().get("quiz_engine")
            channel = if (engine != null) {
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            } else {
                null
            }
        } catch (_: Throwable) {
            Log.w(TAG, "init failed")
        }
    }

    // 通知栏兜底是否已发送（仅兜底，不代表浮窗可见）
    private var notificationSent = false

    /**
     * 真实浮窗是否可见（无障碍悬浮窗 / 普通悬浮窗 / 区域选择器）。
     * 不含通知栏兜底 —— 通知只是降级方案，不能让 UI 误报"浮窗已显示"。
     */
    fun hasOverlayWindow(): Boolean = normalOverlayView != null || regionOverlayView != null ||
        (QuizAccessibilityService.isRunning() && QuizAccessibilityService.hasOverlayView())

    /** 兼容旧调用：通知兜底也算"有东西在显示"。 */
    @Deprecated("use hasOverlayWindow for UI state")
    fun isVisible(): Boolean = hasOverlayWindow() || notificationSent

    /** 返回诊断信息，便于 Dart 端给出精准引导。 */
    fun diagnose(): Map<String, Any> {
        val accessibilityRunning = QuizAccessibilityService.isRunning()
        val hasOverlayView = QuizAccessibilityService.hasOverlayView()
        val canOverlay = canDrawOverlays()
        val notificationReady = notificationReady()
        val a11yFailed = QuizAccessibilityService.accessibilityOverlayCreateFailed
        // 浮窗真实可见（不含通知兜底）
        val overlayWindowVisible = hasOverlayWindow()
        val reason = when {
            overlayWindowVisible -> "ok"
            a11yFailed && !canOverlay -> "a11y_failed_need_overlay"
            a11yFailed -> "accessibility_add_failed"
            // 服务在跑但没有 view：创建路径抛异常未置位时也要引导权限/重试，不能只说 fallback_pending
            accessibilityRunning && !hasOverlayView && !canOverlay -> "a11y_failed_need_overlay"
            accessibilityRunning && !hasOverlayView -> "accessibility_add_failed"
            !accessibilityRunning && !canOverlay && !notificationReady -> "need_permission"
            !accessibilityRunning && !canOverlay -> "need_overlay_or_notification"
            else -> "fallback_pending"
        }
        return mapOf(
            "visible" to overlayWindowVisible,
            "overlayWindowVisible" to overlayWindowVisible,
            "notificationVisible" to notificationSent,
            "accessibilityRunning" to accessibilityRunning,
            "hasOverlayView" to hasOverlayView,
            "canDrawOverlays" to canOverlay,
            "notificationReady" to notificationReady,
            "accessibilityOverlayCreateFailed" to a11yFailed,
            "reason" to reason
        )
    }

    private fun notificationReady(): Boolean {
        return if (Build.VERSION.SDK_INT >= 33) {
            context.checkSelfPermission("android.permission.POST_NOTIFICATIONS") ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    fun setDisplayMode(mode: String?) {
        displayMode = normalizeMode(mode)
    }

    private fun normalizeMode(mode: String?): String = when (mode) {
        "notification", "manual", "accessibility" -> mode
        // 兼容旧配置值
        "accessibility_overlay", "overlay" -> "accessibility"
        else -> "accessibility"
    }

    fun setVisible(visible: Boolean) {
        if (visible) showByDisplayMode() else hide()
    }

    fun showNotificationOnly() {
        showNotificationFallback()
    }

    /** 在通知权限授予后重试显示通知栏兜底。 */
    fun retryShowNotification() {
        showNotificationFallback()
    }

    fun updateContent(
        question: String,
        answers: String?,
        isSearching: Boolean? = null,
        status: String? = null,
        answerKey: String? = null,
        similarity: Int? = null,
        matchIndex: Int? = null,
        matchCount: Int? = null,
        answersList: List<String>? = null,
    ) {
        // 关闭答题助手 / OCR 录入中：不弹出答案窗
        if (!QuizAccessibilityService.isRunning() ||
            !(runningServiceEnabled())
        ) {
            // 仍缓存内容，便于再次开启时显示
            if (question.isNotBlank()) currentQuestion = question
            if (answers != null) currentAnswers = answers
            return
        }
        if (QuizOcrEntryOverlay.isShowing()) {
            if (question.isNotBlank()) currentQuestion = question
            if (answers != null) currentAnswers = answers
            return
        }
        if (question.isNotBlank() && question != currentQuestion && answers == null) {
            currentAnswers = ""
        }
        currentQuestion = question
        if (answers != null) currentAnswers = answers
        currentStatus = status ?: when {
            isSearching == true -> "searching"
            currentAnswers.isBlank() -> "idle"
            currentAnswers.contains("未找到") || currentAnswers.contains("失败") ||
                currentAnswers.contains("未开启") || currentAnswers.contains("未命中") -> "miss"
            else -> "hit"
        }
        currentAnswerKey = answerKey
        currentSimilarity = similarity
        currentMatchIndex = matchIndex ?: 0
        currentMatchCount = matchCount ?: 1
        if (answersList != null) {
            currentAnswersList = answersList
            if (answersList.isNotEmpty()) {
                currentMatchCount = answersList.size
                currentMatchIndex = currentMatchIndex.coerceIn(0, answersList.lastIndex)
                currentAnswers = answersList[currentMatchIndex]
            } else {
                // 新题检索中传空列表：明确废弃上一题的多匹配状态。
                currentMatchIndex = 0
                currentMatchCount = 1
            }
        }

        when (displayMode) {
            "manual" -> { /* 手动模式不主动弹出 */ }
            "notification" -> showNotificationFallback()
            else -> showAccessibilityWithFallback()
        }
    }

    /** 读 Flutter 配置：答题助手 enabled。服务未跑时也查 prefs。 */
    private fun runningServiceEnabled(): Boolean {
        val svc = try {
            // 通过 companion 间接：show 内部会再拦一层；这里先读 prefs
            val prefs = context.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE,
            )
            val raw = prefs.getString("flutter.quiz_plugin_config", null) ?: return false
            Regex("\"enabled\"\\s*:\\s*true").containsMatchIn(raw)
        } catch (_: Throwable) {
            false
        }
        return svc
    }

    private var currentStatus = "idle"
    private var currentAnswerKey: String? = null
    private var currentSimilarity: Int? = null
    private var currentMatchIndex = 0
    private var currentMatchCount = 1
    private var currentAnswersList: List<String> = emptyList()

    fun showByDisplayMode() {
        when (displayMode) {
            "manual" -> hide()
            "notification" -> {
                QuizAccessibilityService.hideOverlayIfRunning()
                showNotificationFallback()
            }
            else -> showAccessibilityWithFallback()
        }
    }

    /**
     * accessibility 模式显示策略（覆盖所有失败分支）：
     *  0. 答题助手关闭 或 OCR 录入打开 → 不显示答案窗；
     *  1. 无障碍服务在运行 → 尝试 TYPE_ACCESSIBILITY_OVERLAY；
     *  2. 上一步失败 或 服务未运行 → 尝试普通系统悬浮窗（TYPE_APPLICATION_OVERLAY）；
     *  3. 再失败 → 通知栏兜底。
     */
    private fun showAccessibilityWithFallback() {
        if (!runningServiceEnabled() || QuizOcrEntryOverlay.isShowing()) {
            QuizAccessibilityService.hideOverlayIfRunning()
            hideNormalOverlay()
            return
        }
        val accessibilityShown = try {
            QuizAccessibilityService.showOverlayIfRunning(
                currentQuestion,
                currentAnswers,
                status = currentStatus,
                answerKey = currentAnswerKey,
                similarity = currentSimilarity,
                matchIndex = currentMatchIndex,
                matchCount = currentMatchCount,
                answersList = currentAnswersList,
            )
        } catch (e: Throwable) {
            Log.w(TAG, "showOverlayIfRunning threw", e)
            false
        }
        if (accessibilityShown) {
            hideNormalOverlay()
            Log.d(TAG, "overlay shown via accessibility service")
            return
        }
        // 无障碍悬浮失败：尝试普通悬浮窗（即便 canDrawOverlays 为 false 也尝试一次，
        // 部分国产 ROM 的 Settings.canDrawOverlays 返回值不可靠）。
        try {
            showNormalOverlay()
        } catch (e: Throwable) {
            Log.w(TAG, "showNormalOverlay threw", e)
        }
        if (normalOverlayView != null) {
            QuizAccessibilityService.hideOverlayIfRunning()
            Log.d(TAG, "overlay shown via normal window")
            return
        }
        // 最后兜底：通知栏
        hideNormalOverlay()
        try {
            showNotificationFallback()
        } catch (e: Throwable) {
            Log.w(TAG, "showNotificationFallback threw", e)
        }
        Log.d(TAG, "overlay fallback to notification (sent=$notificationSent)")
    }

    // ── 识别区域选择器（临时普通悬浮窗，仅用于设置区域）──

    /**
     * 区域选择器必须由 AccessibilityService 自己 addView(TYPE_ACCESSIBILITY_OVERLAY)。
     * 非 Service 类 addView 会 SecurityException/BadTokenException，并可能先把答案窗藏掉导致“屏幕空白”。
     */
    fun openRegionSelector(): Boolean {
        return QuizAccessibilityService.enterRegionModeIfRunning()
    }

    private fun closeRegionSelector() {
        val view = regionOverlayView ?: return
        try { windowManager?.removeView(view) } catch (_: Throwable) {}
        regionOverlayView = null
        regionParams = null
        regionSelectorViewRef = null
        // 恢复答案小窗
        QuizAccessibilityService.restoreOverlayIfRunning()
    }

    fun toggleRegionMode() {
        val root = regionOverlayView ?: return
        val selector = root.findViewById<View>(R.id.region_selector) ?: return
        val toolbar = root.findViewById<View>(R.id.region_toolbar)
        selector.visibility = View.VISIBLE
        toolbar?.visibility = View.VISIBLE
        (selector.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
            lp.width = FrameLayout.LayoutParams.MATCH_PARENT
            lp.height = 420
            selector.layoutParams = lp
        }
        (toolbar?.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
            lp.width = FrameLayout.LayoutParams.MATCH_PARENT
            lp.height = 48
            toolbar.layoutParams = lp
        }
        val regionSelector = selector as? RegionSelectorView
        loadRegion()?.let { regionSelector?.setRegion(screenToSelectorRegion(it, selector)) }
        regionSelector?.setOnRegionChangedListener { rectF ->
            // 拖拽框选时实时回传，用于应用内数字联动
            val screen = selectorToScreenRegion(rectF, selector)
            channel?.invokeMethod(
                "onRegionPreview",
                mapOf(
                    "left" to screen.left.toDouble(),
                    "top" to screen.top.toDouble(),
                    "right" to screen.right.toDouble(),
                    "bottom" to screen.bottom.toDouble(),
                ),
            )
        }
        regionSelector?.setOnRegionConfirmedListener {
            saveSelectorRegion(selector, closeAfterSave = true)
        }
        root.findViewById<View>(R.id.btn_region_cancel)?.setOnClickListener { closeRegionSelector() }
        root.findViewById<View>(R.id.btn_region_save)?.setOnClickListener {
            saveSelectorRegion(selector, closeAfterSave = true)
        }
        root.findViewById<View>(R.id.btn_preset_top)?.setOnClickListener {
            regionSelector?.applyPreset(0.02f, 0.04f, 0.98f, 0.55f)
        }
        root.findViewById<View>(R.id.btn_preset_mid)?.setOnClickListener {
            regionSelector?.applyPreset(0.04f, 0.28f, 0.96f, 0.72f)
        }
        root.findViewById<View>(R.id.btn_preset_full)?.setOnClickListener {
            // 遗留 Manager 路径：尽量铺满当前 selector 安全区
            regionSelector?.applyMaxRegion()
        }
        root.findViewById<View>(R.id.btn_preset_last)?.setOnClickListener {
            // 服务侧主路径已处理；Manager 遗留路径尝试 prefs
            val raw = context.getSharedPreferences("quiz_plugin_prefs", Context.MODE_PRIVATE)
                .getString("quiz_region", null)
            if (raw != null) {
                val parts = raw.split(',').mapNotNull { it.toFloatOrNull() }
                if (parts.size == 4) {
                    regionSelector?.setRegion(RectF(parts[0], parts[1], parts[2], parts[3]))
                }
            }
        }
        // 暴露给 Dart 预设调用
        regionSelectorViewRef = regionSelector
    }

    private var regionSelectorViewRef: RegionSelectorView? = null

    /** 供 Dart 侧调用，应用预设（比例）。 */
    fun applyRegionPreset(leftF: Float, topF: Float, rightF: Float, bottomF: Float) {
        regionSelectorViewRef?.applyPreset(leftF, topF, rightF, bottomF)
    }

    private fun saveSelectorRegion(selectorView: View, closeAfterSave: Boolean) {
        val selector = selectorView as? RegionSelectorView ?: return
        val screenRegion = selectorToScreenRegion(selector.getRegion(), selectorView)
        saveRegion(screenRegion)
        Toast.makeText(context.applicationContext, "识别区域已保存", Toast.LENGTH_SHORT).show()
        if (closeAfterSave) closeRegionSelector()
    }

    private fun selectorToScreenRegion(region: RectF, selectorView: View): RectF {
        val location = IntArray(2)
        selectorView.getLocationOnScreen(location)
        return RectF(
            region.left + location[0],
            region.top + location[1],
            region.right + location[0],
            region.bottom + location[1]
        )
    }

    private fun screenToSelectorRegion(region: RectF, selectorView: View): RectF {
        val location = IntArray(2)
        selectorView.getLocationOnScreen(location)
        return RectF(
            region.left - location[0],
            region.top - location[1],
            region.right - location[0],
            region.bottom - location[1]
        )
    }

    private fun saveRegion(region: RectF) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_REGION, "${region.left},${region.top},${region.right},${region.bottom}")
            .apply()
        notifyAccessibilityServiceRegion(region)
    }

    private fun notifyAccessibilityServiceRegion(region: RectF) {
        val intent = Intent(QuizAccessibilityService.ACTION_UPDATE_REGION).apply {
            setPackage(context.packageName)
            putExtra("left", region.left.toInt())
            putExtra("top", region.top.toInt())
            putExtra("right", region.right.toInt())
            putExtra("bottom", region.bottom.toInt())
        }
        try {
            context.sendBroadcast(intent)
        } catch (_: Throwable) {}
    }

    private fun loadRegion(): RectF? {
        val raw = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).getString(KEY_REGION, null) ?: return null
        val parts = raw.split(',').mapNotNull { it.toFloatOrNull() }
        if (parts.size != 4) return null
        return RectF(parts[0], parts[1], parts[2], parts[3])
    }

    // ── 通知栏兜底 ──

    private fun showNotificationFallback() {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission("android.permission.POST_NOTIFICATIONS") != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(TAG, "notification permission not granted — will retry after permission")
            return
        }
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val channelId = "quiz_overlay_fallback"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(channelId, "答题助手", NotificationManager.IMPORTANCE_HIGH)
            nm.createNotificationChannel(ch)
        }

        val question = currentQuestion.ifEmpty { "等待题目..." }
        val answers = currentAnswers.ifEmpty { "等待答案..." }

        val intent = Intent(context, MainActivity::class.java)
        val pending = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("答题助手")
            .setContentText(answers)
            .setStyle(NotificationCompat.BigTextStyle().bigText("$question\n\n$answers"))
            .setContentIntent(pending)
            .setAutoCancel(displayMode != "notification")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(Notification.CATEGORY_STATUS)
            .setOngoing(displayMode == "notification")
            .build()

        try {
            nm.notify(NOTIFICATION_ID, notification)
            notificationSent = true
        } catch (_: Throwable) {}
    }

    private fun canDrawOverlays(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else {
            true
        }
    }

    private fun themedAppInflater(): LayoutInflater {
        val app = context.applicationContext
        val themed = ContextThemeWrapper(app, android.R.style.Theme_DeviceDefault_Light)
        return LayoutInflater.from(themed)
    }

    private fun createMinimalNormalView(): View {
        val app = context.applicationContext
        val density = app.resources.displayMetrics.density
        val pad = (12 * density).toInt()
        val root = LinearLayout(app).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(0xFFFFFFFF.toInt())
            setPadding(pad, pad, pad, pad)
        }
        root.addView(TextView(app).apply {
            text = "答题助手"
            setTextColor(0xFF4F46E5.toInt())
            textSize = 15f
        })
        root.addView(TextView(app).apply {
            id = R.id.tv_question
            text = "等待捕获题目…"
            setTextColor(0xFF101828.toInt())
            textSize = 14f
        })
        root.addView(TextView(app).apply {
            id = R.id.tv_answer
            text = "等待搜题结果…"
            setTextColor(0xFF344054.toInt())
            textSize = 13f
        })
        root.setOnClickListener { hide() }
        return root
    }

    /** 普通悬浮窗兜底（无障碍服务未运行/被 ROM 拦截时），保证用户立即可见答案窗。 */
    private fun showNormalOverlay() {
        if (normalOverlayView != null) {
            updateNormalOverlay()
            return
        }
        val app = context.applicationContext
        val wm = windowManager
            ?: (app.getSystemService(Context.WINDOW_SERVICE) as? WindowManager).also { windowManager = it }
            ?: return
        val dm = app.resources.displayMetrics
        val w = (dm.widthPixels * 0.50f).toInt().coerceIn(280, 480)
        // 去掉中间相似度条后，普通兜底窗同步收紧，避免视觉空长。
        val h = (dm.heightPixels * 0.29f).toInt().coerceIn(190, 320)
        val view = try {
            themedAppInflater().inflate(R.layout.quiz_overlay, null)
        } catch (e: Throwable) {
            Log.w(TAG, "inflate normal overlay failed, minimal: ${e.message}", e)
            createMinimalNormalView()
        }
        // 普通兜底窗隐藏依赖无障碍服务的能力
        view.findViewById<View>(R.id.btn_area)?.visibility = View.GONE
        view.findViewById<View>(R.id.region_selector)?.visibility = View.GONE
        view.findViewById<View>(R.id.region_toolbar)?.visibility = View.GONE
        view.findViewById<View>(R.id.btn_close)?.setOnClickListener { hide() }
        view.findViewById<View>(R.id.btn_search)?.setOnClickListener {
            // 普通窗无无障碍捕获，仅刷新展示
            updateNormalOverlay()
        }
        view.findViewById<View>(R.id.btn_collapse)?.setOnClickListener {
            toggleNormalCollapse(view)
        }
        view.findViewById<View>(R.id.btn_expand)?.setOnClickListener {
            toggleNormalCollapse(view)
        }
        view.findViewById<View>(R.id.btn_more)?.setOnClickListener { anchor ->
            try {
                val popup = android.widget.PopupMenu(app, anchor)
                popup.menu.add(0, 1, 0, "复制答案")
                popup.setOnMenuItemClickListener {
                    copyNormalToClipboard()
                    true
                }
                popup.show()
            } catch (_: Throwable) {}
        }
        view.findViewById<View>(R.id.tv_answer)?.setOnLongClickListener {
            copyNormalToClipboard(); true
        }
        view.findViewById<View>(R.id.tv_question)?.setOnLongClickListener {
            copyNormalToClipboard(); true
        }
        val params = WindowManager.LayoutParams(
            w, h,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            // 默认右上
            x = (dm.widthPixels - w - dm.widthPixels * 0.04f).toInt().coerceAtLeast(0)
            y = (dm.heightPixels * 0.10f).toInt()
        }
        attachNormalDrag(view, params, wm)
        view.findViewById<View>(R.id.resize_handle)?.setOnTouchListener { _, event ->
            resizeNormal(view, params, wm, event)
        }
        try {
            wm.addView(view, params)
            normalOverlayView = view
            normalOverlayParams = params
            updateNormalOverlay()
        } catch (e: Throwable) {
            Log.w(TAG, "normal overlay add failed: ${e.javaClass.simpleName}: ${e.message}", e)
            normalOverlayView = null
            try {
                params.flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                wm.addView(view, params)
                normalOverlayView = view
                normalOverlayParams = params
                updateNormalOverlay()
            } catch (e2: Throwable) {
                Log.w(TAG, "normal overlay retry failed: ${e2.javaClass.simpleName}: ${e2.message}", e2)
                normalOverlayView = null
            }
        }
    }

    private var normalCollapsed = false
    private var normalExpandedW = 0
    private var normalExpandedH = 0
    private var nResizeStartW = 0
    private var nResizeStartH = 0
    private var nResizeStartX = 0f
    private var nResizeStartY = 0f

    private fun toggleNormalCollapse(view: View) {
        val wm = windowManager ?: return
        val params = normalOverlayParams ?: return
        normalCollapsed = !normalCollapsed
        val container = view.findViewById<View>(R.id.answer_container)
        val pill = view.findViewById<View>(R.id.collapsed_pill)
        val handle = view.findViewById<View>(R.id.resize_handle)
        if (normalCollapsed) {
            if (params.width > 0) normalExpandedW = params.width
            if (params.height > 0) normalExpandedH = params.height
            container?.visibility = View.GONE
            pill?.visibility = View.VISIBLE
            handle?.visibility = View.GONE
            params.width = WindowManager.LayoutParams.WRAP_CONTENT
            params.height = WindowManager.LayoutParams.WRAP_CONTENT
        } else {
            val dm = context.applicationContext.resources.displayMetrics
            params.width = if (normalExpandedW > 0) normalExpandedW else (dm.widthPixels * 0.5f).toInt()
            params.height = if (normalExpandedH > 0) normalExpandedH else (dm.heightPixels * 0.36f).toInt()
            container?.visibility = View.VISIBLE
            pill?.visibility = View.GONE
            handle?.visibility = View.VISIBLE
            clampNormal(params)
        }
        try { wm.updateViewLayout(view, params) } catch (_: Throwable) {}
    }

    private fun clampNormal(params: WindowManager.LayoutParams) {
        val dm = context.applicationContext.resources.displayMetrics
        val w = if (params.width > 0) params.width else (dm.widthPixels * 0.5f).toInt()
        val h = if (params.height > 0) params.height else (dm.heightPixels * 0.35f).toInt()
        params.x = params.x.coerceIn(0, (dm.widthPixels - w).coerceAtLeast(0))
        params.y = params.y.coerceIn(0, (dm.heightPixels - h).coerceAtLeast(0))
    }

    private fun snapNormal(params: WindowManager.LayoutParams) {
        val dm = context.applicationContext.resources.displayMetrics
        val threshold = (24 * dm.density).toInt()
        val w = if (params.width > 0) params.width else (dm.widthPixels * 0.5f).toInt()
        val centerX = params.x + w / 2
        params.x = if (centerX < dm.widthPixels / 2) {
            if (params.x < threshold) 0 else params.x
        } else {
            val right = dm.widthPixels - w
            if (params.x > right - threshold) right.coerceAtLeast(0) else params.x
        }
        clampNormal(params)
    }

    private fun attachNormalDrag(view: View, params: WindowManager.LayoutParams, wm: WindowManager) {
        val slop = android.view.ViewConfiguration.get(context.applicationContext).scaledTouchSlop
        val title = view.findViewById<View>(R.id.title_bar) ?: view
        val pill = view.findViewById<View>(R.id.collapsed_pill)
        fun bind(target: View) {
            var ix = 0; var iy = 0; var tx = 0f; var ty = 0f; var dragging = false
            var lastTap = 0L
            target.setOnTouchListener { v, e ->
                when (e.actionMasked) {
                    android.view.MotionEvent.ACTION_DOWN -> {
                        ix = params.x; iy = params.y; tx = e.rawX; ty = e.rawY; dragging = false; true
                    }
                    android.view.MotionEvent.ACTION_MOVE -> {
                        val dx = e.rawX - tx; val dy = e.rawY - ty
                        if (!dragging && kotlin.math.hypot(dx.toDouble(), dy.toDouble()) > slop) {
                            dragging = true
                            view.findViewById<View>(R.id.answer_container)?.alpha = 0.55f
                            pill?.alpha = 0.55f
                        }
                        if (dragging) {
                            params.x = ix + dx.toInt()
                            params.y = iy + dy.toInt()
                            clampNormal(params)
                            try { wm.updateViewLayout(view, params) } catch (_: Throwable) {}
                        }
                        true
                    }
                    android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL -> {
                        view.findViewById<View>(R.id.answer_container)?.alpha = 1f
                        pill?.alpha = 1f
                        if (dragging) {
                            snapNormal(params)
                            try { wm.updateViewLayout(view, params) } catch (_: Throwable) {}
                        } else {
                            val now = System.currentTimeMillis()
                            if (v.id == R.id.title_bar && now - lastTap < 280) {
                                toggleNormalCollapse(view); lastTap = 0L
                            } else if (v.id == R.id.collapsed_pill) {
                                if (normalCollapsed) toggleNormalCollapse(view)
                                lastTap = now
                            } else lastTap = now
                        }
                        val was = dragging; dragging = false; was
                    }
                    else -> false
                }
            }
        }
        bind(title)
        if (pill != null) bind(pill)
    }

    private fun resizeNormal(
        view: View,
        params: WindowManager.LayoutParams,
        wm: WindowManager,
        event: android.view.MotionEvent,
    ): Boolean {
        val dm = context.applicationContext.resources.displayMetrics
        val minW = (240 * dm.density).toInt()
        val minH = (140 * dm.density).toInt()
        return when (event.actionMasked) {
            android.view.MotionEvent.ACTION_DOWN -> {
                nResizeStartW = params.width; nResizeStartH = params.height
                nResizeStartX = event.rawX; nResizeStartY = event.rawY
                true
            }
            android.view.MotionEvent.ACTION_MOVE -> {
                params.width = (nResizeStartW + (event.rawX - nResizeStartX)).toInt().coerceIn(minW, dm.widthPixels)
                params.height = (nResizeStartH + (event.rawY - nResizeStartY)).toInt().coerceIn(minH, (dm.heightPixels * 0.9f).toInt())
                clampNormal(params)
                try { wm.updateViewLayout(view, params) } catch (_: Throwable) {}
                true
            }
            else -> false
        }
    }

    private fun copyNormalToClipboard() {
        val text = listOf(currentQuestion, currentAnswers).filter { it.isNotBlank() }.joinToString("\n\n")
        if (text.isBlank()) return
        try {
            val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
            cm.setPrimaryClip(android.content.ClipData.newPlainText("quiz", text))
            Toast.makeText(context.applicationContext, "已复制", Toast.LENGTH_SHORT).show()
        } catch (_: Throwable) {}
    }

    private fun updateNormalOverlay() {
        val view = normalOverlayView ?: return
        val q = currentQuestion.ifEmpty { "等待捕获题目…" }
        val raw = currentAnswers.ifEmpty { "等待搜题结果…" }
        val simFromMarker = Regex("\\[\\[SIM:(\\d{1,3})]]").find(raw)
            ?.groupValues?.getOrNull(1)?.toIntOrNull()
        val a = raw.replace(Regex("\\s*\\[\\[SIM:\\d{1,3}]]"), "").trim()
        val displayAnswer = when {
            currentStatus == "searching" -> ""
            currentStatus == "miss" -> a.lineSequence()
                .map { it.trim() }
                .firstOrNull { it.isNotEmpty() && !it.contains("相似度") }
                ?: a.ifBlank { "未命中" }
            else -> {
                val lines = a.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.toList()
                var answerLine = lines.firstOrNull {
                    it.startsWith("答案") && !it.startsWith("答案区") && !it.contains("相似度")
                }
                if (answerLine == null) {
                    answerLine = lines.firstOrNull {
                        it.matches(Regex("^[A-DＡ-Ｄ][.、．:：)].+")) ||
                            it.matches(Regex("^[A-DＡ-Ｄ]$")) ||
                            ((it.contains("正确") || it.contains("错误")) && it.length <= 12)
                    }
                }
                when {
                    answerLine != null && answerLine.startsWith("答案") -> answerLine
                    answerLine != null -> "答案：$answerLine"
                    else -> lines.firstOrNull {
                        !it.startsWith("匹配题目") && !it.startsWith("选项") &&
                            !it.startsWith("解析") && !it.contains("相似度")
                    }?.let { if (it.startsWith("答案")) it else "答案：$it" }
                        ?: a.ifBlank { "等待搜题结果…" }
                }
            }
        }
        view.findViewById<TextView>(R.id.tv_question)?.text = q
        view.findViewById<TextView>(R.id.tv_answer)?.text = displayAnswer
        val status = view.findViewById<View>(R.id.status_bar)
        val color = when (currentStatus) {
            "searching" -> 0xFFF59E0B.toInt()
            "miss" -> 0xFFEF4444.toInt()
            "hit" -> 0xFF22C55E.toInt()
            else -> 0xFF6366F1.toInt()
        }
        status?.setBackgroundColor(color)
        val key = currentAnswerKey
        val sim = simFromMarker ?: Regex("""相似度\s*[:：]?\s*(\d{1,3})\s*%""")
            .find(a)?.groupValues?.getOrNull(1)?.toIntOrNull()
        val titleText = when {
            currentStatus == "searching" -> "检索中…"
            currentMatchCount > 1 && !key.isNullOrBlank() && sim != null ->
                "${currentMatchIndex + 1}/$currentMatchCount · $key · $sim%"
            currentMatchCount > 1 && sim != null ->
                "${currentMatchIndex + 1}/$currentMatchCount · $sim%"
            !key.isNullOrBlank() && sim != null -> "$key · $sim%"
            !key.isNullOrBlank() -> "答案 $key"
            sim != null -> "答案 · $sim%"
            currentAnswers.isBlank() -> "答题助手"
            else -> "答案"
        }
        view.findViewById<TextView>(R.id.tv_pill_label)?.text = titleText
        view.findViewById<TextView>(R.id.tv_title)?.text = titleText
    }

    private fun hideNormalOverlay() {
        val view = normalOverlayView ?: return
        try { windowManager?.removeView(view) } catch (_: Throwable) {}
        normalOverlayView = null
        normalOverlayParams = null
        normalCollapsed = false
    }

    /**
     * Activity 销毁时调用：只清理 Activity 生命周期内的临时 UI。
     * 保留：无障碍答案窗、普通悬浮窗兜底、通知栏——这些必须跨 App 可见。
     */
    fun hideActivityOwned() {
        // 区域选择器已改由服务托管；此处仅清掉遗留的 Manager 侧引用
        val region = regionOverlayView
        if (region != null) {
            try { windowManager?.removeView(region) } catch (_: Throwable) {}
            regionOverlayView = null
            regionParams = null
            regionSelectorViewRef = null
        }
        // 注意：不要 hideNormalOverlay()——普通悬浮窗是跨页面兜底，
        // 且已用 applicationContext 的 WindowManager 创建。
    }

    /** 用户主动关闭 / 关闭答题助手：隐藏所有展示路径。 */
    fun hide() {
        QuizAccessibilityService.hideOverlayIfRunning()
        closeRegionSelector()
        hideNormalOverlay()
        notificationSent = false
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            nm?.cancel(NOTIFICATION_ID)
        } catch (_: Throwable) {}
    }
}
