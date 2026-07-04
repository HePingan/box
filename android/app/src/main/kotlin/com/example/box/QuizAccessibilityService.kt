package com.example.box

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class QuizAccessibilityService : AccessibilityService() {

    companion object {
        private const val CHANNEL = "com.example.box/quiz_plugin"
        private const val TAG = "QuizAccessibility"

        private val NOISE_LINES = setOf(
            "设置", "返回", "取消", "确定", "确认", "保存", "删除",
            "编辑", "搜索", "下一页", "上一页", "加载中", "暂无",
            "请输入", "请选择", "点击", "打开", "关闭",
            "Android", "WLAN", "蓝牙", "移动网络",
            "通知", "电池", "存储", "安全", "应用"
        )

        private val QUIZ_KEYWORDS = setOf(
            "题", "A.", "B.", "C.", "D.", "单选", "多选",
            "判断", "选择", "答案", "题目", "解析",
            "1.", "2.", "3.", "4.", "①", "②", "③", "④",
            "以下", "关于", "下列", "正确", "错误", "不是",
            "?", "？", "___", "____"
        )

        private var lastSendTime = 0L
        private var lastQuestion = ""
    }

    private var channel: MethodChannel? = null
    private var isActive = false

    override fun onServiceConnected() {
        super.onServiceConnected()
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPES_ALL_MASK
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            notificationTimeout = 300
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                flags = flags or AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
            }
        }
        serviceInfo = info
        val engine = FlutterEngineCache.getInstance().get("quiz_engine")
        if (engine != null) {
            channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        }
        isActive = true
        Toast.makeText(applicationContext, "无障碍服务已连接", Toast.LENGTH_SHORT).show()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (!isActive) return

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED,
            AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED,
            AccessibilityEvent.TYPE_VIEW_CLICKED -> {
                val now = System.currentTimeMillis()
                if (now - lastSendTime < 800) return
                extractAndSend(event.source)
                lastSendTime = now
            }
            AccessibilityEvent.TYPE_VIEW_SCROLLED -> {
                val now = System.currentTimeMillis()
                if (now - lastSendTime < 1000) return
                extractAndSend(event.source)
                lastSendTime = now
            }
        }
    }

    override fun onInterrupt() {
        // ignore
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return super.onStartCommand(intent, flags, startId)
    }

    private fun extractAndSend(root: AccessibilityNodeInfo?) {
        if (root == null) return
        val candidates = mutableListOf<String>()
        collectText(root, candidates)

        val cleaned = candidates.filter { line ->
            line.isNotBlank() && !NOISE_LINES.contains(line.trim())
        }.joinToString("\n")

        if (cleaned.isBlank()) return
        if (cleaned == lastQuestion) return
        if (!cleaned.any { QUIZ_KEYWORDS.contains(it.toString()) }) return

        lastQuestion = cleaned
        Log.d(TAG, "捕获题目: $cleaned")
        channel?.invokeMethod("onQuestionCaptured", mapOf("question" to cleaned))
    }

    private fun collectText(node: AccessibilityNodeInfo, out: MutableList<String>) {
        if (!node.isVisibleToUser) return

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
}
