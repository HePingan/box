import 'package:box/update/update_check_outcome.dart';
import 'package:box/update/update_last_check_store.dart';
import 'package:box/update/update_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「上次检查更新」的记录与说人话。
///
/// 背景：清单缓存（`update_manifest_cache_v1`）里没有任何时间戳，所以「上次什么时候
/// 检查、结果如何」只能靠这份记录。两条底线：
///  - 记录坏掉/枚举不认识 → 当作**没有记录**，绝不显示一个错的结论；
///  - 相对时间的边界写死并测住（刚检查完必须是「刚刚」，不是「0 分钟前」）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 用 fromJson 造清单：真实构造器有一堆 required 字段（含可为空的），
  /// 手工填一遍只会让测试比被测代码还长，而 fromJson 本来就容忍缺字段。
  UpdateManifest manifest({int code = 363, String name = '1.21.6'}) =>
      UpdateManifest.fromJson({
        'schemaVersion': 1,
        'appId': 'box',
        'platform': 'android',
        'channel': 'release',
        'packageName': 'top.hpa888.box',
        'latestVersionCode': code,
        'latestVersionName': name,
        'minSupportedVersionCode': 0,
        'blockedVersionCodes': <int>[],
        'forceUpdate': false,
      });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('记录与读取', () {
    test('检查完之后能读回时间、结论与线上版本号', () async {
      await UpdateLastCheckStore.record(
        UpdateCheckOutcome.fromManifest(
          manifest: manifest(),
          currentVersionCode: 362,
        ),
      );

      final last = await UpdateLastCheckStore.read();
      expect(last, isNotNull);
      expect(last!.status, UpdateCheckStatus.updateAvailable);
      expect(last.latestVersionCode, 363);
      expect(last.latestVersionName, '1.21.6');
      expect(
        last.describe(),
        '发现新版本 1.21.6 (363)',
        reason: '说法要与检查当下逐字一致（复用同一函数）',
      );
      // 时间必须是「刚刚」量级 —— 记录的是当下
      expect(last.ageText(DateTime.now()), '刚刚');
    });

    test('失败也照记（网络不通时不能看起来像从没检查过）', () async {
      await UpdateLastCheckStore.record(
        UpdateCheckOutcome.failure(
          UpdateCheckStatus.networkError,
          detail: 'connection timeout',
        ),
      );

      final last = await UpdateLastCheckStore.read();
      expect(last!.status, UpdateCheckStatus.networkError);
      expect(last.describe(), contains('网络请求失败'));
      expect(last.describe(), contains('connection timeout'));
      expect(last.latestVersionCode, isNull);
    });

    test('没记录时返回 null（界面显示原来的说明句，不写占位）', () async {
      expect(await UpdateLastCheckStore.read(), isNull);
    });
  });

  group('坏记录一律当作没有记录', () {
    test('JSON 坏掉 / 不是对象 / 缺字段', () async {
      for (final raw in ['{not json', '"a string"', '{}', '{"at":"x"}']) {
        SharedPreferences.setMockInitialValues({'update_last_check_v1': raw});
        expect(
          await UpdateLastCheckStore.read(),
          isNull,
          reason: 'raw=$raw 时应视为没有记录，而不是抛异常或猜一个结论',
        );
      }
    });

    test('枚举名不认识（版本降级/手改）时也不显示', () async {
      SharedPreferences.setMockInitialValues({
        'update_last_check_v1':
            '{"at":"2026-10-04T10:00:00.000","status":"someFutureStatus"}',
      });
      expect(await UpdateLastCheckStore.read(), isNull);
    });

    test('时间戳解析不了时也不显示', () async {
      SharedPreferences.setMockInitialValues({
        'update_last_check_v1':
            '{"at":"昨天","status":"${'upToDate'}"}',
      });
      expect(await UpdateLastCheckStore.read(), isNull);
    });
  });

  group('相对时间说人话', () {
    final now = DateTime(2026, 10, 4, 12, 0);

    UpdateLastCheck at(DateTime t) =>
        UpdateLastCheck(at: t, status: UpdateCheckStatus.upToDate);

    test('边界', () {
      expect(at(now).ageText(now), '刚刚');
      expect(
        at(now.subtract(const Duration(seconds: 59))).ageText(now),
        '刚刚',
      );
      expect(at(now.subtract(const Duration(minutes: 1))).ageText(now), '1 分钟前');
      expect(
        at(now.subtract(const Duration(minutes: 59))).ageText(now),
        '59 分钟前',
      );
      expect(at(now.subtract(const Duration(hours: 1))).ageText(now), '1 小时前');
      expect(at(now.subtract(const Duration(hours: 23))).ageText(now), '23 小时前');
      expect(at(now.subtract(const Duration(days: 1))).ageText(now), '1 天前');
      expect(at(now.subtract(const Duration(days: 29))).ageText(now), '29 天前');
      expect(
        at(now.subtract(const Duration(days: 30))).ageText(now),
        '2026-09-04',
        reason: '超过 30 天给具体日期，比「30 天前」好对照',
      );
    });

    test('时间戳来自未来时给日期，不编相对时间', () {
      final future = now.add(const Duration(hours: 3));
      expect(
        at(future).ageText(now),
        '2026-10-04',
        reason: '「-3 小时前」或「0 分钟前」都会让人以为刚检查过',
      );
    });
  });
}
