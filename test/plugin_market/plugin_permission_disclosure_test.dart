import 'package:box/features/extensions/market/domain/plugin_market_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

/// FIX-08：权限只做**如实披露**——翻译成人话给用户看，不暗示沙箱。
/// 当前没有第三方代码在下游执行，没有可拦截的承载对象。
void main() {
  group('权限中文标签（单一事实源）', () {
    test('认识的 code 翻成中文，重复项只留一次', () {
      expect(
        permissionLabelsOf(['network', 'clipboard', 'network']),
        ['网络', '剪贴板'],
      );
      expect(permissionLabelsOf(['storage', 'camera']), ['存储', '相机']);
    });

    test('none 不展示（它表示"不申请"）', () {
      expect(permissionLabelsOf(['none']), isEmpty);
    });

    test('认不出的 code 原样保留，不静默吞掉', () {
      expect(permissionLabelsOf(['network', 'bluetooth_xyz']), ['网络', 'bluetooth_xyz']);
    });

    test('空列表与空白项安全', () {
      expect(permissionLabelsOf(const []), isEmpty);
      expect(permissionLabelsOf(['', '   ']), isEmpty);
    });
  });

  group('占位模板判据（FIX-09）', () {
    MarketPluginTemplate tpl({String action = 'toast', String payload = ''}) =>
        MarketPluginTemplate.tryFromJson(<String, dynamic>{
          'id': 'placeholder_probe',
          'title': '占位探针',
          'subtitle': '',
          'areaCode': 'recommend',
          'actionCode': action,
          'payload': payload,
        })!;

    test('toast + 无 payload = 占位（装了只会弹提示）', () {
      expect(tpl().isPlaceholder, isTrue);
    });

    test('toast 但有 payload 内容 = 不是占位', () {
      expect(tpl(payload: '有内容').isPlaceholder, isFalse);
    });

    test('非 toast 动作不是占位', () {
      expect(tpl(action: 'openVideoList').isPlaceholder, isFalse);
    });
  });
}
