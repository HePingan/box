import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_back_button.dart';

/// 音乐入口占位页。
///
/// 内容页四宫格里「音乐」是真入口，但播放器还没开发。这里必须如实说明
/// 「还没做」并写清规划中的形态，而不是弹一句 Toast 或滚动到别处 —— 那两种
/// 处理方式在用户看来都像功能坏了。
///
/// `AppBackButton` 不传 `label`：leading 槽位只有约 34dp，塞中文标签会和
/// `title` 抢位置直接 RenderFlex overflow（已在资讯/在线工具两页踩过）。
class MusicPlaceholderPage extends StatelessWidget {
  const MusicPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // onPressed 必须显式传：AppBackButton 的 onPressed 是可空的且没有
        // 默认 pop 行为，不传就是个点了没反应的死按钮。
        leading: AppBackButton(onPressed: () => Navigator.pop(context)),
        title: const Text('音乐'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              border: Border.all(color: AppTokens.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTokens.emerald.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.music_note_rounded,
                        color: AppTokens.emerald,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '音乐播放还没开发',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '这个入口先占位。现在点进来除了这页说明，没有任何可用功能 —— '
                  '没有播放器，也不能导入或下载。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              border: Border.all(color: AppTokens.cardBorder),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '规划中的形态',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 10),
                _PlanRow(
                  icon: Icons.folder_open_rounded,
                  title: '本地播放',
                  desc: '扫描并播放设备里已有的音频文件',
                ),
                SizedBox(height: 10),
                _PlanRow(
                  icon: Icons.cloud_download_rounded,
                  title: '在线源下载后播放',
                  desc: '由你提供源地址，抓取到本地再播放；App 不内置任何音源',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.icon,
    required this.title,
    required this.desc,
  });

  final IconData icon;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
