package com.example.box

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PointF
import android.graphics.RectF
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import kotlin.math.max
import kotlin.math.min

/**
 * 驾考识别区域选择器
 *
 * 显示一个半透明遮罩 + 可拖动/缩放的选择框。
 * 支持四角和四边拖动调整大小。
 */
class RegionSelectorView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    companion object {
        private const val MIN_SIZE = 80
        private const val HANDLE_RADIUS = 18f
        private const val STROKE_WIDTH = 2f
        private const val DOUBLE_TAP_MAX_DISTANCE = 50f
        private const val DOUBLE_TAP_MAX_TIME = 300
    }

    private val bgPaint = Paint().apply {
        color = Color.parseColor("#33000000")
        style = Paint.Style.FILL
    }

    private val borderPaint = Paint().apply {
        color = Color.parseColor("#4F46E5")
        style = Paint.Style.STROKE
        strokeWidth = STROKE_WIDTH
        isAntiAlias = true
    }

    private val handlePaint = Paint().apply {
        color = Color.WHITE
        style = Paint.Style.FILL
        isAntiAlias = true
    }

    private val textPaint = Paint().apply {
        color = Color.WHITE
        textSize = 32f
        isAntiAlias = true
    }

    private var region = RectF(100f, 300f, 500f, 800f)
    private val tempRegion = RectF()

    private var dragMode = DragMode.NONE
    private var lastPoint: PointF = PointF()

    private var onRegionChanged: ((RectF) -> Unit)? = null
    private var onRegionConfirmed: (() -> Unit)? = null

    private var lastTapTime = 0L
    private var lastTapPoint: PointF = PointF()

    fun getRegion(): RectF = RectF(region)

    fun setRegion(r: RectF) {
        region.set(r)
        invalidate()
    }

    fun setOnRegionChangedListener(listener: (RectF) -> Unit) {
        onRegionChanged = listener
    }

    fun setOnRegionConfirmedListener(listener: () -> Unit) {
        onRegionConfirmed = listener
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val saved = canvas.saveLayer(0f, 0f, width.toFloat(), height.toFloat(), null)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), bgPaint)
        bgPaint.color = Color.TRANSPARENT
        canvas.drawRect(region, bgPaint)
        bgPaint.color = Color.parseColor("#33000000")

        canvas.drawRect(region, borderPaint)

        val handles = getHandleCenters()
        handles.forEach { center ->
            canvas.drawCircle(center.x, center.y, HANDLE_RADIUS, handlePaint)
            canvas.drawCircle(center.x, center.y, HANDLE_RADIUS - 4f, borderPaint)
        }

        canvas.drawText("拖动调整识别区域", region.left + 12f, region.top - 24f, textPaint)
        canvas.restoreToCount(saved)
    }

    private fun getHandleCenters(): List<PointF> {
        return listOf(
            PointF(region.left, region.top),
            PointF(region.right, region.top),
            PointF(region.left, region.bottom),
            PointF(region.right, region.bottom),
            PointF(region.left, region.centerY()),
            PointF(region.right, region.centerY()),
            PointF(region.centerX(), region.top),
            PointF(region.centerX(), region.bottom)
        )
    }

    private fun hitHandle(x: Float, y: Float): DragMode? {
        val handles = getHandleCenters()
        handles.forEachIndexed { index, p ->
            if (Math.hypot((x - p.x).toDouble(), (y - p.y).toDouble()) < HANDLE_RADIUS * 1.5) {
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

    private fun hitInside(x: Float, y: Float): Boolean {
        return x >= region.left && x <= region.right && y >= region.top && y <= region.bottom
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val x = event.x
        val y = event.y

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                lastPoint.set(x, y)
                dragMode = hitHandle(x, y) ?: if (hitInside(x, y)) DragMode.MOVE else DragMode.NONE
                if (dragMode != DragMode.NONE) parent.requestDisallowInterceptTouchEvent(true)

                // 双击检测
                val now = System.currentTimeMillis()
                val dx = x - lastTapPoint.x
                val dy = y - lastTapPoint.y
                if (now - lastTapTime < DOUBLE_TAP_MAX_TIME &&
                    Math.hypot(dx.toDouble(), dy.toDouble()) < DOUBLE_TAP_MAX_DISTANCE) {
                    onRegionConfirmed?.invoke()
                    return true
                }
                lastTapTime = now
                lastTapPoint.set(x, y)
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = x - lastPoint.x
                val dy = y - lastPoint.y
                tempRegion.set(region)
                when (dragMode) {
                    DragMode.MOVE -> {
                        tempRegion.offset(dx, dy)
                        tempRegion.left = max(0f, tempRegion.left)
                        tempRegion.top = max(0f, tempRegion.top)
                        tempRegion.right = min(width.toFloat(), tempRegion.right)
                        tempRegion.bottom = min(height.toFloat(), tempRegion.bottom)
                    }
                    DragMode.TOP_LEFT -> {
                        tempRegion.left = min(tempRegion.right - MIN_SIZE, tempRegion.left + dx)
                        tempRegion.top = min(tempRegion.bottom - MIN_SIZE, tempRegion.top + dy)
                    }
                    DragMode.TOP_RIGHT -> {
                        tempRegion.right = max(tempRegion.left + MIN_SIZE, tempRegion.right + dx)
                        tempRegion.top = min(tempRegion.bottom - MIN_SIZE, tempRegion.top + dy)
                    }
                    DragMode.BOTTOM_LEFT -> {
                        tempRegion.left = min(tempRegion.right - MIN_SIZE, tempRegion.left + dx)
                        tempRegion.bottom = max(tempRegion.top + MIN_SIZE, tempRegion.bottom + dy)
                    }
                    DragMode.BOTTOM_RIGHT -> {
                        tempRegion.right = max(tempRegion.left + MIN_SIZE, tempRegion.right + dx)
                        tempRegion.bottom = max(tempRegion.top + MIN_SIZE, tempRegion.bottom + dy)
                    }
                    DragMode.LEFT -> {
                        tempRegion.left = min(tempRegion.right - MIN_SIZE, tempRegion.left + dx)
                    }
                    DragMode.RIGHT -> {
                        tempRegion.right = max(tempRegion.left + MIN_SIZE, tempRegion.right + dx)
                    }
                    DragMode.TOP -> {
                        tempRegion.top = min(tempRegion.bottom - MIN_SIZE, tempRegion.top + dy)
                    }
                    DragMode.BOTTOM -> {
                        tempRegion.bottom = max(tempRegion.top + MIN_SIZE, tempRegion.bottom + dy)
                    }
                    else -> {}
                }
                region.set(tempRegion)
                invalidate()
                lastPoint.set(x, y)
                onRegionChanged?.invoke(getRegion())
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                dragMode = DragMode.NONE
                parent.requestDisallowInterceptTouchEvent(false)
            }
        }
        return true
    }

    private enum class DragMode {
        NONE, MOVE, TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT, LEFT, RIGHT, TOP, BOTTOM
    }
}