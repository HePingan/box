// 自动读屏的「明显不是题就别发」闸门 + 同屏冷却（2026-10-01 真机事故回归）。
//
// 事故形状：用户在视频/列表界面点 AI，客户端把**界面文字**
// `沉浸浏览，视频220，，2026年9月12日 12:48，，第220个，共1102个`
// 当成题干，照样发了一次**付费**读屏请求（服务端日志两次 200），
// AI 拿到的只是这个界面，自然给不出答案 —— 用户看到的是「未命中」。
//
// 本文件锁两件事：
//   1) 自动路径：明显噪声的屏 → **连截图都不做**（更不会发付费请求）；
//   2) 手动路径：**永远放行** —— 用户 09-13 拍板「所有本地未命中的题都交给读屏」，
//      图题常常只有「如图所示」这种短题干，闸门不能拦用户主动发起。
import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('top.hpa888.box/quiz_plugin');

/// 真机那份界面文字（逐字抄的）。
const _videoScreenText = '沉浸浏览，视频220，，2026年9月12日 12:48，，第220个，共1102个';

int _captureCalls = 0;

void _mockNative() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        switch (call.method) {
          case 'captureRegionScreenshot':
            _captureCalls++;
            return <String, Object?>{
              'bytes': Uint8List.fromList(List<int>.filled(16, 7)),
              'dHash': 'abcdef01',
            };
          case 'isAccessibilityEnabled':
            return true;
          default:
            return null;
        }
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _captureCalls = 0;
    // 真等太久；只用来给"流程被兜底切断"一个短上限，不影响闸门判据。
    QuizPluginEntry.captureTimeout = const Duration(milliseconds: 60);
    QuizPluginEntry.visionFlowTimeout = const Duration(milliseconds: 400);
    QuizPluginEntry.visionRepeatCooldown = const Duration(seconds: 10);
    _mockNative();
  });

  tearDown(() {
    QuizPluginEntry.captureTimeout = const Duration(seconds: 8);
    QuizPluginEntry.visionFlowTimeout = const Duration(seconds: 75);
    QuizPluginEntry.visionRepeatCooldown = const Duration(seconds: 10);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('判据（纯函数，只挡噪声）', () {
    test('真机那份界面文字 → 挡', () {
      expect(QuizPluginEntry.isObviousNonQuestion(_videoScreenText), isTrue);
    });

    test('空文字 / 位置指示 / 时间戳 / 日期开头 / 弹幕字样 → 挡', () {
      for (final noise in <String>[
        '',
        '   ',
        '第220个，共1102个',
        '12:48',
        '2026年9月12日',
        '沉浸浏览',
        '正在播放',
      ]) {
        expect(
          QuizPluginEntry.isObviousNonQuestion(noise),
          isTrue,
          reason: '应挡住：<$noise>',
        );
      }
    });

    test('真题干（含短的图题提示）→ 放行', () {
      for (final real in <String>[
        '下列哪一项属于光合作用的产物',
        '这道题考查的是哪个朝代的赋税制度？',
        '如图所示',
        '看图回答第 3 题',
      ]) {
        expect(
          QuizPluginEntry.isObviousNonQuestion(real),
          isFalse,
          reason: '不该挡：<$real>（用户拍板：所有本地未命中的题都交给读屏）',
        );
      }
    });
  });

  test('自动路径：噪声屏不发付费请求（连截图都不做）', () async {
    QuizPluginEntry.debugSetCurrentRequest(7, 'fp-noise');
    final result = await QuizPluginEntry.debugRunVisionFallback(
      const QuizConfig(allowExternalApi: true),
      QuizEngine(config: const QuizConfig(allowExternalApi: true)),
      hintQuestion: _videoScreenText,
      requestGeneration: 7,
      requestFingerprint: 'fp-noise',
      manual: false,
    );

    expect(result, isNull, reason: '返回 null = 压根没发起，调用方按普通 miss 处理');
    expect(_captureCalls, 0, reason: '闸门要拦在截图之前（截图之后的代价是付费请求）');
  });

  test('手动点 AI：同一个噪声屏也照发（用户意图优先）', () async {
    QuizPluginEntry.debugSetCurrentRequest(8, 'fp-manual');
    await QuizPluginEntry.debugRunVisionFallback(
      const QuizConfig(allowExternalApi: true),
      QuizEngine(config: const QuizConfig(allowExternalApi: true)),
      hintQuestion: _videoScreenText,
      requestGeneration: 8,
      requestFingerprint: 'fp-manual',
      manual: true,
    );

    expect(_captureCalls, greaterThan(0), reason: '手动路径不能被闸门拦住');
  });

  test('同一屏冷却：自动路径不在短时间对同一屏重复发', () async {
    const config = QuizConfig(allowExternalApi: true);
    QuizPluginEntry.debugSetCurrentRequest(9, 'fp-same');
    await QuizPluginEntry.debugRunVisionFallback(
      config,
      QuizEngine(config: config),
      hintQuestion: '下列哪一项属于光合作用的产物',
      requestGeneration: 9,
      requestFingerprint: 'fp-same',
      manual: false,
    );
    final afterFirst = _captureCalls;
    expect(afterFirst, greaterThan(0), reason: '第一次（像题）应放行');

    QuizPluginEntry.debugSetCurrentRequest(10, 'fp-same');
    await QuizPluginEntry.debugRunVisionFallback(
      config,
      QuizEngine(config: config),
      hintQuestion: '下列哪一项属于光合作用的产物',
      requestGeneration: 10,
      requestFingerprint: 'fp-same',
      manual: false,
    );

    expect(_captureCalls, afterFirst, reason: '同一屏冷却期内不该再截一次图');
  });
}
