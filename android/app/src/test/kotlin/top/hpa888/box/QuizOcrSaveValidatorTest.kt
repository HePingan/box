package top.hpa888.box

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * OCR 录入窗保存前校验的纯逻辑测试。
 *
 * 背景：手动「保存题库」和「一键录入」批量保存各自内联了一份校验代码，
 * 两份实现已经漂移（手动那份的字母答案正则漏了 IGNORE_CASE），导致同一道题
 * 批量能存、手动被拦。这里把校验抽成单一实现并钉住行为。
 */
class QuizOcrSaveValidatorTest {

    @Test
    fun `选项少于两项不能保存`() {
        val r = QuizOcrSaveValidator.validate(
            question = "红灯可以通行吗",
            optionsRaw = "A. 可以",
            answerRaw = "",
        )
        assertFalse(r.canSave)
        assertEquals(1, r.optionValues.size)
    }

    @Test
    fun `题干为空不能保存`() {
        val r = QuizOcrSaveValidator.validate(
            question = "   ",
            optionsRaw = "A. 正确\nB. 错误",
            answerRaw = "正确",
        )
        assertFalse(r.canSave)
        assertEquals(QuizOcrSaveValidator.Reason.EMPTY_QUESTION, r.reason)
    }

    @Test
    fun `字母前缀会被剥掉只留选项原文`() {
        val r = QuizOcrSaveValidator.validate(
            question = "限速多少",
            optionsRaw = "A. 60公里\nB、80公里\nC：100公里",
            answerRaw = "B",
        )
        assertTrue(r.canSave)
        assertEquals(listOf("60公里", "80公里", "100公里"), r.optionValues)
    }

    @Test
    fun `判断题被识别为判断题型`() {
        val r = QuizOcrSaveValidator.validate(
            question = "红灯停绿灯行",
            optionsRaw = "A. 正确\nB. 错误",
            answerRaw = "正确",
        )
        assertTrue(r.canSave)
        assertTrue(r.isTrueFalse)
    }

    @Test
    fun `小写字母答案也要判为合法 — 手动保存曾漏 IGNORE_CASE`() {
        val r = QuizOcrSaveValidator.validate(
            question = "限速多少",
            optionsRaw = "A. 60公里\nB. 80公里",
            answerRaw = "b",
        )
        assertTrue("小写 b 应与批量保存一致判为合法字母答案", r.canSave)
    }

    @Test
    fun `全角字母答案合法`() {
        val r = QuizOcrSaveValidator.validate(
            question = "限速多少",
            optionsRaw = "A. 60公里\nB. 80公里",
            answerRaw = "Ｂ",
        )
        assertTrue(r.canSave)
    }

    @Test
    fun `答案带前缀会被剥离后再比对`() {
        val r = QuizOcrSaveValidator.validate(
            question = "限速多少",
            optionsRaw = "A. 60公里\nB. 80公里",
            answerRaw = "答案：80公里",
        )
        assertTrue(r.canSave)
    }

    @Test
    fun `答案完全不在选项内要拦住`() {
        val r = QuizOcrSaveValidator.validate(
            question = "限速多少",
            optionsRaw = "A. 60公里\nB. 80公里",
            answerRaw = "120公里",
        )
        assertFalse(r.canSave)
        assertEquals(QuizOcrSaveValidator.Reason.ANSWER_MISMATCH, r.reason)
    }

    @Test
    fun `答案为空放行 — 留给人工补`() {
        val r = QuizOcrSaveValidator.validate(
            question = "限速多少",
            optionsRaw = "A. 60公里\nB. 80公里",
            answerRaw = "",
        )
        assertTrue(r.canSave)
    }

    @Test
    fun `重复选项要去重 — 同一选项 OCR 串两遍不该充数`() {
        val r = QuizOcrSaveValidator.validate(
            question = "限速多少",
            optionsRaw = "A. 60公里\nB. 60公里",
            answerRaw = "60公里",
        )
        assertFalse("两项内容相同等于只有一项，不足两项", r.canSave)
    }

    @Test
    fun `结构描述文案给出题型与项数`() {
        val r = QuizOcrSaveValidator.validate(
            question = "限速多少",
            optionsRaw = "A. 60公里\nB. 80公里\nC. 100公里",
            answerRaw = "B",
        )
        assertEquals("识别到：选择 · 3 项", r.structureLabel)
    }
}
