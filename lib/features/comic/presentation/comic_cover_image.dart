// 漫画图片（封面 / 预览）统一入口：走**带请求头**的图片缓存，
// 下不来说明原因、点一下能重试。
//
// 为什么不能用 Flutter 自带的 `Image.network`：那条路一份请求头都不带，图床看客户端
// 特征（没有 UA 的请求会被直接丢掉），界面上只剩一个破图标 —— 用户只能说"封面加载不
// 出来"，而我这边连原因都拿不到（2026-09-29 用户报的就是这个）。
library;

import 'dart:io';

import 'package:box/features/comic/domain/comic_fetcher.dart';
import 'package:box/features/comic/domain/comic_image_cache.dart';
import 'package:flutter/material.dart';

/// 一张漫画图：带手机 UA 下载、落本地缓存；失败把**原因**写在图上，点一下重试。
class ComicCoverImage extends StatefulWidget {
  const ComicCoverImage({
    super.key,
    required this.url,
    this.cache,
    this.fit = BoxFit.cover,
    this.height,
    this.borderRadius,
  });

  final String url;

  /// 图片缓存（测试注入用）。生产省略即走"直连头"缓存：只带手机 UA，
  /// **不带设备令牌** —— 令牌只发给自己的中转，发给第三方图床就是泄露。
  final ComicImageCache? cache;

  final BoxFit fit;
  final double? height;
  final BorderRadius? borderRadius;

  @override
  State<ComicCoverImage> createState() => _ComicCoverImageState();
}

class _ComicCoverImageState extends State<ComicCoverImage> {
  late final ComicImageCache _cache =
      widget.cache ?? ComicImageCache(headerFor: (url) => comicDirectHeaders());

  late Future<File> _future;

  @override
  void initState() {
    super.initState();
    _future = _start();
  }

  /// 取图，并**当场**挂一个"吃掉错误"的监听。
  ///
  /// 为什么要多这一下：错误要等 FutureBuilder 建起来才有人接，中间那段空窗期会被
  /// 运行时当成"没人处理的异常"（widget 测试里直接判失败，真机上也是一条噪音日志）。
  /// 真正的错误还是通过返回的这个 Future 交给 FutureBuilder，界面上照旧显示原因。
  Future<File> _start() {
    final loading = _cache.fetch(widget.url);
    loading.then<void>((_) {}, onError: (Object _) {});
    return loading;
  }

  void _retry() {
    // 别写 `setState(() => _future = ...)`：箭头体返回的是 Future，
    // setState 会当场断言报错（要块体、返回 null）。
    final next = _start();
    setState(() {
      _future = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = FutureBuilder<File>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return GestureDetector(
            onTap: _retry,
            child: ColoredBox(
              color: const Color(0x11000000),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.broken_image_outlined, size: 28),
                      const SizedBox(height: 4),
                      Text(
                        '${snap.error}',
                        textAlign: TextAlign.center,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '点一下重试',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        return Image.file(
          snap.data!,
          fit: widget.fit,
          height: widget.height,
          errorBuilder: (_, _, _) => const Center(
            child: Icon(Icons.broken_image_outlined, size: 28),
          ),
        );
      },
    );

    final radius = widget.borderRadius;
    if (radius == null) return image;
    return ClipRRect(borderRadius: radius, child: image);
  }
}
