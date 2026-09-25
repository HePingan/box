// 网络策略纯逻辑（287 P1）：解析与判定都不碰 dart:io/Flutter，所以直接跑。
import 'package:box/features/extensions/plugins/remote_storage/domain/network_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('网络类型解析', () {
    test('认识的四种类型', () {
      expect(networkKindFromName('wifi'), NetworkKind.wifi);
      expect(networkKindFromName('mobile'), NetworkKind.mobile);
      expect(networkKindFromName('ethernet'), NetworkKind.ethernet);
      expect(networkKindFromName('none'), NetworkKind.none);
    });

    test('大小写与空白不影响', () {
      expect(networkKindFromName(' Wi-Fi '.replaceAll('-', '')), NetworkKind.wifi);
      expect(networkKindFromName('MOBILE'), NetworkKind.mobile);
    });

    test('不认识/空/null 一律 other —— 绝不冒充成 wifi', () {
      expect(networkKindFromName('vpn'), NetworkKind.other);
      expect(networkKindFromName(''), NetworkKind.other);
      expect(networkKindFromName(null), NetworkKind.other);
    });

    test('枚举 ↔ 名字往返', () {
      for (final k in NetworkKind.values) {
        expect(networkKindFromName(networkKindName(k)), k);
      }
    });
  });

  group('策略解析', () {
    test('三档往返', () {
      for (final p in TransferNetworkPolicy.values) {
        expect(networkPolicyFromName(networkPolicyName(p)), p);
      }
    });

    test('坏值/缺值回默认「仅 Wi-Fi」（保守）', () {
      expect(networkPolicyFromName(null), TransferNetworkPolicy.wifiOnly);
      expect(networkPolicyFromName('whatever'), TransferNetworkPolicy.wifiOnly);
      expect(networkPolicyFromName(''), TransferNetworkPolicy.wifiOnly);
    });
  });

  group('是否允许直接开传', () {
    test('Wi-Fi 与有线网络：三档都允许', () {
      for (final p in TransferNetworkPolicy.values) {
        expect(networkAllowsTransfer(p, NetworkKind.wifi), isTrue);
        expect(networkAllowsTransfer(p, NetworkKind.ethernet), isTrue);
      }
    });

    test('移动网络：只有「不限网络」允许', () {
      expect(
        networkAllowsTransfer(TransferNetworkPolicy.wifiOnly, NetworkKind.mobile),
        isFalse,
      );
      expect(
        networkAllowsTransfer(
            TransferNetworkPolicy.askEachTime, NetworkKind.mobile),
        isFalse,
        reason: '「先询问」也不是自动放行 —— 等用户确认',
      );
      expect(
        networkAllowsTransfer(TransferNetworkPolicy.allowAll, NetworkKind.mobile),
        isTrue,
      );
    });

    test('未知网络（VPN 等）：按移动网络对待', () {
      expect(
        networkAllowsTransfer(TransferNetworkPolicy.wifiOnly, NetworkKind.other),
        isFalse,
      );
      expect(
        networkAllowsTransfer(TransferNetworkPolicy.allowAll, NetworkKind.other),
        isTrue,
      );
    });

    test('没网：连「不限网络」也不允许（别把任务标成在跑再失败）', () {
      for (final p in TransferNetworkPolicy.values) {
        expect(networkAllowsTransfer(p, NetworkKind.none), isFalse);
      }
    });
  });

  group('文案', () {
    test('等待文案区分"没网"与"策略拦下"', () {
      expect(
        networkWaitLabel(TransferNetworkPolicy.wifiOnly, NetworkKind.none),
        '等待网络',
      );
      expect(
        networkWaitLabel(TransferNetworkPolicy.wifiOnly, NetworkKind.mobile),
        '等待 Wi-Fi',
      );
      expect(
        networkWaitLabel(TransferNetworkPolicy.askEachTime, NetworkKind.mobile),
        contains('确认'),
      );
    });

    test('三档都有可读标签', () {
      for (final p in TransferNetworkPolicy.values) {
        expect(networkPolicyLabel(p), isNotEmpty);
      }
    });
  });
}
