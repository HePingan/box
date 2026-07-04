/// 模板渲染 {{ }} 和表达式求值 $/@
class TemplateRenderer {
  const TemplateRenderer();

  String renderTemplate(
    String input,
    dynamic context,
    dynamic root, {
    Map<String, String> vars = const {},
  }) {
    return input.replaceAllMapped(RegExp(r'\{\{(.*?)\}\}'), (match) {
      final expr = match.group(1)?.trim() ?? '';
      if (expr.isEmpty) return '';
      if (vars.containsKey(expr)) return vars[expr]!;
      return evalExpr(expr, context: context, root: root, vars: vars);
    });
  }

  String evalExpr(
    String expr, {
    required dynamic context,
    required dynamic root,
    Map<String, String> vars = const {},
  }) {
    if (expr.isEmpty) return '';
    if (vars.containsKey(expr)) return vars[expr]!;

    dynamic value;
    if (expr.startsWith(r'$') || expr.startsWith('@')) {
      value = extractPath(context, expr);
      value ??= extractPath(root, expr);
    } else if (context is Map) {
      value = mapLookup(context, expr);
    }

    if (value == null && root is Map) {
      value = mapLookup(root, expr);
    }

    if (value == null) return '';
    return value.toString();
  }

  static dynamic extractPath(dynamic root, String expr) {
    if (root == null || expr.isEmpty) return null;

    // 根引用
    if (expr == r'$' || expr == '@') return root;

    // 去掉前缀
    var path = expr;
    if (path.startsWith(r'$')) {
      path = path.substring(1);
    } else if (path.startsWith('@')) {
      path = path.substring(1);
    }

    if (path.isEmpty) return root;

    // 递归下降
    return _descend(root, path);
  }

  static dynamic _descend(dynamic current, String path) {
    if (current == null) return null;

    // 支持 .. 向上
    final segments = <String>[];
    var remaining = path;
    while (remaining.isNotEmpty) {
      if (remaining.startsWith('..')) {
        segments.add('..');
        remaining = remaining.substring(2);
      } else if (remaining.startsWith('.')) {
        remaining = remaining.substring(1);
      } else {
        final dot = remaining.indexOf('.');
        if (dot >= 0) {
          segments.add(remaining.substring(0, dot));
          remaining = remaining.substring(dot);
        } else {
          segments.add(remaining);
          break;
        }
      }
    }

    dynamic node = current;
    for (final segment in segments) {
      if (segment == '..') {
        // 简化处理：不支持真正的向上，直接返回 null
        return null;
      }

      // 处理 [*] 通配符：如 data[*] → 取 data 的值（期望是数组）
      if (segment.endsWith('[*]')) {
        final key = segment.substring(0, segment.length - 3);
        if (node is Map) {
          node = mapLookup(node, key);
        } else {
          return null;
        }
        // [*] 必须是路径的最后一段，通配后直接返回
        return node;
      }

      if (node is Map) {
        node = mapLookup(node, segment);
      } else if (node is List) {
        final index = int.tryParse(segment);
        node = (index != null && index >= 0 && index < node.length)
            ? node[index]
            : null;
      } else {
        return null;
      }
      if (node == null) return null;
    }
    return node;
  }

  static dynamic mapLookup(dynamic root, String key) {
    if (root is! Map) return null;
    final lower = key.toLowerCase();
    if (root.containsKey(key)) return root[key];
    for (final entry in root.entries) {
      if (entry.key.toString().toLowerCase() == lower) {
        return entry.value;
      }
    }
    return null;
  }

  static dynamic findFirstRecursive(dynamic root, String key) {
    dynamic result;
    void walk(dynamic current) {
      if (result != null) return;
      if (current is Map) {
        if (current.containsKey(key)) {
          result = current[key];
          return;
        }
        for (final v in current.values) {
          walk(v);
        }
      } else if (current is List) {
        for (final item in current) {
          walk(item);
        }
      }
    }

    walk(root);
    return result;
  }
}
