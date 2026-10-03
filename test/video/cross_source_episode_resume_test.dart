import 'dart:io';

import 'package:box/video/controller/video_detail_controller.dart';
import 'package:box/video/models/video_source.dart';
import 'package:box/video/models/vod_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 跨源续播：换了片源后地址必然不同，靠**剧集名**把用户带回同一集，并且
/// **只有认到同名那一集才带进度** —— 认不到就从头播，不许假装能续。
///
/// 真实需求来源：首页「继续使用」的原片源失效后，用户在别的源上找到同一部片，
/// 期望还是接着上次那集、那个位置看。
VodItem detailWith(List<String> episodeNames, {String lineName = '线路A'}) =>
    VodItem(
      vodId: 42,
      vodName: '欢迎来龙餐馆',
      vodPlayFrom: lineName,
      vodPlayUrl: episodeNames
          .map((n) => '$n\$https://new-cdn.example.com/${n.hashCode}.m3u8')
          .join('#'),
    );

VideoSource newSource() => const VideoSource(
  id: 'new-source',
  name: '🎬乙源',
  url: 'https://new.example.com/api.php/provide/vod',
  detailUrl: 'https://new.example.com',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final directory = await Directory.systemTemp.createTemp(
      'box_cross_src_test_',
    );
    Hive.init(directory.path);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  Future<VideoDetailController> boot({
    String? initialEpisodeUrl,
    String? initialEpisodeName,
    int initialPosition = 0,
    List<String> episodes = const ['第01集', '第02集', '第03集'],
  }) async {
    final controller = VideoDetailController(
      source: newSource(),
      vodId: 42,
      initialEpisodeUrl: initialEpisodeUrl,
      initialEpisodeName: initialEpisodeName,
      initialPosition: initialPosition,
      detailFetcher: () async => detailWith(episodes),
    );
    addTearDown(controller.dispose);
    // 等 loadDetail 的网络（这里是注入的 fetcher）走完
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return controller;
  }

  test('原片源地址对不上时，按剧集名选到同一集并带进度续播', () async {
    final controller = await boot(
      initialEpisodeUrl: 'https://old-source.example.com/ep3.m3u8',
      initialEpisodeName: '第03集',
      initialPosition: 90000,
    );

    expect(controller.isLoading, isFalse);
    expect(controller.currentEpisodeName, '第03集');
    expect(
      controller.getEffectiveInitialPosition(),
      90000,
      reason: '认到同名剧集才允许带进度，这是「继续使用」的核心诉求',
    );
    expect(controller.resumeMessage, contains('同名剧集'));
  });

  test('新源里没有同名剧集：正常选片，但不带进度（不假装能续）', () async {
    final controller = await boot(
      initialEpisodeUrl: 'https://old-source.example.com/ep9.m3u8',
      initialEpisodeName: '第09集',
      initialPosition: 90000,
    );

    expect(controller.currentEpisodeName, '第01集', reason: '认不到就按默认选片');
    expect(
      controller.getEffectiveInitialPosition(),
      0,
      reason: '集数对不上还硬 seek，就是放到别的集的时间点上',
    );
  });

  test('片源内续播（地址命中）行为不变', () async {
    // 先拿一个真实地址：注入的详情里第 2 集的地址
    final probe = await boot(episodes: const ['第01集', '第02集']);
    final url = probe.currentEpisodeUrl;

    final controller = await boot(
      initialEpisodeUrl: url,
      initialEpisodeName: '无关名字',
      initialPosition: 5000,
    );
    expect(controller.getEffectiveInitialPosition(), 5000);
    expect(controller.resumeMessage, contains('恢复到上次播放位置'));
  });

  test('剧集名归一化：第03集 与 第3集 是同一集', () async {
    final controller = await boot(
      initialEpisodeUrl: 'https://old-source.example.com/ep3.m3u8',
      initialEpisodeName: '第3集',
      initialPosition: 12000,
      episodes: const ['第01集', '第02集', '第03集'],
    );

    expect(controller.currentEpisodeName, '第03集');
    expect(controller.getEffectiveInitialPosition(), 12000);
  });

  test('用户手动切过集之后，不再套用历史进度', () async {
    final controller = await boot(
      initialEpisodeUrl: 'https://old-source.example.com/ep3.m3u8',
      initialEpisodeName: '第03集',
      initialPosition: 90000,
    );
    expect(controller.getEffectiveInitialPosition(), 90000);

    controller.selectEpisode(1);
    expect(
      controller.getEffectiveInitialPosition(),
      0,
      reason: '切集是用户的明确意图，不能又被拉回旧位置',
    );
  });
}
