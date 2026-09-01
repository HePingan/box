package top.hpa888.box

import android.content.Context
import android.util.AttributeSet
import android.view.MotionEvent
import android.widget.FrameLayout

/**
 * 能可靠上报「本窗口正在被触摸」的根容器。
 *
 * 为什么不用 setOnTouchListener：那个回调只在事件派发到该 View 自身时触发。
 * 手势一旦被子 View（按钮、可滚动的 EditText、ScrollView）消费，父级的
 * OnTouchListener 就不会收到，于是漏掉绝大多数滑动场景。
 * dispatchTouchEvent 在派发链最前端，任何子 View 消费与否都会经过这里。
 */
class TouchAwareFrameLayout @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr) {

    /** true = 手指按下（手势进行中），false = 抬起或取消。 */
    var onTouchActiveChanged: ((Boolean) -> Unit)? = null

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> onTouchActiveChanged?.invoke(true)
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL ->
                onTouchActiveChanged?.invoke(false)
        }
        return super.dispatchTouchEvent(ev)
    }
}
