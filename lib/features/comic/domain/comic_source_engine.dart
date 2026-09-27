// 漫画源取数引擎：在**页面里**（WebView 的 JS 环境）执行的规则解释器。
//
// 为什么引擎跑在页面里而不是 Dart 里：Legado 书源的规则里有 `<js>` / `@js:` 段，
// Dart 没有 JS 求值能力，而 WebView 有 —— 挑战、站点 JS、书源 JS 都在同一个环境里，
// 一次就都解决了（这也是 Legado 自己的做法）。
//
// 两个必须说清的边界（写在这里，也显示在自检界面上，不静默）：
//   * `java.t2s`（繁转简）：**未实现**，直接原样返回 —— 繁体章节会显示成繁体。
//   * `java.*` 只实现了这份源用到的那几个（getElements/attr/text），其它一律抛错，
//     让"规则跑不动"当场暴露，而不是悄悄返回空。
library;

/// 注入页面的引擎源码。用 `legadoExtract(rule)` 取数。
const String kComicSourceEngineJs = r'''
window.__comicSourceEngine = (function () {
  // 与 Dart 侧 parseComicRule 同一套语义：第一个 token 定类型，后面裸 token 是同一
  // 元素上的更多类名；索引 .N 可单独成 token 也可贴在名字尾巴上（tag.amp-img.0）。
  function buildCss(tokens) {
    var type = null, first = null, index = null, extras = [], ok = true;
    for (var i = 0; i < tokens.length; i++) {
      var t = tokens[i];
      if (!t) { continue; }
      var im = t.match(/^\.(\d+)$/);
      if (im) { index = Number(im[1]); continue; }
      var m = t.match(/^(class|tag|id)\.(.+)$/);
      if (m) {
        if (type !== null) { ok = false; break; }
        type = m[1];
        var name = m[2];
        var tail = name.match(/^(.*)\.(\d+)$/);
        if (tail) { name = tail[1]; index = Number(tail[2]); }
        first = name;
        continue;
      }
      if (/^[A-Za-z][A-Za-z0-9_-]*$/.test(t)) { extras.push(t); continue; }
      ok = false; break;
    }
    if (!ok) { return { css: '', index: index, selCount: 0, ok: false }; }
    if (first === null && extras.length) { first = extras.shift(); }
    if (first === null || first === '') { return { css: '', index: index, selCount: 0, ok: false }; }
    var css = type === 'tag' ? first : (type === 'id' ? '#' + first : '.' + first);
    extras.forEach(function (c) { css += '.' + c; });
    return { css: css, index: index, selCount: 1, ok: true };
  }

  function queryAll(css) {
    var out = [];
    try { out = Array.prototype.slice.call(document.querySelectorAll(css)); } catch (e) { out = []; }
    return out;
  }

  // 在给定节点内往下找：起点是 documentElement 时按全局查（否则 contains 会把它自己排除掉）
  function descend(nodes, css) {
    var out = [];
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i];
      if (n === document.documentElement) { out = out.concat(queryAll(css)); continue; }
      if (!n.querySelectorAll) { continue; }
      try { out = out.concat(Array.prototype.slice.call(n.querySelectorAll(css))); } catch (e) {}
    }
    return out;
  }

  function elementHandles(nodes) {
    return nodes.map(function (n) {
      return {
        attr: function (name) { return n.getAttribute ? (n.getAttribute(name) || '') : ''; },
        text: function () { return (n.innerText || n.textContent || '').trim(); },
        html: function () { return n.innerHTML || ''; },
        node: n
      };
    });
  }

  // Legado 的 java.* 子集：只实现这份源用到的，其它抛错（不假装成功）。
  window.java = {
    getElements: function (rule) { return elementHandles(legadoExtractNodes(rule)); },
    t2s: function (s) { return s; }, // 未实现繁转简：原样返回
  };

  function legadoExtractNodes(rule) {
    var steps = String(rule || '').split('@').map(function (s) { return s.trim(); })
      .filter(function (s) { return s; });
    var nodes = [document.documentElement];
    for (var i = 0; i < steps.length; i++) {
      var step = steps[i];
      var im = step.match(/^\.(\d+)$/);
      if (im) { nodes = nodes.slice(Number(im[1]), Number(im[1]) + 1); continue; }
      var built = buildCss(step.split(/\s+/));
      if (built.ok && built.selCount > 0) {
        nodes = descend(nodes, built.css);
        if (built.index !== null) { nodes = nodes.slice(built.index, built.index + 1); }
        continue;
      }
      return nodes; // 取值步交给 legadoExtract 处理；这里只走选择器
    }
    return nodes;
  }

  var VALUE_HOLDERS = ['text', 'html', 'href', 'src', 'alt', 'title'];

  function legadoExtract(rule) {
    rule = String(rule || '').trim();
    if (!rule) { return { error: '（空规则）' }; }
    var steps = rule.split('@').map(function (s) { return s.trim(); }).filter(function (s) { return s; });
    var nodes = [document.documentElement];
    var values = null;
    for (var i = 0; i < steps.length; i++) {
      var step = steps[i];
      var im = step.match(/^\.(\d+)$/);
      if (im) {
        if (nodes.length === 0) { return { error: '索引步 ' + step + ' 之前没有任何节点' }; }
        nodes = nodes.slice(Number(im[1]), Number(im[1]) + 1);
        continue;
      }
      var built = buildCss(step.split(/\s+/));
      if (built.ok && built.selCount > 0) {
        nodes = descend(nodes, built.css);
        if (built.index !== null) { nodes = nodes.slice(built.index, built.index + 1); }
        continue;
      }
      // 与 Dart 侧 parseComicRule(valueRule: true) 对齐：取值名、或写在**最后**的裸 token
      // 才算取值（`text` 与 `amp-img` 长得一样，差别就在这两条上）。
      var isLastStep = i === steps.length - 1;
      if (step.split(/\s+/).length === 1 && /^[A-Za-z][A-Za-z0-9_-]*$/.test(step) &&
          (VALUE_HOLDERS.indexOf(step) >= 0 || isLastStep)) {
        values = nodes.map(function (n) {
          if (step === 'text') { return (n.innerText || n.textContent || '').trim(); }
          if (step === 'html') { return n.innerHTML || ''; }
          return n.getAttribute ? (n.getAttribute(step) || '') : '';
        }).filter(function (v) { return v !== ''; });
        continue;
      }
      return { error: '不认识的规则段: ' + step };
    }
    if (values === null) { return { error: '规则只有选择器、没有取值步（缺 text 或属性名）' }; }
    return { values: values };
  }

  window.legadoExtract = legadoExtract;
  return { extract: legadoExtract, nodes: legadoExtractNodes };
})();
''';

/// 构造"在页面里跑一条取值规则"的 JS（返回值是 JSON 字符串）。
String buildComicRuleScript(String rule) =>
    'javascript:(function(){ $kComicSourceEngineJs '
    'return JSON.stringify(window.legadoExtract(${_jsString(rule)})); })()';

/// 构造"在页面里跑书源自带的 JS 段"的 JS（`<js>` / `@js:` 的脚本体）。
String buildComicJsBlockScript(String body) =>
    'javascript:(function(){ $kComicSourceEngineJs '
    'var __r = (function(){ $body })(); '
    'if (__r === undefined || __r === null) { return JSON.stringify({error: "JS 段没有返回值"}); } '
    'return JSON.stringify({text: String(__r)}); })()';

/// 构造"取某个 CSS 命中的第一个元素的某个属性"的 JS。
///
/// 这是**页面查询**（我自己的等待/取链用），不走书源规则解析 —— 两件事分开：
/// 规则是配置（要能报"不认识"），页面查询是代码（我自己生成的，必须准）。
String buildComicAttrScript(String css, String attr) =>
    'javascript:(function(){ try { var n = document.querySelectorAll(${_jsString(css)}); '
    'if (!n.length) { return ""; } '
    'var v = n[0].getAttribute(${_jsString(attr)}); '
    'return v === null ? "" : String(v); } catch (e) { return ""; } })()';

/// 构造"数一数某个 CSS 命中几个"的 JS（用于等待页面就绪与报命中数）。
String buildComicCountScript(String css) =>
    'javascript:(function(){ try { return String(document.querySelectorAll(${_jsString(css)}).length); } '
    'catch (e) { return "0"; } })()';

/// JS 字符串字面量（用 JSON 编码，省得自己处理引号转义）。
String _jsString(String s) => jsonEncodeJs(s);

/// 极简的 JSON 字符串编码（不引入 dart:convert 的 map 语义，只做字符串转义）。
String jsonEncodeJs(String s) {
  final sb = StringBuffer('"');
  for (final unit in s.codeUnits) {
    switch (unit) {
      case 0x22:
        sb.write(r'\"');
      case 0x5C:
        sb.write(r'\\');
      case 0x0A:
        sb.write(r'\n');
      case 0x0D:
        sb.write(r'\r');
      case 0x09:
        sb.write(r'\t');
      default:
        if (unit < 0x20) {
          sb.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
        } else {
          sb.writeCharCode(unit);
        }
    }
  }
  sb.write('"');
  return sb.toString();
}
