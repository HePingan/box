package com.example.box

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.RectF
import android.os.Build
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
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
        private const val CHANNEL = "com.example.box/quiz_plugin"
        private const val PREFS_NAME = "quiz_plugin_prefs"
        private const val KEY_REGION = "quiz_region"
        private const val NOTIFICATION_ID = 0x2024_11_07
    }

    // 区域选择器专用的临时普通悬浮窗
    private var regionOverlayView: View? = null
    private var windowManager: WindowManager? = null
    private var regionParams: WindowManager.LayoutParams? = null

    private var channel: MethodChannel? = null
    private var currentQuestion = ""
    private var currentAnswers = ""
    private var displayMode = "accessibility"

    init {
        try {
            windowManager = context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
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

    /** 无障碍悬浮窗或区域选择器任一在显示即视为可见。 */
    fun isVisible(): Boolean = QuizAccessibilityService.isRunning() && regionOverlayView == null

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

    fun updateContent(question: String, answers: String?, isSearching: Boolean?) {
        if (question.isNotBlank() && question != currentQuestion && answers == null) {
            currentAnswers = ""
        }
        currentQuestion = question
        if (answers != null) currentAnswers = answers

        when (displayMode) {
            "manual" -> { /* 手动模式不主动弹出 */ }
            "notification" -> showNotificationFallback()
            else -> {
                // accessibility：优先无障碍悬浮，失败降级通知栏
                if (!QuizAccessibilityService.showOverlayIfRunning(currentQuestion, currentAnswers)) {
                    showNotificationFallback()
                }
            }
        }
    }

    fun showByDisplayMode() {
        when (displayMode) {
            "manual" -> {
                hide()
            }
            "notification" -> {
                QuizAccessibilityService.hideOverlayIfRunning()
                showNotificationFallback()
            }
            else -> {
                // accessibility
                val shown = QuizAccessibilityService.showOverlayIfRunning(currentQuestion, currentAnswers)
                if (!shown) {
                    showNotificationFallback()
                    Toast.makeText(
                        context.applicationContext,
                        "请先开启无障碍服务，已暂用通知栏提示",
                        Toast.LENGTH_LONG
                    ).show()
                }
            }
        }
    }

    // ── 识别区域选择器（临时普通悬浮窗，仅用于设置区域）──

    fun openRegionSelector(): Boolean {
        if (regionOverlayView != null) return true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !android.provider.Settings.canDrawOverlays(context)
        ) {
            return false
        }
        val wm = windowManager ?: return false
        val inflater = context.getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
        val view = inflater.inflate(R.layout.quiz_overlay, null)
        // 区域选择器只显示区域相关控件
        view.findViewById<View>(R.id.answer_container)?.visibility = View.GONE
        view.findViewById<View>(R.id.btn_search)?.visibility = View.GONE

        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            android.graphics.PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }

        view.findViewById<View>(R.id.btn_close)?.setOnClickListener { closeRegionSelector() }

        return try {
            wm.addView(view, params)
            regionOverlayView = view
            regionParams = params
            toggleRegionMode()
            true
        } catch (e: Throwable) {
            Log.w(TAG, "open region selector failed", e)
            regionOverlayView = null
            regionParams = null
            false
        }
    }

    private fun closeRegionSelector() {
        val view = regionOverlayView ?: return
        try { windowManager?.removeView(view) } catch (_: Throwable) {}
        regionOverlayView = null
        regionParams = null
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
        regionSelector?.setOnRegionConfirmedListener {
            saveSelectorRegion(selector, closeAfterSave = true)
        }
        root.findViewById<View>(R.id.btn_region_cancel)?.setOnClickListener { closeRegionSelector() }
        root.findViewById<View>(R.id.btn_region_save)?.setOnClickListener {
            saveSelectorRegion(selector, closeAfterSave = true)
        }
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
            Log.w(TAG, "notification permission not granted")
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
        } catch (_: Throwable) {}
    }

    fun hide() {
        QuizAccessibilityService.hideOverlayIfRunning()
        closeRegionSelector()
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            nm?.cancel(NOTIFICATION_ID)
        } catch (_: Throwable) {}
    }
}
