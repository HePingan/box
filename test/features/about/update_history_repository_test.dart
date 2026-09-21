import 'package:box/features/about/data/update_history_models.dart';
import 'package:box/features/about/data/update_history_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 历史更新日志数据层。
///
/// 这一层最要紧的两件事：
///  1. 地址必须由 updateCheckUrl 同源推导，且只接受 https；
///  2. 任何异常都要变成「带原因的失败结果」，不能抛出去让关于页白屏。
void main() {
  group('historyUrlFrom', () {
    test('由 check 地址同源推导出 history 地址', () {
      expect(
        UpdateHistoryRepository.historyUrlFrom(
          'https://box.hpa888.top/api/v1/app-updates/check',
        ),
        'https://box.hpa888.top/api/v1/app-updates/history',
      );
    });

    test('拒绝明文 http：否则别人可以随意改写「历史更新」内容', () {
      expect(
        UpdateHistoryRepository.historyUrlFrom(
          'http://box.hpa888.top/api/v1/app-updates/check',
        ),
        isNull,
      );
    });

    test('地址为空或不以 /check 结尾时返回 null，而不是拼出一个错地址', () {
      expect(UpdateHistoryRepository.historyUrlFrom(''), isNull);
      expect(UpdateHistoryRepository.historyUrlFrom('   '), isNull);
      expect(
        UpdateHistoryRepository.historyUrlFrom('https://box.hpa888.top/api/v1'),
        isNull,
      );
    });
  });

  group('fetch', () {
    /// 用 Dio 拦截器伪造响应，不打真网络。
    Dio dioReturning({
      Object? body,
      int statusCode = 200,
      DioException? throwThis,
    }) {
      final dio = Dio();
      dio.httpClientAdapter = _StubAdapter();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (throwThis != null) {
              handler.reject(throwThis);
              return;
            }
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                data: body,
                statusCode: statusCode,
              ),
            );
          },
        ),
      );
      return dio;
    }

    test('正常返回时按版本号倒序解析出条目', () async {
      final repo = UpdateHistoryRepository(
        dio: dioReturning(
          body: {
            'code': 0,
            'message': 'ok',
            'data': {
              'items': [
                {
                  'versionName': '1.9.8',
                  'versionCode': 198,
                  'title': '侧边栏修复',
                  'changelog': ['修复返回后抽屉被关掉'],
                  'publishedAt': '2026-09-05T08:00:00+00:00',
                  'forceUpdate': false,
                },
                {
                  'versionName': '1.10.2',
                  'versionCode': 203,
                  'title': '调试日志修复',
                  'changelog': ['修复三处问题'],
                  'publishedAt': '2026-09-05T08:27:47+00:00',
                  'forceUpdate': false,
                },
              ],
              'total': 2,
            },
          },
        ),
      );

      final result = await repo.fetch(packageName: 'top.hpa888.box');

      expect(result.isFailure, isFalse);
      expect(result.entries.length, 2);
      expect(
        result.entries.first.versionCode,
        203,
        reason: '新版必须在最上面，不能把顺序押在服务端实现上',
      );
      expect(result.entries.first.title, '调试日志修复');
      expect(result.entries.last.versionName, '1.9.8');
    });

    test('网络不通时给出可读原因，而不是抛异常', () async {
      final repo = UpdateHistoryRepository(
        dio: dioReturning(
          throwThis: DioException(
            requestOptions: RequestOptions(path: '/history'),
            type: DioExceptionType.connectionError,
          ),
        ),
      );

      final result = await repo.fetch(packageName: 'top.hpa888.box');

      expect(result.isFailure, isTrue);
      expect(result.errorMessage, contains('网络'));
      expect(result.entries, isEmpty);
    });

    test('服务端返回业务错误码时透出 message', () async {
      final repo = UpdateHistoryRepository(
        dio: dioReturning(
          body: {'code': 1001, 'message': '参数错误', 'data': null},
        ),
      );

      final result = await repo.fetch(packageName: 'top.hpa888.box');

      expect(result.isFailure, isTrue);
      expect(result.errorMessage, '参数错误');
    });

    test('返回体不是预期结构时如实失败，不静默当成空列表', () async {
      final repo = UpdateHistoryRepository(
        dio: dioReturning(body: 'not-json'),
      );

      final result = await repo.fetch(packageName: 'top.hpa888.box');

      expect(result.isFailure, isTrue);
      expect(result.errorMessage, contains('格式'));
    });

    test('单条记录缺版本号时丢掉该条，不影响其余条目', () async {
      final repo = UpdateHistoryRepository(
        dio: dioReturning(
          body: {
            'code': 0,
            'data': {
              'items': [
                {'versionCode': 0, 'changelog': <String>[]},
                {
                  'versionName': '1.10.2',
                  'versionCode': 203,
                  'changelog': ['修复'],
                },
              ],
            },
          },
        ),
      );

      final result = await repo.fetch(packageName: 'top.hpa888.box');

      expect(result.entries.length, 1);
      expect(result.entries.single.versionName, '1.10.2');
    });
  });

  group('UpdateHistoryEntry', () {
    test('时间戳坏掉时只丢时间，不让整条记录解析失败', () {
      final entry = UpdateHistoryEntry.fromJson({
        'versionName': '1.0.0',
        'versionCode': 100,
        'changelog': ['首个版本'],
        'publishedAt': '不是时间',
      });

      expect(entry.versionName, '1.0.0');
      expect(entry.publishedAt, isNull);
      expect(entry.publishedDateLabel, isNull);
    });

    test('没有 title 时展示标题退回版本号', () {
      final entry = UpdateHistoryEntry.fromJson({
        'versionName': '1.0.0',
        'versionCode': 100,
        'changelog': <String>[],
      });

      expect(entry.displayTitle, 'v1.0.0');
    });

    test('changelog 里的空白条目被剔除', () {
      final entry = UpdateHistoryEntry.fromJson({
        'versionName': '1.0.0',
        'versionCode': 100,
        'changelog': ['真内容', '   ', ''],
      });

      expect(entry.changelog, ['真内容']);
    });
  });
}

/// 拦截器会在请求发出前 resolve/reject，这个 adapter 只是占位，
/// 保证真的不会有任何网络请求逃出去。
class _StubAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw StateError('测试不应真的发起网络请求');
  }
}
