import 'package:box/features/extensions/plugins/github_accel/github_accel_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// GitHub 加速链接转换的行为契约。
///
/// 真实场景（用户实测过的三种形态）：
///   1. release-assets.githubusercontent.com 签名长链 —— 浏览器右键复制到的就是这个，
///      带 sig/jwt/se 过期参数，几十分钟后必然 403，直接拿去代理没意义；
///      但 query 里的 filename 和路径里的 repo 数字 ID 能救回来。
///   2. github.com/.../releases/latest/download/xxx.apk —— 稳定形态，直接可代理。
///   3. 已经带 gh-proxy.com 前缀的链接 —— 不能二次包装。
void main() {
  const asset =
      'https://release-assets.githubusercontent.com/github-production-release-asset/1333629201/'
      'd1ad57b2-76b0-4fe5-8fb5-8f288d544cdd?sp=r&sv=2018-11-09&sr=b'
      '&rscd=attachment%3B+filename%3Ddsh-mobile-apk-v0.13.0-fx-1-arm64.apk'
      '&sig=qBuPX30xE8qVIh4wrnWXAbeiN9JXP9RDLV5h9IFFxZk%3D';

  group('识别签名长链', () {
    test('从 rscd 参数取出文件名', () {
      final r = GithubAccelLink.parse(asset);
      expect(r.fileName, 'dsh-mobile-apk-v0.13.0-fx-1-arm64.apk');
    });

    test('从路径取出仓库数字 ID', () {
      final r = GithubAccelLink.parse(asset);
      expect(r.repositoryId, '1333629201');
    });

    test('标记为需要联网解析仓库名', () {
      final r = GithubAccelLink.parse(asset);
      expect(r.kind, GithubLinkKind.signedAsset);
      expect(
        r.needsRepoLookup,
        isTrue,
        reason: '签名链里只有数字 ID，没有 owner/repo，必须查 API 才能拼稳定链接',
      );
      expect(r.canBuildDirectly, isFalse);
    });

    test('从 response-content-disposition 取文件名（另一种参数名）', () {
      const alt =
          'https://release-assets.githubusercontent.com/x/998877/abc'
          '?response-content-disposition=attachment%3B%20filename%3Dapp-v1.2.3.apk';
      final r = GithubAccelLink.parse(alt);
      expect(r.fileName, 'app-v1.2.3.apk');
      expect(r.repositoryId, '998877');
    });

    test('识别签名链已过期（se 参数在过去）', () {
      const expired =
          'https://release-assets.githubusercontent.com/x/1/a'
          '?se=2020-01-01T00%3A00%3A00Z&rscd=attachment%3B+filename%3Da.apk';
      final r = GithubAccelLink.parse(expired);
      expect(r.expired, isTrue, reason: '过期要在 UI 上明确告知，否则用户以为是加速失败');
    });

    test('未过期的签名链不误报过期', () {
      const fresh =
          'https://release-assets.githubusercontent.com/x/1/a'
          '?se=2099-01-01T00%3A00%3A00Z&rscd=attachment%3B+filename%3Da.apk';
      expect(GithubAccelLink.parse(fresh).expired, isFalse);
    });

    test('缺少 se 参数时不判过期', () {
      const noSe = 'https://release-assets.githubusercontent.com/x/1/a'
          '?rscd=attachment%3B+filename%3Da.apk';
      expect(GithubAccelLink.parse(noSe).expired, isFalse);
    });
  });

  group('标准 release 链接', () {
    const stable =
        'https://github.com/kelai141/dsh-mobile-apk/releases/latest/download/'
        'dsh-mobile-apk-v0.13.0-fx-1-arm64.apk';

    test('直接可加速，无需查 API', () {
      final r = GithubAccelLink.parse(stable);
      expect(r.kind, GithubLinkKind.releaseDownload);
      expect(r.canBuildDirectly, isTrue);
      expect(r.needsRepoLookup, isFalse);
      expect(r.owner, 'kelai141');
      expect(r.repo, 'dsh-mobile-apk');
      expect(r.fileName, 'dsh-mobile-apk-v0.13.0-fx-1-arm64.apk');
    });

    test('加速链接是前缀式拼接，保留完整原始 URL', () {
      final r = GithubAccelLink.parse(stable);
      expect(r.accelUrl, 'https://gh-proxy.com/$stable');
    });

    test('带 tag 的 release 链接同样支持', () {
      const tagged =
          'https://github.com/o/r/releases/download/v1.0.0/app-arm64.apk';
      final r = GithubAccelLink.parse(tagged);
      expect(r.canBuildDirectly, isTrue);
      expect(r.fileName, 'app-arm64.apk');
      expect(r.accelUrl, 'https://gh-proxy.com/$tagged');
    });

    test('raw.githubusercontent.com 也可加速', () {
      const raw =
          'https://raw.githubusercontent.com/o/r/main/README.md';
      final r = GithubAccelLink.parse(raw);
      expect(r.kind, GithubLinkKind.rawFile);
      expect(r.canBuildDirectly, isTrue);
      expect(r.accelUrl, 'https://gh-proxy.com/$raw');
    });

    test('codeload 归档链接可加速', () {
      const zip = 'https://codeload.github.com/o/r/zip/refs/heads/main';
      final r = GithubAccelLink.parse(zip);
      expect(r.canBuildDirectly, isTrue);
    });
  });

  group('已加速链接不二次包装', () {
    test('gh-proxy 前缀链接原样返回', () {
      const already =
          'https://gh-proxy.com/https://github.com/o/r/releases/latest/download/a.apk';
      final r = GithubAccelLink.parse(already);
      expect(r.kind, GithubLinkKind.alreadyAccelerated);
      expect(
        r.accelUrl,
        already,
        reason: '套两层前缀会 404，这是最容易踩的坑',
      );
    });

    test('识别其他常见镜像前缀', () {
      const other = 'https://ghproxy.net/https://github.com/o/r/raw/main/a.bin';
      expect(
        GithubAccelLink.parse(other).kind,
        GithubLinkKind.alreadyAccelerated,
      );
    });
  });

  group('拒绝无关输入', () {
    test('非 GitHub 域名', () {
      final r = GithubAccelLink.parse('https://example.com/a.apk');
      expect(r.kind, GithubLinkKind.unsupported);
      expect(r.accelUrl, isNull);
    });

    test('空串', () {
      expect(GithubAccelLink.parse('').kind, GithubLinkKind.unsupported);
    });

    test('纯空白', () {
      expect(GithubAccelLink.parse('   \n ').kind, GithubLinkKind.unsupported);
    });

    test('不是 URL 的乱字符', () {
      expect(
        GithubAccelLink.parse('随便一段中文').kind,
        GithubLinkKind.unsupported,
      );
    });

    test('缺少协议头时自动补 https', () {
      final r = GithubAccelLink.parse(
        'github.com/o/r/releases/latest/download/a.apk',
      );
      expect(
        r.canBuildDirectly,
        isTrue,
        reason: '用户从聊天里复制常丢掉 https://，不该因此失败',
      );
      expect(r.accelUrl, startsWith('https://gh-proxy.com/https://github.com/'));
    });

    test('首尾空白与包裹的尖括号被清掉', () {
      final r = GithubAccelLink.parse(
        '  <https://github.com/o/r/releases/latest/download/a.apk>  ',
      );
      expect(r.canBuildDirectly, isTrue);
      expect(r.accelUrl, isNot(contains('<')));
    });

    test('github.com 上的非文件页面（仓库首页）不算可下载', () {
      final r = GithubAccelLink.parse('https://github.com/o/r');
      expect(r.canBuildDirectly, isFalse);
      expect(r.kind, GithubLinkKind.unsupported);
    });
  });

  group('按仓库名重建稳定链接', () {
    test('用查到的 owner/repo + 文件名拼出 latest/download', () {
      final r = GithubAccelLink.parse(asset);
      final rebuilt = r.rebuildWithRepo('kelai141/dsh-mobile-apk');

      expect(
        rebuilt.stableUrl,
        'https://github.com/kelai141/dsh-mobile-apk/releases/latest/download/'
        'dsh-mobile-apk-v0.13.0-fx-1-arm64.apk',
      );
      expect(rebuilt.accelUrl, 'https://gh-proxy.com/${rebuilt.stableUrl}');
      expect(rebuilt.canBuildDirectly, isTrue);
    });

    test('仓库名非法时保持不可用，不拼出坏链接', () {
      final r = GithubAccelLink.parse(asset);
      for (final bad in ['', 'noslash', '/leading', 'trailing/', 'a/b/c']) {
        expect(
          r.rebuildWithRepo(bad).canBuildDirectly,
          isFalse,
          reason: '「$bad」不是合法 owner/repo，不能拼链接',
        );
      }
    });

    test('文件名缺失时无法重建', () {
      const noName =
          'https://release-assets.githubusercontent.com/x/12345/abc?sp=r';
      final r = GithubAccelLink.parse(noName);
      expect(r.fileName, isEmpty);
      expect(r.rebuildWithRepo('o/r').canBuildDirectly, isFalse);
    });
  });

  group('镜像站可切换', () {
    test('可指定其他镜像前缀', () {
      const stable =
          'https://github.com/o/r/releases/latest/download/a.apk';
      final r = GithubAccelLink.parse(stable, mirror: 'https://ghfast.top');
      expect(r.accelUrl, 'https://ghfast.top/$stable');
    });

    test('镜像地址末尾斜杠不产生双斜杠', () {
      const stable =
          'https://github.com/o/r/releases/latest/download/a.apk';
      final r = GithubAccelLink.parse(stable, mirror: 'https://gh-proxy.com/');
      expect(r.accelUrl, 'https://gh-proxy.com/$stable');
      expect(r.accelUrl, isNot(contains('.com//')));
    });

    test('内置镜像列表非空且都是 https', () {
      expect(GithubAccelLink.mirrors, isNotEmpty);
      for (final m in GithubAccelLink.mirrors) {
        expect(m.url, startsWith('https://'));
        expect(m.label, isNotEmpty);
      }
    });
  });

  group('API 查询地址', () {
    test('按数字 ID 拼 repositories 接口，直连优先、镜像回退', () {
      final r = GithubAccelLink.parse(asset);
      // 实测直连 api.github.com 是 200，镜像会间歇性 403 限流，
      // 所以先试直连，再回退 gh-proxy。
      expect(
        r.repoLookupUrl,
        'https://api.github.com/repositories/1333629201',
      );
      expect(
        r.repoLookupUrls,
        containsAll([
          'https://api.github.com/repositories/1333629201',
          'https://gh-proxy.com/https://api.github.com/repositories/1333629201',
        ]),
      );
    });

    test('无 ID 时没有查询地址', () {
      final r = GithubAccelLink.parse(
        'https://github.com/o/r/releases/latest/download/a.apk',
      );
      expect(r.repoLookupUrl, isNull);
    });
  });
}
