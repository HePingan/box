import 'package:flutter/material.dart';

import '../../../design_system/app_tokens.dart';
import '../data/permission_notes.dart';

/// 权限说明页。
///
/// 存在的理由见 [kPermissionNotes] 的文档：系统弹窗只会念原文，把最吓人的一句话
/// 丢给用户；这一页逐条翻译「为什么 / 何时 / 不给会怎样 / 怎么关」。
///
/// 视觉沿用「关于」家族的说明页：一张卡一条（`about_content_page.dart` 同款
/// 底色 + 描边 + 圆角），不打散成列表项 —— 每条有四行，列表项放不下。
class AppPermissionsPage extends StatelessWidget {
  const AppPermissionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(
        title: const Text('权限说明'),
        backgroundColor: AppTokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _IntroCard(text: permissionIntro()),
          ...kPermissionNotes.map((note) => _PermissionCard(note: note)),
          // 权限之外最常被问的一件事：有没有第三方 SDK 在偷偷回传数据。
          const _IntroCard(title: '第三方 SDK', text: kThirdPartySdkNote),
          const SizedBox(height: 4),
          Text(
            kPermissionOutro,
            style: TextStyle(
              fontSize: 11,
              height: 1.6,
              color: AppTokens.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.text, this.title});

  final String text;

  /// 可选小标题（「第三方 SDK」那块用；顶部那块直接用段落）。
  final String? title;

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
          if (title != null) ...[
            Text(
              title!,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 1.7,
              color: AppTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.note});

  final PermissionNote note;

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
            note.title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          // 把系统里的原文名也列出来：用户在系统设置里看到的是这个，
          // 不写的话「权限说明」里的名字和系统界面对不上号。
          Text(
            note.manifestName,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: AppTokens.textTertiary,
            ),
          ),
          const SizedBox(height: 10),
          _Row(label: '用来做什么', value: note.why),
          _Row(label: '什么时候用到', value: note.when),
          _Row(label: '不给会怎样', value: note.ifDenied),
          _Row(label: '怎么关掉', value: note.howToRevoke, last: true),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: AppTokens.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: AppTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
