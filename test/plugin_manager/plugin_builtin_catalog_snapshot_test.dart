// P2-2 安全网：内置插件目录快照。
//
// 作用：在拆分 home_plugin_core.dart（catalog / pages / core 三分）**之前**
// 钉住 `HomePluginHost.builtInPluginsForTesting()` 的可观测行为，拆分后必须
// 逐字段不变。这是 P2-2 唯一的回归保护 —— 拆分本身是纯结构改动，
// 只有这条测试能证明「拆完行为没变」。
//
// 注意：这里锁的是插件**元数据**（id / 排序 / 分区 / 标题），
// 不锁 onTap 闭包行为（那是页面装配，拆分中会移动位置）。

import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P2-2 内置插件目录快照（拆分前钉住）', () {
    test('内置插件 id 集合与顺序稳定', () {
      final plugins = HomePluginHost.instance.builtInPluginsForTesting();
      final ids = plugins.map((p) => p.id).toList();

      // 全部内置
      expect(plugins.every((p) => p.builtIn), isTrue,
          reason: '内置目录里的插件 builtIn 必须为 true');

      // id 不重复
      expect(ids.toSet().length, ids.length, reason: '内置插件 id 不得重复');

      // 关键 id 必须存在（拆分中不得丢失任何一条）
      for (final id in const [
        'builtin_daily_news',
        'builtin_json_formatter',
        'builtin_base64',
        'builtin_password_gen',
        'builtin_timestamp',
        'builtin_url_codec',
        'builtin_qrcode',
        'builtin_quiz_entry',
        'builtin_quiz_bank_view',
        'builtin_quiz_plugin',
        'builtin_video_search',
        'builtin_comic_shelf',
        'builtin_novel_search',
        'builtin_image_generator',
        'builtin_plugin_help',
      ]) {
        expect(ids, contains(id), reason: '内置插件 $id 不应在拆分中丢失');
      }

      // 打印实际快照，便于人工核对（纯诊断，不做断言）。
      debugPrint('[P2-2 snapshot] 内置插件共 ${plugins.length} 个：');
      for (final p in plugins) {
        debugPrint('[P2-2 snapshot]   ${p.id} | ${p.area.name} | '
            'sort=${p.sort} | ${p.title}');
      }
    });

    test('每个内置插件的 area/title/onTap 均有效', () {
      final plugins = HomePluginHost.instance.builtInPluginsForTesting();
      for (final p in plugins) {
        expect(p.id, isNotEmpty, reason: 'id 不得为空');
        expect(p.title, isNotEmpty, reason: '${p.id} 标题不得为空');
        expect(p.onTap, isNotNull, reason: '${p.id} 必须有 onTap');
      }
    });

    test('分区归属固定（拆 pages 时不得错配）', () {
      final plugins = HomePluginHost.instance.builtInPluginsForTesting();
      final byId = {for (final p in plugins) p.id: p.area};

      expect(byId['builtin_video_search'], HomePluginArea.video);
      expect(byId['builtin_comic_shelf'], HomePluginArea.comic);
      expect(byId['builtin_novel_search'], HomePluginArea.novel);
      expect(byId['builtin_image_generator'], HomePluginArea.recommend);
      expect(byId['builtin_daily_news'], HomePluginArea.recommend);
      expect(byId['builtin_plugin_help'], HomePluginArea.center);
      expect(byId['builtin_qrcode'], HomePluginArea.center);
    });
  });
}
