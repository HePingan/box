// 小窗（分屏/自由窗口）下正文永久转圈的回归测试。
//
// 朋友真机复现（iQOO / OriginOS，App 1.13.0+209）的关键三行日志：
//
//   _calculatePages: START ... fitWidth=344.0 firstHeight=514.4  ← 小窗高度，重算已触发
//   _restorePagePositionAfterPaginate: START hasClients=false textPages=13
//   _restorePagePositionAfterPaginate: EARLY RETURN (hasClients=false textPagesEmpty=false)
//
// 链条：进小窗 → 高度变化触发重算 → 重算那一帧 _textPages 被替换，build 走
// `_textPages.isEmpty` 的 CircularProgressIndicator 分支 → ReaderPagedView 连同
// PageView 整个从树上摘掉 → _pageController.detach → postFrame 里恢复发现
// hasClients=false 直接 return → _pendingRestore 永远停在 true →
// 此后 _saveProgress 全部 SKIPPED，正文再不刷新，用户看到的就是死转圈。
//
// 全屏时 hasClients=true 走正常跳页路径，所以放大就好了 —— 这正是朋友的症状。
//
// 修法不是「放弃」也不是「无脑重试」：PageView 可能真的已经销毁（退出页面），
// 那种情况下必须停手，否则 postFrame 自己排自己会烧 CPU。所以决策要区分
// 「暂时 detach，下一帧会回来」和「已经没了」。
library;

import 'package:box/novel/pages/reader/reader_restore_retry.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('恢复遇到 PageView detach', () {
    test('复现朋友日志：有内容但 detach，必须重试而不是放弃', () {
      // 对应真实日志那一行：textPages=13（有内容），hasClients=false。
      final decision = ReaderRestoreRetry.decide(
        hasClients: false,
        hasPages: true,
        mounted: true,
        attempt: 0,
      );

      expect(
        decision,
        ReaderRestoreAction.retryNextFrame,
        reason: '有内容却 detach 是暂时状态，放弃就会把闸门永久卡在 pendingRestore=true',
      );
    });

    test('attach 上了就直接恢复', () {
      expect(
        ReaderRestoreRetry.decide(
          hasClients: true,
          hasPages: true,
          mounted: true,
          attempt: 0,
        ),
        ReaderRestoreAction.restoreNow,
      );
    });

    test('页面已卸载：停手，不能自排自帧烧 CPU', () {
      expect(
        ReaderRestoreRetry.decide(
          hasClients: false,
          hasPages: true,
          mounted: false,
          attempt: 0,
        ),
        ReaderRestoreAction.abandon,
      );
    });

    test('真的没有内容：停手（等下一轮分页自己会再来）', () {
      expect(
        ReaderRestoreRetry.decide(
          hasClients: false,
          hasPages: false,
          mounted: true,
          attempt: 0,
        ),
        ReaderRestoreAction.abandon,
      );
    });

    test('重试有上限，不能无限排帧', () {
      final last = ReaderRestoreRetry.decide(
        hasClients: false,
        hasPages: true,
        mounted: true,
        attempt: ReaderRestoreRetry.maxAttempts - 1,
      );
      expect(last, ReaderRestoreAction.retryNextFrame);

      final over = ReaderRestoreRetry.decide(
        hasClients: false,
        hasPages: true,
        mounted: true,
        attempt: ReaderRestoreRetry.maxAttempts,
      );
      expect(
        over,
        ReaderRestoreAction.abandon,
        reason: '超过上限必须停手，否则一个永不 attach 的 PageView 会让它一直排帧',
      );
    });

    test('上限要够跨过一次窗口切换（不能只给 1 帧）', () {
      // 真机日志里从 configuration_changed 到 after_layout 约 36ms，
      // 60fps 下是 2 帧多；只给 1 次重试机会会在慢机上失手。
      expect(ReaderRestoreRetry.maxAttempts, greaterThanOrEqualTo(5));
    });

    test('reader_page 真的用上了这个决策（接线守卫）', () {
      // 光有决策模块不算修好：如果 reader_page 还留着
      // `!_pageController.hasClients` 直接 return，这就是死代码。
      // 注意剥掉注释再扫，否则文档里提到的旧写法会让断言假绿。
      final src = File('lib/novel/pages/reader_page.dart').readAsStringSync();
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');

      expect(
        code,
        contains('ReaderRestoreRetry.decide'),
        reason: '恢复逻辑必须走重试决策',
      );
      expect(
        code.contains('!_pageController.hasClients ||'),
        isFalse,
        reason: '旧的「detach 就放弃」早返回必须已经拆掉',
      );
      // 变异测试暴露的盲区：只验证「调用了 decide」的话，把参数写成死值
      // （hasPages: true）也照样绿，而那会让空内容时无限排帧。
      expect(
        code,
        contains('hasClients: _pageController.hasClients'),
        reason: 'hasClients 必须接真实 PageController 状态，不能是死值',
      );
      expect(
        code,
        contains('hasPages: _textPages.isNotEmpty'),
        reason: 'hasPages 必须接真实页列表，不能是死值',
      );
      expect(
        code,
        contains('mounted: mounted'),
        reason: 'mounted 必须接真实挂载状态，否则卸载后会一直排帧',
      );
    });

    test('闸门必须在停手时也关掉（否则进度永久存不下来）', () {
      // 这是本 bug 最伤的后果：不是「少跳一页」，而是 _saveProgress 全程
      // SKIPPED。无论恢复成功还是放弃，闸门都得关。
      for (final action in ReaderRestoreAction.values) {
        expect(
          ReaderRestoreRetry.shouldCloseGate(action),
          action != ReaderRestoreAction.retryNextFrame,
          reason: '只有「下一帧再来」时才允许继续持有闸门：$action',
        );
      }
    });
  });
}
