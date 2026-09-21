import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/api_hub/application/public_api_registry.dart';
import 'package:box/features/tools/application/tool_catalog.dart';

/// A-1 接线：把「curl 实测可用」的免密钥接口接进工具页。
///
/// 这批接口的可用性证据来自 `tool/probe_60s.sh`（间隔 4s 各打 3 次）：
///   - 60s.viki.moe/v2 系列：60s / today_in_history / luck / bing /
///     baidu/realtime / exchange_rate / ip —— 全部 3/3
///   - open.iciba.com/dsapi —— 每日英语 3/3
///   - cx.shouji.360.cn/phonearea.php —— 手机归属地 3/3
///   - api.mymemory.translated.net —— 翻译 3/3
///
/// 反面证据（写进注释是为了不让后人重新接一遍死接口）：
///   - 今日诗词 jinrishici：返回 404，已下线；
///   - api.oick.cn/api/dutang：返回 `缺少apikey`，不再是免密钥接口；
///   - ip-api.com/json：3/3 失败（国内直连不可达）；
///   - 60s 的 chengyu / today：404。
///
/// 这些接口一律不得写进 kToolTargets，写进去等于给用户造假入口。
void main() {
  group('A-1 新接线工具的 registry 定义', () {
    test('每日英语 / 每日资讯 / 老黄历 / 必应壁纸 等已进入 registry', () {
      for (final id in [
        'daily_english',
        'news60s',
        'today_in_history',
        'luck',
        'bing_wallpaper',
        'baidu_hot',
        'exchange_rate',
        'ip_query',
        'phone_area',
        'translate',
      ]) {
        expect(
          PublicApiRegistry.tryById(id),
          isNotNull,
          reason: 'registry 缺少 $id，工具页接过去会被 byId 静默兜底成天气',
        );
      }
    });

    test('新工具 id 不重复，且都进了 all 列表', () {
      final ids = PublicApiRegistry.all.map((t) => t.id).toList();
      expect(
        ids.toSet().length,
        ids.length,
        reason:
            'registry 出现重复 id：${ids.where((i) => ids.where((x) => x == i).length > 1).toSet()}',
      );

      final allIds = PublicApiRegistry.all.map((t) => t.id).toSet();
      for (final id in ['daily_english', 'news60s', 'translate']) {
        expect(allIds, contains(id));
      }
    });
  });

  group('A-1 新工具在工具页有入口', () {
    test('每个新工具都至少被一个目录条目映射到', () {
      final mapped = kToolTargets.values
          .whereType<ApiHubToolTarget>()
          .map((t) => t.toolId)
          .whereType<String>()
          .toSet();

      final missing = [
        'daily_english',
        'news60s',
        'today_in_history',
        'luck',
        'bing_wallpaper',
        'baidu_hot',
        'exchange_rate',
        'phone_area',
        'translate',
      ].where((id) => !mapped.contains(id)).toList();

      expect(missing, isEmpty, reason: '这些新接口没有工具页入口：$missing');
    });

    test('映射表里不允许出现已被实测否定的接口', () {
      final src = File(
        'lib/features/tools/application/tool_catalog.dart',
      ).readAsStringSync();

      // 今日诗词已 404 下线 —— 它仍是 poetry 面板的 provider 名，
      // 但不能再有依赖 jinrishici 域名的新接线。
      expect(
        src.contains('api.oick.cn'),
        isFalse,
        reason: 'api.oick.cn 实测返回「缺少apikey」，不是免密钥接口',
      );
      expect(
        src.contains('ip-api.com'),
        isFalse,
        reason: 'ip-api.com 国内直连 3/3 失败',
      );
    });
  });

  group('A-1 目录条目分类正确', () {
    test('新增工具落在合理分类里，且分类数没崩', () {
      final categories = createDefaultToolCategories();

      expect(categories.length, greaterThanOrEqualTo(10));
      for (final c in categories) {
        expect(c.title, isNotEmpty);
        expect(c.tools, isNotEmpty);
        expect(c.icon, isA<IconData>());
      }
    });

    test('新增中文条目名唯一', () {
      final seen = <String>{};
      final dup = <String>[];
      for (final c in createDefaultToolCategories()) {
        for (final t in c.tools) {
          if (!seen.add(t)) dup.add(t);
        }
      }
      expect(dup, isEmpty, reason: '目录重名：$dup');
    });
  });
}
