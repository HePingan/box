import 'package:box/features/cloud_sync/data/announcement_service.dart';
import 'package:box/features/cloud_sync/domain/announcement_center.dart';
import 'package:box/features/cloud_sync/domain/cloud_sync_models.dart';
import 'package:box/features/cloud_sync/presentation/announcement_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// 这组测试守的是「接线」而不是「零件」。
///
/// 183/184/185 事故的真正教训：公告数据能拉能解析（零件是好的），但没有任何
/// 地方在启动时调用它（接线是断的）。所以这里必须断言「首帧后 bootstrap 被
/// 调到了」和「未读 warning 真的弹出来了」，而不是只测 center 自己的方法。
class _RecordingService extends AnnouncementService {
  _RecordingService(this._items);

  final List<AnnouncementEntry> _items;
  int loadCalls = 0;

  @override
  Future<AnnouncementState> loadCachedOnly() async => AnnouncementState.empty;

  @override
  Future<AnnouncementState> load({bool force = false}) async {
    loadCalls++;
    return AnnouncementState(
      items: _items,
      readIds: const {},
      fetchedAt: DateTime.now(),
      fromCache: false,
    );
  }

  @override
  Future<Set<String>> markRead(String id) async => {id};
}

AnnouncementEntry entry(String id, String level) => AnnouncementEntry(
  id: id,
  title: '标题 $id',
  body: '正文 $id',
  level: level,
  publishedAt: DateTime(2026, 9, 1),
  pinned: false,
  linkUrl: '',
);

/// 复刻 shell 的接线方式（首帧后 bootstrap + 弹窗），不拉起整个 AppShell
/// —— 后者依赖十几个 provider 和平台通道，在单测里起不来。
class _ShellLike extends StatefulWidget {
  const _ShellLike();

  @override
  State<_ShellLike> createState() => _ShellLikeState();
}

class _ShellLikeState extends State<_ShellLike> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final center = context.read<AnnouncementCenter>();
      await center.bootstrap();
      if (!mounted) return;
      final popup = center.takePopup();
      if (popup == null || !mounted) return;
      await showAnnouncementPopup(
        context: context,
        entry: popup,
        onAcknowledged: () => center.acknowledge(popup.id),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('shell'));
}

Future<_RecordingService> pumpShell(
  WidgetTester tester,
  List<AnnouncementEntry> items,
) async {
  final service = _RecordingService(items);
  await tester.pumpWidget(
    ChangeNotifierProvider<AnnouncementCenter>(
      create: (_) => AnnouncementCenter(service: service),
      child: const MaterialApp(home: _ShellLike()),
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

void main() {
  testWidgets('启动后公告真的被拉了一次（不再依赖用户打开个人中心）', (tester) async {
    final service = await pumpShell(tester, [entry('a', 'info')]);
    expect(
      service.loadCalls,
      1,
      reason: '首帧后必须主动拉公告，否则线上故障时触达不到用户',
    );
  });

  testWidgets('启动后未读 warning 公告真的弹出来了', (tester) async {
    await pumpShell(tester, [entry('w1', 'warning')]);

    expect(find.text('标题 w1'), findsOneWidget, reason: 'warning 必须弹窗');
    expect(find.text('知道了'), findsOneWidget);
  });

  testWidgets('只有 info 级公告时不弹窗打扰用户', (tester) async {
    await pumpShell(tester, [entry('a', 'info'), entry('b', 'notice')]);
    expect(find.text('知道了'), findsNothing);
  });

  testWidgets('红点计数在启动后就可读（供抽屉角标用）', (tester) async {
    await pumpShell(tester, [entry('w1', 'warning'), entry('a', 'info')]);

    final ctx = tester.element(find.text('shell'));
    final center = ctx.read<AnnouncementCenter>();
    expect(center.unreadCount, 2);
    expect(center.hasUnread, isTrue);
  });

  testWidgets('弹窗点「知道了」后未读数下降，不会下次再弹同一条', (tester) async {
    await pumpShell(tester, [entry('w1', 'warning')]);

    final ctx = tester.element(find.text('shell'));
    final center = ctx.read<AnnouncementCenter>();
    expect(center.unreadCount, 1);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    expect(center.unreadCount, 0, reason: '已读需落库，否则每次启动都弹');
    expect(center.takePopup(), isNull, reason: '同一次启动内不重复交付');
  });
}
