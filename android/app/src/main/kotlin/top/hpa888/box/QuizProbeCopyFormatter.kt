package top.hpa888.box

/**
 * 试捕结果「一键复制」载荷。
 *
 * 故意做成不依赖 Android 框架的纯函数：既能单测，也保证悬浮窗与录入窗
 * 两条链路复制出的文本完全一致。
 *
 * 载荷必须同时带读屏原文与解析结果——只有原文能证明是否漏捕，
 * 只有解析结果能证明是否错位，缺一个就无法定位故障。
 */
object QuizProbeCopyFormatter {

    fun build(
        status: String,
        raw: String,
        question: String,
        options: String,
        answer: String,
        analysis: String,
        timestamp: String,
    ): String {
        val rawLines = nonBlankLines(raw)
        val optionLines = nonBlankLines(options)
        val answerText = answer.trim()
        val analysisText = analysis.trim()

        val diagnosis = buildString {
            append("原文 ${rawLines.size} 行")
            append(" / 解析选项 ${optionLines.size} 个")
            append(if (answerText.isEmpty()) " / 答案未填" else " / 答案已填")
            append(if (analysisText.isEmpty()) " / 解析未填" else " / 解析已填")
        }

        val sections = mutableListOf<String>()
        sections += listOf(
            "【Box 试捕结果】",
            "时间：$timestamp",
            "状态：${status.trim().ifEmpty { "（无）" }}",
            "诊断：$diagnosis",
        ).joinToString("\n")
        sections += section("读屏原文", rawLines.joinToString("\n"))
        sections += section("解析题干", question.trim())
        sections += section(
            "解析选项",
            optionLines.mapIndexed { i, line -> "${i + 1}. $line" }.joinToString("\n"),
        )
        sections += section("解析答案", answerText)
        if (analysisText.isNotEmpty()) {
            sections += section("题目解析", analysisText)
        }
        return sections.joinToString("\n\n")
    }

    private fun section(title: String, body: String): String =
        "--- $title ---\n" + body.ifBlank { "（空）" }

    private fun nonBlankLines(source: String): List<String> =
        source.split('\n').map { it.trim() }.filter { it.isNotEmpty() }
}
