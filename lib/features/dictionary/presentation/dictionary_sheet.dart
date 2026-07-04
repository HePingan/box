/// 统一词典查词 Sheet — 输入 + 结果显示在同一个 BottomSheet 中
/// 消除旧版 "输入面板→关闭→结果面板" 双重转场的卡顿
library;

import 'package:flutter/material.dart';

import '../dictionary_manager.dart';
import '../models/dictionary_definition.dart';

/// 统一词典 BottomSheet（输入 + 结果一体化）
class DictionarySheet extends StatefulWidget {
  const DictionarySheet({
    super.key,
    this.initialWord = '',
    required this.bgColor,
    required this.textColor,
    this.manager,
  });

  /// 预填词（来自长按选中的文字）
  final String initialWord;
  final Color bgColor;
  final Color textColor;
  final DictionaryManager? manager;

  @override
  State<DictionarySheet> createState() => _DictionarySheetState();
}

class _DictionarySheetState extends State<DictionarySheet> {
  late final DictionaryManager _manager;
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  DictionaryDefinition? _result;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _manager = widget.manager ?? DictionaryManager();
    _textController.text = widget.initialWord;

    // 如果有预填词，自动查
    if (widget.initialWord.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _doLookup(widget.initialWord);
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _doLookup(String word) async {
    final trimmed = word.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await _manager.lookup(trimmed);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.textColor;
    final bgColor = widget.bgColor;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 标题栏 ──
          Row(
            children: [
              const Icon(Icons.menu_book_rounded, size: 18),
              const SizedBox(width: 8),
              Text(
                '词典',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              // 词典源选择
              const SizedBox(width: 12),
              if (_manager.sources.length > 1)
                _buildSourceSelector(),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close_rounded, size: 20, color: textColor),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── 输入栏 ──
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  autofocus: widget.initialWord.isEmpty,
                  style: TextStyle(fontSize: 16, color: textColor),
                  decoration: InputDecoration(
                    hintText: '输入要查询的字或词',
                    hintStyle:
                        TextStyle(color: textColor.withValues(alpha: 0.4)),
                    filled: true,
                    fillColor: textColor.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (value) {
                    final trimmed = value.trim();
                    if (trimmed.isNotEmpty) {
                      _focusNode.unfocus();
                      _doLookup(trimmed);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () {
                  final trimmed = _textController.text.trim();
                  if (trimmed.isNotEmpty) {
                    _focusNode.unfocus();
                    _doLookup(trimmed);
                  }
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size(64, 48),
                ),
                child: const Text('查词'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── 结果显示区 ──
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(Icons.cloud_off_rounded,
                        size: 32, color: textColor.withValues(alpha: 0.4)),
                    const SizedBox(height: 8),
                    Text(
                      '查询失败',
                      style: TextStyle(
                        fontSize: 13,
                        color: textColor.withValues(alpha: 0.6),
                      ),
                    ),
                    if (_error != null && _error!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 11,
                          color: textColor.withValues(alpha: 0.4),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () {
                        final trimmed = _textController.text.trim();
                        if (trimmed.isNotEmpty) _doLookup(trimmed);
                      },
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          else if (_result != null && _result!.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  '未找到「${_textController.text.trim()}」的解释',
                  style: TextStyle(
                    fontSize: 13,
                    color: textColor.withValues(alpha: 0.6),
                  ),
                ),
              ),
            )
          else if (_result != null)
            // 已查到结果
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 查询词展示
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: textColor.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _textController.text.trim(),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                          if (_result!.phonetic.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            Text(
                              _result!.phonetic,
                              style: TextStyle(
                                fontSize: 14,
                                color: textColor.withValues(alpha: 0.6),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (_result!.source.isNotEmpty)
                            Text(
                              _result!.source,
                              style: TextStyle(
                                fontSize: 11,
                                color: textColor.withValues(alpha: 0.35),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 释义列表
                    ...(_result?.senses ?? []).map((sense) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (sense.partOfSpeech.isNotEmpty)
                              Container(
                                margin:
                                    const EdgeInsets.only(right: 8, top: 1),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: textColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  sense.partOfSpeech,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: textColor.withValues(alpha: 0.7),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    sense.definition,
                                    style: TextStyle(
                                      fontSize: 14,
                                      height: 1.4,
                                      color: textColor,
                                    ),
                                  ),
                                  if (sense.example != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        sense.example!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color:
                                              textColor.withValues(alpha: 0.5),
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSourceSelector() {
    final textColor = widget.textColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: textColor.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _manager.activeSource.id,
          dropdownColor: widget.bgColor,
          style: TextStyle(fontSize: 12, color: textColor),
          items: _manager.sources.map((s) {
            return DropdownMenuItem(
              value: s.id,
              child: Text(s.name,
                  style: TextStyle(fontSize: 12, color: textColor)),
            );
          }).toList(),
          onChanged: (id) {
            if (id != null) {
              setState(() {
                _manager.setActiveSource(id);
              });
              final trimmed = _textController.text.trim();
              if (trimmed.isNotEmpty) _doLookup(trimmed);
            }
          },
        ),
      ),
    );
  }
}
