package com.example.box

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PointF
import android.graphics.RectF
import android.os.SystemClock
import android.util.AttributeSet
import android.util.TypedValue
import android.view.MotionEvent
import android.view.View
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/**
 * 识别区域选择器。
 * R1: CLEAR 镂空 / 大手柄 / 尺寸角标
 * R2: 1/2·1/3 磁吸参考线 / 比例锁定(自由|16:9) / 安全区 inset
 */
class RegionSelectorView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    companion object {
        private const val MIN_SIZE_DP = 80f
        private const val HANDLE_RADIUS_DP = 16f
        private const val HANDLE_HIT_DP = 32f
        private const val STROKE_DP = 3f
        private const val SNAP_DP = 12f
        private const val DOUBLE_TAP_MAX_DISTANCE = 50f
        private const val DOUBLE_TAP_MAX_TIME = 300
        /** 拖动中回传 Flutter 的最小间隔，避免每帧跨进程卡顿 */
        private const val CHANGE_THROTTLE_MS = 48L
    }

    private val density = resources.displayMetrics.density
    private val minSize = MIN_SIZE_DP * density
    private val handleRadius = HANDLE_RADIUS_DP * density
    private val handleHit = HANDLE_HIT_DP * density
    private val strokeW = STROKE_DP * density
    private val snapPx = SNAP_DP * density

    // 不用 saveLayer+CLEAR（全屏离屏缓冲很卡）；四块矩形直接画淡遮罩
    private val dimPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#33000000") // ~20% 黑
        style = Paint.Style.FILL
    }
    private val borderOuterPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#B3FFFFFF")
        style = Paint.Style.STROKE
        strokeWidth = strokeW + 1.5f * density
    }
    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#6366F1")
        style = Paint.Style.STROKE
        strokeWidth = strokeW
    }
    private val guidePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#88F59E0B")
        style = Paint.Style.STROKE
        strokeWidth = 1.5f * density
        pathEffect = android.graphics.DashPathEffect(floatArrayOf(8f * density, 6f * density), 0f)
    }
    private val handleFill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.FILL
    }
    private val handleStroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#6366F1")
        style = Paint.Style.STROKE
        strokeWidth = strokeW * 0.7f
    }
    private val badgeBg = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#CC1F2937")
        style = Paint.Style.FILL
    }
    private val badgeText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP, 12f, resources.displayMetrics
        )
    }

    private var region = RectF(40f, 80f, 360f, 340f)
    private val tempRegion = RectF()
    private var pendingRegion: RectF? = null
    private val handleScratch = Array(8) { PointF() }

    private var dragMode = DragMode.NONE
    private var lastPoint: PointF = PointF()
    private var onRegionChanged: ((RectF) -> Unit)? = null
    private var onRegionConfirmed: (() -> Unit)? = null
    private var lastTapTime = 0L
    private var lastTapPoint: PointF = PointF()
    private var lastChangeNotifyMs = 0L
    private var pendingChangeNotify = false

    /** null = 自由；否则 w/h 比例，如 16/9 */
    private var aspectRatio: Float? = null
    private var activeGuides: MutableList<Float> = mutableListOf() // 竖线 x 或 横线 y，用符号区分：正=x 负=y
    private var safeLeft = 0f
    private var safeTop = 0f
    private var safeRight = 0f
    private var safeBottom = 0f

    fun getRegion(): RectF = RectF(region)

    fun setRegion(r: RectF) {
        if (width <= 0 || height <= 0) {
            pendingRegion = RectF(r)
            return
        }
        pendingRegion = null
        region.set(r)
        clampRegionToBounds()
        invalidate()
        onRegionChanged?.invoke(getRegion())
    }

    fun setOnRegionChangedListener(listener: (RectF) -> Unit) {
        onRegionChanged = listener
    }

    fun setOnRegionConfirmedListener(listener: () -> Unit) {
        onRegionConfirmed = listener
    }

    /** 自由 null；16:9 传 16f/9f */
    fun setAspectRatio(ratio: Float?) {
        aspectRatio = ratio
        if (ratio != null && width > 0) {
            applyAspectFromWidth()
            clampRegionToBounds()
            invalidate()
            onRegionChanged?.invoke(getRegion())
        }
    }

    fun getAspectRatio(): Float? = aspectRatio

    fun cycleAspectRatio(): String {
        aspectRatio = when (aspectRatio) {
            null -> 16f / 9f
            else -> null
        }
        if (aspectRatio != null) applyAspectFromWidth()
        clampRegionToBounds()
        invalidate()
        onRegionChanged?.invoke(getRegion())
        return if (aspectRatio == null) "自由" else "16:9"
    }

    fun setSafeInsets(left: Float, top: Float, right: Float, bottom: Float) {
        safeLeft = left.coerceAtLeast(0f)
        safeTop = top.coerceAtLeast(0f)
        safeRight = right.coerceAtLeast(0f)
        safeBottom = bottom.coerceAtLeast(0f)
        clampRegionToBounds()
        invalidate()
    }

    /**
     * 在当前安全区内铺满可选区域。
     * [marginPx] 仅留极小边距，避免边线贴死系统栏；默认 2dp。
     */
    fun applyMaxRegion(marginPx: Float = 2f * density) {
        if (width <= 0 || height <= 0) {
            post { applyMaxRegion(marginPx) }
            return
        }
        // 全屏预设强制解除比例锁，否则 16:9 会把高度压回中间条。
        aspectRatio = null
        val minL = safeLeft
        val minT = safeTop
        val maxR = (width - safeRight).coerceAtLeast(minL + minSize)
        val maxB = (height - safeBottom).coerceAtLeast(minT + minSize)
        val m = marginPx.coerceIn(0f, minSize / 4f)
        region.set(
            (minL + m).coerceAtMost(maxR - minSize),
            (minT + m).coerceAtMost(maxB - minSize),
            (maxR - m).coerceAtLeast(minL + minSize),
            (maxB - m).coerceAtLeast(minT + minSize),
        )
        clampRegionToBounds()
        invalidate()
        onRegionChanged?.invoke(getRegion())
    }

    fun applyPreset(leftF: Float, topF: Float, rightF: Float, bottomF: Float) {
        if (width <= 0 || height <= 0) {
            post { applyPreset(leftF, topF, rightF, bottomF) }
            return
        }
        // 接近满屏的预设（right-left≥0.95 且 bottom-top≥0.9）走 max 路径，
        // 避免旧比例 0.96 再被底部工具栏 inset 夹成约 2/3 屏。
        val almostFull =
            leftF <= 0.03f &&
                topF <= 0.06f &&
                rightF >= 0.95f &&
                bottomF >= 0.90f
        if (almostFull) {
            applyMaxRegion()
            return
        }
        region.set(leftF * width, topF * height, rightF * width, bottomF * height)
        if (aspectRatio != null) applyAspectFromWidth()
        clampRegionToBounds()
        invalidate()
        onRegionChanged?.invoke(getRegion())
    }

    private fun applyAspectFromWidth() {
        val r = aspectRatio ?: return
        val h = region.width() / r
        val cy = region.centerY()
        region.top = cy - h / 2
        region.bottom = cy + h / 2
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        // 安全区：状态栏/导航栏
        if (safeTop == 0f && safeBottom == 0f) {
            val sb = statusBarHeight()
            val nb = navBarHeight()
            safeTop = sb.toFloat()
            safeBottom = nb.toFloat()
        }
        val pending = pendingRegion
        if (pending != null) {
            pendingRegion = null
            region.set(pending)
        } else if (oldw == 0 && oldh == 0) {
            region.set(w * 0.02f, h * 0.04f + safeTop, w * 0.98f, h * 0.55f)
        }
        clampRegionToBounds()
        invalidate()
        onRegionChanged?.invoke(getRegion())
    }

    private fun statusBarHeight(): Int {
        val id = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) resources.getDimensionPixelSize(id) else (24 * density).toInt()
    }

    private fun navBarHeight(): Int {
        val id = resources.getIdentifier("navigation_bar_height", "dimen", "android")
        return if (id > 0) resources.getDimensionPixelSize(id) else 0
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0f || h <= 0f) return

        // 四块矩形遮罩，避免全屏 saveLayer 离屏缓冲
        val l = region.left
        val t = region.top
        val r = region.right
        val b = region.bottom
        if (t > 0f) canvas.drawRect(0f, 0f, w, t, dimPaint)
        if (b < h) canvas.drawRect(0f, b, w, h, dimPaint)
        if (l > 0f && b > t) canvas.drawRect(0f, t, l, b, dimPaint)
        if (r < w && b > t) canvas.drawRect(r, t, w, b, dimPaint)

        // 磁吸参考线（仅拖动时有）
        if (activeGuides.isNotEmpty()) {
            for (g in activeGuides) {
                if (g >= 0) {
                    canvas.drawLine(g, 0f, g, h, guidePaint)
                } else {
                    val y = -g
                    canvas.drawLine(0f, y, w, y, guidePaint)
                }
            }
        }

        canvas.drawRect(region, borderOuterPaint)
        canvas.drawRect(region, borderPaint)
        fillHandleCenters(handleScratch)
        for (center in handleScratch) {
            canvas.drawCircle(center.x, center.y, handleRadius, handleFill)
            canvas.drawCircle(center.x, center.y, handleRadius, handleStroke)
        }

        // 尺寸角标贴选区右下内侧，避免每帧 measure 屏角文案挡手
        val pad = 6f * density
        val badge = "${region.width().toInt()}×${region.height().toInt()}"
        val tw = badgeText.measureText(badge)
        val th = badgeText.textSize
        val bx = min(region.right - tw - pad * 2, w - tw - pad * 2).coerceAtLeast(pad)
        val by = min(region.bottom - pad, h - pad)
        val badgeRect = RectF(bx, by - th - pad, bx + tw + pad * 2, by + pad / 2)
        canvas.drawRoundRect(badgeRect, 6f * density, 6f * density, badgeBg)
        canvas.drawText(badge, bx + pad, by - pad / 2, badgeText)
    }

    private fun fillHandleCenters(out: Array<PointF>) {
        out[0].set(region.left, region.top)
        out[1].set(region.right, region.top)
        out[2].set(region.left, region.bottom)
        out[3].set(region.right, region.bottom)
        out[4].set(region.left, region.centerY())
        out[5].set(region.right, region.centerY())
        out[6].set(region.centerX(), region.top)
        out[7].set(region.centerX(), region.bottom)
    }

    private fun hitHandle(x: Float, y: Float): DragMode? {
        fillHandleCenters(handleScratch)
        for (index in handleScratch.indices) {
            val p = handleScratch[index]
            if (hypot((x - p.x).toDouble(), (y - p.y).toDouble()) < handleHit) {
                return when (index) {
                    0 -> DragMode.TOP_LEFT
                    1 -> DragMode.TOP_RIGHT
                    2 -> DragMode.BOTTOM_LEFT
                    3 -> DragMode.BOTTOM_RIGHT
                    4 -> DragMode.LEFT
                    5 -> DragMode.RIGHT
                    6 -> DragMode.TOP
                    7 -> DragMode.BOTTOM
                    else -> DragMode.NONE
                }
            }
        }
        return null
    }

    private fun notifyRegionChanged(force: Boolean) {
        val listener = onRegionChanged ?: return
        val now = SystemClock.uptimeMillis()
        if (!force && now - lastChangeNotifyMs < CHANGE_THROTTLE_MS) {
            pendingChangeNotify = true
            return
        }
        lastChangeNotifyMs = now
        pendingChangeNotify = false
        listener.invoke(getRegion())
    }

    private fun hitInside(x: Float, y: Float): Boolean =
        x >= region.left && x <= region.right && y >= region.top && y <= region.bottom

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val x = event.x
        val y = event.y
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                lastPoint.set(x, y)
                dragMode = hitHandle(x, y) ?: if (hitInside(x, y)) DragMode.MOVE else DragMode.NONE
                if (dragMode != DragMode.NONE) parent?.requestDisallowInterceptTouchEvent(true)
                val now = System.currentTimeMillis()
                val dx = x - lastTapPoint.x
                val dy = y - lastTapPoint.y
                if (now - lastTapTime < DOUBLE_TAP_MAX_TIME &&
                    hypot(dx.toDouble(), dy.toDouble()) < DOUBLE_TAP_MAX_DISTANCE &&
                    hitInside(x, y)
                ) {
                    onRegionConfirmed?.invoke()
                    return true
                }
                lastTapTime = now
                lastTapPoint.set(x, y)
            }
            MotionEvent.ACTION_MOVE -> {
                if (dragMode == DragMode.NONE) return true
                val dx = x - lastPoint.x
                val dy = y - lastPoint.y
                tempRegion.set(region)
                when (dragMode) {
                    DragMode.MOVE -> {
                        tempRegion.offset(dx, dy)
                        keepMoveInsideBounds(tempRegion)
                    }
                    DragMode.TOP_LEFT -> {
                        tempRegion.left = min(tempRegion.right - minSize, tempRegion.left + dx)
                        tempRegion.top = min(tempRegion.bottom - minSize, tempRegion.top + dy)
                    }
                    DragMode.TOP_RIGHT -> {
                        tempRegion.right = max(tempRegion.left + minSize, tempRegion.right + dx)
                        tempRegion.top = min(tempRegion.bottom - minSize, tempRegion.top + dy)
                    }
                    DragMode.BOTTOM_LEFT -> {
                        tempRegion.left = min(tempRegion.right - minSize, tempRegion.left + dx)
                        tempRegion.bottom = max(tempRegion.top + minSize, tempRegion.bottom + dy)
                    }
                    DragMode.BOTTOM_RIGHT -> {
                        tempRegion.right = max(tempRegion.left + minSize, tempRegion.right + dx)
                        tempRegion.bottom = max(tempRegion.top + minSize, tempRegion.bottom + dy)
                    }
                    DragMode.LEFT -> tempRegion.left = min(tempRegion.right - minSize, tempRegion.left + dx)
                    DragMode.RIGHT -> tempRegion.right = max(tempRegion.left + minSize, tempRegion.right + dx)
                    DragMode.TOP -> tempRegion.top = min(tempRegion.bottom - minSize, tempRegion.top + dy)
                    DragMode.BOTTOM -> tempRegion.bottom = max(tempRegion.top + minSize, tempRegion.bottom + dy)
                    else -> {}
                }
                // 比例锁定
                aspectRatio?.let { r ->
                    when (dragMode) {
                        DragMode.LEFT, DragMode.RIGHT, DragMode.TOP_LEFT, DragMode.TOP_RIGHT,
                        DragMode.BOTTOM_LEFT, DragMode.BOTTOM_RIGHT -> {
                            val nh = tempRegion.width() / r
                            val cy = tempRegion.centerY()
                            tempRegion.top = cy - nh / 2
                            tempRegion.bottom = cy + nh / 2
                        }
                        DragMode.TOP, DragMode.BOTTOM -> {
                            val nw = tempRegion.height() * r
                            val cx = tempRegion.centerX()
                            tempRegion.left = cx - nw / 2
                            tempRegion.right = cx + nw / 2
                        }
                        else -> {}
                    }
                }
                // 磁吸（轻量）
                activeGuides.clear()
                applySnap(tempRegion)
                region.set(tempRegion)
                clampRegionToBounds()
                invalidate()
                lastPoint.set(x, y)
                // 拖动中节流回传，避免每帧 MethodChannel 卡顿
                notifyRegionChanged(force = false)
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                dragMode = DragMode.NONE
                activeGuides.clear()
                invalidate()
                parent?.requestDisallowInterceptTouchEvent(false)
                // 抬手强制同步最终区域
                if (pendingChangeNotify || onRegionChanged != null) {
                    notifyRegionChanged(force = true)
                }
            }
        }
        return true
    }

    private fun applySnap(rect: RectF) {
        if (width <= 0 || height <= 0) return
        val xs = listOf(width / 3f, width / 2f, width * 2f / 3f)
        val ys = listOf(height / 3f, height / 2f, height * 2f / 3f)
        fun snapEdge(value: Float, targets: List<Float>, isX: Boolean): Float {
            for (t in targets) {
                if (abs(value - t) <= snapPx) {
                    if (isX) activeGuides.add(t) else activeGuides.add(-t)
                    return t
                }
            }
            return value
        }
        when (dragMode) {
            DragMode.LEFT, DragMode.TOP_LEFT, DragMode.BOTTOM_LEFT -> {
                val s = snapEdge(rect.left, xs, true)
                val d = s - rect.left
                rect.left = s
                if (dragMode == DragMode.LEFT) { /* only left */ }
            }
            DragMode.RIGHT, DragMode.TOP_RIGHT, DragMode.BOTTOM_RIGHT -> {
                rect.right = snapEdge(rect.right, xs, true)
            }
            DragMode.TOP -> rect.top = snapEdge(rect.top, ys, false)
            DragMode.BOTTOM -> rect.bottom = snapEdge(rect.bottom, ys, false)
            DragMode.MOVE -> {
                // 中心磁吸
                val cx = rect.centerX()
                val cy = rect.centerY()
                val scx = snapEdge(cx, xs, true)
                val scy = snapEdge(cy, ys, false)
                rect.offset(scx - cx, scy - cy)
            }
            else -> {}
        }
    }

    private fun keepMoveInsideBounds(rect: RectF) {
        if (width <= 0 || height <= 0) return
        val minL = safeLeft
        val minT = safeTop
        val maxR = width - safeRight
        val maxB = height - safeBottom
        val dx = when {
            rect.left < minL -> minL - rect.left
            rect.right > maxR -> maxR - rect.right
            else -> 0f
        }
        val dy = when {
            rect.top < minT -> minT - rect.top
            rect.bottom > maxB -> maxB - rect.bottom
            else -> 0f
        }
        rect.offset(dx, dy)
    }

    private fun clampRegionToBounds() {
        if (width <= 0 || height <= 0) return
        val minL = safeLeft
        val minT = safeTop
        val maxR = (width - safeRight).coerceAtLeast(minL + minSize)
        val maxB = (height - safeBottom).coerceAtLeast(minT + minSize)
        if (region.width() < minSize) region.right = min(maxR, region.left + minSize)
        if (region.height() < minSize) region.bottom = min(maxB, region.top + minSize)
        region.left = region.left.coerceIn(minL, max(minL, maxR - minSize))
        region.top = region.top.coerceIn(minT, max(minT, maxB - minSize))
        region.right = region.right.coerceIn(region.left + minSize, maxR)
        region.bottom = region.bottom.coerceIn(region.top + minSize, maxB)
    }

    private enum class DragMode {
        NONE, MOVE, TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT, LEFT, RIGHT, TOP, BOTTOM
    }
}
