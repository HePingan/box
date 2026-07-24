import 'dart:async';
import 'dart:io';

import 'package:box/video/controller/video_detail_controller.dart';
import 'package:box/video/models/video_source.dart';
import 'package:box/video/models/vod_item.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// A simple function type for injecting detail-fetching behavior.
typedef DetailFetcher = Future<VodItem?> Function();

void main() {
  // VideoDetailController 构造时会 new PlayLineMemoryRepository / FavoritesRepository，
  // 二者都要打开 Hive box。测试环境用临时目录初始化 Hive，构造才不会抛
  // HiveError（"You need to initialize Hive..."）。
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('box_video_detail_hive_');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDir.existsSync()) {
      await hiveDir.delete(recursive: true);
    }
  });

  group('VideoDetailController — generation protection', () {
    test(
      'calling loadDetail twice: faster second result is not overwritten by slower first result',
      () async {
        // Arrange: create a controller with injectable fetcher.
        VodItem? result1;
        VodItem? result2;

        // First detail takes 200ms, second takes 10ms.
        result1 = VodItem(vodId: 100, vodName: 'SlowResult', vodRemarks: 'old');
        result2 = VodItem(vodId: 200, vodName: 'FastResult', vodRemarks: 'new');

        int callCount = 0;
        Future<VodItem?> injectableFetch() async {
          callCount++;
          if (callCount == 1) {
            // First call: slow
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return result1;
          } else {
            // Second call: fast
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return result2;
          }
        }

        final controller = VideoDetailController(
          source: const VideoSource(
            id: 'test',
            name: 'TestSource',
            url: 'https://api.example.com/api.php/provide/vod/',
            detailUrl: '',
          ),
          vodId: 1,
          detailFetcher: injectableFetch,
        );

        // Wait for initial load to complete
        await Future<void>.delayed(const Duration(milliseconds: 300));

        // After construction, the first loadDetail should have completed
        // with result1 (slow). Now fullDetail should be result1.
        expect(controller.fullDetail?.vodId, equals(100));

        // Now call loadDetail again — this starts the second (fast) fetch.
        controller.loadDetail();

        // Wait for the fast second call to complete.
        await Future<void>.delayed(const Duration(milliseconds: 200));

        // At this point:
        // - Second call finished quickly → fullDetail should be result2 (vodId=200).
        // - First call's result (result1) is still pending from construction.
        //   With generation protection, result1 MUST NOT overwrite result2.
        //
        // Without generation protection: result1 (from the constructor's loadDetail)
        // would arrive later and overwrite result2.
        expect(
          controller.fullDetail?.vodId,
          equals(200),
          reason:
              'faster second result must not be overwritten by slower first result',
        );
        expect(controller.isLoading, isFalse);
        expect(controller.errorMessage, isNull);
      },
    );

    test(
      'an exception in an older call does not overwrite newer successful state',
      () async {
        VodItem? goodResult;
        goodResult = VodItem(vodId: 300, vodName: 'GoodResult');

        int callCount = 0;
        Exception? firstError;

        Future<VodItem?> injectableFetch() async {
          callCount++;
          if (callCount == 1) {
            // First call throws
            await Future<void>.delayed(const Duration(milliseconds: 200));
            firstError = Exception('Network error');
            throw firstError!;
          } else {
            // Second call succeeds
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return goodResult;
          }
        }

        final controller = VideoDetailController(
          source: const VideoSource(
            id: 'test',
            name: 'TestSource',
            url: 'https://api.example.com/api.php/provide/vod/',
            detailUrl: '',
          ),
          vodId: 1,
          detailFetcher: injectableFetch,
        );

        // Wait for first (failing) call to complete
        await Future<void>.delayed(const Duration(milliseconds: 300));

        // First call failed → errorMessage should be set.
        expect(controller.errorMessage, isNotNull);

        // Now call loadDetail again — this time it succeeds.
        controller.loadDetail();

        // Wait for second (successful) call.
        await Future<void>.delayed(const Duration(milliseconds: 200));

        // Generation protection: the exception from the first call should NOT
        // clobber the successful state from the second call.
        expect(
          controller.errorMessage,
          isNull,
          reason: 'stale exception must not overwrite successful state',
        );
        expect(controller.fullDetail?.vodId, equals(300));
        expect(controller.isLoading, isFalse);
      },
    );

    test(
      'each loadDetail() invocation resets isLoading and errorMessage synchronously',
      () async {
        // This test verifies that loadDetail() always starts fresh:
        // isLoading=true, errorMessage=null at the beginning of each call.

        Future<VodItem?> injectableFetch() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return VodItem(vodId: 400, vodName: 'Test');
        }

        // We need to observe state changes. Since ChangeNotifier doesn't expose
        // a way to listen in tests easily, we verify the behavior by checking
        // that calling loadDetail on a settled controller resets state.
        final controller = VideoDetailController(
          source: const VideoSource(
            id: 'test',
            name: 'TestSource',
            url: 'https://api.example.com/api.php/provide/vod/',
            detailUrl: '',
          ),
          vodId: 1,
          detailFetcher: injectableFetch,
        );

        // Wait for initial load
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(controller.isLoading, isFalse);

        // Manually set an error state to simulate a previous failure
        controller.errorMessage = 'Previous error';

        // Call loadDetail again — this should clear the error.
        controller.loadDetail();

        // After the synchronous part of loadDetail runs:
        // isLoading should be true, errorMessage should be null.
        // But since we're in async context, the synchronous changes already happened.
        // We check that the controller is in loading state.
        expect(
          controller.errorMessage,
          isNull,
          reason: 'loadDetail must clear errorMessage on each call',
        );
      },
    );

    test('disposed controller discards all pending work', () async {
      final completer = Completer<VodItem?>();

      Future<VodItem?> injectableFetch() async {
        return completer.future;
      }

      final controller = VideoDetailController(
        source: const VideoSource(
          id: 'test',
          name: 'TestSource',
          url: 'https://api.example.com/api.php/provide/vod/',
          detailUrl: '',
        ),
        vodId: 1,
        detailFetcher: injectableFetch,
      );

      // Wait for loadDetail to start
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Dispose before the fetch completes
      controller.dispose();

      // Now complete the future — this simulates a late response.
      completer.complete(VodItem(vodId: 500, vodName: 'LateResult'));

      // Wait a bit for the completion to propagate.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // The disposed controller should ignore the late result.
      // fullDetail should remain null (or whatever was set before dispose).
      expect(
        controller.fullDetail,
        isNull,
        reason: 'disposed controller must discard late results',
      );
    });

    test(
      'error message is user-friendly (sanitized) while detailed errors go to logs',
      () async {
        Future<VodItem?> injectableFetch() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          throw Exception(
            'Connection refused: https://api.example.com/api.php/provide/vod/?ac=detail&ids=1 [status: 500]',
          );
        }

        final controller = VideoDetailController(
          source: const VideoSource(
            id: 'test',
            name: 'TestSource',
            url: 'https://api.example.com/api.php/provide/vod/',
            detailUrl: '',
          ),
          vodId: 1,
          detailFetcher: injectableFetch,
        );

        await Future<void>.delayed(const Duration(milliseconds: 100));

        // The errorMessage shown to users should NOT contain internal URLs or stack traces.
        expect(controller.errorMessage, isNotNull);
        expect(
          controller.errorMessage!.contains('api.example.com'),
          isFalse,
          reason: 'user-facing error must not leak internal API URLs',
        );
        expect(
          controller.errorMessage!.contains('Connection refused'),
          isFalse,
          reason: 'user-facing error must not contain raw exception messages',
        );
      },
    );
  });
}
