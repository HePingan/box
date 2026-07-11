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
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

private const val TAG = "QuizOverlayManager"

class QuizOverlayManager(private val context: Context) {

    companion object {
        private const val CHANNEL = "com.example.box/quiz_plugin"
        private const val PREFS_NAME = "quiz_plugin_prefs"
        private const val KEY_REGION = "quiz_region"
        private const val NOTIFICATION_ID = 0x2024_11_07
    }

    private var overlayView: View? = null
    private var windowManager: WindowManager? = null
    private var params: WindowManager.LayoutParams? = null
    private var isVisible = false
    private var channel: MethodChannel? = null
    private var currentQuestion = ""
    private var currentAnswers = ""
    private var displayMode = "overlay"

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

    fun isVisible(): Boolean = isVisible

    fun setDisplayMode(mode: String?) {
        displayMode = when (mode) {
            "notification", "manual", "overlay", "accessibility_overlay" -> mode
            else -> "overlay"
        }
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
        updateView()
        if (displayMode == "accessibility_overlay") {
            if (!showAccessibilityOverlay()) {
                showNotificationFallback()
            }
        }
        if (isSearching == true) {
            Toast.makeText(context.applicationContext, "正在搜题...", Toast.LENGTH_SHORT).show()
        }
    }

    fun showByDisplayMode() {
        when (displayMode) {
            "manual" -> {
                hide()
                Toast.makeText(context.applicationContext, "已启用手动模式：请在应用内手动搜题", Toast.LENGTH_SHORT).show()
            }
            "notification" -> {
                hideOverlayViewOnly()
                showNotificationFallback()
                Toast.makeText(context.applicationContext, "已切换到通知栏提示模式", Toast.LENGTH_SHORT).show()
            }
            "accessibility_overlay" -> {
                hideOverlayViewOnly()
                if (!showAccessibilityOverlay()) {
                    showNotificationFallback()
                    Toast.makeText(context.applicationContext, "无障碍悬浮不可用，已改用通知栏提示", Toast.LENGTH_LONG).show()
                }
            }
            else -> showWithFallback()
        }
    }

    fun showWithFallback() {
        if (isVisible) {
            bringToFront()
            Toast.makeText(context.applicationContext, "悬浮窗已在显示中", Toast.LENGTH_SHORT).show()
            return
        }

        val success = runCatching { show() }.getOrElse { false }
        if (!success) {
            Log.w(TAG, "overlay failed; fallback to notification")
            showNotificationFallback()
            Toast.makeText(context.applicationContext, "悬浮窗不可用，已改用通知栏提示", Toast.LENGTH_LONG).show()
        }
    }

    private fun show(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val hasPermission = try {
                android.provider.Settings.canDrawOverlays(context)
            } catch (_: Exception) {
                false
            }
            if (!hasPermission) {
                Toast.makeText(context.applicationContext, "请先允许悬浮窗权限：设置 > 应用 > box > 悬浮窗", Toast.LENGTH_LONG).show()
                return false
            }
        }

        val inflater = context.getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
        overlayView = inflater.inflate(R.layout.quiz_overlay, null)
        Toast.makeText(context.applicationContext, "正在创建悬浮窗视图...", Toast.LENGTH_SHORT).show()

        val width = (context.resources.displayMetrics.widthPixels * 0.86f).toInt()
        val layoutFlag: Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        params = WindowManager.LayoutParams(
            width,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            android.graphics.PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 50
            y = 200
        }

        overlayView?.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_OUTSIDE) {
                return@setOnTouchListener true
            }
            params?.let { p ->
                if (event.action == MotionEvent.ACTION_MOVE) {
                    p.x = (event.rawX - (overlayView?.width ?: 0) / 2).toInt()
                    p.y = (event.rawY - (overlayView?.height ?: 0) / 2).toInt()
                    try { windowManager?.updateViewLayout(overlayView, p) } catch (_: Exception) {}
                    return@setOnTouchListener true
                }
            }
            false
        }

        overlayView?.findViewById<View>(R.id.btn_area)?.setOnClickListener {
            toggleRegionMode()
        }
        overlayView?.findViewById<View>(R.id.btn_search)?.setOnClickListener {
            channel?.invokeMethod("manualSearch", mapOf("question" to currentQuestion))
        }
        overlayView?.findViewById<View>(R.id.btn_close)?.setOnClickListener {
            hide()
        }

        updateView()

        try {
            windowManager?.addView(overlayView, params)
            isVisible = true
            Toast.makeText(context.applicationContext, "悬浮窗创建成功", Toast.LENGTH_SHORT).show()
            return true
        } catch (e: Exception) {
            e.printStackTrace()
            Toast.makeText(context.applicationContext, "悬浮窗创建失败(${e.javaClass.simpleName})：${e.message}", Toast.LENGTH_LONG).show()
        }

        return false
    }

    fun toggleRegionMode() {
        val root = overlayView ?: return
        val selector = root.findViewById<View>(R.id.region_selector) ?: return
        val toolbar = root.findViewById<View>(R.id.region_toolbar)
        val show = selector.visibility != View.VISIBLE
        selector.visibility = if (show) View.VISIBLE else View.GONE
        toolbar?.visibility = if (show) View.VISIBLE else View.GONE
        root.findViewById<View>(R.id.answer_container)?.visibility = if (show) View.GONE else View.VISIBLE
        if (show) {
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
        }
        val regionSelector = selector as? RegionSelectorView
        if (show) {
            loadRegion()?.let { regionSelector?.setRegion(screenToSelectorRegion(it, selector)) }
            regionSelector?.setOnRegionConfirmedListener {
                saveSelectorRegion(selector, closeAfterSave = true)
            }
        }
        root.findViewById<View>(R.id.btn_region_cancel)?.setOnClickListener { toggleRegionMode() }
        root.findViewById<View>(R.id.btn_region_save)?.setOnClickListener {
            saveSelectorRegion(selector, closeAfterSave = true)
        }
    }

    private fun saveSelectorRegion(selectorView: View, closeAfterSave: Boolean) {
        val selector = selectorView as? RegionSelectorView ?: return
        val screenRegion = selectorToScreenRegion(selector.getRegion(), selectorView)
        saveRegion(screenRegion)
        Toast.makeText(context.applicationContext, "识别区域已保存", Toast.LENGTH_SHORT).show()
        if (closeAfterSave) toggleRegionMode()
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

    private fun showAccessibilityOverlay(): Boolean {
        if (!QuizAccessibilityService.isRunning()) return false
        val intent = Intent(QuizAccessibilityService.ACTION_SHOW_ACCESSIBILITY_OVERLAY).apply {
            setPackage(context.packageName)
            putExtra(QuizAccessibilityService.EXTRA_QUESTION, currentQuestion)
            putExtra(QuizAccessibilityService.EXTRA_ANSWERS, currentAnswers)
        }
        return try {
            context.sendBroadcast(intent)
            true
        } catch (e: Throwable) {
            Log.w(TAG, "send accessibility overlay command failed", e)
            false
        }
    }

    private fun hideAccessibilityOverlay() {
        if (!QuizAccessibilityService.isRunning()) return
        val intent = Intent(QuizAccessibilityService.ACTION_HIDE_ACCESSIBILITY_OVERLAY).setPackage(context.packageName)
        try {
            context.sendBroadcast(intent)
        } catch (_: Throwable) {}
    }

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

    private fun bringToFront() {
        val view = overlayView ?: return
        val lp = params ?: return
        val wm = windowManager ?: return
        try {
            wm.removeView(view)
            wm.addView(view, lp)
            isVisible = true
        } catch (e: Exception) {
            Log.w(TAG, "bring overlay to front failed", e)
            try { wm.updateViewLayout(view, lp) } catch (_: Exception) {}
        }
    }

    fun hide() {
        hideOverlayViewOnly()
        hideAccessibilityOverlay()
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            nm?.cancel(NOTIFICATION_ID)
        } catch (_: Exception) {}
    }

    private fun hideOverlayViewOnly() {
        if (!isVisible && overlayView == null) return
        try { windowManager?.removeView(overlayView) } catch (_: Exception) {}
        overlayView = null
        isVisible = false
    }

    private fun updateView() {
        overlayView?.findViewById<TextView>(R.id.tv_question)?.text = currentQuestion.ifEmpty { "等待捕获题目…" }
        overlayView?.findViewById<TextView>(R.id.tv_answer)?.text = currentAnswers.ifEmpty { "等待搜题结果…" }
    }
}
