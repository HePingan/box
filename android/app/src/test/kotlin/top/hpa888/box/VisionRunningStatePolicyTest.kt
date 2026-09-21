package top.hpa888.box

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [VisionRunningStatePolicy] 决策测试（2026-09-19 报障：手动 AI 读屏时胶囊停在旧
 * 「未命中」、进度横幅不出现、结束后按钮残留「AI…」）。
 *
 * 直接调用生产代码断言输出值（非源码文本断言——吸取 254「测试绿而真机坏」教训）。
 *
 * 背景：手动 AI 读屏运行中，Dart 侧 `_tryVisionFallback` 会先推一条
 * `status=searching` 的内容（「新题 · AI 读屏中…」）。旧实现里这条推送穿过
 * `showOrUpdateAccessibilityOverlay` 汇聚点时无条件 `resetVisionButton()` →
 * `stopVisionTicker()` → 横幅 GONE、ticker 停转、按钮文字「AI…」永不还原。
 */
class VisionRunningStatePolicyTest {

    // ── 运行态保护：searching 推送不得掐死手动读屏的运行态 UI ──────

    /** 核心修复：手动读屏运行中 + searching 推送 → 保留 ticker/横幅/按钮态。 */
    @Test
    fun `手动读屏运行中收到searching推送应保留运行态UI`() {
        assertTrue(
            VisionRunningStatePolicy.shouldPreserveRunningUi(
                incomingStatus = "searching",
                visionRunning = true,
            )
        )
    }

    /** 手动读屏运行中 + 终态推送（命中/未命中/歧义）→ 正常复位。 */
    @Test
    fun `运行中收到终态推送应结束运行态`() {
        assertFalse(
            VisionRunningStatePolicy.shouldPreserveRunningUi(incomingStatus = "hit", visionRunning = true)
        )
        assertFalse(
            VisionRunningStatePolicy.shouldPreserveRunningUi(incomingStatus = "miss", visionRunning = true)
        )
        assertFalse(
            VisionRunningStatePolicy.shouldPreserveRunningUi(incomingStatus = "ambiguous", visionRunning = true)
        )
    }

    /** 非手动读屏期间（纯自动搜题）的 searching 推送不触发保护（正常渲染 searching 态）。 */
    @Test
    fun `未在手动读屏时searching推送不触发保护`() {
        assertFalse(
            VisionRunningStatePolicy.shouldPreserveRunningUi(incomingStatus = "searching", visionRunning = false)
        )
    }

    /** 状态大小写归一：Dart 侧恒小写，但防御性容忍大写/空白。 */
    @Test
    fun `状态归一化忽略大小写与空白`() {
        assertTrue(
            VisionRunningStatePolicy.shouldPreserveRunningUi(incomingStatus = " SEARCHING ", visionRunning = true)
        )
    }

    // ── 终态判定：哪些推送代表「读屏已结束」 ─────────────────────

    @Test
    fun `终态状态判定`() {
        assertTrue(VisionRunningStatePolicy.endsVisionRun("hit"))
        assertTrue(VisionRunningStatePolicy.endsVisionRun("miss"))
        assertTrue(VisionRunningStatePolicy.endsVisionRun("ambiguous"))
        // 归一化：大小写/空白不影响终态判定
        assertTrue(VisionRunningStatePolicy.endsVisionRun(" HIT "))
    }

    @Test
    fun `非终态状态判定`() {
        assertFalse(VisionRunningStatePolicy.endsVisionRun("searching"))
        assertFalse(VisionRunningStatePolicy.endsVisionRun("idle"))
        assertFalse(VisionRunningStatePolicy.endsVisionRun(""))
        assertFalse(VisionRunningStatePolicy.endsVisionRun("  "))
    }

    // ── 尺寸：schema v8 清除历史 SAVED 污染（0.80 新默认生效前提） ──

    /** schema < 8 的历史保存值必须清除一次，让 0.80 新默认落地。 */
    @Test
    fun `历史schema保存值应清除`() {
        assertTrue(OverlayGeometryPolicy.shouldDropSavedSizeForCompact(0))
        assertTrue(OverlayGeometryPolicy.shouldDropSavedSizeForCompact(7))
    }

    /** 已迁移（≥8）：尊重用户手拖，绝不再清（否则拖动永远记不住）。 */
    @Test
    fun `已迁移schema不再清除保存值`() {
        assertFalse(OverlayGeometryPolicy.shouldDropSavedSizeForCompact(8))
        assertFalse(OverlayGeometryPolicy.shouldDropSavedSizeForCompact(9))
    }
}
