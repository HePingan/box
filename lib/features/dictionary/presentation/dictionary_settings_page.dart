import 'package:flutter/material.dart';

import '../dictionary_manager.dart';
import '../sources/api_dictionary_source.dart';

/// 词典设置页 — 管理词典源
class DictionarySettingsPage extends StatefulWidget {
  const DictionarySettingsPage({
    super.key,
    required this.manager,
  });

  final DictionaryManager manager;

  @override
  State<DictionarySettingsPage> createState() => _DictionarySettingsPageState();
}

class _DictionarySettingsPageState extends State<DictionarySettingsPage> {
  late final TextEditingController _urlController;
  late final TextEditingController _sourceNameController;
  late final TextEditingController _wordFieldController;
  late final TextEditingController _defFieldController;
  final _headersKeyController = TextEditingController();
  final _headersValueController = TextEditingController();
  final _headers = <MapEntry<String, String>>[];

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _sourceNameController = TextEditingController();
    _wordFieldController = TextEditingController(text: 'word');
    _defFieldController = TextEditingController(text: 'definition');
  }

  @override
  void dispose() {
    _urlController.dispose();
    _sourceNameController.dispose();
    _wordFieldController.dispose();
    _defFieldController.dispose();
    _headersKeyController.dispose();
    _headersValueController.dispose();
    super.dispose();
  }

  void _addApiSource() {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 API URL')),
      );
      return;
    }

    final config = ApiDictionarySourceConfig(
      apiUrl: url,
      headers: Map.fromEntries(_headers),
      wordField: _wordFieldController.text.trim(),
      definitionField: _defFieldController.text.trim(),
      sourceName: _sourceNameController.text.trim().isNotEmpty
          ? _sourceNameController.text.trim()
          : '自定义词典',
    );

    widget.manager.register(ApiDictionarySource(config: config));
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已添加词典源「${config.sourceName}」')),
    );

    _urlController.clear();
    _sourceNameController.clear();
    _headers.clear();
  }

  void _removeSource(String id) {
    widget.manager.unregister(id);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已移除词典源')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sources = widget.manager.sources;

    return Scaffold(
      appBar: AppBar(
        title: const Text('词典设置'),
        actions: [
          TextButton.icon(
            onPressed: _showAddDialog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加源'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '词典源列表（共 ${sources.length} 个）',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          ...sources.map((source) {
            final isBuiltIn = source.id == 'built_in';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  isBuiltIn ? Icons.book_rounded : Icons.cloud_rounded,
                ),
                title: Text(source.name),
                subtitle: Text('ID: ${source.id}'),
                trailing: isBuiltIn
                    ? const Chip(label: Text('内置'))
                    : IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _removeSource(source.id),
                      ),
                onTap: source.isConfigurable ? null : null,
              ),
            );
          }),
          if (sources.length == 1 && sources.first.id == 'built_in')
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Center(
                child: Text(
                  '点击右上角 + 添加自定义词典 API',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showAddDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '添加自定义词典源',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _sourceNameController,
                      decoration: const InputDecoration(
                        labelText: '源名称（可选）',
                        hintText: '例如：我的词典',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                        labelText: 'API URL *',
                        hintText: '例如：https://api.example.com/lookup?q={{word}}',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '使用 {{word}} 作为查询词占位符',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _wordFieldController,
                      decoration: const InputDecoration(
                        labelText: '响应中单词字段路径',
                        hintText: '默认: word',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _defFieldController,
                      decoration: const InputDecoration(
                        labelText: '响应中释义字段路径',
                        hintText: '默认: definition',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 请求头
                    Row(
                      children: [
                        const Text('自定义请求头：',
                            style: TextStyle(fontSize: 14)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            final key = _headersKeyController.text.trim();
                            final value = _headersValueController.text.trim();
                            if (key.isNotEmpty && value.isNotEmpty) {
                              setSheetState(() {
                                _headers.add(MapEntry(key, value));
                                _headersKeyController.clear();
                                _headersValueController.clear();
                              });
                            }
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('添加'),
                        ),
                      ],
                    ),
                    ..._headers.asMap().entries.map((e) {
                      return ListTile(
                        dense: true,
                        title: Text('${e.value.key}: ${e.value.value}',
                            style: const TextStyle(fontSize: 13)),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            setSheetState(() => _headers.removeAt(e.key));
                          },
                        ),
                      );
                    }),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _headersKeyController,
                            decoration: const InputDecoration(
                              labelText: 'Key',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _headersValueController,
                            decoration: const InputDecoration(
                              labelText: 'Value',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _addApiSource();
                        },
                        child: const Text('添加'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
