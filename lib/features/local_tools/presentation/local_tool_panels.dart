import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter/services.dart';

import '../../../design_system/app_tokens.dart';
import '../domain/local_tool_math.dart' as m;
import '../domain/local_tool_text.dart' as tt;
import '../domain/local_tool_device.dart' as dv;
import '../domain/local_tool_sensor.dart' as sv;

// 拆分（2026-10-18）：本文件一度到 3772 行、70 个类，改一个工具要在一整片里翻。
// 按用途切成 4 个 part（同库作用域，私有符号照旧可用，行为零变化）：
//   *_calc   计算类    *_text   文本编码类
//   *_timer  计时设备  *_sensor 传感器
part 'local_tool_panels_calc.part.dart';
part 'local_tool_panels_text.part.dart';
part 'local_tool_panels_timer.part.dart';
part 'local_tool_panels_sensor.part.dart';

/// 纯本地工具的界面主体（面板类散在下面 4 个 part 里，清单见 local_tools_registry.dart）。
///
/// 这一层刻意只做三件事：收输入 → 调 `local_tool_math.dart` → 画结果。
/// 所有可出错、可验证的逻辑都在 domain 层，这里不重复实现一份
/// （否则会出现「UI 算对了但单测测的是另一个实现」）。
///
/// 错误处理统一走 [localToolErrorTextFor]，把 [m.LocalToolError] 显示成
/// 红条；这样每个工具不用各写一遍 try/catch。

/// 从任意异常取用户可读文案。
String localToolErrorTextFor(Object e) =>
    e is m.LocalToolError ? e.message : '内部错误：$e';

/// 本地工具页面统一的外壳卡片（标题 + 说明 + 主体）。
class LocalToolCard extends StatelessWidget {
  const LocalToolCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 外壳用 Material 而不是 Container+BoxDecoration —— 和 ApiHubPanel 同因：
    // 视觉一致（白底 + 26 圆角 + 描边 + 阴影），但 ListTile/SwitchListTile/
    // InkWell 会把背景与水波纹画到最近的 Material 祖先上。之前的白底
    // Container 会把它们盖掉，framework 直接抛
    // 「ListTile background color or ink splashes may be invisible」——
    // 随机密码那两个开关就撞上了。修在外壳上，所有本地工具一次受益。
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(26),
        elevation: 1.5,
        shadowColor: AppTokens.primaryBlue.withValues(alpha: 0.06),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: AppTokens.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            // 卡片被外壳撑满而内容不够高时，把「标题 + 内容」这块整体居中 ——
            // 否则内容全挤在卡片顶部，底下留一大片白，还是"半屏"的观感。
            // 内容本来就有卡片高时（长工具）这里不产生任何位移。
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _header(),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppTokens.primaryBlue.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 19, color: AppTokens.primaryBlue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 结果展示条（本地工具到处在用：输入 → 结果）。
class LocalToolResult extends StatelessWidget {
  const LocalToolResult({
    super.key,
    required this.text,
    this.error = false,
    this.selectable = true,
  });

  final String text;
  final bool error;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final color = error ? const Color(0xFFD14343) : AppTokens.textPrimary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: error
            ? AppTokens.danger.withValues(alpha: 0.12)
            : AppTokens.primaryBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: selectable
          ? SelectableText(
              text,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            )
          : Text(
              text,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
    );
  }
}
