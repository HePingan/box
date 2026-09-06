import 'package:flutter_test/flutter_test.dart';
import 'package:box/video/video_module.dart';
import 'package:box/video/controller/video_controller.dart';
import 'package:box/video/controller/video_catalog_repository.dart';
import 'package:box/video/models/video_source.dart';

/// 真实现象（用户 17:27 截图，iQOO）：冷启动直接进「内容 → 收藏库」，
/// 点影视收藏卡片弹「该视频的片源已失效或被移除」。
///
/// 但片源没有失效。`initSources()` 只在 video_sliver_home.dart:119
/// 和 video_source_tab.dart:133 被调用 —— 也就是只有进过影视首页或管理后台
/// 才会加载片源目录。收藏库是影视模块之外的入口，`VideoController._sources`
/// 起步是空 List，于是 findVideoSourceForFavorite 必然返回 null，
/// 被误报成「片源失效」。
///
/// 这里锁的契约：必须有一个「确保片源目录就绪」的公开入口，
/// 且它要幂等（已有片源就不重复拉网络），供收藏库这类模块外入口调用。
class _FakeCatalogRepository extends VideoCatalogRepository {
  _FakeCatalogRepository(this.sources);

  final List<VideoSource> sources;
  int loadSourcesCalls = 0;

  @override
  Future<List<VideoSource>> loadSources(String catalogUrl) async {
    loadSourcesCalls += 1;
    return sources;
  }
}

VideoSource _source(String id, String name) =>
    VideoSource(id: id, name: name, url: 'https://$id.example/api', detailUrl: '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(VideoModule.resetForTest);
  tearDown(VideoModule.resetForTest);

  group('缺陷：模块外入口没有加载片源就去匹配收藏', () {
    test('片源为空时 ensureCatalogReady 会真的把目录加载出来', () async {
      final repo = _FakeCatalogRepository([_source('s1', '量子资源')]);
      final controller = VideoController(repository: repo);

      expect(
        controller.sources,
        isEmpty,
        reason: '冷启动进收藏库时就是这个状态 —— 正是误报「片源失效」的根因',
      );

      await VideoModule.ensureCatalogReady(controller);

      expect(controller.sources, isNotEmpty, reason: '加载后才可能匹配到收藏对应的片源');
      expect(repo.loadSourcesCalls, 1);
    });

    test('已有片源时不重复走网络（幂等，收藏库每次点击都会调）', () async {
      final repo = _FakeCatalogRepository([_source('s1', '量子资源')]);
      final controller = VideoController(repository: repo);

      await VideoModule.ensureCatalogReady(controller);
      await VideoModule.ensureCatalogReady(controller);
      await VideoModule.ensureCatalogReady(controller);

      expect(
        repo.loadSourcesCalls,
        1,
        reason: '点一次收藏就重拉一次目录的话，弱网下每次点击都要等 8 秒探测',
      );
    });
  });
}
