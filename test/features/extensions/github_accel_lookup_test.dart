import 'package:box/features/extensions/plugins/github_accel/github_accel_link.dart';
import 'package:box/features/extensions/plugins/github_accel/github_accel_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 复现用例：粘贴 RikkaHub 的签名长链，报
/// 「查询仓库信息失败: DioException [bad response] ... status code of 403」。
///
/// 真实成因（已对线上逐个 curl 核实）：
/// 查 owner/repo 走的是 `<镜像>/https://api.github.com/repositories/<id>`，
/// 而 gh-proxy 用一个共享 GitHub 账号回源，该账号的 API 限额被打满，
/// 同一地址连打 6 次出现 403,403,403,200,403,403 —— 是间歇性限流，不是死路。
/// 老代码只查一次、只用当前选中的镜像，撞上 403 就整个失败。
///
/// 另外已验证：
///   - 直连 api.github.com 是 200（有网络的设备可直接走）
///   - ghfast.top / hk.gh-proxy.com 代理 api 一律 403 / 302，不可用
///   - 镜像不代理 release-assets 签名链（"Web page content is not allowed"），
///     所以绕不开这次查询
void main() {
  const repoJson = '{"id":1333629201,"full_name":"kelai141/dsh-mobile-apk"}';
  const rateLimited =
      '{"message":"API rate limit exceeded for user ID 10094017."}';

  // RikkaHub 那条的等价形态：路径里带 repo 数字 ID，query 里带真实文件名。
  const signed =
      'https://release-assets.githubusercontent.com/github-production-release-asset/'
      '1333629201/d1ad57b2-aaaa-bbbb-cccc-ddddeeeeffff'
      '?sp=r&sig=abc&se=2099-01-01T00%3A00%3A00Z'
      '&response-content-disposition=attachment%3B%20filename%3D'
      'RikkaHub-2.4.15-arm64-v8a.apk'
      '&response-content-type=application%2Fvnd.android.package-archive';

  group('仓库查询：多通道 + 重试', () {
    test('第一个通道 403 时自动换通道，最终转换成功', () async {
      final tried = <String>[];
      final svc = GithubAccelService(
        retryDelay: Duration.zero,
        fetch: (url) async {
          tried.add(url);
          // 模拟手机上的典型情况：直连 api.github.com 不通（被墙/超时），
          // 只有 gh-proxy 镜像那条能成。
          if (url.startsWith('https://gh-proxy.com/')) return repoJson;
          throw Exception('DioException [bad response]: status code of 403');
        },
      );

      final r = await svc.resolve(signed);

      expect(r.ok, isTrue, reason: '有一个通道能通就该成功，而不是报 403');
      expect(
        r.accelUrl,
        'https://gh-proxy.com/https://github.com/kelai141/dsh-mobile-apk'
        '/releases/latest/download/RikkaHub-2.4.15-arm64-v8a.apk',
      );
      expect(tried.length, greaterThan(1), reason: '第一个通道失败后必须再试别的');
    });

    test('同一通道间歇性 403：重试后拿到 200', () async {
      var n = 0;
      final svc = GithubAccelService(
        retryDelay: Duration.zero,
        fetch: (url) async {
          n++;
          // 复现线上观察到的 403,403,200 序列。
          if (n < 3) {
            throw Exception('DioException [bad response]: status code of 403');
          }
          return repoJson;
        },
      );

      final r = await svc.resolve(signed);

      expect(r.ok, isTrue);
      expect(n, greaterThanOrEqualTo(3), reason: '限流是间歇的，必须重试');
    });

    test('限流响应体是 200 但内容是 rate limit 提示时，也要继续换通道', () async {
      final svc = GithubAccelService(
        retryDelay: Duration.zero,
        fetch: (url) async {
          if (url.startsWith('https://api.github.com/')) return repoJson;
          return rateLimited; // HTTP 200 但没有 full_name
        },
      );

      final r = await svc.resolve(signed);
      expect(r.ok, isTrue, reason: '没有 full_name 的响应应视为失败并换通道');
      expect(r.link.owner, 'kelai141');
    });

    test('所有通道都失败时，报错要说清是镜像限流并给出可操作建议', () async {
      final svc = GithubAccelService(
        retryDelay: Duration.zero,
        fetch: (url) async {
          throw Exception('DioException [bad response]: status code of 403');
        },
      );

      final r = await svc.resolve(signed);

      expect(r.ok, isFalse);
      // 用户要能看懂下一步怎么办，而不是读 Dio 的英文堆栈。
      expect(r.message, contains('限流'));
      expect(
        r.message,
        contains('RikkaHub-2.4.15-arm64-v8a.apk'),
        reason: '应提示用文件名去 Release 页面复制稳定链接',
      );
      expect(
        r.message,
        isNot(contains('RequestOptions')),
        reason: '不该把 Dio 英文堆栈原样塞给用户',
      );
    });

    test('文件名已知时，报错里要附上可直接手填的稳定链接模板', () async {
      final svc = GithubAccelService(
        retryDelay: Duration.zero,
        fetch: (url) async => throw Exception('403'),
      );
      final r = await svc.resolve(signed);

      expect(r.ok, isFalse);
      expect(
        r.message,
        contains('/releases/latest/download/'),
        reason: '给出模板，用户补上 owner/repo 就能自己拼',
      );
    });
  });

  group('查询通道清单', () {
    test('包含直连与可用镜像，且直连优先（服务器/有梯子时最稳）', () {
      final link = GithubAccelLink.parse(signed);
      final urls = link.repoLookupUrls;

      expect(urls, isNotEmpty);
      expect(
        urls.first,
        'https://api.github.com/repositories/1333629201',
        reason: '直连实测 200，应当先试',
      );
      expect(
        urls.any((u) => u.startsWith('https://gh-proxy.com/')),
        isTrue,
        reason: 'gh-proxy 实测可用（间歇限流），保留作为回退',
      );
    });

    test('不含实测不可用的通道', () {
      final urls = GithubAccelLink.parse(signed).repoLookupUrls;
      // ghfast.top / hk.gh-proxy.com 代理 api.github.com 实测 403/302。
      expect(urls.any((u) => u.contains('ghfast.top')), isFalse);
      expect(urls.any((u) => u.contains('hk.gh-proxy.com')), isFalse);
    });

    test('非签名链不需要查询', () {
      final link = GithubAccelLink.parse(
        'https://github.com/a/b/releases/latest/download/c.apk',
      );
      expect(link.repoLookupUrls, isEmpty);
    });
  });
}
