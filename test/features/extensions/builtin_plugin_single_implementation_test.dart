// 一个能力只有一份实现（2026-10-03）。
//
// 改前：JSON 格式化 / Base64 编解码 / 密码生成 / 时间戳转换 / URL 编解码 / 二维码生成
// 这 6 个能力，**工具页**走 `LocalToolPage`（整页）或 API Hub 面板（整页），
// **扩展页**的 6 个内置插件却各有一份自己的底部面板实现（`PluginToolbox`，约 750 行），
// 名字还不一样（「随机密码」vs「密码生成器」）。两套代码、两个入口、两处维护：
// 修了一边另一边还是老样子，用户也看不出差别。
//
// 现在只有一份实现：插件入口改跳工具侧那唯一的实现。
// 本文件钉住这件事，并钉住那份重复实现已经被删干净。
library;

import 'dart:io';

import 'package:box/features/api_hub/application/public_api_registry.dart';
import 'package:box/features/local_tools/presentation/local_tools_registry.dart';
import 'package:box/features/tools/application/tool_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

String _catalogSource() => File(
  'lib/features/extensions/core/builtin_plugin_catalog.dart',
).readAsStringSync();

/// 能力 → (扩展页插件 id, 工具页里的工具名, 本地工具 id 或 api hub 面板 id)
const _sharedCapabilities =
    <({String pluginId, String toolName, String localId, bool isLocal})>[
      (
        pluginId: 'builtin_json_formatter',
        toolName: 'JSON格式化',
        localId: 'json',
        isLocal: true,
      ),
      (
        pluginId: 'builtin_base64',
        toolName: 'Base64编解码',
        localId: 'base64',
        isLocal: true,
      ),
      (
        pluginId: 'builtin_password_gen',
        toolName: '随机密码',
        localId: 'password_gen',
        isLocal: true,
      ),
      (
        pluginId: 'builtin_timestamp',
        toolName: '时间戳转换',
        localId: 'timestamp',
        isLocal: true,
      ),
      (
        pluginId: 'builtin_url_codec',
        toolName: 'URL编码',
        localId: 'urlcodec',
        isLocal: true,
      ),
      (
        pluginId: 'builtin_qrcode',
        toolName: '二维码生成',
        localId: 'qr',
        isLocal: false,
      ),
    ];

void main() {
  group('工具页与扩展页共用同一份实现', () {
    test('工具页那边：这 6 个能力指向的还是同一个实现', () {
      for (final cap in _sharedCapabilities) {
        final target = kToolTargets[cap.toolName];
        expect(target, isNotNull, reason: '工具页少了「${cap.toolName}」这个入口');
        if (cap.isLocal) {
          expect(
            target,
            isA<LocalToolTarget>(),
            reason: '${cap.toolName} 应该是纯本地工具',
          );
          expect(
            (target! as LocalToolTarget).localId,
            cap.localId,
            reason: '${cap.toolName} 的实现 id 变了，插件的跳转要跟着改',
          );
          expect(
            kLocalTools.containsKey(cap.localId),
            isTrue,
            reason: '${cap.localId} 不在 kLocalTools 里 —— 跳过去是个空壳',
          );
        } else {
          expect(
            (target! as ApiHubToolTarget).toolId,
            cap.localId,
            reason: '${cap.toolName} 应该指向 API Hub 的 ${cap.localId} 面板',
          );
          expect(
            PublicApiRegistry.byId(cap.localId),
            isNotNull,
            reason: '${cap.localId} 面板不存在',
          );
        }
      }
    });

    test('扩展页那边：这 6 个插件的点击都跳工具侧，不再有自己的面板实现', () {
      final src = _catalogSource();
      for (final cap in _sharedCapabilities) {
        final block = _pluginBlock(src, cap.pluginId);
        expect(block, isNotNull, reason: '找不到插件 ${cap.pluginId}');
        final expected = cap.isLocal
            ? "LocalToolPage(localId: '${cap.localId}')"
            : "ApiHubPage(initialTool: '${cap.localId}')";
        expect(
          block!.contains(expected),
          isTrue,
          reason: '${cap.pluginId} 应该跳 $expected（唯一的实现）',
        );
        expect(
          block.contains('PluginToolbox'),
          isFalse,
          reason: '${cap.pluginId} 又在用那份重复实现了',
        );
      }
    });

    test('那份重复实现（PluginToolbox）已经删干净，全仓零引用', () {
      expect(
        File(
          'lib/features/extensions/plugins/plugin_toolbox.dart',
        ).existsSync(),
        isFalse,
        reason: '零引用的第二份实现不该留在仓库里',
      );

      // 扫源码前先把 `//` 注释去掉：本文件自己就在讲 PluginToolbox 这件事，
      // 不去注释会把自己扫出来（假红）。
      String stripComments(String src) => src
          .split('\n')
          .map((line) {
            final idx = line.indexOf('//');
            return idx == -1 ? line : line.substring(0, idx);
          })
          .join('\n');

      final hits = <String>[];
      for (final dir in ['lib', 'test']) {
        for (final entity in Directory(dir).listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          // 跳过本文件：下面这行断言里就有 'PluginToolbox' 这个字面量。
          if (entity.path.endsWith(
            'builtin_plugin_single_implementation_test.dart',
          )) {
            continue;
          }
          if (stripComments(
            entity.readAsStringSync(),
          ).contains('PluginToolbox')) {
            hits.add(entity.path);
          }
        }
      }
      expect(hits, isEmpty, reason: '还有文件引用 PluginToolbox：$hits');
    });
  });
}

/// 取出某个插件在目录里的那一段源码（从它的 id 到下一个 HomePlugin 之前）。
String? _pluginBlock(String src, String pluginId) {
  final marker = "id: '$pluginId',";
  final start = src.indexOf(marker);
  if (start < 0) return null;
  final next = src.indexOf('HomePlugin(', start);
  return next < 0 ? src.substring(start) : src.substring(start, next);
}
