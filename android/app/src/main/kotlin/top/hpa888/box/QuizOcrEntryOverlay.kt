package top.hpa888.box

import android.content.Context
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.EditText
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import kotlin.math.hypot

/**
 * OCR 悬浮录入窗：框选区域 → OCR → 解析填表 → 保存题库。
 * 必须由 AccessibilityService 创建 TYPE_ACCESSIBILITY_OVERLAY。
 */
class QuizOcrEntryOverlay private constructor(private val service: QuizAccessibilityService) {

    companion object {
        private const val TAG = "QuizOcrEntry"
        private const val CHANNEL = "top.hpa888.box/quiz_plugin"
        /** 与 MainActivity / QuizAccessibilityService 一致 */
        private const val ENGINE_ID = "quiz_engine"
        private const val PREFS = "quiz_plugin_prefs"
        private const val KEY_X = "ocr_entry_x"
        private const val KEY_Y = "ocr_entry_y"
        private const val KEY_W = "ocr_entry_w"
        private const val KEY_H = "ocr_entry_h"

        @Volatile private var instance: QuizOcrEntryOverlay? = null

        fun showOn(service: QuizAccessibilityService) {
            if (instance == null) instance = QuizOcrEntryOverlay(service)
            instance?.show()
        }

        fun hideIfShowing() {
            instance?.hide()
            instance = null
        }

        fun applyParsed(
            question: String,
            options: String,
            answer: String,
            analysis: String,
            raw: String,
            status: String,
        ) {
            instance?.applyFields(question, options, answer, analysis, raw, status)
        }

        fun setStatus(msg: String) {
            instance?.setStatusText(msg)
        }

        fun isShowing(): Boolean = instance?.rootView != null

        fun isMinimizedForRegion(): Boolean = instance?.minimizedForRegion == true

        /** 框选区域时收起录入窗，避免挡视线 */
        fun minimizeForRegionIfShowing() {
            instance?.minimizeForRegion()
        }

        /** 区域确认/取消后恢复录入窗 */
        fun restoreAfterRegionIfNeeded() {
            instance?.restoreAfterRegion()
        }

        /** 试捕结束后强制显示录入窗（避免 GONE 后“点了没反应”） */
        fun ensureVisibleAfterProbeIfNeeded(status: String? = null) {
            instance?.ensureVisibleAfterProbe(status)
        }

        /** 查询当前批量录入是否运行中 */
        fun isBatchRunning(): Boolean = instance?.batchRunning == true
        /** 通过硬件快捷键停止批量录入；仅运行中才有副作用。 */
        fun stopBatchEntryIfRunning(reason: String = "手动") {
            instance?.takeIf { it.batchRunning }?.stopBatchEntry(reason)
        }

        /** 获取批量录入成功数 */
        fun getBatchSuccessCount(): Int = instance?.batchSuccessCount ?: 0
        /** 获取批量录入失败数 */
        fun getBatchFailCount(): Int = instance?.batchFailCount ?: 0
        /** 重置批量计数 */
        fun resetBatchCount() {
            instance?.let {
                it.batchSuccessCount = 0
                it.batchFailCount = 0
            }
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var rootView: View? = null
    private var params: WindowManager.LayoutParams? = null
    private var minimizedForRegion = false
    /** 根视图仍保留，但已从 WindowManager 暂时卸下，供批量翻题避开 overlay 触摸层。 */
    private var detachedForBatchNavigation = false
    private var wm: WindowManager? =
        service.getSystemService(Context.WINDOW_SERVICE) as? WindowManager

    // ========== 一键批量录入状态 ==========
    @Volatile private var batchRunning = false
    private var batchSuccessCount = 0
    private var batchDuplicateCount = 0
    private var batchVariantCount = 0
    private var batchReviewCount = 0
    private var batchFailCount = 0
    private var batchCaptureRetryCount = 0
    private var batchNavigationWatchdog: Runnable? = null
    /** 上一题结构指纹；翻页后必须变更才允许再次保存，防止重复录同一题。 */
    private var lastBatchFingerprint: String? = null
    private var pendingPreviousFingerprint: String? = null

    fun show() {
        if (rootView != null) {
            // 试捕/框选后可能仍处于 GONE + minimized；必须清标记再显示
            minimizedForRegion = false
            bringToFront()
            return
        }
        val windowManager = wm ?: return
        val inflater = LayoutInflater.from(
            android.view.ContextThemeWrapper(service, android.R.style.Theme_DeviceDefault_Light)
        )
        val view = try {
            inflater.inflate(R.layout.quiz_ocr_entry_overlay, null)
        } catch (e: Throwable) {
            Log.e(TAG, "inflate ocr entry failed", e)
            toast("无法创建 OCR 录入窗")
            return
        }
        val dm = service.resources.displayMetrics
        val prefW = service.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getInt(KEY_W, 0)
        val prefH = service.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getInt(KEY_H, 0)
        val w = if (prefW > 0) prefW else (dm.widthPixels * 0.88f).toInt().coerceIn(300, dm.widthPixels)
        val h = if (prefH > 0) prefH else (dm.heightPixels * 0.62f).toInt().coerceIn(360, dm.heightPixels)
        val (sx, sy) = loadPos(dm.widthPixels, dm.heightPixels, w, h)
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        // FLAG_HARDWARE_ACCELERATED 必须显式声明：Manifest 的 hardwareAccelerated
        // 只作用于 Activity，WindowManager 直加的浮层默认走软件渲染，
        // 滚动与拖动会明显发涩。
        val lp = WindowManager.LayoutParams(
            w, h, type,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = sx
            y = sy
        }

        view.findViewById<View>(R.id.btn_ocr_entry_close)?.setOnClickListener { hide() }
        view.findViewById<View>(R.id.btn_ocr_entry_region)?.setOnClickListener {
            setStatusText("请框选识别区域…")
            // 保存后应回到录入试捕，不能落到答题搜题
            QuizAccessibilityService.requestEntryProbeAfterRegionIfRunning()
            // 由 service 统一切换区域模式并暂时隐藏录入窗，避免重复最小化。
            QuizAccessibilityService.enterRegionModeIfRunning()
        }
        view.findViewById<View>(R.id.btn_ocr_entry_capture)?.setOnClickListener {
            startOcrCapture()
        }
        view.findViewById<View>(R.id.btn_ocr_entry_probe)?.setOnClickListener {
            setStatusText("试捕中…（用已框选区域读屏）")
            // 先收起录入窗，延迟读屏：给系统时间把 active window 从我们的浮层切回目标 App
            minimizeForRegion()
            // 180ms 在部分 ROM 上不够，active window 仍是浮层导致“没反应”
            QuizAccessibilityService.probeFromSavedRegionIfRunning(delayMs = 320L)
        }
        view.findViewById<View>(R.id.btn_ocr_entry_copy)?.setOnClickListener {
            copyProbeResult()
        }
        view.findViewById<View>(R.id.btn_ocr_entry_parse)?.setOnClickListener {
            reparseOnly()
        }
        view.findViewById<View>(R.id.btn_ocr_entry_save)?.setOnClickListener {
            saveToBank()
        }
        view.findViewById<View>(R.id.btn_ocr_entry_batch_start)?.setOnClickListener {
            startBatchEntry()
        }
        view.findViewById<View>(R.id.btn_ocr_entry_batch_stop)?.setOnClickListener {
            stopBatchEntry()
        }
        attachDrag(view.findViewById(R.id.ocr_entry_title), view, lp, windowManager)
        attachResizeHandle(view, lp, windowManager)
        attachNestedTextScrollArbitration(view)
        attachScanPauseWhileTouching(view)

        try {
            windowManager.addView(view, lp)
            rootView = view
            params = lp
            setStatusText("驾考：框题干+选项+「答案X」，少框底栏")
        } catch (e: Throwable) {
            Log.e(TAG, "addView failed", e)
            toast("OCR 录入窗添加失败：${e.javaClass.simpleName}")
            rootView = null
            params = null
        }
    }

    /**
     * 滑动/触摸本窗口期间暂停无障碍抓题扫描。
     *
     * 抓题扫描（枚举窗口 + 递归节点树，数百次 binder 调用）跑在主线程，
     * 也就是渲染本窗口的同一条线程。不暂停的话，上下滑内容、左右滑功能按钮
     * 都会被自身的 TYPE_VIEW_SCROLLED 事件反复触发重扫，直接掉帧。
     *
     * 用 dispatchTouchEvent 级别的监听：无论手势最终被哪个子 View 消费都能覆盖。
     */
    private fun attachScanPauseWhileTouching(root: View) {
        (root as? TouchAwareFrameLayout)?.onTouchActiveChanged = { active ->
            service.setOwnOverlayInteracting(active)
        }
        // 抬手后 fling 惯性仍在滚动，必须把滚动本身也算作「活动」，
        // 否则扫描会按固定延迟插进减速动画中段，表现为松手瞬间顿一下。
        val scrollIds = intArrayOf(
            R.id.ocr_entry_toolbar_scroll,
            R.id.ocr_entry_form_scroll,
        )
        for (id in scrollIds) {
            val v = root.findViewById<View>(id) ?: continue
            v.setOnScrollChangeListener { _, _, _, _, _ ->
                service.notifyOwnOverlayScrolled()
            }
        }
    }

    /**
     * 让多行输入框只在自己真的还能滚动时消费竖向手势，否则交回面板。
     * 不做这件事时，手指落在输入框上面板就滑不动（用户报的「不丝滑」主因之一）。
     */
    private fun attachNestedTextScrollArbitration(root: View) {
        val ids = intArrayOf(
            R.id.et_ocr_raw,
            R.id.et_ocr_question,
            R.id.et_ocr_options,
            R.id.et_ocr_answer,
            R.id.et_ocr_analysis,
        )
        for (id in ids) {
            val edit = root.findViewById<View>(id) ?: continue
            var downY = 0f
            var handedToParent = false
            edit.setOnTouchListener { v, e ->
                when (e.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        downY = e.rawY
                        handedToParent = false
                        // 先允许父级拦截权按需转移，不在 DOWN 阶段锁死。
                        v.parent?.requestDisallowInterceptTouchEvent(false)
                        false
                    }
                    MotionEvent.ACTION_MOVE -> {
                        if (handedToParent) return@setOnTouchListener false
                        val dy = e.rawY - downY
                        val toParent = NestedTextScrollArbiter.shouldParentScroll(
                            canScrollUp = v.canScrollVertically(-1),
                            canScrollDown = v.canScrollVertically(1),
                            dy = dy,
                        )
                        if (toParent) {
                            handedToParent = true
                            v.parent?.requestDisallowInterceptTouchEvent(false)
                        } else {
                            v.parent?.requestDisallowInterceptTouchEvent(true)
                        }
                        false
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        v.parent?.requestDisallowInterceptTouchEvent(false)
                        false
                    }
                    else -> false
                }
            }
        }
    }

    fun hide() {
        val v = rootView ?: return
        if (!detachedForBatchNavigation) {
            try { wm?.removeView(v) } catch (_: Throwable) {}
        }
        rootView = null
        params = null
        minimizedForRegion = false
        detachedForBatchNavigation = false
        if (instance === this) instance = null
    }

    private fun bringToFront() {
        val v = rootView ?: return
        val lp = params ?: return
        val windowManager = wm ?: return
        try {
            v.visibility = View.VISIBLE
            windowManager.updateViewLayout(v, lp)
        } catch (_: Throwable) {}
    }

    /**
     * 批量翻题前把 accessibility overlay 从 WindowManager 真正移除。
     * View.GONE 只隐藏绘制，窗口仍会拦截 dispatchGesture；该方法才会释放触摸层。
     */
    private fun detachForBatchNavigation(): Boolean {
        if (detachedForBatchNavigation) return true
        val v = rootView ?: return false
        return try {
            wm?.removeView(v)
            detachedForBatchNavigation = true
            true
        } catch (e: Throwable) {
            Log.w(TAG, "detach batch overlay failed", e)
            false
        }
    }

    /** 手势结束后重新挂回录入窗；批量模式保持隐藏，避免干扰下一次试捕。 */
    private fun reattachAfterBatchNavigation() {
        if (!detachedForBatchNavigation) return
        val v = rootView ?: return
        val lp = params ?: return
        try {
            wm?.addView(v, lp)
            detachedForBatchNavigation = false
            v.visibility = View.GONE
            minimizedForRegion = true
        } catch (e: Throwable) {
            Log.w(TAG, "reattach batch overlay failed", e)
        }
    }

    /** 区域调节期间隐藏录入窗本体（实例保留，便于恢复） */
    fun minimizeForRegion() {
        val v = rootView ?: return
        minimizedForRegion = true
        try {
            v.visibility = View.GONE
        } catch (_: Throwable) {}
    }

    fun restoreAfterRegion() {
        val v = rootView ?: return
        // 批量翻题卸窗后，也允许强制恢复
        if (detachedForBatchNavigation && !batchRunning) {
            reattachAfterBatchNavigation()
        }
        if (!minimizedForRegion && v.visibility == View.VISIBLE) return
        minimizedForRegion = false
        try {
            v.visibility = View.VISIBLE
            params?.let { lp -> wm?.updateViewLayout(v, lp) }
            setStatusText("区域已更新，可继续 OCR 识别")
        } catch (_: Throwable) {}
    }

    /** 试捕结束（成功/失败）强制把录入窗拉回前台。 */
    fun ensureVisibleAfterProbe(status: String? = null) {
        val v = rootView ?: return
        minimizedForRegion = false
        try {
            if (detachedForBatchNavigation && !batchRunning) {
                reattachAfterBatchNavigation()
            }
            v.visibility = View.VISIBLE
            params?.let { lp -> wm?.updateViewLayout(v, lp) }
            if (!status.isNullOrBlank()) setStatusText(status)
        } catch (_: Throwable) {}
    }

    private fun startOcrCapture() {
        setStatusText("正在截图 OCR…")
        QuizAccessibilityService.lastScreenshotBytes = null
        val ok = QuizAccessibilityService.captureRegionIfRunning { bytes ->
            mainHandler.post {
                if (bytes == null || bytes.isEmpty()) {
                    setStatusText("截图失败（可能 FLAG_SECURE 或权限）")
                    return@post
                }
                QuizAccessibilityService.lastScreenshotBytes = bytes
                val ch = channel()
                if (ch == null) {
                    setStatusText("请先打开 box 应用（Flutter 通道未就绪）")
                    return@post
                }
                setStatusText("截图成功，正在识别…")
                try {
                    ch.invokeMethod(
                        "ocrEntryRecognize",
                        mapOf("bytes" to bytes, "bytesLen" to bytes.size)
                    )
                } catch (e: Throwable) {
                    setStatusText("调用 OCR 失败：${e.message}")
                }
            }
        }
        if (!ok) setStatusText("无障碍服务未运行")
    }

    /**
     * 一键复制试捕结果：读屏原文 + 解析结果 + 行数/选项数诊断。
     *
     * 报障时用户只能贴文本，缺原文就无法判断是漏捕还是解析错位，
     * 所以这里复制的是完整快照而不是单个输入框内容。
     */
    private fun copyProbeResult() {
        val v = rootView ?: return
        val payload = QuizProbeCopyFormatter.build(
            status = v.findViewById<TextView>(R.id.tv_ocr_entry_status)?.text?.toString().orEmpty(),
            raw = v.findViewById<EditText>(R.id.et_ocr_raw)?.text?.toString().orEmpty(),
            question = v.findViewById<EditText>(R.id.et_ocr_question)?.text?.toString().orEmpty(),
            options = v.findViewById<EditText>(R.id.et_ocr_options)?.text?.toString().orEmpty(),
            answer = v.findViewById<EditText>(R.id.et_ocr_answer)?.text?.toString().orEmpty(),
            analysis = v.findViewById<EditText>(R.id.et_ocr_analysis)?.text?.toString().orEmpty(),
            timestamp = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US)
                .format(java.util.Date()),
        )
        try {
            val cm = service.getSystemService(Context.CLIPBOARD_SERVICE)
                as android.content.ClipboardManager
            cm.setPrimaryClip(android.content.ClipData.newPlainText("box-probe", payload))
            setStatusText("试捕结果已复制，可直接粘贴反馈")
            toast("已复制试捕结果")
        } catch (e: Throwable) {
            Log.w(TAG, "copy probe result failed", e)
            setStatusText("复制失败：${e.message ?: e.javaClass.simpleName}")
        }
    }

    private fun reparseOnly() {
        val raw = rootView?.findViewById<EditText>(R.id.et_ocr_raw)?.text?.toString().orEmpty()
        if (raw.isBlank()) {
            setStatusText("原文为空，请先 OCR 识别")
            return
        }
        val ch = channel()
        if (ch == null) {
            setStatusText("请先打开 box 应用")
            return
        }
        try {
            ch.invokeMethod("ocrEntryParse", mapOf("raw" to raw))
            setStatusText("正在重解析…")
        } catch (e: Throwable) {
            setStatusText("重解析失败：${e.message}")
        }
    }

    private fun saveToBank() {
        val v = rootView ?: return
        val q = v.findViewById<EditText>(R.id.et_ocr_question)?.text?.toString()?.trim().orEmpty()
        val opts = v.findViewById<EditText>(R.id.et_ocr_options)?.text?.toString().orEmpty()
        val ans = v.findViewById<EditText>(R.id.et_ocr_answer)?.text?.toString()?.trim().orEmpty()
        val ana = v.findViewById<EditText>(R.id.et_ocr_analysis)?.text?.toString()?.trim().orEmpty()
        // 与批量录入共用同一份校验：原先两处内联实现已漂移
        // （手动这份的字母答案正则漏了 IGNORE_CASE，小写 b 会被误拦）。
        val verdict = QuizOcrSaveValidator.validate(
            question = q,
            optionsRaw = opts,
            answerRaw = ans,
        )
        if (!verdict.canSave) {
            setStatusText(QuizOcrSaveValidator.statusFor(verdict))
            toast(
                when (verdict.reason) {
                    QuizOcrSaveValidator.Reason.EMPTY_QUESTION -> "请填写题目"
                    QuizOcrSaveValidator.Reason.NOT_ENOUGH_OPTIONS -> "选项不足，未保存"
                    else -> "答案与选项不一致，未保存"
                },
            )
            return
        }
        val structure = verdict.structureLabel
        val ch = channel()
        if (ch == null) {
            setStatusText("请先打开 box 应用")
            return
        }
        setStatusText("$structure，正在保存…")
        try {
            ch.invokeMethod(
                "ocrEntrySave",
                mapOf(
                    "question" to q,
                    "options" to opts,
                    "answer" to ans,
                    "analysis" to ana,
                ),
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        val resp = result as? Map<*, *>
                        val ok = resp?.get("ok") as? Boolean ?: false
                        val msg = resp?.get("message")?.toString() ?: "保存完成"
                        val status = resp?.get("status")?.toString()
                        mainHandler.post {
                            // 原先 if(ok)/else 两个分支代码完全一样，等于没分支：
                            // 「已存入」和「重复跳过」显示成同一个样子，
                            // 用户分不清这题到底进库了没有。
                            if (ok) {
                                setStatusText("✓ $msg")
                                toast(msg)
                                // 存进去了就清空表单，否则下一题试捕回填时
                                // 残留的旧答案/解析可能被误当成新题一起保存。
                                rootView?.let { clearBatchFields(it) }
                            } else {
                                val hint = when (status) {
                                    "duplicateSkipped" -> "题库已有，未重复写入"
                                    "incompleteVariantNeedsRetry" -> "内容不全，请重新框选后再存"
                                    else -> msg
                                }
                                setStatusText("未保存：$hint")
                                toast(hint)
                            }
                        }
                    }
                    override fun error(
                        errorCode: String,
                        errorMessage: String?,
                        errorDetails: Any?,
                    ) {
                        val reason = errorMessage ?: errorCode
                        mainHandler.post {
                            setStatusText("保存失败：$reason")
                            toast("保存失败：$reason")
                        }
                    }
                    override fun notImplemented() {
                        mainHandler.post {
                            setStatusText("保存失败：Dart 端未实现")
                            toast("保存失败：Dart 端未实现")
                        }
                    }
                },
            )
        } catch (e: Throwable) {
            setStatusText("保存失败：${e.message}")
        }
    }

    private fun applyFields(
        question: String,
        options: String,
        answer: String,
        analysis: String,
        raw: String,
        status: String,
    ) {
        // 试捕成功回填时，录入窗可能仍被 minimize 成 GONE
        if (minimizedForRegion) {
            minimizedForRegion = false
            try { rootView?.visibility = View.VISIBLE } catch (_: Throwable) {}
        }
        val v = rootView ?: return
        try { v.visibility = View.VISIBLE } catch (_: Throwable) {}
        // 兜底清洗：选项框不应含录入窗自身文案（极端情况下串入时剔除）
        val optsClean = options
            .lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.contains("OCR悬浮录入") && !it.contains("打开悬浮录入") }
            .joinToString("\n")
        v.findViewById<EditText>(R.id.et_ocr_question)?.setText(question.trim())
        v.findViewById<EditText>(R.id.et_ocr_options)?.setText(optsClean)
        v.findViewById<EditText>(R.id.et_ocr_answer)?.setText(answer.trim())
        v.findViewById<EditText>(R.id.et_ocr_analysis)?.setText(analysis.trim())
        v.findViewById<EditText>(R.id.et_ocr_raw)?.setText(raw)
        setStatusText(status)
    }

    private fun setStatusText(msg: String) {
        val v = rootView ?: return
        v.findViewById<TextView>(R.id.tv_ocr_entry_status)?.text = msg
    }

    private fun channel(): MethodChannel? {
        // 必须与 MainActivity.put("quiz_engine") 一致；勿用 CHANNEL 名当 engine id
        val engine = FlutterEngineCache.getInstance().get(ENGINE_ID) ?: return null
        return MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
    }

    private fun toast(msg: String) {
        mainHandler.post { Toast.makeText(service, msg, Toast.LENGTH_SHORT).show() }
    }

    // ========== 一键批量录入 ==========
    /**
     * 当前一轮「等 OCR 回填」的轮询 handler。
     *
     * 必须持有：原先每轮 runBatchStep 都新建一个局部 Handler 且无人引用，
     * stopBatchEntry 无从取消。停止后马上再启动时，上一轮遗留的 tick
     * 会带着 batchRunning=true 撞进新一轮，出现重复保存/计数错乱。
     */
    private var batchProbeWaitHandler: Handler? = null

    /** 取消在途的轮询 tick。 */
    private fun cancelBatchProbeWait() {
        batchProbeWaitHandler?.removeCallbacksAndMessages(null)
        batchProbeWaitHandler = null
    }

    private fun batchStats(): String =
        "新增:$batchSuccessCount 变体:$batchVariantCount 重复:$batchDuplicateCount 待复核:$batchReviewCount 失败:$batchFailCount"

    /** 启动一键批量录入：试捕→解析→保存→左滑→循环 */
    fun startBatchEntry() {
        if (batchRunning) {
            setStatusText("已在批量录入中")
            return
        }
        // 确保已有识别区域
        if (!QuizAccessibilityService.hasRegionIfRunning()) {
            setStatusText("请先框选识别区域")
            QuizAccessibilityService.enterRegionModeIfRunning()
            return
        }
        batchRunning = true
        batchSuccessCount = 0
        batchDuplicateCount = 0
        batchVariantCount = 0
        batchReviewCount = 0
        batchFailCount = 0
        batchCaptureRetryCount = 0
        lastBatchFingerprint = null
        pendingPreviousFingerprint = null
        mainHandler.post {
            // UI切换
            rootView?.findViewById<View>(R.id.btn_ocr_entry_batch_start)?.visibility = View.GONE
            rootView?.findViewById<View>(R.id.btn_ocr_entry_batch_stop)?.visibility = View.VISIBLE
            setStatusText("一键录入开始 · ${batchStats()}")
        }
        toast("一键录入已启动")
        runBatchStep()
    }

    /** 停止一键批量录入，并保证因翻题暂卸下的窗口重新可见。 */
    fun stopBatchEntry(reason: String = "手动") {
        val wasRunning = batchRunning
        batchRunning = false
        pendingPreviousFingerprint = null
        cancelBatchProbeWait()
        batchNavigationWatchdog?.let { mainHandler.removeCallbacks(it) }
        batchNavigationWatchdog = null
        reattachAfterBatchNavigation()
        restoreAfterRegion()
        mainHandler.post {
            rootView?.findViewById<View>(R.id.btn_ocr_entry_batch_start)?.visibility = View.VISIBLE
            rootView?.findViewById<View>(R.id.btn_ocr_entry_batch_stop)?.visibility = View.GONE
            setStatusText("已停止批量录入（$reason）· 成功:$batchSuccessCount 失败:$batchFailCount")
            if (wasRunning) toast("批量录入停止（$reason）· 成功:$batchSuccessCount 失败:$batchFailCount")
        }
    }

    /**
     * 清空表单各字段。
     *
     * 批量轮询用它保证只接受本轮试捕/解析的回填，不把旧题再次保存；
     * 手动保存成功后也调用，避免残留答案/解析串到下一题。
     */
    private fun clearBatchFields(view: View) {
        view.findViewById<EditText>(R.id.et_ocr_question)?.setText("")
        view.findViewById<EditText>(R.id.et_ocr_options)?.setText("")
        view.findViewById<EditText>(R.id.et_ocr_answer)?.setText("")
        view.findViewById<EditText>(R.id.et_ocr_analysis)?.setText("")
        view.findViewById<EditText>(R.id.et_ocr_raw)?.setText("")
    }

    /** 批量录入单步循环 */
    private fun runBatchStep() {
        if (!batchRunning) return
        val v = rootView ?: return
        clearBatchFields(v)

        // 1. 收起浮层，延迟试捕
        minimizeForRegion()
        QuizAccessibilityService.probeFromSavedRegionIfRunning(delayMs = 200L)

        // 2. 等待OCR解析完成（通过轮询表单字段判断）
        // 先清掉上一轮可能还在途的 tick，再建本轮，避免两轮轮询叠加。
        cancelBatchProbeWait()
        val checkHandler = Handler(Looper.getMainLooper())
        batchProbeWaitHandler = checkHandler
        var checks = 0
        val maxChecks = 60 // 最多等6秒
        val checkRunnable = object : Runnable {
            override fun run() {
                if (!batchRunning) return
                val q = v.findViewById<EditText>(R.id.et_ocr_question)?.text?.toString()?.trim().orEmpty()
                // 判定收敛到 BatchProbeWaitPolicy：原先「已回填」与「未到上限」
                // 用 && 绑在一起，checks==maxChecks 那一 tick 即使抓到题干
                // 也会掉进超时分支，把已识别的题记成失败跳过。
                when (BatchProbeWaitPolicy.decide(q.isNotEmpty(), checks, maxChecks)) {
                    BatchProbeWaitPolicy.Action.SAVE -> {
                        checks = 0
                        batchSaveAndSwipe(v, q)
                    }
                    BatchProbeWaitPolicy.Action.TIMEOUT -> {
                        batchFailCount++
                        mainHandler.post {
                            setStatusText("本轮超时未解析到题目 · 成功:$batchSuccessCount 失败:$batchFailCount")
                        }
                        batchNext()
                    }
                    BatchProbeWaitPolicy.Action.WAIT -> {
                        checks++
                        checkHandler.postDelayed(this, 100)
                    }
                }
            }
        }
        checkHandler.postDelayed(checkRunnable, 100)
    }

    /** 保存当前题目并导航到下一题 */
    private fun batchSaveAndSwipe(view: View, question: String) {
        val opts = view.findViewById<EditText>(R.id.et_ocr_options)?.text?.toString().orEmpty()
        val ans = view.findViewById<EditText>(R.id.et_ocr_answer)?.text?.toString()?.trim().orEmpty()
        val ana = view.findViewById<EditText>(R.id.et_ocr_analysis)?.text?.toString()?.trim().orEmpty()
        val fingerprint = batchFingerprint(question, opts)
        if (pendingPreviousFingerprint != null && fingerprint == pendingPreviousFingerprint) {
            batchFailCount++
            setStatusText("未检测到下一题，已停止避免重复录入 · 成功:$batchSuccessCount 失败:$batchFailCount")
            stopBatchEntry()
            return
        }
        if (lastBatchFingerprint == fingerprint) {
            batchFailCount++
            setStatusText("重复题目，已停止避免重复录入 · 成功:$batchSuccessCount 失败:$batchFailCount")
            stopBatchEntry()
            return
        }

        // 与手动保存共用同一份校验，避免两处规则再次漂移。
        val verdict = QuizOcrSaveValidator.validate(
            question = question,
            optionsRaw = opts,
            answerRaw = ans,
        )
        if (!verdict.canSave) {
            batchFailCount++
            val why = when (verdict.reason) {
                QuizOcrSaveValidator.Reason.ANSWER_MISMATCH -> "答案不匹配，跳过"
                else -> "本轮数据不完整"
            }
            mainHandler.post {
                setStatusText("$why · 成功:$batchSuccessCount 失败:$batchFailCount")
            }
            batchNext()
            return
        }

        // 调用Flutter端保存
        val structure = verdict.structureLabel
        val ch = channel()
        if (ch == null) {
            batchFailCount++
            mainHandler.post {
                setStatusText("通道未就绪 · 成功:$batchSuccessCount 失败:$batchFailCount")
            }
            batchNext()
            return
        }

        try {
            ch.invokeMethod(
                "ocrEntrySave",
                mapOf(
                    "question" to question,
                    "options" to opts,
                    "answer" to ans,
                    "analysis" to ana,
                    "batchMode" to true,
                ),
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        val resp = result as? Map<*, *> ?: emptyMap<Any?, Any?>()
                        val ok = resp["ok"] as? Boolean ?: false
                        mainHandler.post {
                            if (ok) {
                                when (resp["status"]?.toString()) {
                                    "inserted" -> {
                                        lastBatchFingerprint = fingerprint
                                        batchSuccessCount++
                                        batchCaptureRetryCount = 0
                                        setStatusText("$structure，已保存 · ${batchStats()}")
                                        toast("已保存 #$batchSuccessCount")
                                        batchNext()
                                    }
                                    "variantInserted" -> {
                                        lastBatchFingerprint = fingerprint
                                        batchVariantCount++
                                        batchCaptureRetryCount = 0
                                        setStatusText("同题干不同选项，已保存变体 · ${batchStats()}")
                                        batchNext()
                                    }
                                    "duplicateSkipped" -> {
                                        lastBatchFingerprint = fingerprint
                                        batchDuplicateCount++
                                        batchCaptureRetryCount = 0
                                        setStatusText("完全相同，跳过 · ${batchStats()}")
                                        batchNext()
                                    }
                                    "incompleteVariantNeedsRetry" -> {
                                        if (batchCaptureRetryCount++ == 0) {
                                            setStatusText("同题干选项疑似漏捕，重试试捕一次 · ${batchStats()}")
                                            mainHandler.postDelayed({ if (batchRunning) runBatchStep() }, 350L)
                                        } else {
                                            batchReviewCount++
                                            batchCaptureRetryCount = 0
                                            lastBatchFingerprint = fingerprint
                                            setStatusText("选项仍疑似漏捕，标记待复核并跳过 · ${batchStats()}")
                                            batchNext()
                                        }
                                    }
                                    else -> {
                                        batchFailCount++
                                        setStatusText("保存返回未知状态 · ${batchStats()}")
                                        batchNext()
                                    }
                                }
                            } else {
                                val msg = resp["message"]?.toString() ?: "未知错误"
                                batchFailCount++
                                setStatusText("保存失败: $msg · ${batchStats()}")
                                batchNext()
                            }
                        }
                    }
                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        val reason = errorMessage ?: errorCode
                        mainHandler.post {
                            batchFailCount++
                            setStatusText("保存异常: $reason · 成功:$batchSuccessCount 失败:$batchFailCount")
                            batchNext()
                        }
                    }
                    override fun notImplemented() {
                        mainHandler.post {
                            batchFailCount++
                            setStatusText("Dart端未实现 · 成功:$batchSuccessCount 失败:$batchFailCount")
                            batchNext()
                        }
                    }
                },
            )
        } catch (e: Throwable) {
            mainHandler.post {
                batchFailCount++
                setStatusText("保存异常: ${e.message} · 成功:$batchSuccessCount 失败:$batchFailCount")
                batchNext()
            }
        }
    }

    /** 归一化题干+选项，用于确认翻页后读到的是不同题。 */
    private fun batchFingerprint(question: String, options: String): String =
        (question + "\n" + options).replace(Regex("\\s+"), "").take(360)

    /**
     * 批量导航：先真正卸下 overlay，优先点击「下一题」节点，回退左滑；
     * 仅在导航完成并等待目标页面渲染后重新试捕。
     */
    private fun batchNext() {
        if (!batchRunning) return
        pendingPreviousFingerprint = lastBatchFingerprint
        minimizeForRegion()
        if (!detachForBatchNavigation()) {
            batchFailCount++
            setStatusText("无法释放录入浮窗，已停止 · 成功:$batchSuccessCount 失败:$batchFailCount")
            stopBatchEntry()
            return
        }
        mainHandler.postDelayed({
            if (!batchRunning) return@postDelayed
            batchNavigationWatchdog = Runnable {
                if (!batchRunning) return@Runnable
                reattachAfterBatchNavigation()
                batchFailCount++
                setStatusText("翻题回调超时，已恢复浮窗并停止 · 成功:$batchSuccessCount 失败:$batchFailCount")
                stopBatchEntry()
            }.also { mainHandler.postDelayed(it, 3500L) }
            QuizAccessibilityService.navigateToNextQuestion(service) { completed, method ->
                mainHandler.post {
                    batchNavigationWatchdog?.let { mainHandler.removeCallbacks(it) }
                    batchNavigationWatchdog = null
                    reattachAfterBatchNavigation()
                    if (!batchRunning) return@post
                    if (!completed) {
                        batchFailCount++
                        setStatusText("$method 未执行，已停止 · 成功:$batchSuccessCount 失败:$batchFailCount")
                        stopBatchEntry()
                        return@post
                    }
                    setStatusText("$method 已发送，等待下一题… · 成功:$batchSuccessCount 失败:$batchFailCount")
                    mainHandler.postDelayed({
                        if (batchRunning) runBatchStep()
                    }, 1200L)
                }
            }
        }, 180L)
    }

    // ========== 拖拽移动 ==========
    private fun loadPos(screenW: Int, screenH: Int, winW: Int, winH: Int): Pair<Int, Int> {
        val sp = service.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val x = sp.getInt(KEY_X, (screenW * 0.06f).toInt())
        val y = sp.getInt(KEY_Y, (screenH * 0.15f).toInt())
        return x.coerceIn(0, maxOf(0, screenW - winW)) to
               y.coerceIn(0, maxOf(0, screenH - winH))
    }

    private fun savePos(x: Int, y: Int) {
        service.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putInt(KEY_X, x).putInt(KEY_Y, y).apply()
    }

    // ========== 拖拽移动 ==========
    private fun attachDrag(
        target: View?,
        root: View,
        lp: WindowManager.LayoutParams,
        wm: WindowManager,
    ) {
        if (target == null) return
        val slop = ViewConfiguration.get(service).scaledTouchSlop
        var ix = 0; var iy = 0; var tx = 0f; var ty = 0f; var dragging = false
        // 逐 MOVE 提交会让 WindowManager 一帧内多次跨进程布局，手感发涩；
        // 统一走同帧合并门闸。
        val committer = OverlayLayoutCommitter(ChoreographerFrameScheduler()) { g ->
            lp.x = g.x; lp.y = g.y
            try { wm.updateViewLayout(root, lp) } catch (_: Throwable) {}
        }
        target.setOnTouchListener { _, e ->
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    ix = lp.x; iy = lp.y; tx = e.rawX; ty = e.rawY; dragging = false; true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = e.rawX - tx
                    val dy = e.rawY - ty
                    if (!dragging && hypot(dx.toDouble(), dy.toDouble()) > slop) dragging = true
                    if (dragging) {
                        committer.request(
                            OverlayGeometry(ix + dx.toInt(), iy + dy.toInt(), lp.width, lp.height),
                        )
                    }
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    val was = dragging
                    if (dragging) {
                        // 最后一段位移必须立即落地，否则松手时会少走一截。
                        val dx = e.rawX - tx
                        val dy = e.rawY - ty
                        committer.flush(
                            OverlayGeometry(ix + dx.toInt(), iy + dy.toInt(), lp.width, lp.height),
                        )
                        savePos(lp.x, lp.y)
                    }
                    dragging = false
                    was
                }
                else -> false
            }
        }
    }

    // ========== 拖拽调节大小 ==========
    private fun attachResizeHandle(root: View, lp: WindowManager.LayoutParams, wm: WindowManager) {
        val handle = root.findViewById<View>(R.id.ocr_entry_resize_handle) ?: return
        val density = root.context.resources.displayMetrics.density
        val minW = (240 * density).toInt()
        val minH = (300 * density).toInt()
        val maxW = (root.context.resources.displayMetrics.widthPixels * 0.95f).toInt()
        val maxH = (root.context.resources.displayMetrics.heightPixels * 0.95f).toInt()
        var startX = 0f; var startY = 0f; var startW = lp.width; var startH = lp.height
        // 缩放同样是高频事件，与拖动共用同帧合并策略。
        val committer = OverlayLayoutCommitter(ChoreographerFrameScheduler()) { g ->
            lp.width = g.width; lp.height = g.height
            try { wm.updateViewLayout(root, lp) } catch (_: Throwable) {}
        }

        handle.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = event.rawX; startY = event.rawY
                    startW = lp.width; startH = lp.height
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val nw = (startW + (event.rawX - startX)).toInt().coerceIn(minW, maxW)
                    val nh = (startH + (event.rawY - startY)).toInt().coerceIn(minH, maxH)
                    committer.request(OverlayGeometry(lp.x, lp.y, nw, nh))
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    val nw = (startW + (event.rawX - startX)).toInt().coerceIn(minW, maxW)
                    val nh = (startH + (event.rawY - startY)).toInt().coerceIn(minH, maxH)
                    committer.flush(OverlayGeometry(lp.x, lp.y, nw, nh))
                    savePos(lp.x, lp.y)
                    saveSize(lp.width, lp.height)
                    false
                }
                else -> false
            }
        }
    }

    private fun saveSize(w: Int, h: Int) {
        service.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putInt(KEY_W, w).putInt(KEY_H, h).apply()
    }
}
