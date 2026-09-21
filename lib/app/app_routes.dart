import 'package:flutter/widgets.dart';

import '../features/account/presentation/account_page.dart';
import '../features/account/presentation/personal_center_page.dart';
import '../features/admin/presentation/admin_page.dart';
import '../features/cloud_sync/presentation/announcement_page.dart';
import '../novel/pages/source_manager/book_source_bootstrap.dart';
import '../novel/pages/source_manager/book_source_manager_page.dart';
import '../features/settings/presentation/data_settings_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../pages/debug_log_page.dart';
import '../features/about/data/legal_documents.dart';
import '../features/about/presentation/about_content_page.dart';
import '../features/about/presentation/about_page.dart';
import '../features/about/presentation/legal_document_page.dart';
import '../features/about/presentation/update_check_page.dart';
import '../features/about/presentation/update_history_page.dart';

class AppRoutes {
  const AppRoutes._();

  static const debugLog = '/debug-log';
  static const bookSourceManager = '/book-source-manager';
  static const account = '/account';
  static const personalCenter = '/account/personal-center';
  static const accountAdmin = '/account/admin';

  /// 独立设置页。改之前抽屉里的「设置」和「账号中心」跳的是同一个
  /// [account]，两个入口撞同一个页面。
  static const settings = '/settings';
  static const dataSettings = '/settings/data';

  /// 公告一级入口。原先只能从「抽屉 → 账号 → 个人中心」三层点进去，
  /// 线上出故障时等于没有触达手段。
  static const announcements = '/announcements';

  /// 关于页及其二级页。
  ///
  /// 关于原先是抽屉里的一个 AlertDialog，装不下版本信息 / 软件介绍 / 使用文档 /
  /// 推荐教程 / 历史更新 / 用户协议 / 隐私政策这一堆内容，改成设置式整页。
  static const about = '/about';
  static const aboutIntroduction = '/about/introduction';
  static const aboutGuide = '/about/guide';
  static const aboutTutorial = '/about/tutorial';
  static const updateCheck = '/about/update-check';
  static const updateHistory = '/about/update-history';

  /// 法律条款。这两个入口是**常驻**的：用户在首启闸门同意过之后，
  /// 仍然必须能随时回来复查自己同意了什么。
  static const legalUserAgreement = '/legal/user-agreement';
  static const legalPrivacyPolicy = '/legal/privacy-policy';

  static Map<String, WidgetBuilder> buildRoutes(
    BookSourceBootstrapResult novelBootstrap,
  ) {
    return {
      debugLog: (_) => const DebugLogPage(),
      account: (_) => const AccountPage(),
      personalCenter: (_) => const PersonalCenterPage(),
      accountAdmin: (_) => const AdminPage(),
      settings: (_) => const SettingsPage(),
      dataSettings: (_) => const DataSettingsPage(),
      announcements: (_) => const AnnouncementPage(),
      about: (_) => const AboutPage(),
      aboutIntroduction: (_) => AboutContentPage.introduction(),
      aboutGuide: (_) => AboutContentPage.usageDocs(),
      aboutTutorial: (_) => const AboutTutorialPage(),
      updateCheck: (_) => const UpdateCheckPage(),
      updateHistory: (_) => const UpdateHistoryPage(),
      legalUserAgreement: (_) => const LegalDocumentPage(
        title: LegalDocuments.userAgreementTitle,
        clauses: LegalDocuments.userAgreement,
      ),
      legalPrivacyPolicy: (_) => const LegalDocumentPage(
        title: LegalDocuments.privacyPolicyTitle,
        clauses: LegalDocuments.privacyPolicy,
      ),
      bookSourceManager: (_) => BookSourceManagerPage(
        startupMessage: novelBootstrap.configured ? '' : novelBootstrap.message,
      ),
    };
  }
}
