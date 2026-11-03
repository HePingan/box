import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 把一枚刚生成的恢复码显示给用户。
///
/// 这个框只在**生成的那一刻**出现：恢复码只存 `sha256(salt:code)`，
/// 关掉这个框就再也没有第二次看明文的机会。所以它必须把话说全：
/// - 关掉就没了，抄下来；
/// - 忘了口令时靠它救命（计算器界面按住结果行 5 秒）；
/// - 它同样是一把钥匙，别贴在手机壳后面。
///
/// 两个入口共用（设置页生成 / 计算器里恢复成功后轮换），所以单独成文件，
/// 避免两处文案各写一份、日后只改一处。
Future<void> showRecoveryCodeDialog(
  BuildContext context,
  String code, {
  String title = '恢复码',
  String? subtitle,
}) {
  return showDialog<void>(
    context: context,
    // 不让点空白关掉：用户很可能是在最后一刻滑到别处，误触就永久失去这枚码。
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (subtitle != null) ...[
            Text(subtitle, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
          ],
          SelectableText(
            code,
            key: const ValueKey<String>('disguise_recovery_code'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              letterSpacing: 2,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '抄在纸上或存进密码管理器。这串只在现在显示一次，关掉就再也看不到。\n'
            '忘了口令时：在计算器界面按住结果行 5 秒，输入它就能重设口令。',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: code));
          },
          child: const Text('复制'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('我已抄下'),
        ),
      ],
    ),
  );
}
