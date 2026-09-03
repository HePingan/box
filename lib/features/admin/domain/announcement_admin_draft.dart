/// 管理员编辑公告时使用的纯数据模型。
///
/// `warning` 会触发客户端的阻断式启动弹窗；普通版本说明应使用 `notice`。
enum AnnouncementLevel {
  info('info', '信息'),
  notice('notice', '通知'),
  warning('warning', '重要提醒（启动弹窗）');

  const AnnouncementLevel(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static AnnouncementLevel fromApi(String? value) {
    return AnnouncementLevel.values.firstWhere(
      (level) => level.apiValue == value?.trim().toLowerCase(),
      orElse: () => AnnouncementLevel.info,
    );
  }
}

class AnnouncementAdminDraft {
  const AnnouncementAdminDraft({
    this.title = '',
    this.body = '',
    this.linkUrl = '',
    this.level = AnnouncementLevel.info,
    this.pinned = false,
  });

  final String title;
  final String body;
  final String linkUrl;
  final AnnouncementLevel level;
  final bool pinned;

  bool get canSaveDraft => true;

  String? get publishError {
    if (title.trim().isEmpty && body.trim().isEmpty) return '请填写公告标题和正文';
    if (title.trim().isEmpty) return '请填写公告标题';
    if (body.trim().isEmpty) return '请填写公告正文';
    return null;
  }

  bool get isStartupBlocking => level == AnnouncementLevel.warning;

  Map<String, dynamic> toPayload({required bool published}) {
    return {
      'title': title.trim(),
      'body': body.trim(),
      'level': level.apiValue,
      'pinned': pinned,
      'linkUrl': linkUrl.trim(),
      'published': published,
    };
  }
}
