import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/app_tokens.dart';
import '../data/about_content.dart';

/// 软件介绍 / 使用文档 通用展示页。
///
/// 两者结构相同（若干「小标题 + 要点列表」），共用一个页面而不是写两个几乎
/// 一样的 widget。
class AboutContentPage extends StatelessWidget {
  const AboutContentPage({
    super.key,
    required this.title,
    required this.sections,
    this.footer,
  });

  final String title;
  final List<AboutSection> sections;
  final String? footer;

  factory AboutContentPage.introduction() => const AboutContentPage(
        title: '软件介绍',
        sections: AboutContent.introduction,
        footer: AboutContent.disclaimerShort,
      );

  factory AboutContentPage.usageDocs() => const AboutContentPage(
        title: '使用文档',
        sections: AboutContent.usageDocs,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppTokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          ...sections.map((s) => _SectionCard(section: s)),
          if (footer != null) ...[
            const SizedBox(height: 8),
            Text(
              footer!,
              style: const TextStyle(
                fontSize: 11,
                height: 1.6,
                color: AppTokens.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});

  final AboutSection section;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: AppTokens.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          // 段落先出，要点列表后出。
          ...section.paragraphs.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                t,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.7,
                  color: AppTokens.textSecondary,
                ),
              ),
            ),
          ),
          ...section.bullets.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 8),
                    child: SizedBox(
                      width: 4,
                      height: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppTokens.textTertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      p,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: AppTokens.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 推荐教程页。
///
/// 与介绍/文档分开，因为这里的条目带**链接**，且只列真实存在的目标：
/// 开源仓库与 Issues。刻意不编造"B站教学视频""官方频道"这类不存在的东西。
///
/// 链接的处理方式是**复制到剪贴板**而不是调起浏览器：项目没有引入
/// url_launcher（抽屉里那个 github 链接也是复制到剪贴板的），为一个教程页
/// 单独加一个原生插件依赖不划算，且复制在无浏览器/无默认浏览器的设备上更稳。
class AboutTutorialPage extends StatelessWidget {
  const AboutTutorialPage({super.key, this.onCopy});

  /// 供测试注入，避免测试里真的写系统剪贴板（widget test 里
  /// `await Clipboard.setData` 会挂住，这个项目踩过）。
  final Future<void> Function(String url)? onCopy;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(
        title: const Text('推荐教程'),
        backgroundColor: AppTokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          ...AboutContent.tutorials.map(
            (t) => _TutorialCard(
              entry: t,
              onTap: t.hasLink ? () => _copy(context, t.url!) : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final copier = onCopy ??
        (String u) => Clipboard.setData(ClipboardData(text: u));
    try {
      await copier(url);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('复制失败，请手动记录：$url')),
      );
      return;
    }
    // messenger 在 await 前抓好：不判 context.mounted，否则页面被切走时
    // 提示会整个丢掉，用户只看到「点了没反应」。
    messenger.showSnackBar(
      SnackBar(
        content: Text('地址已复制到剪贴板：$url'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _TutorialCard extends StatelessWidget {
  const _TutorialCard({required this.entry, this.onTap});

  final TutorialEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: AppTokens.divider),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTokens.textPrimary,
                      ),
                    ),
                  ),
                  if (onTap != null)
                    const Icon(
                      Icons.copy_rounded,
                      size: 16,
                      color: AppTokens.textTertiary,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                entry.description,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: AppTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
