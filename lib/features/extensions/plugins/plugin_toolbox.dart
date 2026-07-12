// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 内置插件工具箱 — 6 个独立实用工具
class PluginToolbox {
  PluginToolbox._();

  // ═══════════════════════════════════════════════════════════════
  // 1. JSON 格式化
  // ═══════════════════════════════════════════════════════════════

  static Future<void> showJsonFormatter(BuildContext context) async {
    final controller = TextEditingController();
    String result = '';
    String errorMsg = '';
    bool formatted = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.75,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.data_object_rounded,
                            color: Colors.orange,
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'JSON 格式化工具',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () {
                              try {
                                final parsed = jsonDecode(controller.text);
                                result = const JsonEncoder.withIndent(
                                  '  ',
                                ).convert(parsed);
                                errorMsg = '';
                                formatted = true;
                              } catch (e) {
                                errorMsg = 'JSON 格式错误：$e';
                                formatted = false;
                              }
                              setSheetState(() {});
                            },
                            icon: const Icon(Icons.auto_fix_high, size: 16),
                            label: const Text('格式化'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: controller,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: const InputDecoration(
                            hintText: '粘贴 JSON 文本...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.all(10),
                          ),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (errorMsg.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            errorMsg,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (formatted) ...[
                        const SizedBox(height: 10),
                        Expanded(
                          flex: 3,
                          child: _ToolOutputArea(
                            text: result,
                            copyMessage: '已复制到剪贴板',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    controller.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // 2. Base64 编解码
  // ═══════════════════════════════════════════════════════════════

  static Future<void> showBase64Tool(BuildContext context) async {
    final controller = TextEditingController();
    String result = '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.7,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.lock_outline,
                            color: Colors.teal,
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Base64 编解码',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () {
                              try {
                                result = base64Encode(
                                  utf8.encode(controller.text),
                                );
                              } catch (_) {
                                result = '编码失败';
                              }
                              setSheetState(() {});
                            },
                            icon: const Icon(Icons.lock, size: 14),
                            label: const Text('编码'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () {
                              try {
                                result = utf8.decode(
                                  base64Decode(controller.text.trim()),
                                  allowMalformed: true,
                                );
                              } catch (_) {
                                result = '解码失败（非有效 Base64）';
                              }
                              setSheetState(() {});
                            },
                            icon: const Icon(Icons.lock_open, size: 14),
                            label: const Text('解码'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: controller,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: const InputDecoration(
                            hintText: '输入文本或 Base64 字符串...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.all(10),
                          ),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (result.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Expanded(flex: 2, child: _ToolOutputArea(text: result)),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    controller.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // 3. 密码生成器
  // ═══════════════════════════════════════════════════════════════

  static Future<void> showPasswordGenerator(BuildContext context) async {
    int length = 16;
    bool upper = true, lower = true, digits = true, symbols = true;
    String generated = '';

    String generatePassword() {
      final rng = Random.secure();
      final chars = <String>[];
      if (upper) chars.addAll('ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''));
      if (lower) chars.addAll('abcdefghijklmnopqrstuvwxyz'.split(''));
      if (digits) chars.addAll('0123456789'.split(''));
      if (symbols) chars.addAll('!@#\$%^&*()_+-=[]{}|;:,.<>?'.split(''));
      if (chars.isEmpty) return '请选择至少一种字符类型';
      return List.generate(
        length,
        (_) => chars[rng.nextInt(chars.length)],
      ).join();
    }

    void regeneratePassword(StateSetter setSheetState) {
      generated = generatePassword();
      setSheetState(() {});
    }

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            if (generated.isEmpty) {
              generated = generatePassword();
            }
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '密码生成器',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F8FA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              generated,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => regeneratePassword(setSheetState),
                            icon: const Icon(Icons.refresh),
                            tooltip: '重新生成',
                          ),
                          IconButton(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: generated));
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('已复制到剪贴板')),
                              );
                            },
                            icon: const Icon(Icons.copy),
                            tooltip: '复制',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('长度: '),
                        Expanded(
                          child: Slider(
                            value: length.toDouble(),
                            min: 6,
                            max: 64,
                            divisions: 58,
                            label: '$length',
                            onChanged: (v) {
                              length = v.round();
                              regeneratePassword(setSheetState);
                            },
                          ),
                        ),
                        Text(
                          '$length',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 12,
                      children: [
                        _buildToggle(setSheetState, '大写', upper, (v) {
                          upper = v;
                          regeneratePassword(setSheetState);
                        }),
                        _buildToggle(setSheetState, '小写', lower, (v) {
                          lower = v;
                          regeneratePassword(setSheetState);
                        }),
                        _buildToggle(setSheetState, '数字', digits, (v) {
                          digits = v;
                          regeneratePassword(setSheetState);
                        }),
                        _buildToggle(setSheetState, '符号', symbols, (v) {
                          symbols = v;
                          regeneratePassword(setSheetState);
                        }),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: generated));
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('密码已复制')),
                          );
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('复制并关闭'),
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

  static Widget _buildToggle(
    StateSetter setSheetState,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: onChanged,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 4. 时间戳转换
  // ═══════════════════════════════════════════════════════════════

  static Future<void> showTimestampConverter(BuildContext context) async {
    final controller = TextEditingController();
    String result = '';
    String error = '';

    final now = DateTime.now();
    controller.text = '${now.millisecondsSinceEpoch ~/ 1000}';

    void convertToDate(StateSetter setSheetState) {
      final text = controller.text.trim();
      if (text.isEmpty) return;
      try {
        final ts = int.parse(text);
        // 10位=秒, 13位=毫秒
        final ms = ts > 9999999999 ? ts : ts * 1000;
        final dt = DateTime.fromMillisecondsSinceEpoch(ms);
        result =
            '本地时间: ${dt.toLocal().toString().substring(0, 19)}\n'
            'UTC 时间: ${dt.toUtc().toString().substring(0, 19)}\n'
            '星期: ${_weekday(dt.weekday)}\n'
            '毫秒戳: $ms\n'
            '秒   戳: ${ms ~/ 1000}';
        error = '';
        setSheetState(() {});
      } catch (_) {
        error = '无效的时间戳';
        setSheetState(() {});
      }
    }

    void convertNow(StateSetter setSheetState) {
      final now = DateTime.now();
      controller.text = '${now.millisecondsSinceEpoch ~/ 1000}';
      convertToDate(setSheetState);
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.65,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            color: Colors.deepPurple,
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              '时间戳转换',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => convertNow(setSheetState),
                            child: const Text('当前时间'),
                          ),
                          FilledButton.tonal(
                            onPressed: () => convertToDate(setSheetState),
                            child: const Text('转换'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '输入时间戳（秒或毫秒）',
                          hintText: '1700000000',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => convertToDate(setSheetState),
                      ),
                      if (error.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            error,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      if (result.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _ToolResultBox(text: result),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    controller.dispose();
  }

  static String _weekday(int d) {
    const ws = ['一', '二', '三', '四', '五', '六', '日'];
    return '星期${ws[d - 1]}';
  }

  // ═══════════════════════════════════════════════════════════════
  // 5. URL 编解码
  // ═══════════════════════════════════════════════════════════════

  static Future<void> showUrlCodec(BuildContext context) async {
    final controller = TextEditingController();
    String result = '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.65,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.link_rounded,
                            color: Colors.indigo,
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'URL 编解码',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              result = Uri.encodeComponent(controller.text);
                              setSheetState(() {});
                            },
                            icon: const Icon(Icons.lock, size: 14),
                            label: const Text('编码'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonalIcon(
                            onPressed: () {
                              result = Uri.decodeComponent(controller.text);
                              setSheetState(() {});
                            },
                            icon: const Icon(Icons.lock_open, size: 14),
                            label: const Text('解码'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: controller,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: const InputDecoration(
                            hintText: '输入文本或 URL 编码字符串...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.all(10),
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      if (result.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Expanded(
                          flex: 2,
                          child: _ToolOutputArea(text: result, fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    controller.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // 6. 二维码生成
  // ═══════════════════════════════════════════════════════════════

  static Future<void> showQrCodeGenerator(BuildContext context) async {
    final controller = TextEditingController();
    String? qrUrl;

    void generateQrCode(StateSetter setSheetState) {
      final text = controller.text.trim();
      if (text.isEmpty) return;
      qrUrl =
          'https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=${Uri.encodeComponent(text)}';
      setSheetState(() {});
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.7,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.qr_code_2_rounded,
                            color: Colors.blueGrey,
                            size: 24,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '二维码生成',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: controller,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: '输入文本或链接',
                          hintText: 'https://example.com',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => generateQrCode(setSheetState),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => generateQrCode(setSheetState),
                              icon: const Icon(Icons.qr_code, size: 16),
                              label: const Text('生成二维码'),
                            ),
                          ),
                        ],
                      ),
                      if (qrUrl != null) ...[
                        const SizedBox(height: 14),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Image.network(
                              qrUrl!,
                              width: 250,
                              height: 250,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.broken_image,
                                size: 100,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    controller.dispose();
  }
}

class _ToolOutputArea extends StatelessWidget {
  const _ToolOutputArea({
    required this.text,
    this.fontSize = 12,
    this.copyMessage = '已复制',
  });

  final String text;
  final double fontSize;
  final String copyMessage;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFF6F8FA),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: fontSize,
                height: 1.4,
              ),
            ),
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: IconButton.filledTonal(
            iconSize: 16,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(copyMessage)));
            },
            icon: const Icon(Icons.copy),
          ),
        ),
      ],
    );
  }
}

class _ToolResultBox extends StatelessWidget {
  const _ToolResultBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.6,
        ),
      ),
    );
  }
}
