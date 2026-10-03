import 'dart:io';

import 'package:box/video/controller/video_detail_controller.dart';
import 'package:box/video/models/video_source.dart';
import 'package:box/video/models/vod_item.dart';
import 'package:box/video/services/line_reachability_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ② 线路可用性前置标注的护栏。
///
/// 起因（实测）：部分采集线路拿不到流（`/share/<id>` 这类网页地址没有
/// `var main`；个别媒体域名 DNS/TCP 连不上），在线路 chip 上毫无预兆 ——
/// 用户点进去先卡一次，再被自动换到另一条线。
/// 这里守三件事：记忆判得对（含过期）、默认选线会跳过被标记的线、
/// 起播成功后标记要立刻清掉（线路恢复不用等 TTL）。
const _source = VideoSource(
  id: 'test-source',
  name: '测试源',
  url: 'https://api.example.com/api.php/provide/vod/',
  detailUrl: '',
);

VodItem _detailWithTwoLines() {
  return VodItem(
    vodId: 1,
    vodName: '测试片',
    vodPlayFrom: 'lzm3u8\$\$\$HD',
    vodPlayUrl:
        '第1集\$https://a.example.com/1.m3u8#第2集\$https://a.example.com/2.m3u8'
        '\$\$\$'
        '第1集\$https://b.example.com/1.m3u8#第2集\$https://b.example.com/2.m3u8',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('box_line_reach_hive_');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDir.existsSync()) await hiveDir.delete(recursive: true);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LineReachabilityStore.resetForTest();
  });

  group('LineReachabilityStore —— 记忆判据', () {
    test('失败后判为「最近取不到流」，成功后立刻清掉', () async {
      await LineReachabilityStore.markFailure(
        sourceKey: 'test-source',
        lineName: 'lzm3u8',
        reason: '上次这条线路取不到流',
      );
      expect(
        LineReachabilityStore.isRecentlyUnreachable(
          sourceKey: 'test-source',
          lineName: 'lzm3u8',
        ),
        isTrue,
      );
      // 大小写 / 空白归一：同一个线路名不该因为写法不同而漏判。
      expect(
        LineReachabilityStore.isRecentlyUnreachable(
          sourceKey: 'test-source',
          lineName: ' LZM3U8 ',
        ),
        isTrue,
      );

      await LineReachabilityStore.markSuccess(
        sourceKey: 'test-source',
        lineName: 'lzm3u8',
      );
      expect(
        LineReachabilityStore.isRecentlyUnreachable(
          sourceKey: 'test-source',
          lineName: 'lzm3u8',
        ),
        isFalse,
      );
    });

    test('过期（超过 6 小时）就视为可以再试一次，不再标注', () async {
      final now = DateTime(2026, 10, 3, 12);
      await LineReachabilityStore.markFailure(
        sourceKey: 'test-source',
        lineName: 'HD',
        now: now,
      );

      expect(
        LineReachabilityStore.isRecentlyUnreachable(
          sourceKey: 'test-source',
          lineName: 'HD',
          now: now.add(const Duration(hours: 5)),
        ),
        isTrue,
      );
      expect(
        LineReachabilityStore.isRecentlyUnreachable(
          sourceKey: 'test-source',
          lineName: 'HD',
          now: now.add(const Duration(hours: 7)),
        ),
        isFalse,
      );
    });

    test('成功发生在失败之后 → 不算「最近取不到流」', () async {
      final failedAt = DateTime(2026, 10, 3, 12);
      await LineReachabilityStore.markFailure(
        sourceKey: 'test-source',
        lineName: 'HD',
        now: failedAt,
      );
      await LineReachabilityStore.markSuccess(
        sourceKey: 'test-source',
        lineName: 'HD',
        now: failedAt.add(const Duration(minutes: 10)),
      );
      expect(
        LineReachabilityStore.isRecentlyUnreachable(
          sourceKey: 'test-source',
          lineName: 'HD',
          now: failedAt.add(const Duration(hours: 1)),
        ),
        isFalse,
      );
    });

    test('没见过的线路一律判「可用」，不误伤', () {
      expect(
        LineReachabilityStore.isRecentlyUnreachable(
          sourceKey: 'test-source',
          lineName: '从未用过',
        ),
        isFalse,
      );
      expect(
        LineReachabilityStore.failureReasonOf(
          sourceKey: 'test-source',
          lineName: '从未用过',
        ),
        isNull,
      );
    });
  });

  group('VideoDetailController —— 默认选线 + 失败记账', () {
    test('被标记的线路默认不选（改成选另一条线路）', () async {
      await LineReachabilityStore.markFailure(
        sourceKey: _source.id,
        lineName: 'lzm3u8',
        reason: '上次这条线路取不到流',
      );

      final controller = VideoDetailController(
        source: _source,
        vodId: 1,
        detailFetcher: () async => _detailWithTwoLines(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(controller.playLines.length, 2);
      expect(controller.playLines[0].name, 'lzm3u8');
      // 原判据会优先选 m3u8 线路（index 0），但它被标记过 → 落到 HD。
      expect(controller.selectedLineIndex, 1);
      expect(controller.isLineRecentlyUnreachable(0), isTrue);
      expect(controller.isLineRecentlyUnreachable(1), isFalse);
      expect(controller.lineUnreachableReason(0), '上次这条线路取不到流');
      controller.dispose();
    });

    test('所有线路都被标记时忽略标记，仍按原判据选（别把用户锁死）', () async {
      for (final name in ['lzm3u8', 'HD']) {
        await LineReachabilityStore.markFailure(
          sourceKey: _source.id,
          lineName: name,
        );
      }

      final controller = VideoDetailController(
        source: _source,
        vodId: 1,
        detailFetcher: () async => _detailWithTwoLines(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(controller.selectedLineIndex, 0, reason: 'm3u8 仍优先');
      controller.dispose();
    });

    test('起播成功清掉当前线路的标记', () async {
      await LineReachabilityStore.markFailure(
        sourceKey: _source.id,
        lineName: 'lzm3u8',
      );

      final controller = VideoDetailController(
        source: _source,
        vodId: 1,
        detailFetcher: () async => _detailWithTwoLines(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      controller.selectLine(0);
      await controller.markCurrentLineStarted();

      expect(
        LineReachabilityStore.isRecentlyUnreachable(
          sourceKey: _source.id,
          lineName: 'lzm3u8',
        ),
        isFalse,
      );
      controller.dispose();
    });

    test('换线时记下失败的那条线，且下次换线优先选没被标记的', () async {
      final controller = VideoDetailController(
        source: _source,
        vodId: 1,
        detailFetcher: () async => _detailWithTwoLines(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(controller.selectedLineIndex, 0);
      // 当前线路（lzm3u8）取不到流 → 自动换到 HD，并记下 lzm3u8 失败。
      final fallback = controller.findFallbackLineIndex(
        excludingLineIndex: controller.selectedLineIndex,
      );
      expect(fallback, 1);
      controller.selectFallbackLine(1);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        LineReachabilityStore.isRecentlyUnreachable(
          sourceKey: _source.id,
          lineName: 'lzm3u8',
        ),
        isTrue,
      );
      // 再换一次（HD 也失败了）：候选里 lzm3u8 虽被标记，但仍按顺序给出。
      expect(
        controller.findFallbackLineIndex(
          excludingLineIndex: controller.selectedLineIndex,
        ),
        0,
      );
      controller.dispose();
    });
  });
}
