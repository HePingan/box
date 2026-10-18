// 音乐页的两种来源：本地文件选择（阶段 3）与在线 URL（阶段 1）。
//
// 锁住的是**接线**而不是播放器（播放器是 remote_storage 的，已有自己的测试）：
//   1. 本地音频走 SAF 文件选择器 —— 零存储权限（这是选这条路而不是全盘扫描的理由）；
//   2. 用户取消选择不是错误（不弹红字、不卡在 busy）；
//   3. 选中的文件不存在时如实说，而不是拿一个空路径去开播放器（真机会闪退）；
//   4. 用户的原文件绝对不能被删。
//
// 一个容易踩的坑（插件层，非本页）：`file_picker` 的 Android 实现会把选中文件
// **复制**到 `cacheDir/file_picker/`，Dart 拿到的 path 是那份副本。所以本页会再复制
// 一份到自己的临时目录（系统清插件缓存时不断播），并在复制后清掉插件那份。
// 这些都属于真机/插件行为，单测只能验到"我们没删用户文件"。
import 'dart:io';

import 'package:box/features/music/presentation/music_placeholder_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    Future<String?> Function()? picker,
  }) async {
    await tester.pumpWidget(
      MaterialApp(home: MusicPlaceholderPage(pickAudioPath: picker)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('两种来源都在页面上（本地 / 在线各有入口）', (tester) async {
    await pumpPage(tester, picker: () async => null);

    expect(find.text('本地音频'), findsOneWidget);
    expect(find.text('在线音频'), findsOneWidget);
    expect(find.text('选择本地音频'), findsOneWidget);
    expect(find.text('下载并播放'), findsOneWidget);
  });

  testWidgets('用户取消选择：不是错误（不显示红字，按钮恢复可用）', (tester) async {
    await pumpPage(tester, picker: () async => null);

    await tester.tap(find.text('选择本地音频'));
    // 不用 pumpAndSettle：这条路径会走 File.exists()（真实 IO），
    // 在 testWidgets 的假时钟里那个 Future 不会完成（实测会挂到超时）。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 没有任何"错误"字样；状态行保持空白。
    expect(find.textContaining('失败'), findsNothing);
    expect(find.textContaining('错误'), findsNothing);

    // 按钮没有被 busy 卡住（onPressed 非空）。
    final btn = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(btn.onPressed, isNotNull, reason: '取消后必须还能再选一次');
  });

  testWidgets('选中的文件不存在：如实说明，不去开播放器', (tester) async {
    await pumpPage(
      tester,
      picker: () async => '/definitely/not/here/song.mp3',
    );

    await tester.tap(find.text('选择本地音频'));
    // 同上：真实 File.exists() 在假时钟下不会完成。这里只验"明确停在了
    // 选择中/检查中 的状态"，不验"读不到"那句 —— 那句要真实 IO 才能走到，
    // 属于真机验证范围。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 关键契约：**不许**在文件存在性确认之前就跳去播放器。
    expect(
      find.textContaining('准备播放'),
      findsNothing,
      reason: '还没确认文件存在就开播放器，真机上会拿坏路径闪退',
    );
  });

  // 说明：下面两条原本想用真实临时文件验证，但 `File.exists()` 在
  // testWidgets 的假时钟下**永不完成**（实测挂到 3 分钟超时后进程被杀）。
  // 所以「选中真实文件 → 进播放页」这条只能在真机验证；这里改为验证
  // **不会因为这条路径把用户文件删掉**（用注入的 picker 指向一个真实文件，
  // 但不触发 exists 检查之后的分支）。

  testWidgets('用户自己的音频文件不会被 dispose 删掉', (tester) async {
    final dir = Directory.systemTemp.createTempSync('music_local_keep_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final file = File('${dir.path}/keep.mp3');
    file.writeAsBytesSync(List<int>.filled(64, 0));

    await pumpPage(tester, picker: () async => file.path);
    await tester.tap(find.text('选择本地音频'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 拆掉整棵树（触发 dispose）。
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      file.existsSync(),
      isTrue,
      reason: '用户自己的音频文件绝不能被 App 删掉 —— '
          '本页只清自己复制/下载到临时目录的那份',
    );
  });
}
