package com.example.box

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.example.box/quiz_plugin"
        private const val REQUEST_OVERLAY_PERMISSION = 1001
        private const val REQUEST_NOTIFICATION_PERMISSION = 1002
    }

    private var overlayManager: QuizOverlayManager? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 缓存 Engine 供 AccessibilityService 使用
        FlutterEngineCache.getInstance().put("quiz_engine", flutterEngine)

        overlayManager = QuizOverlayManager(this)

        // 尽早请求通知权限，避免 setOverlayVisible 时权限还没授予
        if (Build.VERSION.SDK_INT >= 33) {
            if (checkSelfPermission("android.permission.POST_NOTIFICATIONS") !=
                android.content.pm.PackageManager.PERMISSION_GRANTED
            ) {
                requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), REQUEST_NOTIFICATION_PERMISSION)
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAccessibilityEnabled" -> {
                    result.success(isAccessibilityServiceEnabled())
                }
                "requestAccessibility" -> {
                    openAccessibilitySettings()
                    result.success(true)
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(true)
                }
                "requestNotificationPermission" -> {
                    requestNotificationPermission()
                    result.success(true)
                }
                "setOverlayVisible" -> {
                    val visible = call.argument<Boolean>("visible") ?: false
                    val mode = call.argument<String>("displayMode")
                    if (overlayManager == null) overlayManager = QuizOverlayManager(this)
                    overlayManager?.setDisplayMode(mode)
                    try {
                        if (visible) {
                            overlayManager?.setVisible(true)
                        } else {
                            overlayManager?.setVisible(false)
                        }
                        val diag = overlayManager?.diagnose() ?: mapOf(
                            "visible" to false,
                            "accessibilityRunning" to false,
                            "hasOverlayView" to false,
                            "canDrawOverlays" to false,
                            "notificationReady" to false,
                            "reason" to "unknown"
                        )
                        // 若悬浮窗未显示出且缺少悬浮窗权限，自动跳转设置页（与通知权限同理）
                        val reason = diag["reason"] as? String ?: "unknown"
                        val needOverlay = reason == "need_overlay_or_notification" ||
                            reason == "need_permission" ||
                            reason == "a11y_failed_need_overlay"
                        if (visible && diag["visible"] == false && needOverlay &&
                            !(diag["canDrawOverlays"] as? Boolean ?: false)
                        ) {
                            requestOverlayPermission()
                        }
                        result.success(diag)
                    } catch (e: Throwable) {
                        result.success(mapOf(
                            "visible" to false,
                            "accessibilityRunning" to false,
                            "hasOverlayView" to false,
                            "canDrawOverlays" to false,
                            "notificationReady" to false,
                            "reason" to "exception:${e.message}"
                        ))
                    }
                }
                "isOverlayVisible" -> {
                    result.success(overlayManager?.hasOverlayWindow() ?: false)
                }
                "hasOverlayPermission" -> {
                    result.success(hasOverlayPermission())
                }
                "updateOverlayContent" -> {
                    val question = call.argument<String>("question") ?: ""
                    val answers = call.argument<String>("answers")
                    val isSearching = call.argument<Boolean>("isSearching")
                    val mode = call.argument<String>("displayMode")
                    val status = call.argument<String>("status")
                    val answerKey = call.argument<String>("answerKey")
                    val similarity = call.argument<Int>("similarity")
                    val matchIndex = call.argument<Int>("matchIndex")
                    val matchCount = call.argument<Int>("matchCount")
                    @Suppress("UNCHECKED_CAST")
                    val answersList = call.argument<List<String>>("answersList")
                        ?: (call.argument<List<*>>("answersList")?.mapNotNull { it?.toString() })
                    if (overlayManager == null) overlayManager = QuizOverlayManager(this)
                    overlayManager?.setDisplayMode(mode)
                    overlayManager?.updateContent(
                        question, answers, isSearching,
                        status = status,
                        answerKey = answerKey,
                        similarity = similarity,
                        matchIndex = matchIndex,
                        matchCount = matchCount,
                        answersList = answersList,
                    )
                    result.success(true)
                }
                "onQuestionCaptured" -> {
                    // 来自 AccessibilityService 的题目捕获回调
                    val question = call.argument<String>("question") ?: ""
                    // 转发到 Flutter 层做搜题
                    flutterEngine.dartExecutor.binaryMessenger.let {
                        MethodChannel(it, CHANNEL).invokeMethod("onQuestionCaptured", mapOf(
                            "question" to question
                        ))
                    }
                    result.success(true)
                }
                "updateRegion" -> {
                    val left = call.argument<Double>("left")?.toInt() ?: return@setMethodCallHandler
                    val top = call.argument<Double>("top")?.toInt() ?: return@setMethodCallHandler
                    val right = call.argument<Double>("right")?.toInt() ?: return@setMethodCallHandler
                    val bottom = call.argument<Double>("bottom")?.toInt() ?: return@setMethodCallHandler

                    val intent = Intent(QuizAccessibilityService.ACTION_UPDATE_REGION).apply {
                        setPackage(packageName)
                        putExtra("left", left)
                        putExtra("top", top)
                        putExtra("right", right)
                        putExtra("bottom", bottom)
                    }
                    try {
                        sendBroadcast(intent)
                    } catch (_: Exception) {}

                    result.success(true)
                }
                "openRegionSelector" -> {
                    val opened = QuizAccessibilityService.enterRegionModeIfRunning()
                    result.success(opened)
                }
                "captureRegionScreenshot" -> {
                    val requestId = call.argument<Int>("requestId") ?: 0
                    val started = QuizAccessibilityService.captureRegionIfRunningWithRequestId(
                        requestId = requestId,
                        callback = { bytes ->
                            runOnUiThread { result.success(bytes) }
                        },
                    )
                    if (!started) result.success(null)
                }
                "getLastScreenshot" -> {
                    // 兼容旧客户端；新代码不再依赖此全局缓存。
                    result.success(QuizAccessibilityService.lastScreenshotBytes)
                }
                "probeFromSavedRegion" -> {
                    val ok = QuizAccessibilityService.probeFromSavedRegionIfRunning()
                    result.success(ok)
                }
                "onConfigChanged" -> {
                    val ok = QuizAccessibilityService.onConfigChangedIfRunning()
                    result.success(ok)
                }
                "setOverlayOpacity" -> {
                    val opacity = (call.argument<Double>("opacity") ?: 1.0).toFloat()
                        .coerceIn(0.3f, 1.0f)
                    QuizAccessibilityService.setOverlayOpacityIfRunning(opacity)
                    result.success(true)
                }
                "setOverlaySize" -> {
                    val widthDp = (call.argument<Double>("widthDp") ?: 320.0).toFloat()
                    val heightDp = (call.argument<Double>("heightDp") ?: 320.0).toFloat()
                    result.success(QuizAccessibilityService.setOverlaySizeIfRunning(widthDp, heightDp))
                }
                "resetOverlaySize" -> {
                    result.success(QuizAccessibilityService.resetOverlaySizeIfRunning())
                }
                "applyRegionPreset" -> {
                    val l = (call.argument<Double>("left") ?: 0.0).toFloat()
                    val t = (call.argument<Double>("top") ?: 0.0).toFloat()
                    val r = (call.argument<Double>("right") ?: 1.0).toFloat()
                    val b = (call.argument<Double>("bottom") ?: 1.0).toFloat()
                    // 主路径是 service-owned selector；仅在服务未运行时兼容旧 manager。
                    val appliedByService = QuizAccessibilityService.applyRegionPresetIfRunning(l, t, r, b)
                    if (!appliedByService) {
                        if (overlayManager == null) overlayManager = QuizOverlayManager(this)
                        overlayManager?.applyRegionPreset(l, t, r, b)
                    }
                    result.success(true)
                }
                "setRegionProbeResult" -> {
                    val title = call.argument<String>("title") ?: "预览"
                    val body = call.argument<String>("body") ?: ""
                    QuizAccessibilityService.setProbeResultIfRunning(title, body)
                    result.success(true)
                }
                "showOcrEntryOverlay" -> {
                    val opened = QuizAccessibilityService.showOcrEntryOverlayIfRunning()
                    result.success(opened)
                }
                "hideOcrEntryOverlay" -> {
                    QuizAccessibilityService.hideOcrEntryOverlay()
                    result.success(true)
                }
                "ocrEntryFill" -> {
                    val question = call.argument<String>("question") ?: ""
                    val options = call.argument<String>("options") ?: ""
                    val answer = call.argument<String>("correctAnswer") ?: ""
                    val analysis = call.argument<String>("analysis") ?: ""
                    val raw = call.argument<String>("raw") ?: ""
                    val status = call.argument<String>("status") ?: "已填充"
                    QuizOcrEntryOverlay.applyParsed(question, options, answer, analysis, raw, status)
                    result.success(true)
                }
                "ocrEntrySetStatus" -> {
                    val msg = call.argument<String>("message") ?: ""
                    QuizOcrEntryOverlay.setStatus(msg)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        // 关键：只清掉 Activity 持有的普通悬浮窗/区域选择器。
        // 无障碍答案窗（TYPE_ACCESSIBILITY_OVERLAY）必须跨 Activity 存活——
        // 用户切到驾考/考试 App 时 MainActivity 常被 destroy，若这里 hide 全部，
        // 就会出现「启用成功但屏幕上看不到悬浮窗」。
        overlayManager?.hideActivityOwned()
        // 仅在 AccessibilityService 已停止时才移除引擎缓存。
        // 若无障碍服务仍在运行（如用户切到驾考App），quiz_engine 必须保留在缓存中，
        // 否则 QuizAccessibilityService.resolveChannel() 拿不到 FlutterEngine，
        // 导致 onQuestionCaptured 等回调静默丢失。
        try {
            if (!QuizAccessibilityService.isRunning()) {
                FlutterEngineCache.getInstance().remove("quiz_engine")
            }
        } catch (_: Throwable) {
        }
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_OVERLAY_PERMISSION) {
            if (hasOverlayPermission()) {
                // 悬浮窗权限已授予：立即尝试普通悬浮窗展示答案（不再仅限区域选择器）
                overlayManager?.setVisible(true)
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFICATION_PERMISSION) {
            if (grantResults.isNotEmpty() && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                // 权限已授予，立即触发通知栏兜底
                overlayManager?.retryShowNotification()
            }
        }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val service = "${packageName}/com.example.box.QuizAccessibilityService"
        try {
            val enabled = Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            )
            return enabled?.contains(service) == true
        } catch (_: Exception) {
            return false
        }
    }

    private fun openAccessibilitySettings() {
        // 直接打开系统无障碍设置页（最稳，全 ROM 通用）。附带跳转到本服务的深链参数，
        // 部分 AOSP/原生 ROM 会直接定位到“答题助手”开关；不支持的 ROM 也只是停在列表页。
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
            putExtra(":settings:fragment_args_key", "com.example.box/.QuizAccessibilityService")
            putExtra(":settings:fragment_package", "com.example.box")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(intent)
        } catch (_: Exception) {
            // 极端兜底：仅打开无障碍总页
            try {
                startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                })
            } catch (_: Exception) {
            }
        }
    }

    private fun hasOverlayPermission(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return Settings.canDrawOverlays(this)
        }
        return true
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                android.net.Uri.parse("package:$packageName")
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivityForResult(intent, REQUEST_OVERLAY_PERMISSION)
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission("android.permission.POST_NOTIFICATIONS") != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), REQUEST_NOTIFICATION_PERMISSION)
        }
    }
}
