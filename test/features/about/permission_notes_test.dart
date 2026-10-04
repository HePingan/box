import 'dart:io';

import 'package:box/features/about/data/permission_notes.dart';
import 'package:flutter_test/flutter_test.dart';

/// 权限说明页的内容必须与清单逐条对应。
///
/// 这一页是「自证」用的：用户看到系统弹窗里那句「可以查看屏幕上的所有内容并控制
/// 设备」之后，唯一能拿到人话解释的地方就是这里。所以它对清单的**双向**一致是硬要求：
///  - 漏写一条 → 有一项权限用户看不到解释（最敏感的那些恰恰最容易漏）；
///  - 多写一条 → 解释了一个并不存在的权限，等于自己编了个权限出来。
///
/// 纯源码断言，不是行为测试：内容与清单不一致是结构问题，只有拿真实清单比对才拦得住。
void main() {
  Set<String> manifestPermissions() {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    return RegExp(r'<uses-permission\s+android:name="([^"]+)"')
        .allMatches(manifest)
        .map((m) => m.group(1)!)
        .toSet();
  }

  Set<String> documentedNames() =>
      kPermissionNotes.map((n) => n.manifestName).toSet();

  group('与 AndroidManifest 双向一致', () {
    test('清单里的每一项权限都有解释', () {
      final missing = manifestPermissions().difference(documentedNames());
      expect(
        missing,
        isEmpty,
        reason: '这些权限在清单里声明了，但「权限说明」里没有解释：$missing',
      );
    });

    test('不解释清单里不存在的权限', () {
      final extra = documentedNames().difference(manifestPermissions());
      expect(
        extra,
        isEmpty,
        reason: '这些权限在「权限说明」里有，但清单里并不存在 —— '
            '解释一个不存在的权限等于自己编：$extra',
      );
    });

    test('没有重复条目', () {
      expect(
        kPermissionNotes.map((n) => n.manifestName).toSet().length,
        kPermissionNotes.length,
        reason: '同一个权限被写了两条，用户会看到两遍',
      );
    });
  });

  group('每条都要说清四件事', () {
    test('四个字段都非空，且不留占位符', () {
      for (final note in kPermissionNotes) {
        for (final entry in {
          '为什么': note.why,
          '什么时候': note.when,
          '不给会怎样': note.ifDenied,
          '怎么关': note.howToRevoke,
        }.entries) {
          expect(
            entry.value.trim(),
            isNotEmpty,
            reason: '${note.title} 缺少「${entry.key}」',
          );
          for (final placeholder in ['TODO', '待补', '暂未']) {
            expect(
              entry.value.contains(placeholder),
              isFalse,
              reason: '${note.title} 的「${entry.key}」还留着占位符',
            );
          }
        }
        expect(note.title.trim(), isNotEmpty);
      }
    });

    test('敏感权限的说明必须写明「只在开启后才工作」与「不给不影响其它功能」', () {
      final accessibility = kPermissionNotes.firstWhere(
        (n) => n.manifestName.endsWith('BIND_ACCESSIBILITY_SERVICE'),
      );
      expect(
        accessibility.when.contains('插件'),
        isTrue,
        reason: '无障碍服务只在答题插件启用后工作，这句必须说清楚',
      );
      expect(
        accessibility.why.contains('不模拟点击'),
        isTrue,
        reason: '系统原文说「控制设备」，必须明确说本项目不模拟点击',
      );
      expect(
        accessibility.ifDenied.contains('其它功能'),
        isTrue,
        reason: '要明确告诉用户关掉它不影响应用的其它部分',
      );
      expect(
        accessibility.howToRevoke.contains('无障碍'),
        isTrue,
        reason: '必须给出系统里真正的关闭路径',
      );

      final mic = kPermissionNotes.firstWhere(
        (n) => n.manifestName.endsWith('RECORD_AUDIO'),
      );
      expect(
        mic.why.contains('不上传'),
        isTrue,
        reason: '麦克风是唯一运行时申请的权限，必须说清只在本机算数字',
      );
      expect(
        mic.when.contains('开始测量'),
        isTrue,
        reason: '要说清什么时候才会申请，用户才知道自己按过什么',
      );
    });

    test('顶部那句的条数是现算的，不是写死的数字', () {
      final intro = permissionIntro();
      expect(intro.contains('${kPermissionNotes.length} 项'), isTrue);
      // 写死数字会随增删权限变成假话：这里盯住「没有第二个数字版本」。
      expect(kPermissionNotes.length, manifestPermissions().length);
    });
  });

  group('第三方 SDK 自证（「没有偷偷回传数据」这句话要能被核对）', () {
    /// 已知的统计 / 推送 / 广告 / 崩溃上报 SDK 关键词。
    ///
    /// 这份清单是**闸门**：以后谁引入其中一个，这条用例就会红，逼着人来改
    /// 「权限说明」里那句自证 —— 而不是让界面上继续挂着已经过期的「没有第三方 SDK」。
    const bannedSdkKeywords = <String>[
      'firebase',
      'umeng',
      'jpush',
      'getui',
      'bugly',
      'sentry',
      'admob',
      'talkingdata',
      'growingio',
      'sensors_analytics',
      'flutter_umeng',
      'push_plugin',
    ];

    test('pubspec 里确实没有任何统计/推送/广告 SDK', () {
      final pubspec = File('pubspec.yaml').readAsStringSync().toLowerCase();
      for (final keyword in bannedSdkKeywords) {
        expect(
          pubspec.contains(keyword),
          isFalse,
          reason: '检测到 $keyword：要么移除它，要么改掉「权限说明」里'
              '「未集成任何统计、推送、广告 SDK」这句自证',
        );
      }
    });

    test('AndroidManifest 里没有第三方推送/统计组件', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      for (final component in [
        'com.umeng',
        'cn.jpush',
        'com.igexin',
        'com.google.firebase',
        'com.google.android.gms.ads',
      ]) {
        expect(manifest.contains(component), isFalse);
      }
    });

    test('自证文案本身：既说了「没有」也说了「数据会去哪」', () {
      expect(kThirdPartySdkNote.contains('未集成任何统计、推送、广告 SDK'), isTrue);
      expect(
        kThirdPartySdkNote.contains('Sentry'),
        isTrue,
        reason: '点名几个，比一句空泛的「没有第三方 SDK」可信',
      );
      expect(
        kThirdPartySdkNote.contains('自己配置'),
        isTrue,
        reason: '必须说清数据只会发往本应用服务器或用户自己配置的服务',
      );
      // 不能说死「绝不外传任何数据」——云同步/OCR 是真的会传，只是由用户发起
      expect(kThirdPartySdkNote.contains('绝不'), isFalse);
    });

    test('权限说明页会把这块渲染出来', () {
      final page = File(
        'lib/features/about/presentation/app_permissions_page.dart',
      ).readAsStringSync();
      expect(page.contains('kThirdPartySdkNote'), isTrue);
      expect(page.contains("'第三方 SDK'"), isTrue);
    });
  });
}
