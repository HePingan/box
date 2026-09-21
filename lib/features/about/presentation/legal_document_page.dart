import 'package:flutter/material.dart';

import '../../../design_system/app_tokens.dart';
import '../data/legal_documents.dart';

/// 协议正文阅读页（用户协议 / 隐私政策共用）。
///
/// 纯展示，没有"同意"按钮 —— 同意只发生在首启闸门里。关于页里的入口是
/// 「复查」，用户随时能回来看自己同意了什么，这也是协议类需求的常规要求。
class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({
    super.key,
    required this.title,
    required this.clauses,
  });

  final String title;
  final List<LegalClause> clauses;

  /// 命名构造：避免调用方各自去引 LegalDocuments 的字段，写错就串页。
  factory LegalDocumentPage.userAgreement() => const LegalDocumentPage(
        title: LegalDocuments.userAgreementTitle,
        clauses: LegalDocuments.userAgreement,
      );

  factory LegalDocumentPage.privacyPolicy() => const LegalDocumentPage(
        title: LegalDocuments.privacyPolicyTitle,
        clauses: LegalDocuments.privacyPolicy,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (LegalDocuments.isDraft) const LegalDraftBanner(),
          ...clauses.map((c) => LegalClauseView(clause: c)),
        ],
      ),
    );
  }
}

/// 草稿提示条。
///
/// 协议还带着【待填写】占位符就发到用户手上是很糟的观感，所以这里显式提示。
/// 定稿后把 [LegalDocuments.isDraft] 改成 false 即消失。
class LegalDraftBanner extends StatelessWidget {
  const LegalDraftBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('legal_draft_banner'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Color(0xFFC2410C),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              LegalDocuments.draftNotice,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: Color(0xFF9A3412),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个条款：小标题 + 正文段落。
class LegalClauseView extends StatelessWidget {
  const LegalClauseView({super.key, required this.clause});

  final LegalClause clause;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            clause.heading,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...clause.body.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                line,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.7,
                  color: AppTokens.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
