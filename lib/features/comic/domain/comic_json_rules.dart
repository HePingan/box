// JSON 规则子集（书源的 `ruleExplore` 用 `$.` 写法，取的是 **JSON 接口**而不是网页）。
//
// 只实现这份源真实用到的形状：
//   $.items[*]     取数组
//   $.name         取字段（`$.a.b` 也行）
//   $[0]           取第几个
//   {{$.comic_id}} 把一条记录的字段填进地址模板
//
// 与 DOM 规则同一口径：**不认识的一律显式报错**，不静默返回空 ——
// "取不到"和"我看不懂这条规则"必须能分开，否则真机上只会看到"没有结果"。
library;

/// JSON 规则/模板出错（规则不认识、字段缺失、类型不对）。
class ComicJsonRuleException implements Exception {
  const ComicJsonRuleException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 字段不存在。**单独一类**：取值时"这个字段没有"是正常的（作者/封面这类可选字段），
/// 但"规则我看不懂"必须报错 —— 两者要能分开。
class ComicJsonMissingField extends ComicJsonRuleException {
  const ComicJsonMissingField(super.message);
}

/// 是不是 JSON 规则（以 `$` 开头）。
bool isComicJsonRule(String rule) => rule.trimLeft().startsWith(r'$');

/// 按 `$.a.b` / `$.items[*]` / `$[0]` 取值；`[*]` 表示"往下都是列表"。
Object? comicJsonPick(Object? root, String path) {
  final p = path.trim();
  if (!p.startsWith(r'$')) {
    throw ComicJsonRuleException('JSON 规则只支持 \$ 开头：「$path」');
  }
  Object? cur = root;
  var i = 1; // 跳过 `$`
  while (i < p.length) {
    final c = p[i];
    if (c == '.') {
      i++;
      final start = i;
      while (i < p.length && p[i] != '.' && p[i] != '[') {
        i++;
      }
      final key = p.substring(start, i);
      if (key.isEmpty) {
        throw ComicJsonRuleException('JSON 规则里有空的字段名：「$path」');
      }
      if (cur is Map) {
        if (!cur.containsKey(key)) {
          throw ComicJsonMissingField('JSON 里没有字段 `$key`（规则「$path」）');
        }
        cur = cur[key];
      } else if (cur is List) {
        // `$.items.name` 这种：对列表里每条取字段（宽松一点，等价于 `[*].name`）
        cur = cur.map((e) => comicJsonPick(e, '\$.$key')).toList();
      } else {
        throw ComicJsonRuleException('取 `$key` 时上一层不是对象（规则「$path」）');
      }
      continue;
    }
    if (c == '[') {
      final end = p.indexOf(']', i);
      if (end < 0) throw ComicJsonRuleException('JSON 规则里的 `[` 没闭合：「$path」');
      final inner = p.substring(i + 1, end).trim();
      i = end + 1;
      if (inner == '*') {
        if (cur is! List) {
          throw ComicJsonRuleException('`[*]` 要求上一层是数组（规则「$path」）');
        }
      } else {
        final n = int.tryParse(inner);
        if (n == null) throw ComicJsonRuleException('`[$inner]` 不是数字也不是 `*`（规则「$path」）');
        if (cur is! List || n >= cur.length) {
          throw ComicJsonRuleException('取第 $n 个时越界或不是数组（规则「$path」）');
        }
        cur = cur[n];
      }
      continue;
    }
    throw ComicJsonRuleException('JSON 规则里不认识的字符 `$c`（规则「$path」）');
  }
  return cur;
}

/// `$.items[*]` → 列表（不是列表就报错，附上实际类型便于对号入座）。
List<Object?> comicJsonList(Object? root, String path) {
  final v = comicJsonPick(root, path);
  if (v is List) return v;
  if (v is Map) return [v];
  throw ComicJsonRuleException('规则「$path」没取到列表（实际是 ${v.runtimeType}）');
}

/// 取字段并转成文本：数组用 `,` 连接，对象转 JSON，null → 空串。
///
/// **字段不存在时给空串**（作者/封面这类可选字段）；规则写法错照样报错。
String comicJsonFieldText(Object? item, String path) {
  final Object? v;
  try {
    v = comicJsonPick(item, path);
  } on ComicJsonMissingField {
    return '';
  }
  return _asText(v);
}

String _asText(Object? v) {
  switch (v) {
    case null:
      return '';
    case String s:
      return s.trim();
    case List l:
      return l.map((e) => e?.toString() ?? '').join(',');
    case Map m:
      return m.entries.map((e) => '${e.key}=${e.value}').join(',');
    default:
      return v.toString();
  }
}

/// 地址模板：`https://…/comic/{{$.comic_id}}` + 一条记录 → 填好的地址。
///
/// 字段缺失**报错**（不拼出半个地址 —— 半个地址点下去只会开一个 404 页面）。
String comicTemplate(String tpl, Object? item) {
  final out = StringBuffer();
  var i = 0;
  while (i < tpl.length) {
    final open = tpl.indexOf('{{', i);
    if (open < 0) {
      out.write(tpl.substring(i));
      break;
    }
    out.write(tpl.substring(i, open));
    final close = tpl.indexOf('}}', open);
    if (close < 0) {
      throw ComicJsonRuleException('模板里的 `{{` 没闭合：「$tpl」');
    }
    final key = tpl.substring(open + 2, close).trim();
    // 模板**严格**：缺字段就报错，不拼出半个地址。
    out.write(_asText(comicJsonPick(item, key)));
    i = close + 2;
  }
  return out.toString();
}
