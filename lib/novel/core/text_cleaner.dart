/// 小说正文文本清洗工具
class TextCleaner {
  TextCleaner._();

  /// 剥离 HTML 标签并归一化空白（适用于所有小说源正文清洗）
  static String stripHtml(String text) {
    var result = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('\u3000', ' ')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '')
        .replaceAll(
          RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    return normalizeWhitespace(result);
  }

  /// 归一化空白字符（折叠空格、归一化换行、去除首尾空白）
  static String cleanRaw(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 归一化换行符和多余空行
  static String normalizeWhitespace(String text) {
    return text
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// 判定「正文被压平」的最小长度阈值。低于此长度的无换行文本视为正常
  /// （空章节提示、极短章节），不触发兜底断段。
  static const int flatContentMinLength = 200;

  /// 正文分段归一化：剥离 HTML、还原段落换行，但**保留** `\n`。
  ///
  /// 这是**全源共享的唯一一份**正文分段实现。各源的 `_cleanText` 都应调用它，
  /// 不要各自拼 stripHtml —— 历史上 wtzw 源裸调 [stripHtml] 导致整章压平成
  /// 一行（stripHtml 会把 `\u3000` 归一化成空格，抹掉唯一的分段信号）。
  ///
  /// 兼容三种真实源形态：
  ///   1. HTML 正文（`<br>` / `<p>` 分段）→ stripHtml 转成 `\n`
  ///   2. JSON 字符串里的转义换行（字面量 `\n` / `\r\n`）→ 先还原成真换行
  ///   3. 无任何换行的纯文本 → 全角空格缩进 / 中文句末标点兜底分段
  ///
  /// 注意**不能**用 [cleanRaw]：它把 `\s+` 折叠成单空格，而 `\s` 包含 `\n`，
  /// 会消灭全部段落换行。[cleanRaw] 只适合书名、作者这类单行字段。
  static String normalizeParagraphs(String raw) {
    if (raw.isEmpty) return '';

    // JSON 里常见字面量 `\n`（两个字符）。部分源会双重转义，这里还原一次。
    var text = raw
        .replaceAll(r'\r\n', '\n')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\t', ' ');

    // 关键顺序：全角空格缩进的检测必须在 stripHtml **之前**。
    // stripHtml 会把 \u3000 归一化成普通空格，段首缩进这个分段信号就没了。
    if (!text.contains('\n') && text.contains('\u3000\u3000')) {
      text = text.replaceAll(RegExp(r'\u3000{2,}'), '\n');
    }

    // 剥离 HTML 标签（内部会把 <br>/</p> 转成 \n 并归一化空白，保留换行）
    text = stripHtml(text);

    // 仍无换行说明源把整章塞成一行纯文本且没有缩进，按句末标点兜底断段。
    if (!text.contains('\n') && text.length >= flatContentMinLength) {
      text = _splitFlatText(text);
    }

    return text;
  }

  /// 无换行长文本的兜底分段。
  ///
  /// 在中文句末标点（。！？…）+ 右引号收尾处断段。这是启发式的，宁可少断
  /// 也不断错：只在标点后紧跟非标点字符时才断，避免把 `。」` 或 `……` 拆开。
  ///
  /// 全角空格缩进的形态由 [normalizeParagraphs] 在 [stripHtml] 前处理，
  /// 不在这里重复（stripHtml 会吃掉 `\u3000`，到这里已无缩进信号）。
  static String _splitFlatText(String flat) {
    final text = flat.trim();
    if (text.isEmpty) return '';

    return text.replaceAllMapped(
      RegExp(r'([。！？…]+[”」』）]*)(?=[^。！？…”」』）\s])'),
      (m) => '${m.group(1)}\n',
    );
  }
}
