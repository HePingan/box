// 工具页「我的收藏」自定义网址：模型 / 持久化 / 分享 / 备份覆盖。
//
// 需求背景：工具页大部分条目就是直接访问对应网站，所以用户应该能自己添加
// 好用的网站收藏起来，并且能作为个人数据导出、分享给朋友。
//
// 安全前提：URL 直接喂给 WebView，所以 javascript: / data: / file: 这类
// scheme 必须在入口就拦掉，不能等到 WebView 里再说。
library;

import 'dart:convert';

import 'package:box/features/backup/backup_pref_keys.dart';
import 'package:box/features/tools/domain/custom_site.dart';
import 'package:box/features/tools/domain/custom_site_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CustomSite 规范化与校验', () {
    test('缺少 scheme 时补 https，而不是判为无效', () {
      final site = CustomSite.tryCreate(title: '示例', url: 'example.com/tools');
      expect(site, isNotNull);
      expect(site!.url, 'https://example.com/tools');
    });

    test('http/https 都放行，大小写与首尾空格不影响', () {
      expect(
        CustomSite.tryCreate(title: 'a', url: '  HTTP://Example.com  ')?.url,
        'http://example.com',
      );
    });

    test('危险 scheme 一律拒绝（会被直接喂给 WebView）', () {
      for (final bad in [
        'javascript:alert(1)',
        'data:text/html;base64,PHNjcmlwdD4=',
        'file:///etc/passwd',
        'about:blank',
      ]) {
        expect(
          CustomSite.tryCreate(title: 'x', url: bad),
          isNull,
          reason: '$bad 必须在入口就被拦掉',
        );
      }
    });

    test('带 host 的危险 scheme 也必须拒绝（不能靠空 host 兜底）', () {
      // 变异测试暴露的盲区：上一条用例里的 javascript:alert(1) 其实是被
      // 「空 host」守卫挡下的，把 scheme 白名单整条删掉它照样绿。
      // 这些变体 host 非空，只有真正检查 scheme 才拦得住。
      for (final bad in [
        'javascript://evil.com/%0aalert(1)',
        'ftp://example.com/x',
        'ws://example.com',
        'intent://example.com#Intent;scheme=http;end',
        'content://com.android.providers/x',
      ]) {
        expect(
          CustomSite.tryCreate(title: 'x', url: bad),
          isNull,
          reason: '$bad 的 scheme 不在 http/https 白名单内，必须拒绝',
        );
      }
    });

    test('空 host / 空串无效', () {
      expect(CustomSite.tryCreate(title: 'x', url: ''), isNull);
      expect(CustomSite.tryCreate(title: 'x', url: '   '), isNull);
      expect(CustomSite.tryCreate(title: 'x', url: 'https://'), isNull);
    });

    test('标题留空时回落到 host，不出现无名条目', () {
      final site = CustomSite.tryCreate(
        title: '  ',
        url: 'https://photopea.com',
      );
      expect(site, isNotNull);
      expect(site!.title, 'photopea.com');
    });

    test('JSON 往返不丢字段', () {
      final site = CustomSite.tryCreate(title: '在线PS', url: 'photopea.com')!;
      final back = CustomSite.fromJson(site.toJson());
      expect(back, isNotNull);
      expect(back!.id, site.id);
      expect(back.title, site.title);
      expect(back.url, site.url);
      expect(back.createdAt, site.createdAt);
    });
  });

  group('CustomSiteStore 持久化', () {
    late Map<String, String> fakePrefs;

    setUp(() {
      fakePrefs = <String, String>{};
      CustomSiteStore.readRaw = () async => fakePrefs[CustomSiteStore.prefsKey];
      CustomSiteStore.writeRaw = (raw) async {
        fakePrefs[CustomSiteStore.prefsKey] = raw;
      };
    });

    tearDown(CustomSiteStore.resetHooksForTest);

    test('新增后能读回来', () async {
      final store = CustomSiteStore();
      final added = await store.add(title: '示例', url: 'example.com');
      expect(added, isNotNull);

      final all = await store.load();
      expect(all, hasLength(1));
      expect(all.single.url, 'https://example.com');
    });

    test('同一个 URL 不重复入库（重复添加视为更新标题）', () async {
      final store = CustomSiteStore();
      await store.add(title: '旧标题', url: 'example.com');
      await store.add(title: '新标题', url: 'https://example.com');

      final all = await store.load();
      expect(all, hasLength(1), reason: '同 URL 不该产生两条');
      expect(all.single.title, '新标题');
    });

    test('非法 URL 不入库', () async {
      final store = CustomSiteStore();
      expect(await store.add(title: 'x', url: 'javascript:alert(1)'), isNull);
      expect(await store.load(), isEmpty);
    });

    test('按 id 删除', () async {
      final store = CustomSiteStore();
      final a = await store.add(title: 'A', url: 'a.com');
      await store.add(title: 'B', url: 'b.com');

      await store.remove(a!.id);
      final all = await store.load();
      expect(all, hasLength(1));
      expect(all.single.title, 'B');
    });

    test('存储内容损坏时返回空列表而不是抛异常', () async {
      fakePrefs[CustomSiteStore.prefsKey] = '{not json at all';
      expect(await CustomSiteStore().load(), isEmpty);
    });

    test('最近添加的排在前面', () async {
      final store = CustomSiteStore();
      await store.add(title: 'A', url: 'a.com');
      await store.add(title: 'B', url: 'b.com');
      final all = await store.load();
      expect(all.first.title, 'B', reason: '新添加的应排在最前，方便立即看到');
    });
  });

  group('分享给朋友', () {
    test('导出 JSON 能被再导入，条目一致', () {
      final sites = [
        CustomSite.tryCreate(title: 'A', url: 'a.com')!,
        CustomSite.tryCreate(title: 'B', url: 'b.com')!,
      ];
      final raw = CustomSiteShare.encode(sites);
      final back = CustomSiteShare.decode(raw);
      expect(back.map((e) => e.url), ['https://a.com', 'https://b.com']);
    });

    test('导出内容是人可读的 JSON，带版本号（朋友那边好排查）', () {
      final raw = CustomSiteShare.encode([
        CustomSite.tryCreate(title: 'A', url: 'a.com')!,
      ]);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['version'], isNotNull);
      expect(decoded['sites'], isA<List>());
    });

    test('朋友发来的内容里混了坏条目时，跳过坏的、保留好的', () {
      final raw = jsonEncode({
        'version': 1,
        'sites': [
          {'title': '好的', 'url': 'https://good.com'},
          {'title': '坏的', 'url': 'javascript:alert(1)'},
          {'title': '缺 url'},
          'not even a map',
        ],
      });
      final back = CustomSiteShare.decode(raw);
      expect(back, hasLength(1));
      expect(back.single.url, 'https://good.com');
    });

    test('完全无法解析时返回空列表，不抛异常', () {
      expect(CustomSiteShare.decode('garbage'), isEmpty);
      expect(CustomSiteShare.decode(''), isEmpty);
    });

    test('单条裸对象也能导入（朋友只贴了一条）', () {
      final raw = jsonEncode({'title': 'A', 'url': 'a.com'});
      final back = CustomSiteShare.decode(raw);
      expect(back, hasLength(1));
      expect(back.single.url, 'https://a.com');
    });
  });

  group('B2 备份覆盖', () {
    test('自定义网址的存储键必须在备份范围内，否则重装即丢', () {
      expect(
        BackupPrefKeys.covers(CustomSiteStore.prefsKey),
        isTrue,
        reason: '用户自己攒的网址属于「自己攒出来的数据」，必须进备份',
      );
    });
  });
}
