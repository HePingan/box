// 在**取到的 HTML 文本**上跑书源规则（与页面里的 JS 引擎同一套语义）。
//
// 为什么要有这一份：
//   * 搜索页 / 详情页的数据本来就在 HTML 里（真页面实测：卡片 326 处、目录 1212 处），
//     不必"打开页面 → 等渲染 → 在 DOM 里查" —— 取文本直接解析**快得多**；
//   * 而且这条路**可以离线单测**（不需要 WebView），假目标也不用再模拟浏览器行为。
//
// 语义必须与 `kComicSourceEngineJs` 对齐（同一份规则在两处跑出不同结果是最坏的情况）：
//   * 步骤按 `@` 切、去空白；
//   * 单 token 且（是取值名 或 写在最后一段）→ **取值步**（先判它，再判选择器）；
//   * `.N` 单独成段 → 取第 N 个；
//   * 其余当选择器（合成 CSS 的逻辑复用 parseComicRule，只有一处）；
//   * 取值步会**丢掉空值**；按卡片取字段时"这张卡取不到"补空串 ⇒ **卡片数不变**（不会错位）。
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'comic_source.dart';

/// 取值名（与页面引擎的 VALUE_HOLDERS 一致）。
const List<String> kComicHtmlValueHolders = [
  'text',
  'html',
  'href',
  'src',
  'alt',
  'title',
];

/// HTML 规则引擎出错（规则不认识 / 只有选择器没有取值步）。
class ComicHtmlRuleException implements Exception {
  const ComicHtmlRuleException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 解析 HTML 文本成文档。
Document parseComicHtml(String html) => html_parser.parse(html);

/// 整页取值（对应页面引擎的 `legadoExtract`）。
List<String> comicHtmlExtract(Document doc, String rule) {
  final root = doc.documentElement;
  if (root == null) return const [];
  return _extractWithRoot([root], rule);
}

/// 按**卡片**取字段：每张卡片各取一个值，顺序与卡片一致（取不到给空串）。
///
/// 与页面引擎的 `legadoExtractInEach` 一致 —— 拉平后按序号配对会错位（真源上
/// 每卡 2 个链接、77 卡对 154 条 ⇒ 点进去会开错书）。
List<String> comicHtmlPerElement(Document doc, String cardRule, String fieldRule) {
  final cards = comicHtmlNodes(doc, cardRule);
  if (cards.isEmpty) return const [];
  // 字段规则缺省（这份源没写 author 这类字段）→ 每张卡补一个空值，**卡片数不变**：
  // 与页面引擎那边"取不到就给空、不报错"的口径一致，`_at` 会把它当"没有"。
  if (fieldRule.trim().isEmpty) return List<String>.filled(cards.length, '');
  final scoped = stripComicRootPrefix(cardRule, fieldRule);
  final out = <String>[];
  for (final card in cards) {
    final vals = _extractWithRoot([card], scoped);
    out.add(vals.isEmpty ? '' : vals.first);
  }
  return out;
}

/// 只取卡片节点（对应页面引擎的 `legadoExtractNodes`）。
List<Element> comicHtmlNodes(Document doc, String rootRule) {
  final root = doc.documentElement;
  if (root == null) return const [];
  final parsed = parseComicRule(rootRule, valueRule: false);
  if (!parsed.ok) throw ComicHtmlRuleException('不认识的规则段: $rootRule');
  final sel = parsed.steps.whereType<ComicSelectorStep>().lastOrNull;
  if (sel == null) throw ComicHtmlRuleException('不认识的规则段: $rootRule');
  var nodes = _queryDown([root], sel.css);
  if (sel.index != null) {
    final n = sel.index!;
    nodes = n < nodes.length ? [nodes[n]] : const [];
  }
  return nodes;
}

/// 去掉字段规则里重复写了一遍的卡片选择器前缀（页面引擎同款）。
String stripComicRootPrefix(String rootRule, String fieldRule) {
  final r = rootRule.trim();
  final f = fieldRule.trim();
  if (r.isNotEmpty && f.startsWith(r)) {
    final rest = f.substring(r.length);
    if (rest.startsWith('@')) return rest.substring(1);
  }
  return f;
}

List<String> _extractWithRoot(List<Element> rootNodes, String rawRule) {
  final rule = rawRule.trim();
  if (rule.isEmpty) throw const ComicHtmlRuleException('（空规则）');
  final steps = rule.split('@').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  var nodes = rootNodes;
  List<String>? values;
  for (var i = 0; i < steps.length; i++) {
    final step = steps[i];
    final idxOnly = RegExp(r'^\.(\d+)$').firstMatch(step);
    if (idxOnly != null) {
      if (nodes.isEmpty) {
        throw ComicHtmlRuleException('索引步 $step 之前没有任何节点');
      }
      final n = int.parse(idxOnly.group(1)!);
      nodes = n < nodes.length ? [nodes[n]] : const [];
      continue;
    }
    final tokens = step.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final isLast = i == steps.length - 1;
    // ⚠️ 取值步必须**先**判：`href` 和 `amp-img` 长得一样，差别只在"是取值名 或 写在最后"。
    if (tokens.length == 1 &&
        RegExp(r'^[A-Za-z][A-Za-z0-9_-]*$').hasMatch(step) &&
        (kComicHtmlValueHolders.contains(step) || isLast)) {
      values = nodes
          .map((n) => _valueOf(n, step))
          .where((v) => v != '')
          .toList();
      continue;
    }
    final parsed = parseComicRule(step, valueRule: false);
    if (!parsed.ok || parsed.steps.isEmpty) {
      throw ComicHtmlRuleException('不认识的规则段: $step');
    }
    final sel = parsed.steps.last;
    if (sel is! ComicSelectorStep) {
      throw ComicHtmlRuleException('不认识的规则段: $step');
    }
    nodes = _queryDown(nodes, sel.css);
    if (sel.index != null) {
      final n = sel.index!;
      if (n >= nodes.length) continue; // 越界 = 没有（与页面引擎一致：不报错、给空）
      nodes = [nodes[n]];
    }
  }
  if (values == null) {
    throw const ComicHtmlRuleException('规则只有选择器、没有取值步（缺 text 或属性名）');
  }
  return values;
}

/// 从这批节点往下查（对应页面引擎的 `descend`）：一次选择器 = 一次下探。
List<Element> _queryDown(List<Element> nodes, String css) {
  final out = <Element>[];
  for (final n in nodes) {
    out.addAll(n.querySelectorAll(css));
  }
  return out;
}

String _valueOf(Element n, String step) {
  if (step == 'text') return n.text.trim();
  if (step == 'html') return n.innerHtml;
  return (n.attributes[step] ?? '').trim();
}
