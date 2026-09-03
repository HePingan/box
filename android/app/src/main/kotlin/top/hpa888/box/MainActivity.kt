package top.hpa888.box

import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /**
     * HyperOS 自由小窗在 resize 后会偶发让默认 SurfaceView 丢掉绘制层，
     * 因此这里固定使用 TextureView。代价是多一次纹理合成，但普通全屏行为不变，
     * 且只影响 Flutter 的承载 View，可随时回退这一处 override。
     */
    override fun getRenderMode(): RenderMode = RenderMode.texture

    override fun onResume() {
        super.onResume()
        logFlutterWindowState("resume")
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        logFlutterWindowState("window_focus:$hasFocus")
    }

    override fun onMultiWindowModeChanged(
        isInMultiWindowMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onMultiWindowModeChanged(isInMultiWindowMode, newConfig)
        logFlutterWindowState("multi_window:$isInMultiWindowMode")
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        logFlutterWindowState("configuration_changed")
    }

    private fun logFlutterWindowState(event: String) {
        val root = window?.decorView
        FlutterWindowDiagnostics.record(
            "event=$event renderMode=${getRenderMode()} " +
                "size=${root?.width ?: 0}x${root?.height ?: 0} " +
                "multiWindow=$isInMultiWindowMode " +
                "orientation=${resources.configuration.orientation}",
        )
    }

    companion object {
        // 视频下载 MethodChannel — top.hpa888.box/video_downloads
        const val DOWNLOAD_CHANNEL = "top.hpa888.box/video_downloads"

        private const val CHANNEL = "top.hpa888.box/quiz_plugin"

        // 阅读器按键 MethodChannel — 音量键翻页
        const val READER_KEYS_CHANNEL = "top.hpa888.box/reader_keys"

        private const val REQUEST_OVERLAY_PERMISSION = 1001
        private const val REQUEST_NOTIFICATION_PERMISSION = 1002
    }

    private var overlayManager: QuizOverlayManager? = null

    /// 仅当阅读页开启「音量键翻页」时才拦截音量键；
    /// 其余场景必须放行，否则整个 App 都调不了系统音量。
    private var volumeKeyNavEnabled = false
    private var readerKeyChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 缓存 Engine 供 AccessibilityService 使用
        FlutterEngineCache.getInstance().put("quiz_engine", flutterEngine)

        overlayManager = QuizOverlayManager(this)

        // 小窗诊断通道：logcat 之外再给 Dart 侧 AppLogger 一份，
        // 让拿不到 adb 的用户能直接在「调试日志」页复制现场。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FlutterWindowDiagnostics.CHANNEL,
        ).also { diagnosticsChannel ->
            FlutterWindowDiagnostics.attachChannel(diagnosticsChannel)
            diagnosticsChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    FlutterWindowDiagnostics.METHOD_READY -> {
                        // Dart handler 已就位，回放引擎就绪前攒下的早期事件。
                        FlutterWindowDiagnostics.onDartReady()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }

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
                "openImageRegionSelector" -> {
                    val opened = QuizAccessibilityService.enterImageRegionModeIfRunning()
                    result.success(opened)
                }
                "captureImageRegionScreenshot" -> {
                    val requestId = call.argument<Int>("requestId") ?: 0
                    val started = QuizAccessibilityService.captureImageRegionIfRunning(
                        requestId = requestId,
                        callback = { bytes ->
                            runOnUiThread {
                                if (bytes != null) {
                                    val dHash = QuizAccessibilityService.computeDHashFromPng(bytes)
                                    result.success(mapOf("bytes" to bytes, "dHash" to dHash))
                                } else {
                                    result.success(null)
                                }
                            }
                        },
                    )
                    if (!started) result.success(null)
                }
                "captureRegionScreenshot" -> {
                    val requestId = call.argument<Int>("requestId") ?: 0
                    val started = QuizAccessibilityService.captureRegionIfRunningWithRequestId(
                        requestId = requestId,
                        callback = { bytes ->
                            runOnUiThread {
                                if (bytes != null) {
                                    val dHash = QuizAccessibilityService.computeDHashFromPng(bytes)
                                    result.success(mapOf("bytes" to bytes, "dHash" to dHash))
                                } else {
                                    result.success(null)
                                }
                            }
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

        // ── 视频下载 MethodChannel（独立通道）──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOWNLOAD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enqueue" -> {
                    val args = mutableMapOf<String, Any?>()
                    call.arguments?.let {
                        if (it is Map<*, *>) {
                            @Suppress("UNCHECKED_CAST")
                            args.putAll(it as Map<String, Any?>)
                        }
                    }
                    handleEnqueue(args, result)
                }
                "pause" -> handleControlPause(call.argument("id"), result)
                "resume" -> handleControlResume(call.argument("id"), result)
                "cancel" -> handleControlCancel(call.argument("id"), result)
                "remove" -> handleRemove(call.argument("id"), result)
                "snapshots" -> handleSnapshots(result)
                else -> result.notImplemented()
            }
        }

        // ── 阅读器按键 MethodChannel（音量键翻页）──
        readerKeyChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            READER_KEYS_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    // 阅读页进入/退出、或用户拨动开关时调用。
                    // 退出阅读页必须置 false，否则音量键在别的页面也被吞掉。
                    "setVolumeKeyNavEnabled" -> {
                        volumeKeyNavEnabled = call.argument<Boolean>("enabled") ?: false
                        result.success(true)
                    }
                    "isVolumeKeyNavEnabled" -> result.success(volumeKeyNavEnabled)
                    else -> result.notImplemented()
                }
            }
        }
    }

    // ─────────────────────── 音量键翻页 ───────────────────────

    /// 在 dispatch 阶段拦截，早于任何 View 消费音量键。
    /// 只吞 ACTION_DOWN 并向 Flutter 派发一次翻页；ACTION_UP 同样吞掉，
    /// 否则系统会在抬起时补一次音量 UI。长按 repeatCount>0 也放行给翻页，
    /// 让用户可以按住连续翻页。
    override fun dispatchKeyEvent(event: android.view.KeyEvent): Boolean {
        if (!volumeKeyNavEnabled) return super.dispatchKeyEvent(event)

        val direction = when (event.keyCode) {
            android.view.KeyEvent.KEYCODE_VOLUME_UP -> "previous"
            android.view.KeyEvent.KEYCODE_VOLUME_DOWN -> "next"
            else -> return super.dispatchKeyEvent(event)
        }

        if (event.action == android.view.KeyEvent.ACTION_DOWN) {
            try {
                readerKeyChannel?.invokeMethod(
                    "onVolumeKey",
                    mapOf("direction" to direction),
                )
            } catch (_: Throwable) {
                // 通道异常不能让按键卡死，也不回落到系统音量——
                // 用户已明确开启翻页，突然改音量比无响应更糟。
            }
        }
        return true
    }

    // ─────────────────────── 下载任务处理 ───────────────────────

    private fun handleEnqueue(args: Map<String, Any?>, result: MethodChannel.Result) {
        try {
            val taskId = args["id"]?.toString() ?: ""
            val mediaUrl = args["media_url"]?.toString() ?: ""
            val episodeName = args["episode_name"]?.toString() ?: ""
            val sourceName = args["source_name"]?.toString() ?: ""

            if (taskId.isEmpty()) {
                result.error("INVALID_ARGS", "Missing task id", null)
                return
            }
            if (mediaUrl.isEmpty()) {
                result.error("INVALID_ARGS", "Missing media url", null)
                return
            }
            if (!mediaUrl.startsWith("https://")) {
                result.error("UNSUPPORTED_URL", "仅支持 HTTPS 地址", null)
                return
            }

            val referer = args["referer"]?.toString() ?: ""

            val bundle = Bundle().apply {
                putString("id", taskId)
                putString("media_url", mediaUrl)
                putString("episode_name", episodeName)
                putString("source_name", sourceName)
                putString("referer", referer)
            }

            val intent = Intent(this, VideoDownloadService::class.java).apply {
                action = VideoDownloadService.ACTION_ENQUEUE
                putExtra(VideoDownloadService.EXTRA_TASK_DATA, bundle)
            }
            // startForegroundService 在 Android 8+ 上需要 FOREGROUND_SERVICE_MEDIA_PLAYBACK 权限
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("ENQUEUE_FAILED", e.message, null)
        }
    }

    private fun sendControlIntent(action: String, taskId: String) {
        val intent = Intent(this, VideoDownloadService::class.java).apply {
            this.action = action
            putExtra(VideoDownloadService.EXTRA_TASK_ID, taskId)
        }
        // 控制指令不启动前台服务：若服务已死，控制无意义（任务快照也已清空）。
        try {
            startService(intent)
        } catch (_: Exception) {
            // 服务未运行时 startService 可能抛异常，静默忽略——控制目标已不存在。
        }
    }

    private fun handleControlPause(taskId: String?, result: MethodChannel.Result) {
        if (taskId == null || taskId.isEmpty()) {
            return result.error("INVALID_ARGS", "Missing task id", null)
        }
        sendControlIntent(VideoDownloadService.ACTION_PAUSE, taskId)
        result.success(true)
    }

    private fun handleControlResume(taskId: String?, result: MethodChannel.Result) {
        if (taskId == null || taskId.isEmpty()) {
            return result.error("INVALID_ARGS", "Missing task id", null)
        }
        if (VideoDownloadService.taskForId(this, taskId) == null) {
            return result.error("TASK_NOT_FOUND", "下载任务不存在，请重新创建", null)
        }
        sendControlIntent(VideoDownloadService.ACTION_RESUME, taskId)
        result.success(true)
    }

    private fun handleControlCancel(taskId: String?, result: MethodChannel.Result) {
        if (taskId == null || taskId.isEmpty()) {
            return result.error("INVALID_ARGS", "Missing task id", null)
        }
        sendControlIntent(VideoDownloadService.ACTION_CANCEL, taskId)
        result.success(true)
    }

    private fun handleRemove(taskId: String?, result: MethodChannel.Result) {
        if (taskId == null || taskId.isEmpty()) {
            return result.error("INVALID_ARGS", "Missing task id", null)
        }
        sendControlIntent(VideoDownloadService.ACTION_REMOVE, taskId)
        result.success(true)
    }

    private fun handleSnapshots(result: MethodChannel.Result) {
        VideoDownloadService.restoreTasks(this)
        result.success(VideoDownloadService.snapshotList())
    }

    override fun onDestroy() {
        // 关键：只清掉 Activity 持有的普通悬浮窗/区域选择器。
        // 无障碍答案窗（TYPE_ACCESSIBILITY_OVERLAY）必须跨 Activity 存活——
        // 用户切到驾考/考试 App 时 MainActivity 常被 destroy，若这里 hide 全部，
        // 就会出现「启用成功但屏幕上看不到悬浮窗」。
        overlayManager?.hideActivityOwned()
        // 诊断通道绑在这个 Activity 的 engine 上，必须随之解绑，
        // 否则重建后事件会投向失效 channel 而静默丢掉。
        FlutterWindowDiagnostics.detachChannel()
        // 仅在 AccessibilityService 已停止时才移除引擎缓存。
        // 若无障碍服务仍在运行（如用户切到驾考App），quiz_engine 必须保留在缓存中，
        // 否则 QuizAccessibilityService.resolveChannel() 拿不到 FlutterEngine，
        // 导致 onQuestionCaptured 等回调静默丢失。
        try {
            if (EngineCacheRetentionPolicy.shouldEvictEngineCache(
                    QuizAccessibilityService.isRunning()
                )
            ) {
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
        val service = "${packageName}/top.hpa888.box.QuizAccessibilityService"
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
            putExtra(":settings:fragment_args_key", "top.hpa888.box/.QuizAccessibilityService")
            putExtra(":settings:fragment_package", "top.hpa888.box")
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
