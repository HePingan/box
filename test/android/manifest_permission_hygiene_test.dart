import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// AndroidManifest 权限卫生回归。
///
/// 由来：manifest 里曾声明 `USE_EXACT_ALARM`，注释说是「视频下载断点续传恢复」用的，
/// 但原生侧全库搜不到任何 AlarmManager / setExact / canScheduleExactAlarms 调用，
/// 续传实际靠 VideoDownloadService 前台服务 + DownloadTaskStore 落盘实现。
/// 这属于「写了没做」的多余高敏感权限：既要在隐私政策里向用户解释，
/// 也是应用商店审核的扣分项。
///
/// 这个测试是为了让它别被顺手加回来 —— 复制粘贴一段权限声明太容易了。
/// 如果将来真的要用精确闹钟，请先实现调用、再改这里的白名单，
/// 并同步更新隐私政策「六、系统权限」一节。
void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  );

  /// 声明了就必须有对应实现的高敏感权限。
  const sensitivePermissions = <String, String>{
    'USE_EXACT_ALARM': 'AlarmManager / setExact 调用',
    'SCHEDULE_EXACT_ALARM': 'AlarmManager / setExact 调用',
    'REQUEST_INSTALL_PACKAGES': '安装更新包',
    'MANAGE_EXTERNAL_STORAGE': '全盘文件访问',
  };

  test('manifest 存在', () {
    expect(manifest.existsSync(), isTrue,
        reason: '测试需从项目根目录运行：flutter test');
  });

  test('不再声明 USE_EXACT_ALARM（原生侧无 AlarmManager 实现）', () {
    final xml = manifest.readAsStringSync();

    // 只看真实的权限声明行，注释里提到名字是允许的（我们留了说明注释）。
    final declared = _declaredPermissions(xml);

    expect(
      declared,
      isNot(contains('android.permission.USE_EXACT_ALARM')),
      reason: '原生侧没有 AlarmManager 调用，续传走前台服务；'
          '若确需精确闹钟请先落地实现并更新隐私政策第六条',
    );
    expect(
      declared,
      isNot(contains('android.permission.SCHEDULE_EXACT_ALARM')),
    );
  });

  test('高敏感权限清单可枚举（便于人工复核）', () {
    final xml = manifest.readAsStringSync();
    final declared = _declaredPermissions(xml);

    // 不断言"必须为空"，只保证我们知道有哪些 —— 有些是真需要的。
    final sensitive = declared
        .where(
          (p) => sensitivePermissions.keys.any((k) => p.endsWith('.$k')),
        )
        .toList();

    for (final p in sensitive) {
      final key = sensitivePermissions.keys.firstWhere(
        (k) => p.endsWith('.$k'),
      );
      // 打印而非失败：让 CI 日志留痕，人工能看到"这个权限需要有 X 支撑"。
      // ignore: avoid_print
      print('高敏感权限 $p 需要有实现支撑：${sensitivePermissions[key]}');
    }

    expect(sensitive, isNot(contains('android.permission.USE_EXACT_ALARM')));
  });
}

/// 提取真实的 `<uses-permission>` 声明，跳过 XML 注释块。
///
/// 直接对整个文件 `contains('USE_EXACT_ALARM')` 会被我们留下的说明注释绊倒，
/// 那样测试就永远是红的、且理由是错的。
List<String> _declaredPermissions(String xml) {
  final withoutComments = xml.replaceAll(
    RegExp(r'<!--.*?-->', dotAll: true),
    '',
  );
  return RegExp(r'<uses-permission[^>]*android:name="([^"]+)"')
      .allMatches(withoutComments)
      .map((m) => m.group(1)!)
      .toList();
}
