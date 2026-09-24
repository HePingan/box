// 播放中继：本机 127.0.0.1 回环 HTTP 服务。
//
// 为什么需要：原生播放器（ExoPlayer）受 Android 网络安全配置约束——
// 明文 http 与自签名证书站点无法直连；Dart 侧（dio）不受该约束。
// 方案：插件在回环端口起一个极小的转发服务，播放器连 http://127.0.0.1:port/rs/<token>，
// 中继带上 Basic 认证去远端取流并逐块转发（Range 透传，支持拖动进度）。
// 拍板 7「直连播」的落地形态；拍板 5 已在网络安全配置中对回环显式放行。
//
// 断线回收（探针实证，勿改回 await for）：
// dart:io 不会向服务端上报「客户端单方断开」——连接销毁后 response.add/flush
// 静默成功、response.done 不报错，写失败路径不存在。因此转发循环必须持有
// 可取消的订阅，由 close()（播放页退出时调用）显式取消在途取流；
// 否则被中断的播放会继续把上游整段读进空处。

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:box/utils/app_logger.dart';
import 'package:box/utils/log_channels.dart';

import '../domain/remote_storage_models.dart';
import '../domain/webdav_client.dart';

/// 中继预读缓冲上限（279 C6）。
///
/// "来一块转一块"（严格背压）在弱 NAS 上会让播放器频繁等下一块；这里让上游先跑在
/// 前面。但缓冲不能无界——那等于把整部片子读进手机内存。4MB 约等于 1080p 高码率的
/// 十几秒，足够吸收抖动，又小到可以忽略。
const int kRelayReadAheadBytes = 4 * 1024 * 1024;

/// 排空到这个水位以下才放开上游（迟滞）：否则会在上限附近"攒满-暂停-放开"高频抖动，
/// 每次抖动都要重新等一次上游首字节。
const int kRelayResumeBelowBytes = 1 * 1024 * 1024;

/// 上游取流：head=true 取元信息；rangeHeader 原样透传（如 `bytes=1024-`）。
typedef RelayUpstream = Future<WebdavResponse> Function({
  required bool head,
  String? rangeHeader,
});

/// 一笔在途取流：转发订阅 + 完成信号，close() 依据它做回收。
class _InflightFetch {
  _InflightFetch(this.subscription, this.done);

  final StreamSubscription<List<int>> subscription;
  final Completer<void> done;
}

/// 一个播放会话对应一个中继实例；用完务必 [close]。
class PlaybackRelay {
  PlaybackRelay._(this._server, this._token);

  final HttpServer _server;
  final String _token;
  late final RelayUpstream _upstream;
  final Set<_InflightFetch> _inflight = <_InflightFetch>{};
  DateTime _lastActivity = DateTime.now();
  Timer? _idleTimer;
  bool _closed = false;

  /// 播放器使用的直链。
  String get url => 'http://127.0.0.1:${_server.port}/rs/$_token';

  static Future<PlaybackRelay> start({required RelayUpstream upstream}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final relay = PlaybackRelay._(server, _randomToken());
    relay._upstream = upstream;
    server.listen(
      relay._handle,
      onError: (Object e) => AppLogger.instance.logTo(
            LogChannel.storage,
            '中继监听错误: $e',
            level: LogLevel.error,
          ),
    );
    relay._idleTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      // 有在途取流不视为空闲（暂停中的播放器可能保留连接、取流停住）；
      // 仅当无请求且无在途取流超过 kRelayIdleTimeout 才自关。
      if (relay._inflight.isEmpty &&
          DateTime.now().difference(relay._lastActivity) > kRelayIdleTimeout) {
        AppLogger.instance.logTo(LogChannel.storage, '中继空闲超时，自动关闭');
        unawaited(relay.close());
      }
    });
    AppLogger.instance.logTo(LogChannel.storage, '中继已启动: ${relay.url}');
    return relay;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _idleTimer?.cancel();
    // 先取消在途取流——客户端单方断开无法被感知，这是唯一的可靠回收点。
    for (final fetch in _inflight.toList(growable: false)) {
      _inflight.remove(fetch);
      try {
        await fetch.subscription.cancel();
      } catch (_) {}
      if (!fetch.done.isCompleted) fetch.done.complete();
    }
    try {
      await _server.close(force: true);
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '中继关闭异常: $e',
        level: LogLevel.warn,
      );
    }
    AppLogger.instance.logTo(LogChannel.storage, '中继已关闭');
  }

  static String _randomToken() {
    final rand = Random.secure();
    return List.generate(
      16,
      (_) => rand.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> _handle(HttpRequest request) async {
    _lastActivity = DateTime.now();
    final path = request.uri.path;
    AppLogger.instance.logTo(
      LogChannel.storage,
      '中继请求 ${request.method} $path '
      '(range: ${request.headers.value(HttpHeaders.rangeHeader) ?? '-'})',
      level: LogLevel.debug,
    );

    if (!path.startsWith('/rs/$_token')) {
      await _simpleResponse(request, HttpStatus.notFound);
      return;
    }
    final method = request.method.toUpperCase();
    if (method != 'GET' && method != 'HEAD') {
      await _simpleResponse(request, HttpStatus.methodNotAllowed);
      return;
    }

    WebdavResponse upstream;
    try {
      upstream = await _upstream(
        head: method == 'HEAD',
        rangeHeader: request.headers.value(HttpHeaders.rangeHeader),
      );
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '中继上游失败: $e',
        level: LogLevel.warn,
      );
      await _simpleResponse(request, HttpStatus.badGateway);
      return;
    }

    final response = request.response;
    // dart:io 默认把小于 8KB 的写入攒在内部发送缓冲里，flush() 并不会把它推给
    // 客户端（只有缓冲满 8KB 或 close() 时才真正发出）——小分片流会一直卡在
    // 服务端，播放器只收到响应头、收不到数据。关掉缓冲，让每个 chunk 立即到达。
    response.bufferOutput = false;
    try {
      response.statusCode = upstream.statusCode;
      const forwardHeaders = [
        'content-type',
        'content-length',
        'content-range',
        'accept-ranges',
        'last-modified',
        'etag',
      ];
      for (final key in forwardHeaders) {
        final value = upstream.headers[key];
        if (value != null && value.isNotEmpty) {
          response.headers.set(key, value);
        }
      }
      if (method == 'HEAD' || upstream.bodyStream == null) {
        await response.close();
        return;
      }
      if (_closed) {
        await response.close();
        return;
      }

      final done = Completer<void>();
      late final StreamSubscription<List<int>> subscription;
      // 预读缓冲（C6）：上游先跑在前面，弱 NAS 上"来一块转一块"会让播放器饿着。
      final buffer = <List<int>>[];
      var bufferedBytes = 0;
      var pumping = false;
      var upstreamDone = false;

      /// 把缓冲区尽力写给下游；排空到低水位后放开上游（迟滞，避免抖动）。
      Future<void> pump() async {
        if (pumping) return;
        pumping = true;
        try {
          while (buffer.isNotEmpty) {
            final chunk = buffer.removeAt(0);
            bufferedBytes -= chunk.length;
            response.add(chunk);
            await response.flush();
            _lastActivity = DateTime.now();
            if (!upstreamDone &&
                subscription.isPaused &&
                bufferedBytes <= kRelayResumeBelowBytes) {
              subscription.resume();
            }
          }
        } catch (e, st) {
          if (!done.isCompleted) done.completeError(e, st);
        } finally {
          pumping = false;
          if (upstreamDone && buffer.isEmpty && !done.isCompleted) {
            done.complete();
          }
        }
      }

      subscription = upstream.bodyStream!.listen(
        (chunk) {
          buffer.add(chunk);
          bufferedBytes += chunk.length;
          // 到上限就暂停上游：缓冲无界 = 把整部片子读进内存。
          if (bufferedBytes >= kRelayReadAheadBytes && !subscription.isPaused) {
            subscription.pause();
          }
          unawaited(pump());
        },
        onError: (Object e, StackTrace st) {
          if (!done.isCompleted) done.completeError(e, st);
        },
        onDone: () {
          upstreamDone = true;
          if (buffer.isEmpty && !pumping && !done.isCompleted) {
            done.complete();
          }
        },
        cancelOnError: true,
      );
      final fetch = _InflightFetch(subscription, done);
      _inflight.add(fetch);
      if (_closed) {
        // 竞态：订阅注册前中继已关闭，立即回收。
        _inflight.remove(fetch);
        await subscription.cancel();
        await response.close();
        return;
      }
      try {
        await done.future;
        await response.close();
      } finally {
        _inflight.remove(fetch);
        try {
          await subscription.cancel();
        } catch (_) {}
      }
    } catch (e) {
      // 上游取流异常（断流/超时等）经 done 传出后在此收尾。
      // 播放器单方断开不会走到这里：dart:io 对 HttpResponse 的写失败静默吞掉，
      // 回收依赖 close() 取消在途取流。
      AppLogger.instance.logTo(
        LogChannel.storage,
        '中继转发中断: $e',
        level: LogLevel.debug,
      );
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _simpleResponse(HttpRequest request, int status) async {
    try {
      request.response.statusCode = status;
      await request.response.close();
    } catch (_) {}
  }
}
