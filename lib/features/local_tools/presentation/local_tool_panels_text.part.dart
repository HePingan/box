part of './local_tool_panels.dart';

// 文本与编码类工具：JSON / 正则 / Base64 / 摘要 / URL / 文本编辑器 / 颜文字。
//
// domain 逻辑在 local_tool_text.dart。

class RelationPanelBody extends StatefulWidget {
  const RelationPanelBody({super.key});

  @override
  State<RelationPanelBody> createState() => _RelationPanelBodyState();
}

class _RelationPanelBodyState extends State<RelationPanelBody> {
  final List<String> _path = [];

  static const _steps = [
    '爸爸', '妈妈', '哥哥', '弟弟', '姐姐', '妹妹',
    '丈夫', '妻子', '儿子', '女儿',
  ];

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: '亲戚称呼计算',
      subtitle: '从「我」出发，按顺序点关系，算出该怎么称呼',
      icon: Icons.family_restroom_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTokens.primaryBlue.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _path.isEmpty ? '我' : '我 → ${_path.join(' → ')}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _steps)
                ActionChip(
                  label: Text(s),
                  onPressed: () => setState(() => _path.add(s)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LocalToolResult(text: m.relationTitle(_path)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _path.isEmpty
                      ? null
                      : () => setState(_path.removeLast),
                  child: const Text('退一步'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _path.isEmpty ? null : () => setState(_path.clear),
                  child: const Text('重来'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── JSON 格式化 ───────────────────────────
class JsonPanelBody extends StatefulWidget {
  const JsonPanelBody({super.key});
  @override
  State<JsonPanelBody> createState() => _JsonPanelBodyState();
}

class _JsonPanelBodyState extends State<JsonPanelBody> {
  final _ctrl = TextEditingController();
  String _out = '';
  bool _error = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _run({required bool minify}) {
    try {
      final v = minify ? tt.minifyJson(_ctrl.text) : tt.formatJson(_ctrl.text);
      setState(() {
        _out = v;
        _error = false;
      });
    } on tt.TextToolError catch (e) {
      setState(() {
        _out = e.message;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: 'JSON 格式化',
      subtitle: '美化 / 压缩 / 校验，中文不会被转义',
      icon: Icons.data_object_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: '粘贴 JSON，如 {"a":1,"中文":"值"}',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _run(minify: false),
                  child: const Text('美化'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _run(minify: true),
                  child: const Text('压缩'),
                ),
              ),
            ],
          ),
          if (_out.isNotEmpty) ...[
            const SizedBox(height: 10),
            LocalToolResult(text: _out, error: _error),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────── 正则测试 ───────────────────────────
class RegexPanelBody extends StatefulWidget {
  const RegexPanelBody({super.key});
  @override
  State<RegexPanelBody> createState() => _RegexPanelBodyState();
}

class _RegexPanelBodyState extends State<RegexPanelBody> {
  final _pat = TextEditingController();
  final _src = TextEditingController();
  String _out = '';
  bool _error = false;

  @override
  void dispose() {
    _pat.dispose();
    _src.dispose();
    super.dispose();
  }

  void _run() {
    try {
      final r = tt.testRegex(_pat.text, _src.text);
      final buf = StringBuffer();
      if (r.isEmpty) {
        buf.write('没有匹配到任何内容');
      } else {
        buf.write('匹配到 ');
        buf.write(r.count);
        buf.write(' 处（耗时 ');
        buf.write(r.elapsedMicros);
        buf.write(' 微秒）：');
        for (final m in r.matches.take(50)) {
          buf.write('\n  [');
          buf.write(m.start);
          buf.write('-');
          buf.write(m.end);
          buf.write('] ');
          buf.write(m.text);
          if (m.groups.isNotEmpty) {
            buf.write('   组: ');
            buf.write(m.groups.map((g) => g ?? '(未匹配)').join(' | '));
          }
        }
        if (r.matches.length > 50) {
          buf.write('\n  …… 还有 ');
          buf.write(r.matches.length - 50);
          buf.write(' 处');
        }
      }
      setState(() {
        _out = buf.toString();
        _error = false;
      });
    } on tt.TextToolError catch (e) {
      setState(() {
        _out = e.message;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: '正则测试',
      subtitle: '列出全部匹配、位置与捕获组',
      icon: Icons.code_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _pat,
            decoration: const InputDecoration(
              hintText: r'正则，如 (\w+)@(\w+)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _src,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '要匹配的文本',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(onPressed: _run, child: const Text('开始匹配')),
          if (_out.isNotEmpty) ...[
            const SizedBox(height: 10),
            LocalToolResult(text: _out, error: _error),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────── Base64 ───────────────────────────
class Base64PanelBody extends StatefulWidget {
  const Base64PanelBody({super.key});
  @override
  State<Base64PanelBody> createState() => _Base64PanelBodyState();
}

class _Base64PanelBodyState extends State<Base64PanelBody> {
  final _ctrl = TextEditingController();
  String _out = '';
  bool _error = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _run({required bool encode}) {
    try {
      final v = encode
          ? tt.base64EncodeText(_ctrl.text)
          : tt.base64DecodeText(_ctrl.text);
      setState(() {
        _out = v;
        _error = false;
      });
    } on tt.TextToolError catch (e) {
      setState(() {
        _out = e.message;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: 'Base64 编解码',
      subtitle: '按 UTF-8 处理，中文和 emoji 都不会乱码',
      icon: Icons.swap_horiz_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: '输入文本或 Base64',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _run(encode: true),
                  child: const Text('编码'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _run(encode: false),
                  child: const Text('解码'),
                ),
              ),
            ],
          ),
          if (_out.isNotEmpty) ...[
            const SizedBox(height: 10),
            LocalToolResult(text: _out, error: _error),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────── 哈希 ───────────────────────────
class HashPanelBody extends StatefulWidget {
  const HashPanelBody({super.key});
  @override
  State<HashPanelBody> createState() => _HashPanelBodyState();
}

class _HashPanelBodyState extends State<HashPanelBody> {
  final _ctrl = TextEditingController();
  tt.HashAlgo _algo = tt.HashAlgo.md5;
  String _out = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: 'MD5 / SHA 加密',
      subtitle: '摘要计算，输入按 UTF-8 编码',
      icon: Icons.fingerprint_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '要计算摘要的文本',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final a in tt.HashAlgo.values)
                ChoiceChip(
                  label: Text(a.label),
                  selected: _algo == a,
                  onSelected: (_) => setState(() => _algo = a),
                ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () => setState(
              () => _out = tt.hashText(_ctrl.text, _algo),
            ),
            child: const Text('计算'),
          ),
          if (_out.isNotEmpty) ...[
            const SizedBox(height: 10),
            LocalToolResult(text: _out),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────── URL 编码 ───────────────────────────
class UrlCodecPanelBody extends StatefulWidget {
  const UrlCodecPanelBody({super.key});
  @override
  State<UrlCodecPanelBody> createState() => _UrlCodecPanelBodyState();
}

class _UrlCodecPanelBodyState extends State<UrlCodecPanelBody> {
  final _ctrl = TextEditingController();
  String _out = '';
  bool _error = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _run({required bool encode}) {
    try {
      final v = encode
          ? tt.urlEncodeText(_ctrl.text)
          : tt.urlDecodeText(_ctrl.text);
      setState(() {
        _out = v;
        _error = false;
      });
    } on tt.TextToolError catch (e) {
      setState(() {
        _out = e.message;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: 'URL 编码',
      subtitle: 'RFC 3986 百分号编码，空格用 %20',
      icon: Icons.link_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '输入 URL 或要编码的文本',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _run(encode: true),
                  child: const Text('编码'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _run(encode: false),
                  child: const Text('解码'),
                ),
              ),
            ],
          ),
          if (_out.isNotEmpty) ...[
            const SizedBox(height: 10),
            LocalToolResult(text: _out, error: _error),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────── 文本编辑器 ───────────────────────────
class TextEditorPanelBody extends StatefulWidget {
  const TextEditorPanelBody({super.key});
  @override
  State<TextEditorPanelBody> createState() => _TextEditorPanelBodyState();
}

class _TextEditorPanelBodyState extends State<TextEditorPanelBody> {
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 统计要随着输入实时变，所以监听而不是只在按钮按下时算。
    _ctrl.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _ctrl.removeListener(_onChanged);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = tt.textStats(_ctrl.text);
    return LocalToolCard(
      title: '文本编辑器',
      subtitle: '随手记一段文字，实时统计字数',
      icon: Icons.edit_note_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: '在这里写点什么……',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatChip(label: '字符', value: s.chars.toString()),
              _StatChip(label: '不含空白', value: s.charsNoSpace.toString()),
              _StatChip(label: '行数', value: s.lines.toString()),
              _StatChip(label: '词数', value: s.words.toString()),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final m = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: _ctrl.text));
                    m.showSnackBar(
                      const SnackBar(content: Text('已复制到剪贴板')),
                    );
                  },
                  child: const Text('复制全文'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(_ctrl.clear),
                  child: const Text('清空'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTokens.radiusChip),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTokens.textSecondary,
        ),
      ),
    );
  }
}

// ─────────────────────────── 颜文字 ───────────────────────────
class KaomojiPanelBody extends StatefulWidget {
  const KaomojiPanelBody({super.key});
  @override
  State<KaomojiPanelBody> createState() => _KaomojiPanelBodyState();
}

class _KaomojiPanelBodyState extends State<KaomojiPanelBody> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    final current = tt.pickKaomoji(_idx);
    return LocalToolCard(
      title: '颜文字',
      subtitle: '随手挑一个，点一下就复制',
      icon: Icons.emoji_emotions_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                current,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => setState(
                    () => _idx = (_idx + 1) % tt.kaomojiList.length,
                  ),
                  child: const Text('换一个'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final m = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: current));
                    m.showSnackBar(
                      const SnackBar(content: Text('已复制到剪贴板')),
                    );
                  },
                  child: const Text('复制'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final k in tt.kaomojiList)
                GestureDetector(
                  onTap: () async {
                    final m = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: k));
                    m.showSnackBar(SnackBar(content: Text('已复制 $k')));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTokens.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppTokens.radiusChip),
                    ),
                    child: Text(k, style: const TextStyle(fontSize: 14)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── 秒表 ───────────────────────────
