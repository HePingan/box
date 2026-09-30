// 续传判定：27MB 的包断一次不该从 0 再下（用户报过「只能重新再次下载更新」）。
//
// 这些是纯逻辑，把它们从下载流程里抽出来单独锁住：真正的下载在手机上才跑得起来。

import 'package:flutter_test/flutter_test.dart';

import 'package:box/update/update_resume.dart';

void main() {
  group('Range / If-Range 头', () {
    test('没下到东西就不带 Range（从头下）', () {
      expect(resumeHeaders(partBytes: 0, state: null), isNull);
      expect(
        resumeHeaders(
          partBytes: 0,
          state: const UpdateResumeState(etag: '"abc"', totalBytes: 5000),
        ),
        isNull,
      );
    });

    test('有半成品就带 Range，偏移量正好是已下字节数', () {
      final headers = resumeHeaders(
        partBytes: 1234,
        state: const UpdateResumeState(etag: '"abc"', totalBytes: 5000),
      );
      expect(headers?['Range'], 'bytes=1234-');
      expect(headers?['If-Range'], '"abc"', reason: '包换了就得让服务端整包重发，不能拼接');
    });

    test('没有 ETag 就退用 Last-Modified 当 If-Range；都没有就不带', () {
      expect(
        resumeHeaders(
          partBytes: 10,
          state: const UpdateResumeState(
            lastModified: 'Wed, 30 Sep 2026 01:00:00 GMT',
          ),
        )?['If-Range'],
        'Wed, 30 Sep 2026 01:00:00 GMT',
      );
      final noValidator = resumeHeaders(
        partBytes: 10,
        state: const UpdateResumeState(totalBytes: 100),
      );
      expect(noValidator?['Range'], 'bytes=10-');
      expect(noValidator?.containsKey('If-Range'), isFalse);
    });

    test('半成品已经和整包一样大 → 不续传（上次其实下完了，只是没改名）', () {
      expect(
        canResume(
          partBytes: 100,
          state: const UpdateResumeState(totalBytes: 100),
        ),
        isFalse,
      );
      expect(canResume(partBytes: 101, state: const UpdateResumeState(totalBytes: 100)), isFalse);
      expect(
        canResume(
          partBytes: 99,
          state: const UpdateResumeState(totalBytes: 100),
        ),
        isTrue,
      );
      expect(canResume(partBytes: 99, state: null), isTrue, reason: '不知道总长也能接着下');
    });
  });

  group('Content-Range 解析', () {
    test('正常的 206 响应：起点与总长都取得到', () {
      const value = 'bytes 100-999/1000';
      expect(startFromContentRange(value), 100);
      expect(totalFromContentRange(value), 1000);
      expect(isPartialContent(206), isTrue);
      expect(isPartialContent(200), isFalse, reason: '200 = 服务端整包重发，要从头写');
    });

    test('总长是 * 或者格式不对 → 不猜', () {
      expect(startFromContentRange('bytes 5-9/*'), 5);
      expect(totalFromContentRange('bytes 5-9/*'), isNull);
      expect(startFromContentRange('items 5-9/10'), isNull);
      expect(startFromContentRange('bytes abc'), isNull);
      expect(startFromContentRange(null), isNull);
    });
  });

  group('半成品记录（.part.meta）', () {
    test('往返编解码：ETag / Last-Modified / 总长', () {
      const state = UpdateResumeState(
        etag: 'W/"xyz"',
        lastModified: 'Wed, 30 Sep 2026 01:00:00 GMT',
        totalBytes: 27920780,
      );

      final back = UpdateResumeState.decode(state.encode())!;

      expect(back.etag, 'W/"xyz"');
      expect(back.lastModified, 'Wed, 30 Sep 2026 01:00:00 GMT');
      expect(back.totalBytes, 27920780);
    });

    test('记录坏了/是空的 → 当没有（续传是省流量，不是正确性的前提）', () {
      expect(UpdateResumeState.decode(''), isNull);
      expect(UpdateResumeState.decode('{坏了'), isNull);
      expect(UpdateResumeState.decode('[1,2]'), isNull);
      expect(UpdateResumeState.fromJson(const <String, Object?>{})?.totalBytes, isNull);
    });
  });
}
