import 'dart:convert';

import 'package:box/features/quiz_plugin/domain/quiz_submission_image.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuizSubmissionImage.isDeviceLocalPath', () {
    test('设备本地路径必须被识别（否则会被当成服务器相对路径拼域名）', () {
      expect(
        QuizSubmissionImage.isDeviceLocalPath(
          '/data/user/0/com.example.box/app_flutter/quiz_images/a.png',
        ),
        isTrue,
      );
      expect(
        QuizSubmissionImage.isDeviceLocalPath('/storage/emulated/0/DCIM/b.jpg'),
        isTrue,
      );
      expect(
        QuizSubmissionImage.isDeviceLocalPath('file:///data/user/0/x/c.png'),
        isTrue,
      );
    });

    test('服务端相对路径与绝对 URL 不算设备本地路径', () {
      expect(
        QuizSubmissionImage.isDeviceLocalPath('/api/quiz/images/abc.png'),
        isFalse,
      );
      expect(
        QuizSubmissionImage.isDeviceLocalPath(
          'https://background.hpa888.top/api/quiz/images/abc.png',
        ),
        isFalse,
      );
      expect(QuizSubmissionImage.isDeviceLocalPath('data:image/png;base64,AA'),
          isFalse);
      expect(QuizSubmissionImage.isDeviceLocalPath(''), isFalse);
    });
  });

  group('QuizSubmissionImage.resolveForDisplay', () {
    const host = 'https://background.hpa888.top';

    test('设备本地路径不得拼成服务器 URL —— 这正是审核端图片加载失败的根因', () {
      const raw = '/data/user/0/com.example.box/app_flutter/q.png';
      final r = QuizSubmissionImage.resolveForDisplay(raw, serverUrl: host);
      expect(r.kind, QuizImageSourceKind.unavailable);
      expect(r.url, isNull);
      // 关键：绝不能出现 https://background.hpa888.top/data/user/0/...
      expect(r.url ?? '', isNot(contains('/data/user/0')));
      expect(r.reason, contains('投稿端未上传图片'));
    });

    test('data URL 走内存解码', () {
      final b64 = base64Encode(<int>[1, 2, 3, 4]);
      final r = QuizSubmissionImage.resolveForDisplay(
        'data:image/png;base64,$b64',
        serverUrl: host,
      );
      expect(r.kind, QuizImageSourceKind.inlineBytes);
      expect(r.bytes, isNotNull);
      expect(r.bytes!.length, 4);
    });

    test('损坏的 data URL 归类为不可用而非崩溃', () {
      final r = QuizSubmissionImage.resolveForDisplay(
        'data:image/png;base64,@@@not-base64@@@',
        serverUrl: host,
      );
      expect(r.kind, QuizImageSourceKind.unavailable);
      expect(r.reason, contains('图片数据损坏'));
    });

    test('服务端相对路径拼到当前 serverUrl，不硬编码域名', () {
      final r = QuizSubmissionImage.resolveForDisplay(
        '/api/quiz/images/abc.png',
        serverUrl: 'https://example.test',
      );
      expect(r.kind, QuizImageSourceKind.networkUrl);
      expect(r.url, 'https://example.test/api/quiz/images/abc.png');
    });

    test('已是绝对 URL 时原样使用', () {
      const u = 'https://cdn.test/x/y.png';
      final r = QuizSubmissionImage.resolveForDisplay(u, serverUrl: host);
      expect(r.kind, QuizImageSourceKind.networkUrl);
      expect(r.url, u);
    });

    test('serverUrl 为空时相对路径不可用，不得拼出裸路径去请求', () {
      final r = QuizSubmissionImage.resolveForDisplay(
        '/api/quiz/images/abc.png',
        serverUrl: '',
      );
      expect(r.kind, QuizImageSourceKind.unavailable);
    });

    test('空来源归类为无图', () {
      final r = QuizSubmissionImage.resolveForDisplay('  ', serverUrl: host);
      expect(r.kind, QuizImageSourceKind.none);
    });
  });
}
