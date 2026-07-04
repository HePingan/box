import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

/// Legado 标准 CSS 选择器规则解析器
///
/// 支持格式：
///   `class.novelinfo-l@tag.li.0@text`
///   `class.info@tag.span.1@text`
///   `class.pt-ll-l@tag.a@tag.img@src`
///   `id.chaptercontent@textNodes`
/// 索引语法：
///   `tag.span.0` — 第一个匹配的 span
///   `class.item.2` — 第三个匹配的 class 元素
class CssSelectorParser {
  const CssSelectorParser();

  /// 解析复合规则，返回匹配的文本或属性
  static String? parse(String rule, String html) {
    if (rule.isEmpty) return null;

    final segments = rule.split('@').map((s) => s.trim()).toList();
    if (segments.isEmpty) return null;

    final doc = html_parser.parse(html);
    List<Element> candidates =
        doc.body?.nodes.whereType<Element>().toList() ?? [];

    if (candidates.isEmpty) return null;

    for (final seg in segments) {
      if (seg.isEmpty) continue;

      // ── 从 seg 中提取「选择器部分」和「索引」 ──
      // 支持纯索引 .N / tag.span.0 / class.foo.1 / id.bar.2 语法
      final String effectiveSelector;
      final int? indexValue;

      // 1) 纯索引 .N
      final pureIndexMatch = RegExp(r'^\.(\d+)$').firstMatch(seg);
      if (pureIndexMatch != null) {
        final idx = int.parse(pureIndexMatch.group(1)!);
        if (idx >= 0 && idx < candidates.length) {
          candidates = [candidates[idx]];
        } else {
          return null;
        }
        continue;
      }

      // 2) 选择器 + 索引 tag.span.0 / class.foo.1 / id.bar.2
      final idxMatch = RegExp(r'^(.+)\.(\d+)$').firstMatch(seg);
      if (idxMatch != null) {
        final base = idxMatch.group(1)!;
        final idx = int.parse(idxMatch.group(2)!);
        if (base.startsWith('tag.') ||
            base.startsWith('class.') ||
            base.startsWith('id.')) {
          effectiveSelector = base;
          indexValue = idx;
        } else {
          effectiveSelector = seg;
          indexValue = null;
        }
      } else {
        effectiveSelector = seg;
        indexValue = null;
      }

      // ── 后缀提取器 ──
      if (const {'text', 'src', 'href', 'textNodes'}
          .contains(effectiveSelector)) {
        // 最后一个 seg 才做提取，否则继续下钻
        continue;
      }

      // ── 选择器匹配 ──
      final next = <Element>[];
      for (final el in candidates) {
        selectInto(el, effectiveSelector, next);
      }
      candidates = next;
      if (candidates.isEmpty) return null;

      // ── 应用索引 ──
      if (indexValue != null) {
        if (indexValue >= 0 && indexValue < candidates.length) {
          candidates = [candidates[indexValue]];
        } else {
          return null;
        }
      }
    }

    // ── 最终提取 ──
    final actualLast = segments.last;

    if (actualLast == 'textNodes') {
      final texts = <String>[];
      for (final el in candidates) {
        _collectTextNodes(el, texts);
      }
      return texts.join('\n').trim();
    }
    if (actualLast == 'src') {
      return candidates
          .map((e) => e.attributes['src'] ?? '')
          .join('\n')
          .trim();
    }
    if (actualLast == 'href') {
      return candidates
          .map((e) => e.attributes['href'] ?? '')
          .join('\n')
          .trim();
    }
    return candidates.map(extractText).join('\n').trim();
  }

  /// 将选择器段应用到元素，结果加入 out
  static void selectInto(Element el, String selector, List<Element> out) {
    if (selector.startsWith('class.')) {
      final cls = selector.substring(6);
      if (el.classes.any((c) => c.contains(cls))) {
        out.add(el);
      }
      out.addAll(el.querySelectorAll('[class*="$cls"]'));
      return;
    }

    if (selector.startsWith('id.')) {
      final idVal = selector.substring(3);
      if (el.id == idVal) {
        out.add(el);
      }
      out.addAll(el.querySelectorAll('#$idVal'));
      return;
    }

    if (selector.startsWith('tag.')) {
      final tag = selector.substring(4).toLowerCase();
      if (el.localName?.toLowerCase() == tag) out.add(el);
      out.addAll(el.getElementsByTagName(tag));
      return;
    }

    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9]*$').hasMatch(selector)) {
      out.addAll(el.getElementsByTagName(selector.toLowerCase()));
      return;
    }

    try {
      out.addAll(el.querySelectorAll(selector));
    } catch (_) {}
  }

  static String extractText(Element el) {
    final buffer = StringBuffer();
    _extractTextRecursive(el, buffer);
    return buffer.toString().trim();
  }

  /// 递归提取文本，块级元素后插入换行以保留段落结构
  static void _extractTextRecursive(Node node, StringBuffer buffer) {
    if (node is Text) {
      buffer.write(node.text);
      return;
    }
    if (node is Element) {
      final tag = node.localName?.toLowerCase() ?? '';
      final isBlock = _blockTags.contains(tag);
      final isBr = tag == 'br';

      if (isBr) {
        buffer.write('\n');
        return;
      }

      // 块级元素：在内容前插入换行（除非在开头）
      if (isBlock && buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
        buffer.write('\n');
      }

      for (final child in node.nodes) {
        _extractTextRecursive(child, buffer);
      }
    }
  }

  /// 块级 HTML 标签（提取文本时在这些标签后插入换行）
  static const Set<String> _blockTags = {
    'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'li', 'ol', 'ul', 'blockquote', 'section', 'article',
    'nav', 'header', 'footer', 'aside', 'main', 'figure',
    'figcaption', 'details', 'summary', 'pre', 'hr',
  };

  static void _collectTextNodes(Node node, List<String> out) {
    if (node is Text) {
      final t = node.text.trim();
      if (t.isNotEmpty) out.add(t);
      return;
    }
    if (node is Element) {
      final tag = node.localName?.toLowerCase() ?? '';

      // <br> → 段落分隔
      if (tag == 'br') {
        out.add('');
        return;
      }

      // 块级元素：在进入第一个子节点前，如果 out 已有内容则追加空白行分隔
      final isBlock = _blockTags.contains(tag);
      if (isBlock && out.isNotEmpty && out.last.isNotEmpty) {
        out.add('');
      }

      for (final child in node.nodes) {
        _collectTextNodes(child, out);
      }
    }
  }
}
