package com.example.box

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
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

    fun setVisible(visible: Boolean) {
        if (visible) showWithFallback() else hide()
    }

    fun updateContent(question: String, answers: String?, isSearching: Boolean?) {
        currentQuestion = question
        if (answers != null) currentAnswers = answers
        updateView()
        if (isSearching == true) {
            Toast.makeText(context.applicationContext, "正在搜题...", Toast.LENGTH_SHORT).show()
        }
    }

    fun showWithFallback() {
        if (isVisible) {
            bringToFront()
            Toast.makeText(context.applicationContext, "悬浮窗已在显示中", Toast.LENGTH_SHORT).show()
            return
        }

        var success = runCatching { show() }.getOrElse { false }
        if (!success) {
            Log.w(TAG, "try fallback notification + activity")
            showNotificationFallback()
            showFallbackActivity()
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

        var layoutFlag: Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
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

        if (layoutFlag == WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                layoutFlag = WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                params?.type = layoutFlag
                windowManager?.addView(overlayView, params)
                isVisible = true
                Toast.makeText(context.applicationContext, "已切换为普通悬浮窗模式", Toast.LENGTH_SHORT).show()
                return true
            } catch (e2: Exception) {
                e2.printStackTrace()
                Toast.makeText(context.applicationContext, "悬浮窗仍无法启动：${e2.message}", Toast.LENGTH_LONG).show()
            }
        }

        return false
    }

    private fun showFallbackActivity() {
        try {
            val intent = Intent(context, OverlayFallbackActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra("question", currentQuestion)
                putExtra("answers", currentAnswers)
            }
            context.startActivity(intent)
            Toast.makeText(context.applicationContext, "已启动保底显示层", Toast.LENGTH_SHORT).show()
        } catch (e: Throwable) {
            Log.w(TAG, "fallback activity failed", e)
            Toast.makeText(context.applicationContext, "保底显示层启动失败", Toast.LENGTH_SHORT).show()
        }
    }

    private fun showNotificationFallback() {
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
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(Notification.CATEGORY_CALL)
            .setFullScreenIntent(pending, true)
            .setOngoing(true)
            .build()

        try {
            nm.notify(NOTIFICATION_ID, notification)
        } catch (_: Throwable) {}
    }

    private fun bringToFront() {
        try {
            params?.let {
                it.flags = it.flags or WindowManager.LayoutParams.FLAG_SHOW_WALLPAPER
                windowManager?.updateViewLayout(overlayView, it)
            }
        } catch (_: Exception) {}
    }

    fun hide() {
        if (!isVisible && overlayView == null) return
        try { windowManager?.removeView(overlayView) } catch (_: Exception) {}
        overlayView = null
        isVisible = false

        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            nm?.cancel(NOTIFICATION_ID)
        } catch (_: Exception) {}

        try {
            val intent = Intent(context, OverlayFallbackActivity::class.java)
            (context as? MainActivity)?.finishAffinity()
            context.startActivity(intent)
        } catch (_: Exception) {}
    }

    private fun updateView() {
        overlayView?.findViewById<TextView>(R.id.tv_question)?.text = currentQuestion.ifEmpty { "等待捕获题目…" }
        overlayView?.findViewById<TextView>(R.id.tv_answer)?.text = currentAnswers.ifEmpty { "等待搜题结果…" }
    }
}
