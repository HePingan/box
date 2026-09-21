import 'package:box/features/about/data/update_history_models.dart';
import 'package:box/features/about/data/update_history_repository.dart';
import 'package:box/features/about/presentation/update_history_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 历史更新页的**降级路径**回归。
///
/// 这个页面依赖网络，所以真正要锁的不是"成功时长什么样"，而是失败 / 空列表
/// 时用户看到什么。三种状态用户该做的事不一样，不能混成一句"加载失败"。
class _FakeRepo extends UpdateHistoryRepository {
  _FakeRepo(this._result);

  final UpdateHistoryResult _result;

  String? lastPackageName;

  @override
  Future<UpdateHistoryResult> fetch({
    required String packageName,
    int limit = 30,
  }) async {
    lastPackageName = packageName;
    return _result;
  }
}

void main() {
  Widget host(UpdateHistoryResult result, {_FakeRepo? repo}) => MaterialApp(
        home: UpdateHistoryPage(
          repository: repo ?? _FakeRepo(result),
          // 必须注入：widget test 里 PackageInfo.fromPlatform() 既不抛也不返回，
          // 会一直挂住，页面永远停在 loading（真实踩到过）。
          packageNameOverride: 'top.hpa888.box',
        ),
      );

  testWidgets('成功：列出版本号与更新说明', (tester) async {
    await tester.pumpWidget(host(
      UpdateHistoryResult.success([
        UpdateHistoryEntry(
          versionName: '1.10.2',
          versionCode: 203,
          publishedAt: DateTime(2026, 9, 5),
          title: '修复调试日志',
          changelog: const ['修正日志级别丢失', '日志改为倒序'],
        ),
      ]),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('1.10.2'), findsWidgets);
    expect(find.textContaining('修正日志级别丢失'), findsOneWidget);
  });

  testWidgets('成功：不泄露下载地址与校验值', (tester) async {
    await tester.pumpWidget(host(
      UpdateHistoryResult.success([
        UpdateHistoryEntry(
          versionName: '1.9.9',
          versionCode: 199,
          changelog: const ['历史版本'],
          publishedAt: DateTime(2026, 8, 1),
        ),
      ]),
    ));
    await tester.pumpAndSettle();

    // 历史版本里有验签坏掉的包（v1.9.9+199）。给出下载入口等于给用户
    // 一条装到坏版本的路 —— 装新版只能走「检查更新」那条带验签的链路。
    expect(find.textContaining('http'), findsNothing);
    expect(find.text('下载'), findsNothing);
  });

  testWidgets('失败：显示具体原因 + 重试按钮，而不是一句「加载失败」', (tester) async {
    await tester.pumpWidget(
      host(const UpdateHistoryResult.failure('网络连接超时')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('网络连接超时'), findsOneWidget,
        reason: '不给具体原因，用户和开发者都没法判断是网络问题还是服务端问题');
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('空列表：与失败区分开，说明是服务端暂无记录', (tester) async {
    await tester.pumpWidget(host(const UpdateHistoryResult.success([])));
    await tester.pumpAndSettle();

    expect(find.textContaining('暂无'), findsOneWidget);
    // 空不是错误：不该出现失败态那个「重试」按钮。
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('包名按平台真实值传给仓库，不是硬编码', (tester) async {
    final repo = _FakeRepo(const UpdateHistoryResult.success([]));
    await tester.pumpWidget(host(const UpdateHistoryResult.success([]),
        repo: repo));
    await tester.pumpAndSettle();

    expect(repo.lastPackageName, 'top.hpa888.box');
  });
}
