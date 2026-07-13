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
                            // 无障碍/通知模式都可能用到通知栏兜底，提前请求通知权限
                            requestNotificationPermission()
                            overlayManager?.setVisible(true)
                        } else {
                            overlayManager?.setVisible(false)
                        }
                        result.success(true)
                    } catch (e: Throwable) {
                        result.success(false)
                    }
                }
                "isOverlayVisible" -> {
                    result.success(overlayManager?.isVisible() ?: false)
                }
                "hasOverlayPermission" -> {
                    result.success(hasOverlayPermission())
                }
                "updateOverlayContent" -> {
                    val question = call.argument<String>("question") ?: ""
                    val answers = call.argument<String>("answers")
                    val isSearching = call.argument<Boolean>("isSearching")
                    val mode = call.argument<String>("displayMode")
                    if (overlayManager == null) overlayManager = QuizOverlayManager(this)
                    overlayManager?.setDisplayMode(mode)
                    overlayManager?.updateContent(question, answers, isSearching)
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
                    if (overlayManager == null) overlayManager = QuizOverlayManager(this)
                    val opened = overlayManager?.openRegionSelector() ?: false
                    if (!opened) {
                        requestOverlayPermission()
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    result.success(true)
                }
                "captureRegionScreenshot" -> {
                    val started = QuizAccessibilityService.captureRegionIfRunning { bytes ->
                        runOnUiThread { result.success(bytes) }
                    }
                    if (!started) {
                        result.success(null)
                    }
                }
                "setOverlayOpacity" -> {
                    val opacity = (call.argument<Double>("opacity") ?: 1.0).toFloat()
                        .coerceIn(0.3f, 1.0f)
                    QuizAccessibilityService.setOverlayOpacityIfRunning(opacity)
                    result.success(true)
                }
                "applyRegionPreset" -> {
                    if (overlayManager == null) overlayManager = QuizOverlayManager(this)
                    val l = (call.argument<Double>("left") ?: 0.0).toFloat()
                    val t = (call.argument<Double>("top") ?: 0.0).toFloat()
                    val r = (call.argument<Double>("right") ?: 1.0).toFloat()
                    val b = (call.argument<Double>("bottom") ?: 1.0).toFloat()
                    overlayManager?.applyRegionPreset(l, t, r, b)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        overlayManager?.setVisible(false)
        FlutterEngineCache.getInstance().remove("quiz_engine")
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_OVERLAY_PERMISSION) {
            // 悬浮窗权限仅用于「识别区域选择器」，答案展示走无障碍悬浮，无需在此自动显示。
            if (hasOverlayPermission()) {
                overlayManager?.openRegionSelector()
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
        // 先尝试直接跳到本应用辅助功能详情页，再回退通用页
        val intent = Intent().apply {
            setClassName("com.android.settings", "com.android.settings.Settings\$AccessibilityApplicationsSettingsActivity")
            putExtra(":settings:fragment_args_key", "com.example.box/.QuizAccessibilityService")
            putExtra(":settings:fragment_package", "com.example.box")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (intent.resolveActivity(packageManager) != null) {
            try { startActivity(intent); return } catch (_: Exception) {}
        }
        val fallback = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
            putExtra(":settings:fragment_args_key", "com.example.box/.QuizAccessibilityService")
            putExtra(":settings:fragment_package", "com.example.box")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(fallback)
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
