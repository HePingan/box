import 'dart:async';
import 'dart:io';

/// An HTTP status failure kept separate from transport exceptions so callers
/// can make safe retry decisions without parsing exception text.
class VideoHttpException implements Exception {
  const VideoHttpException(this.statusCode, {this.message});

  final int statusCode;
  final String? message;

  bool get isTransient =>
      statusCode == 408 || statusCode == 429 || statusCode >= 500;

  @override
  String toString() => 'VideoHttpException(status=$statusCode)';
}

/// A user-facing failure that deliberately excludes request URLs, headers and
/// raw exception text.
class VideoRequestFailure {
  const VideoRequestFailure._(this.userMessage);

  final String userMessage;

  factory VideoRequestFailure.from(Object error) {
    if (error is VideoHttpException) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        return const VideoRequestFailure._('服务拒绝访问，请检查片源配置');
      }
      if (error.statusCode >= 500 ||
          error.statusCode == 408 ||
          error.statusCode == 429) {
        return const VideoRequestFailure._('服务暂时不可用，请稍后重试');
      }
      return const VideoRequestFailure._('请求失败，请稍后重试');
    }
    if (error is SocketException || error is TimeoutException) {
      return const VideoRequestFailure._('网络连接失败，请稍后重试');
    }
    return const VideoRequestFailure._('请求失败，请稍后重试');
  }
}

typedef VideoRequestWait = Future<void> Function(Duration delay);

/// Retry policy for idempotent GET work only.  It has no knowledge of URLs or
/// authentication and therefore cannot accidentally log or expose secrets.
class VideoGetRequestPolicy {
  const VideoGetRequestPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 250),
    this.wait = _defaultWait,
  }) : assert(maxAttempts > 0);

  final int maxAttempts;
  final Duration baseDelay;
  final VideoRequestWait wait;

  static Future<void> _defaultWait(Duration delay) =>
      Future<void>.delayed(delay);

  Future<T> execute<T>(Future<T> Function() request) async {
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await request();
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (!_shouldRetry(error) || attempt == maxAttempts) break;
        await wait(_backoffFor(attempt));
      }
    }

    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  bool _shouldRetry(Object error) {
    if (error is VideoHttpException) return error.isTransient;
    return error is SocketException ||
        error is TimeoutException ||
        error is HttpException;
  }

  Duration _backoffFor(int failedAttempt) {
    final multiplier = 1 << (failedAttempt - 1);
    return baseDelay * multiplier;
  }
}
