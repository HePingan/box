import 'package:flutter/material.dart';
import 'reader_dictionary_service.dart';

/// 词典查词结果面板 — 底部弹出
class ReaderDictionaryPanel extends StatefulWidget {
  const ReaderDictionaryPanel({
    super.key,
    required this.word,
    required this.bgColor,
    required this.textColor,
  });

  final String word;
  final Color bgColor;
  final Color textColor;

  @override
  State<ReaderDictionaryPanel> createState() => _ReaderDictionaryPanelState();
}

class _ReaderDictionaryPanelState extends State<ReaderDictionaryPanel> {
  final _service = const ReaderDictionaryService();
  WordDefinition? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  Future<void> _lookup() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.lookup(widget.word);
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
          // 标题栏
          Row(
            children: [
              Icon(Icons.menu_book_rounded, size: 18, color: textColor),
              const SizedBox(width: 8),
              Text(
                '词典',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close_rounded, size: 20, color: textColor),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 查询词
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(
                  widget.word,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
                if (_result != null && _result!.phonetic.isNotEmpty) ...[
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
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 加载/错误/结果
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
                  ],
                ),
              ),
            )
          else if (_result != null && _result!.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  '未找到「${widget.word}」的解释',
                  style: TextStyle(
                    fontSize: 13,
                    color: textColor.withValues(alpha: 0.6),
                  ),
                ),
              ),
            )
          else
            // 释义列表
            ...(_result?.definitions ?? []).map((def) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (def.partOfSpeech.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(right: 8, top: 1),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: textColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          def.partOfSpeech,
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
                            def.definition,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: textColor,
                            ),
                          ),
                          if (def.example != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                def.example!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textColor.withValues(alpha: 0.5),
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

          // 来源
          if (_result != null && _result!.source.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '来源：${_result!.source}',
                style: TextStyle(
                  fontSize: 11,
                  color: textColor.withValues(alpha: 0.35),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
