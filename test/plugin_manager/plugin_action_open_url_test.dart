// openUrl / httpProbe 的安全边界与导入校验。
//
// 这两个动作会让 App 真的对外发请求、真的跳出 App —— 校验漏一处，
// 用户装完点一下就是「网址无效」，或者被带去一个陌生域名。
//
// 单一事实源：App 端 _httpsUrlFromRawPayload、服务端 pluginPayloadHttpsUrl、
// 投稿入口三处同口径（只认 https + 有主机名）。这里锁 App 侧这一份。

import 'package:box/features/extensions/core/external_link_bridge.dart';
import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:flutter_test/flutter_test.dart';

HomeCustomPluginConfig _pluginWith(String action, String payload) =>
    HomeCustomPluginConfig.fromJson({
      'id': 'p-$action',
      'title': '测试插件',
      'area': 'recommend',
      'actionCode': action,
      'payload': payload,
    });

void main() {
  group('ExternalLinkBridge.isOpenable', () {
    test('https 放行', () {
      expect(ExternalLinkBridge.isOpenable('https://example.com/a?b=1'), isTrue);
    });

    test('http 明文拒绝（插件不能静默降级到明文）', () {
      expect(ExternalLinkBridge.isOpenable('http://example.com'), isFalse);
    });

    test('危险 scheme 一律拒绝', () {
      for (final url in [
        'javascript:alert(1)',
        'intent://scan/#Intent;scheme=zxing;end',
        'tel:10086',
        'sms:10086',
        'file:///etc/passwd',
      ]) {
        expect(ExternalLinkBridge.isOpenable(url), isFalse, reason: url);
      }
    });

    test('没有主机名的拒绝', () {
      expect(ExternalLinkBridge.isOpenable('https://'), isFalse);
      expect(ExternalLinkBridge.isOpenable('https:///path'), isFalse);
    });
  });

  group('导入校验：openUrl / httpProbe 需要 https 网址', () {
    test('openUrl 带 {"url"} 通过', () {
      expect(
        pluginImportRejectReason(_pluginWith('openUrl', '{"url":"https://example.com"}')),
        isNull,
      );
    });

    test('openUrl 裸 https 也通过', () {
      expect(
        pluginImportRejectReason(_pluginWith('openUrl', 'https://example.com')),
        isNull,
      );
    });

    test('openUrl 空 payload 被拒', () {
      expect(
        pluginImportRejectReason(_pluginWith('openUrl', '')),
        contains('https'),
      );
    });

    test('openUrl 用 http 被拒', () {
      expect(
        pluginImportRejectReason(_pluginWith('openUrl', '{"url":"http://example.com"}')),
        contains('https'),
      );
    });

    test('openUrl payload 是坏 JSON 被拒', () {
      expect(
        pluginImportRejectReason(_pluginWith('openUrl', '{"url":')),
        contains('https'),
      );
    });

    test('httpProbe 带 url + label 通过', () {
      expect(
        pluginImportRejectReason(
          _pluginWith(
            'httpProbe',
            '{"url":"https://box.hpa888.top","label":"我的服务器"}',
          ),
        ),
        isNull,
      );
    });

    test('httpProbe 只有 label 没 url 被拒', () {
      expect(
        pluginImportRejectReason(_pluginWith('httpProbe', '{"label":"我的服务器"}')),
        contains('https'),
      );
    });

    test('未知动作仍被拒（新动作不是白名单漏洞）', () {
      expect(
        pluginImportRejectReason(
          _pluginWith('openSomethingElse', 'https://example.com'),
        ),
        contains('未知动作'),
      );
    });
  });

  group('投稿页动作下拉', () {
    test('只保留通用动作：navigate / toast / openUrl / httpProbe', () {
      expect(
        HomePluginActionType.displayOrder.map((a) => a.name).toList(),
        <String>['navigate', 'toast', 'openUrl', 'httpProbe'],
      );
    });

    test('旧的 openXxx 仍在枚举里 —— 已装插件继续可用', () {
      final names = HomePluginActionType.values.map((a) => a.name).toList();
      expect(names, contains('openMusic'));
      expect(names, contains('openWallpaperGallery'));
      expect(names, contains('openQuickNote'));
    });

    test('每个动作都有非空中文标签（下拉里不出现英文 key）', () {
      for (final action in HomePluginActionType.values) {
        expect(action.label.trim(), isNotEmpty, reason: action.name);
      }
    });
  });
}
