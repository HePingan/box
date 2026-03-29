// 文件路径: lib/video/video_module.dart
// 版本: 支持 TVBox 接口解析的完整版本

import '../novel/core/cache_store.dart';
import 'core/tvbox_video_source.dart'; // 1. 导入 TVBox 专用解析类
import 'core/video_repository.dart';
import 'core/video_source.dart';
import 'core/models.dart';

class VideoModule {
  static VideoRepository? _repository;

  /// 获取存储库实例。如果未配置，将返回一个抛出错误的状态。
  static VideoRepository get repository {
    _repository ??= VideoRepository(
      source: const _UnconfiguredVideoSource(),
      cache: CacheStore(namespace: 'video_module'),
    );
    return _repository!;
  }

  /// 检查模块是否已成功配置真实数据源
  static bool get isConfigured =>
      _repository != null && _repository!.source is! _UnconfiguredVideoSource;

  /// 通用配置方法：允许手动注入任何实现了 VideoSource 接口的源
  static void configure({
    required VideoSource source,
    CacheStore? cache,
  }) {
    _repository = VideoRepository(
      source: source,
      cache: cache ?? CacheStore(namespace: 'video_module'),
    );
  }

  /// 【核心配置】使用国内主流 TVBox 聚合接口
  /// 您可以在这里修改 configUrl 为任何有效的 TVBox JSON 接口地址
  static void configurePublicVideoSource({CacheStore? cache}) {
    configure(
      source: TvBoxVideoSource(
        // 这里默认使用饭太硬的源，也可以换成：http://肥猫.com/
        configUrl: 'http://饭太硬.com/tv/', 
      ),
      cache: cache,
    );
  }

  /// 测试或重置时使用
  static void resetForTest() {
    _repository = null;
  }
}

/// 内部保护类：当开发者忘记调用配置方法时，给予友好的报错提示
class _UnconfiguredVideoSource implements VideoSource {
  const _UnconfiguredVideoSource();

  StateError _err() => StateError(
        'VideoModule 未配置。请先在 main.dart 或初始化位置调用：\n'
        'VideoModule.configurePublicVideoSource();',
      );

  @override
  String get sourceName => 'unconfigured';

  @override
  List<VideoCategory> get categories => const [];

  @override
  Future<List<VideoItem>> searchVideos(String keyword, {int page = 1}) {
    return Future.error(_err());
  }

  @override
  Future<List<VideoItem>> fetchByPath(String path, {int page = 1}) {
    return Future.error(_err());
  }

  @override
  Future<VideoDetail> fetchDetail({
    required String videoId,
    String? detailUrl,
  }) {
    return Future.error(_err());
  }
}