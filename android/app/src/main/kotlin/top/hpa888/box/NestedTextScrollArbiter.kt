package top.hpa888.box

/**
 * 决定多行输入框内的竖向拖动该由谁消费。
 *
 * OCR 录入窗把 5 个可滚动的多行 EditText 放进同一个 ScrollView。
 * 手指落在输入框上时，默认行为是输入框吃掉整个竖向手势：
 * 内容不足一屏时面板完全滑不动，内容滚到边界后也不会把手势交回面板，
 * 用户感受就是「卡住 / 不丝滑」。
 *
 * 规则：只有当输入框在手势方向上真的还能滚动时才由它消费，否则交给父面板。
 */
object NestedTextScrollArbiter {

    /**
     * @param canScrollUp 输入框内部还能往上滚（顶部有被裁掉的内容）
     * @param canScrollDown 输入框内部还能往下滚（底部有被裁掉的内容）
     * @param dy 手指位移，正值表示手指下移（内容向下走、即向上滚动）
     * @return true 表示应由父级 ScrollView 消费该手势
     */
    fun shouldParentScroll(canScrollUp: Boolean, canScrollDown: Boolean, dy: Float): Boolean {
        // 输入框本身不可滚动：手势必须交给面板，否则面板滑不动。
        if (!canScrollUp && !canScrollDown) return true
        // 位移尚未成形时不抢，等方向明确再判定。
        if (dy == 0f) return false
        return if (dy > 0f) !canScrollUp else !canScrollDown
    }
}
