package top.hpa888.box

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 试捕结果「一键复制」的载荷格式。
 *
 * 复制内容是用户用来报障的唯一证据，必须同时带上读屏原文与解析结果，
 * 否则无法区分「读屏漏捕」和「解析错位」两类完全不同的故障。
 */
class QuizProbeCopyFormatterTest {

    @Test
    fun `载荷同时包含原文与解析结果并给出行数选项数诊断`() {
        val text = QuizProbeCopyFormatter.build(
            status = "试捕完成，请核对后保存",
            raw = "这个标志是何含义？\nT形交叉路口\nY形交叉路口\n十字交叉路口\n环形交叉路口\n答案：十字交叉路口",
            question = "这个标志是何含义？",
            options = "T形交叉路口\nY形交叉路口\n十字交叉路口\n环形交叉路口",
            answer = "十字交叉路口",
            analysis = "",
            timestamp = "2026-08-18 12:40:32",
        )

        assertEquals(
            """
            【Box 试捕结果】
            时间：2026-08-18 12:40:32
            状态：试捕完成，请核对后保存
            诊断：原文 6 行 / 解析选项 4 个 / 答案已填 / 解析未填

            --- 读屏原文 ---
            这个标志是何含义？
            T形交叉路口
            Y形交叉路口
            十字交叉路口
            环形交叉路口
            答案：十字交叉路口

            --- 解析题干 ---
            这个标志是何含义？

            --- 解析选项 ---
            1. T形交叉路口
            2. Y形交叉路口
            3. 十字交叉路口
            4. 环形交叉路口

            --- 解析答案 ---
            十字交叉路口
            """.trimIndent(),
            text,
        )
    }

    @Test
    fun `原文缺失时明确标注空缺而不是静默省略`() {
        val text = QuizProbeCopyFormatter.build(
            status = "试捕失败：读不到前台窗口",
            raw = "   ",
            question = "",
            options = "",
            answer = "",
            analysis = "",
            timestamp = "2026-08-18 12:41:00",
        )

        assertTrue(text.contains("诊断：原文 0 行 / 解析选项 0 个 / 答案未填 / 解析未填"))
        assertTrue(text.contains("--- 读屏原文 ---\n（空）"))
        assertTrue(text.contains("--- 解析题干 ---\n（空）"))
        assertTrue(text.contains("--- 解析选项 ---\n（空）"))
        assertTrue(text.contains("--- 解析答案 ---\n（空）"))
    }

    @Test
    fun `解析文本存在时作为独立段落附在末尾`() {
        val text = QuizProbeCopyFormatter.build(
            status = "试捕完成",
            raw = "题干",
            question = "题干",
            options = "甲\n乙",
            answer = "甲",
            analysis = "考点：路口标志",
            timestamp = "2026-08-18 12:42:00",
        )

        assertTrue(text.contains("/ 解析已填"))
        assertTrue(text.trimEnd().endsWith("--- 题目解析 ---\n考点：路口标志"))
    }

    @Test
    fun `选项行内空行与前后空白不参与编号`() {
        val text = QuizProbeCopyFormatter.build(
            status = "试捕完成",
            raw = "题干\n甲\n乙",
            question = " 题干 ",
            options = "  甲  \n\n 乙 \n",
            answer = " 甲 ",
            analysis = "",
            timestamp = "2026-08-18 12:43:00",
        )

        assertTrue(text.contains("诊断：原文 3 行 / 解析选项 2 个"))
        assertTrue(text.contains("--- 解析选项 ---\n1. 甲\n2. 乙"))
        assertTrue(text.contains("--- 解析答案 ---\n甲"))
    }
}
