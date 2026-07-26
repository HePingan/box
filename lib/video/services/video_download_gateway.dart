import 'dart:async';

import 'package:flutter/services.dart';

import '../models/video_download_task.dart';

abstract interface class VideoDownloadGateway {
  Future<void> enqueue(VideoDownloadTask task);
  Future<void> pause(String id);
  Future<void> resume(String id);
  Future<void> cancel(String id);
  Future<void> remove(String id);
  Future<List<Map<String, dynamic>>> snapshots();
}

class MethodChannelVideoDownloadGateway implements VideoDownloadGateway {
  MethodChannelVideoDownloadGateway({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'com.example.box/video_downloads';
  final MethodChannel _channel;

  @override
  Future<void> enqueue(VideoDownloadTask task) async {
    final map = <String, dynamic>{
      'id': task.id,
      'media_url': task.mediaUrl,
      'episode_name': task.episodeName,
      'source_name': task.sourceName,
      'vod_id': task.vodId,
      'vod_name': task.vodName,
      'vod_pic': task.vodPic,
      'source_id': task.sourceId,
      'referer': task.referer,
      'created_at': task.createdAt.toIso8601String(),
    };
    await _channel
        .invokeMethod<void>('enqueue', map)
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('Native enqueue 超时'),
        );
  }

  @override
  Future<void> pause(String id) =>
      _channel.invokeMethod<void>('pause', {'id': id});

  @override
  Future<void> resume(String id) =>
      _channel.invokeMethod<void>('resume', {'id': id});

  @override
  Future<void> cancel(String id) =>
      _channel.invokeMethod<void>('cancel', {'id': id});

  @override
  Future<void> remove(String id) =>
      _channel.invokeMethod<void>('remove', {'id': id});

  @override
  Future<List<Map<String, dynamic>>> snapshots() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('snapshots') ?? [];
    return raw.whereType<Map>().map((item) {
      return Map<String, dynamic>.from(
        item.map((k, v) => MapEntry(k.toString(), v)),
      );
    }).toList();
  }
}
