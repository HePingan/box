package com.example.box

import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.TextView

private const val TAG = "OverlayFallbackActivity"

class OverlayFallbackActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val root = FrameLayout(this)
        root.setBackgroundColor(0x33000000.toInt())

        val container = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP or Gravity.START
            )
            setPadding(48, 220, 48, 48)
        }

        val card = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            )
            setBackgroundResource(R.drawable.quiz_overlay_bg)
        }

        val title = TextView(this).apply {
            text = "答题助手（保底层）"
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 16f
            setPadding(48, 40, 48, 40)
            setBackgroundColor(0xFF4F46E5.toInt())
        }
        card.addView(title)

        val btnClose = Button(this).apply {
            text = "关闭"
            setPadding(24, 12, 24, 12)
            setOnClickListener { finish() }
        }
        val titleBar = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            )
            addView(title)
            addView(btnClose)
            (btnClose.layoutParams as FrameLayout.LayoutParams).gravity = Gravity.END or Gravity.CENTER_VERTICAL
            (btnClose.layoutParams as FrameLayout.LayoutParams).rightMargin = 24
            (btnClose.layoutParams as FrameLayout.LayoutParams).marginEnd = 24
        }
        card.addView(titleBar)

        val question = intent.getStringExtra("question") ?: "等待题目..."
        val answers = intent.getStringExtra("answers") ?: "等待答案..."

        val tvQuestion = TextView(this).apply {
            id = View.generateViewId()
            text = question
            setTextColor(0xFF101828.toInt())
            textSize = 14f
            setPadding(48, 36, 48, 24)
            maxLines = 6
        }
        card.addView(tvQuestion)

        val divider = View(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                2
            )
            setBackgroundColor(0xFFE6EAF2.toInt())
        }
        card.addView(divider)

        val tvAnswer = TextView(this).apply {
            id = View.generateViewId()
            text = answers
            setTextColor(0xFF667085.toInt())
            textSize = 13f
            setPadding(48, 24, 48, 36)
            maxLines = 10
        }
        card.addView(tvAnswer)

        container.addView(card)
        root.addView(container)
        setContentView(root)

        try {
            window.setLayout(
                (resources.displayMetrics.widthPixels * 0.92).toInt(),
                WindowManager.LayoutParams.WRAP_CONTENT
            )
            window.setGravity(Gravity.TOP or Gravity.START)
            window.setDimAmount(0.2f)
            window.addFlags(
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
            )
        } catch (e: Throwable) {
            Log.w(TAG, "window flags failed", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            nm?.cancel(0x2024_11_07)
        } catch (_: Throwable) {}
    }
}
