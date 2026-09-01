package top.hpa888.box

/**
 * OCR 录入保存前的校验，手动保存与批量录入共用同一份实现。
 *
 * 为什么要抽出来：原先 [QuizOcrEntryOverlay.saveToBank]（手动）和
 * batchSaveAndSwipe（一键录入）各自内联了一份几乎相同的校验代码，两份已经漂移：
 *
 *  - 手动那份的字母答案正则 `^[A-DＡ-Ｄ]$` 漏了 `RegexOption.IGNORE_CASE`，
 *    批量那份有。结果 OCR 把答案读成小写 `b` 时，一键录入能存进去，
 *    手动点「保存题库」却被判「答案与选项不一致」拦下。
 *  - 两份都只按「非空」过滤选项，没有去重；OCR 把同一选项串成两行时，
 *    `size >= 2` 通过，实际只有一个有效选项。
 *
 * 纯函数无 Android 依赖，可直接单测。
 */
object QuizOcrSaveValidator {

    enum class Reason {
        OK,

        /** 题干为空。 */
        EMPTY_QUESTION,

        /** 去重后有效选项不足两项。 */
        NOT_ENOUGH_OPTIONS,

        /** 答案既不是选项原文，也不是合法字母序号。 */
        ANSWER_MISMATCH,
    }

    data class Result(
        val canSave: Boolean,
        val reason: Reason,
        val optionValues: List<String>,
        val isTrueFalse: Boolean,
        val answerValue: String,
        val structureLabel: String,
    )

    /** 选项行首的字母序号前缀，如 `A. ` / `B、` / `C：`。 */
    private val OPTION_PREFIX = Regex("^[A-DＡ-Ｄa-dａ-ｄ]\\s*[.、．:：)）\\s]+")

    /** 合法的单字母答案（含全角、忽略大小写）。 */
    private val LETTER_ANSWER = Regex("^[A-DＡ-Ｄ]$", RegexOption.IGNORE_CASE)

    private val ANSWER_PREFIXES = listOf("答案：", "答案:", "正确答案：", "正确答案:")

    /** 把选项文本按行切开，剥掉字母前缀，去空去重，保持原顺序。 */
    fun parseOptions(optionsRaw: String): List<String> {
        val seen = LinkedHashSet<String>()
        for (line in optionsRaw.lineSequence()) {
            val cleaned = line.trim().replaceFirst(OPTION_PREFIX, "").trim()
            if (cleaned.isNotEmpty()) seen.add(cleaned)
        }
        return seen.toList()
    }

    /** 剥掉「答案：」这类前缀。 */
    fun normalizeAnswer(answerRaw: String): String {
        var out = answerRaw.trim()
        for (p in ANSWER_PREFIXES) {
            if (out.startsWith(p)) {
                out = out.removePrefix(p).trim()
                break
            }
        }
        return out
    }

    fun validate(
        question: String,
        optionsRaw: String,
        answerRaw: String,
    ): Result {
        val q = question.trim()
        val optionValues = parseOptions(optionsRaw)
        val answerValue = normalizeAnswer(answerRaw)
        val isTrueFalse = optionValues.size == 2 &&
            optionValues.any { it == "正确" || it == "对" } &&
            optionValues.any { it == "错误" || it == "错" }
        val structureLabel =
            "识别到：${if (isTrueFalse) "判断" else "选择"} · ${optionValues.size} 项"

        fun fail(reason: Reason) = Result(
            canSave = false,
            reason = reason,
            optionValues = optionValues,
            isTrueFalse = isTrueFalse,
            answerValue = answerValue,
            structureLabel = structureLabel,
        )

        if (q.isEmpty()) return fail(Reason.EMPTY_QUESTION)
        if (optionValues.size < 2) return fail(Reason.NOT_ENOUGH_OPTIONS)

        // 答案留空是允许的：批量录入时后端会标「待补全」，人工再回填。
        val answerMatches = answerValue.isBlank() ||
            optionValues.any { option ->
                option == answerValue ||
                    option.contains(answerValue) ||
                    answerValue.contains(option)
            } ||
            LETTER_ANSWER.matches(answerValue)
        if (!answerMatches) return fail(Reason.ANSWER_MISMATCH)

        return Result(
            canSave = true,
            reason = Reason.OK,
            optionValues = optionValues,
            isTrueFalse = isTrueFalse,
            answerValue = answerValue,
            structureLabel = structureLabel,
        )
    }

    /** 给用户看的拦截原因文案。 */
    fun statusFor(result: Result): String = when (result.reason) {
        Reason.OK -> result.structureLabel
        Reason.EMPTY_QUESTION -> "题目不能为空"
        Reason.NOT_ENOUGH_OPTIONS ->
            "识别到 ${result.optionValues.size} 项选项，不能保存：请补齐至少两项"
        Reason.ANSWER_MISMATCH ->
            "${result.structureLabel}；答案不在选项内，请核对"
    }
}
