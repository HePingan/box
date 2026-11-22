// 可配置字段（configSchema）的契约与插值。
//
// 这是「插件能被别人用」的关键：payload 写死时插件只对作者有用，
// 声明字段 + 用户填值后，同一个插件装上每人填自己的地址就能跑。
//
// 强制 default 是底线：没默认值就等于「装上还得改配置」，问题原样推给用户。

import 'dart:convert';

import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:flutter_test/flutter_test.dart';

HomeCustomPluginConfig _config(
  Map<String, dynamic> schema, {
  Map<String, String> user = const <String, String>{},
}) {
  return HomeCustomPluginConfig.fromJson(<String, dynamic>{
    'id': 'p1',
    'title': '我的服务器',
    'area': 'recommend',
    'actionCode': 'httpProbe',
    'payload': jsonEncode(<String, String>{
      'url': '{{url}}',
      'label': '{{label}}',
    }),
    'configSchema': schema,
    'userConfig': user,
  });
}

void main() {
  final good = <String, dynamic>{
    'url': <String, dynamic>{
      'label': '探测地址',
      'type': 'url',
      'default': 'https://box.hpa888.top',
    },
    'label': <String, dynamic>{
      'label': '按钮名称',
      'type': 'text',
      'default': '我的服务器',
    },
  };

  group('schema 契约', () {
    test('合法 schema 通过', () {
      expect(pluginConfigSchemaRejectReason(good), isNull);
      expect(pluginImportRejectReason(_config(good)), isNull);
    });

    test('空 schema 通过（老插件原样可用）', () {
      expect(pluginConfigSchemaRejectReason(const {}), isNull);
    });

    test('缺 default 被拒 —— 装上就能用是底线', () {
      final bad = <String, dynamic>{
        'url': <String, dynamic>{'label': '地址', 'type': 'url'},
      };
      expect(pluginConfigSchemaRejectReason(bad), contains('default'));
      expect(pluginImportRejectReason(_config(bad)), contains('default'));
    });

    test('字段名不合法被拒', () {
      for (final key in ['1url', 'url-x', 'url x', '']) {
        final bad = <String, dynamic>{
          key: <String, dynamic>{
            'label': '地址',
            'type': 'url',
            'default': 'https://box.hpa888.top',
          },
        };
        expect(pluginConfigSchemaRejectReason(bad), contains('字段名'), reason: key);
      }
    });

    test('type 只支持 text / url', () {
      final bad = <String, dynamic>{
        'url': <String, dynamic>{
          'label': '地址',
          'type': 'number',
          'default': 'https://box.hpa888.top',
        },
      };
      expect(pluginConfigSchemaRejectReason(bad), contains('text / url'));
    });

    test('缺 label 被拒（表单里不能出现裸 key）', () {
      final bad = <String, dynamic>{
        'url': <String, dynamic>{
          'type': 'url',
          'default': 'https://box.hpa888.top',
        },
      };
      expect(pluginConfigSchemaRejectReason(bad), contains('label'));
    });

    test('字段数上限 8', () {
      final bad = <String, dynamic>{
        for (var i = 0; i < 9; i++)
          'f$i': <String, dynamic>{
            'label': '字段$i',
            'type': 'text',
            'default': 'x',
          },
      };
      expect(pluginConfigSchemaRejectReason(bad), contains('8 个'));
    });
  });

  group('payload 插值', () {
    test('未填时用 default，插值后是可用 https', () {
      final resolved = resolvePluginPayload(_config(good));
      final decoded = jsonDecode(resolved) as Map<String, dynamic>;
      expect(decoded['url'], 'https://box.hpa888.top');
      expect(decoded['label'], '我的服务器');
      expect(resolved.contains('{{'), isFalse);
    });

    test('用户值覆盖 default', () {
      final cfg = _config(
        good,
        user: const <String, String>{
          'url': 'https://my-server.example.com',
          'label': '我的机器',
        },
      );
      final decoded = jsonDecode(resolvePluginPayload(cfg)) as Map<String, dynamic>;
      expect(decoded['url'], 'https://my-server.example.com');
      expect(decoded['label'], '我的机器');
    });

    test('用户填了 http 时导入校验仍按 default 放行，但执行时用用户值', () {
      // 导入期校验的是「装上就能用」的 default 形态；运行时如果用户改成 http，
      // openUrl 的确认框会显示完整 URL 让用户自己负责 —— 这是他本机的选择。
      final cfg = _config(
        good,
        user: const <String, String>{'url': 'http://intranet.local'},
      );
      expect(pluginImportRejectReason(cfg), isNull);
      expect(resolvePluginPayload(cfg), contains('http://intranet.local'));
    });
  });

  group('快照兼容', () {
    test('toJson 带 schema 与 userConfig，round-trip 不丢', () {
      final cfg = _config(
        good,
        user: const <String, String>{'url': 'https://my.example.com'},
      );
      final restored = HomeCustomPluginConfig.fromJson(cfg.toJson());
      expect(restored.configSchema, equals(good));
      expect(restored.userConfig['url'], 'https://my.example.com');
    });

    test('老快照没有字段时读到空表，不抛异常', () {
      final old = HomeCustomPluginConfig.fromJson(<String, dynamic>{
        'id': 'old',
        'title': '老插件',
        'actionCode': 'toast',
      });
      expect(old.configSchema, isEmpty);
      expect(old.userConfig, isEmpty);
    });

    test('脏字段类型不合法时丢弃，不让整个快照起不来', () {
      final dirty = HomeCustomPluginConfig.fromJson(<String, dynamic>{
        'id': 'dirty',
        'title': '脏数据',
        'actionCode': 'toast',
        'configSchema': 'not-a-map',
        'userConfig': <String, dynamic>{'a': 123},
      });
      expect(dirty.configSchema, isEmpty);
      expect(dirty.userConfig, isEmpty);
    });
  });
}
