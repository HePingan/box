import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 一个自带生命周期的文本输入框。
///
/// ## 为什么不能在外面 `showDialog` 之后 `controller.dispose()`
///
/// `await showDialog(...)` 拿到返回值的那一刻，对话框的**退场动画还在跑**，
/// `TextField` 仍然挂在树上用着这个控制器。这时候 dispose 会让下一帧的重建抛
/// `A TextEditingController was used after being disposed`（debug 下直接红屏，
/// release 下是看不见的状态错乱）。控制器必须由对话框自己的 `State` 拥有，
/// 在它的 `dispose()` 里释放 —— 那才是真的"已经不在树上了"。
///
/// 校验不通过时**留在框里**显示原因，而不是关掉框什么都不说。
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  required String hint,
  required String? Function(String value) validate,
  bool obscure = false,
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
  Color? backgroundColor,
  Color? textColor,
}) {
  return showDialog<String>(
    context: context,
    // 手指刚离开按钮/结果行，落在 barrier 上的那一下不该把框关掉。
    barrierDismissible: false,
    builder: (_) => _TextPromptDialog(
      title: title,
      hint: hint,
      validate: validate,
      obscure: obscure,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      backgroundColor: backgroundColor,
      textColor: textColor,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.hint,
    required this.validate,
    required this.obscure,
    required this.keyboardType,
    required this.inputFormatters,
    required this.backgroundColor,
    required this.textColor,
  });

  final String title;
  final String hint;
  final String? Function(String value) validate;
  final bool obscure;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Color? backgroundColor;
  final Color? textColor;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final message = widget.validate(_controller.text);
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: widget.backgroundColor,
      title: Text(
        widget.title,
        style: widget.textColor == null
            ? null
            : TextStyle(fontSize: 18, color: widget.textColor),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: widget.obscure,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.inputFormatters,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(hintText: widget.hint, errorText: _error),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}
