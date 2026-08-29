import 'package:box/features/extensions/plugins/github_accel/github_accel_link.dart';
import 'package:box/features/extensions/plugins/github_accel/github_accel_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const signed =
      'https://release-assets.githubusercontent.com/github-production-release-asset/1333629201/'
      'uuid?se=2020-01-01T00%3A00%3A00Z'
      '&rscd=attachment%3B+filename%3Ddsh-mobile-apk-v0.13.0-fx-1-arm64.apk';

  const stable =
      'https://github.com/kelai141/dsh-mobile-apk/releases/latest/download/'
      'dsh-mobile-apk-v0.13.0-fx-1-arm64.apk';

  // 真实 API 返回体的关键片段（已用 curl 核对过字段名）
  const apiBody = '{"id":1333629201,"name":"dsh-mobile-apk",'
      '"full_name":"kelai141/dsh-mobile-apk","private":false}';

  group('稳定链接：不联网', () {
    test('release 链接直接转换，不发请求', () async {
      var calls = 0;
      final svc = GithubAccelService(
        fetch: (_) async {
          calls++;
          return apiBody;
        },
      );

      final r = await svc.resolve(stable);

      expect(r.ok, isTrue);
      expect(r.accelUrl, 'https://gh-proxy.com/$stable');
      expect(calls, 0, reason: '稳定链接不该浪费一次网络请求');
    });

    test('raw 链接直接转换', () async {
      final svc = GithubAccelService();
      final r = await svc.resolve(
        'https://raw.githubusercontent.com/o/r/main/a.txt',
      );
      expect(r.ok, isTrue);
      expect(r.accelUrl, contains('gh-proxy.com/https://raw.'));
    });
  });

  group('签名链：查仓库后重建', () {
    test('查到 full_name 后拼出稳定链接与加速链接', () async {
      final svc = GithubAccelService(fetch: (_) async => apiBody);
      final r = await svc.resolve(signed);

      expect(r.ok, isTrue);
      expect(r.stableUrl, stable);
      expect(r.accelUrl, 'https://gh-proxy.com/$stable');
    });

    test('先直连 api，失败后自动回退镜像通道', () async {
      final requested = <String>[];
      final svc = GithubAccelService(
        retryDelay: Duration.zero,
        fetch: (url) async {
          requested.add(url);
          // 直连不通时（手机常见），必须还能走镜像成功。
          if (url.startsWith('https://api.github.com/')) {
            throw Exception('连接超时');
          }
          return apiBody;
        },
      );
      final r = await svc.resolve(signed);

      expect(r.ok, isTrue);
      expect(requested.first, 'https://api.github.com/repositories/1333629201');
      expect(
        requested,
        contains(
          'https://gh-proxy.com/https://api.github.com/repositories/1333629201',
        ),
      );
    });

    test('过期签名链会在提示里说明已重建', () async {
      final svc = GithubAccelService(fetch: (_) async => apiBody);
      final r = await svc.resolve(signed);
      expect(r.message, contains('过期'));
      expect(r.ok, isTrue, reason: '过期不该阻断转换，重建后照样能下');
    });

    test('返回体不是 JSON 时用正则兜底', () async {
      final svc = GithubAccelService(
        fetch: (_) async => '<html>x "full_name": "kelai141/dsh-mobile-apk" y',
      );
      final r = await svc.resolve(signed);
      expect(r.ok, isTrue, reason: '镜像回 HTML 包裹时也要能救出仓库名');
      expect(r.stableUrl, stable);
    });

    test('所有通道都缺 full_name 时失败，并给出限流说明', () async {
      final svc = GithubAccelService(
        retryDelay: Duration.zero,
        fetch: (_) async => '{"id":1}',
      );
      final r = await svc.resolve(signed);
      expect(r.ok, isFalse);
      // 限流响应常是 200 + {"message":"API rate limit exceeded"}，
      // 对用户讲「限流 + 怎么办」比讲「缺 full_name」有用。
      expect(r.message, contains('限流'));
      expect(r.message, contains('/releases/latest/download/'));
    });

    test('网络异常时不抛，返回可操作的失败提示', () async {
      final svc = GithubAccelService(
        retryDelay: Duration.zero,
        fetch: (_) async => throw Exception('连接超时'),
      );
      final r = await svc.resolve(signed);
      expect(r.ok, isFalse);
      expect(r.message, contains('查不到这个仓库的名字'));
      // 不把 Dio/Exception 的英文堆栈原样丢给用户。
      expect(r.message, isNot(contains('Exception')));
    });

    test('无 fetch 注入时给出可操作提示', () async {
      final svc = GithubAccelService();
      final r = await svc.resolve(signed);
      expect(r.ok, isFalse);
      expect(r.message, contains('联网'));
    });

    test('签名链缺文件名时提示改用 releases 地址', () async {
      final svc = GithubAccelService(fetch: (_) async => apiBody);
      final r = await svc.resolve(
        'https://release-assets.githubusercontent.com/x/1333629201/uuid?sp=r',
      );
      expect(r.ok, isFalse);
      expect(r.message, contains('releases'));
    });

    test('查到的仓库名非法时不产出坏链接', () async {
      final svc = GithubAccelService(
        fetch: (_) async => '{"full_name":"a/b/c"}',
      );
      final r = await svc.resolve(signed);
      expect(r.ok, isFalse);
      expect(r.accelUrl, isNull);
    });
  });

  group('边界输入', () {
    test('已加速链接提示不要二次包装', () async {
      final svc = GithubAccelService();
      final r = await svc.resolve('https://gh-proxy.com/$stable');
      expect(r.ok, isTrue);
      expect(r.accelUrl, 'https://gh-proxy.com/$stable');
      expect(r.message, contains('已经'));
    });

    test('非 GitHub 链接给出支持范围说明', () async {
      final svc = GithubAccelService();
      final r = await svc.resolve('https://example.com/a.apk');
      expect(r.ok, isFalse);
      expect(r.message, contains('GitHub'));
    });

    test('空输入不崩', () async {
      final svc = GithubAccelService();
      final r = await svc.resolve('');
      expect(r.ok, isFalse);
      expect(r.accelUrl, isNull);
    });
  });

  group('镜像切换', () {
    test('选了 ghfast 时下载走 ghfast，但查询不用它（实测不支持 api 子域）', () async {
      final requested = <String>[];
      final svc = GithubAccelService(
        mirror: 'https://ghfast.top',
        retryDelay: Duration.zero,
        fetch: (url) async {
          requested.add(url);
          return apiBody;
        },
      );
      final r = await svc.resolve(signed);

      // ghfast.top 代理 api.github.com 实测回 403 "Invalid input."，
      // 放进查询通道只会白等，所以排除；但下载前缀仍尊重用户选择。
      expect(requested.any((u) => u.contains('ghfast.top')), isFalse);
      expect(r.accelUrl, 'https://ghfast.top/$stable');
    });

    test('镜像列表里每个都能产出可用前缀', () async {
      for (final m in GithubAccelLink.mirrors) {
        final svc = GithubAccelService(mirror: m.url);
        final r = await svc.resolve(stable);
        expect(r.ok, isTrue);
        expect(r.accelUrl, '${m.url}/$stable');
      }
    });
  });
}
