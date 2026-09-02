import 'package:box/features/cloud_sync/domain/cloud_sync_models.dart';
import 'package:box/features/cloud_sync/presentation/announcement_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AnnouncementEntry warning({String link = ''}) {
  return AnnouncementEntry(
    id: 'w1',
    title: '更新检查失败？请手动装一次 1.8.6',
    body: '183/184/185 版本无法通过更新检查，请手动下载安装。',
    level: 'warning',
    publishedAt: DateTime(2026, 9, 1),
    pinned: true,
    linkUrl: link,
  );
}

/// 把弹窗挂到一个最小 App 上，模拟 shell 在首帧后调用它。
Future<int> pumpPopup(
  WidgetTester tester, {
  required AnnouncementEntry entry,
}) async {
  var ackCalls = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return ElevatedButton(
            onPressed: () => showAnnouncementPopup(
              context: context,
              entry: entry,
              onAcknowledged: () async => ackCalls++,
            ),
            child: const Text('go'),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return ackCalls;
}

void main() {
  testWidgets('弹窗真的显示出标题和正文', (tester) async {
    await pumpPopup(tester, entry: warning());

    expect(find.text('更新检查失败？请手动装一次 1.8.6'), findsOneWidget);
    expect(
      find.textContaining('183/184/185'),
      findsOneWidget,
      reason: '正文必须可见，用户才知道自己是否受影响',
    );
  });

  testWidgets('点「知道了」会标已读并关闭', (tester) async {
    var ackCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () => showAnnouncementPopup(
                context: context,
                entry: warning(),
                onAcknowledged: () async => ackCalls++,
              ),
              child: const Text('go'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    expect(ackCalls, 1, reason: '必须落已读，否则下次启动会重复弹');
    expect(find.text('知道了'), findsNothing, reason: '弹窗应关闭');
  });

  testWidgets('点「稍后再看」不标已读，下次仍会提醒', (tester) async {
    var ackCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () => showAnnouncementPopup(
                context: context,
                entry: warning(),
                onAcknowledged: () async => ackCalls++,
              ),
              child: const Text('go'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('稍后再看'));
    await tester.pumpAndSettle();

    expect(ackCalls, 0);
    expect(find.text('稍后再看'), findsNothing);
  });

  testWidgets('有 linkUrl 时给出可复制的地址（项目无 url_launcher）', (tester) async {
    const url =
        'https://box.hpa888.top/updates/box/android/release/box-1.8.6-186.apk';
    await pumpPopup(tester, entry: warning(link: url));

    expect(find.text(url), findsOneWidget, reason: '地址要显示出来供复制');
    expect(find.byTooltip('复制链接'), findsOneWidget);
  });

  testWidgets('没有 linkUrl 时不渲染空链接行', (tester) async {
    await pumpPopup(tester, entry: warning());
    expect(find.byTooltip('复制链接'), findsNothing);
  });

  testWidgets('点遮罩不能糊掉弹窗，避免误触后再也看不到', (tester) async {
    await pumpPopup(tester, entry: warning());

    // 点弹窗外的区域
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(
      find.text('知道了'),
      findsOneWidget,
      reason: 'barrierDismissible 必须为 false',
    );
  });
}
