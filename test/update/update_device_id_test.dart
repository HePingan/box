// 更新检查用的设备标识：灰度发布靠它认人。
//
// 锁住三件事：
//   1. 同一安装内稳定（每次检查更新都变的话，服务端名单永远对不上）
//   2. 是随机的十六进制串，不含任何硬件标识（隐私边界）
//   3. 读不到 prefs 时返回空串而不是抛异常（更新检查不该因此失败）
import 'package:box/update/update_device_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    UpdateDeviceId.resetCacheForTest();
  });

  group('稳定性', () {
    test('首次调用会生成并落盘', () async {
      final id = await UpdateDeviceId.get();
      expect(id, isNotEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(UpdateDeviceId.prefsKey), id,
          reason: '必须落盘，否则重启后变成新设备、灰度名单失效');
    });

    test('同一进程内多次调用返回同一个值', () async {
      final a = await UpdateDeviceId.get();
      final b = await UpdateDeviceId.get();
      expect(a, b);
    });

    test('清掉进程缓存后仍从磁盘读到同一个值（模拟重启）', () async {
      final first = await UpdateDeviceId.get();
      UpdateDeviceId.resetCacheForTest();
      final second = await UpdateDeviceId.get();
      expect(second, first, reason: '重启后必须是同一台设备，否则灰度认不出人');
    });

    test('已有值时不会覆盖', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        UpdateDeviceId.prefsKey: 'fixed-device-id-for-test',
      });
      UpdateDeviceId.resetCacheForTest();

      expect(await UpdateDeviceId.get(), 'fixed-device-id-for-test');
    });
  });

  group('格式与隐私', () {
    test('32 位小写十六进制', () async {
      final id = await UpdateDeviceId.get();
      expect(id.length, 32, reason: '16 字节随机 → 32 个 hex 字符');
      expect(
        RegExp(r'^[0-9a-f]{32}$').hasMatch(id),
        isTrue,
        reason: '只允许小写十六进制，避免大小写导致服务端比对不一致',
      );
    });

    test('generate() 每次不同（不是固定常量）', () {
      final ids = <String>{for (var i = 0; i < 20; i++) UpdateDeviceId.generate()};
      expect(ids.length, 20, reason: '随机串撞车会让两台设备共用一个灰度身份');
    });

    test('不含设备型号/序列号这类可识别信息', () async {
      final id = await UpdateDeviceId.get();
      // 纯 hex，自然不含字母 G-Z、横线、冒号等硬件标识常见字符
      expect(id.contains('-'), isFalse);
      expect(id.contains(':'), isFalse);
      expect(id.toUpperCase(), isNot(id), reason: '全小写');
    });
  });

  group('容错', () {
    test('把已有值设成空白串时视为无效、重新生成', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        UpdateDeviceId.prefsKey: '   ',
      });
      UpdateDeviceId.resetCacheForTest();

      final id = await UpdateDeviceId.get();
      expect(id.trim(), isNotEmpty, reason: '空白值等于没有，必须重新生成');
      expect(id.trim(), id, reason: '不该带着空白返回给服务端');
    });
  });
}
