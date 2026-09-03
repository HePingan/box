import 'package:box/features/admin/domain/announcement_admin_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnnouncementAdminDraft', () {
    test('草稿可保存但发布前必须有标题和正文', () {
      const empty = AnnouncementAdminDraft();
      expect(empty.canSaveDraft, isTrue);
      expect(empty.publishError, '请填写公告标题和正文');

      const titled = AnnouncementAdminDraft(title: '修复通知');
      expect(titled.publishError, '请填写公告正文');

      const ready = AnnouncementAdminDraft(title: '修复通知', body: '正文内容');
      expect(ready.publishError, isNull);
    });

    test('warning 发布说明会阻断启动流程，notice 不会', () {
      expect(
        const AnnouncementAdminDraft(
          level: AnnouncementLevel.warning,
        ).isStartupBlocking,
        isTrue,
      );
      expect(
        const AnnouncementAdminDraft(
          level: AnnouncementLevel.notice,
        ).isStartupBlocking,
        isFalse,
      );
    });

    test('toPayload trim 文本并保留草稿的 published=false', () {
      const draft = AnnouncementAdminDraft(
        title: '  标题  ',
        body: '  正文  ',
        linkUrl: ' https://example.com ',
        level: AnnouncementLevel.notice,
        pinned: true,
      );
      expect(draft.toPayload(published: false), {
        'title': '标题',
        'body': '正文',
        'level': 'notice',
        'pinned': true,
        'linkUrl': 'https://example.com',
        'published': false,
      });
    });
  });
}
