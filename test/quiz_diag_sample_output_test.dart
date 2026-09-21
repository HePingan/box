import 'package:box/features/quiz_plugin/domain/quiz_diag.dart';
import 'package:flutter_test/flutter_test.dart';

/// 演示：一次真实答题（命中）在日志里长什么样。
/// 这个文件只是给人看的样例输出，同时锁定日志格式不漂移。
void main() {
  test('演示：命中一题的完整日志链', () {
    final sw = Stopwatch()..start();

    // ── 1. 识别：OCR 解析出题干/选项 ──────────────────────
    QuizDiag.log(
      QuizDiagStage.parse,
      'parsed',
      fields: {
        'rawLines': 14,
        'keptLines': 11,
        'q': QuizDiag.snip('驾驶机动车不按规定使用灯光的，一次记多少分？'),
        'opts': 4,
        'ans': '3分',
        'trueFalse': false,
      },
    );

    // ── 2. 匹配：打分与命中 ──────────────────────────────
    QuizDiag.log(
      QuizDiagStage.match,
      'score=98 q=97 o=100 base=97.9 final=98',
      fields: {'id': 'Q1042', 'src': '本地题库'},
    );
    QuizDiag.log(QuizDiagStage.match, 'HIT',
        fields: {'n': 1, 'score': 0.98});

    // ── 3. 来源裁决 ──────────────────────────────────────
    QuizDiag.log(
      QuizDiagStage.source,
      'recordSuccess',
      fields: {
        'src': 'localBank',
        'q': 98,
        'o': 100,
        'reliable': true,
        'locked': 'yes(已锁定,可节流)',
      },
    );

    // ── 4. 呈现 ──────────────────────────────────────────
    sw.stop();
    QuizDiag.log(QuizDiagStage.result, 'engine.search 返回', fields: {
      'ok': true,
      'ms': 87,
      'src': 'localBank',
    });
    QuizDiag.log(QuizDiagStage.result, 'OVERLAY 更新答案',
        fields: {'ans': '3分', 'conf': '0.98'});
  });

  test('演示：不出答案时日志会指出卡在哪一步', () {
    // 场景 A：识别就失败（题干空）
    QuizDiag.warn(QuizDiagStage.parse, '题干为空：题库必然查不到，必然是解析器/采集问题',
        fields: {'raw': '…设置驾驶机动车…'});

    // 场景 B：指纹口径不一致 → 节流彻底失效
    QuizDiag.warn(QuizDiagStage.throttle, '指纹不匹配：attempt 与 success 用了不同指纹函数？',
        fields: {'attempt': 46, 'now': 31});

    // 场景 C：被旧来源掐住 → 悬浮窗停在「检索中」
    QuizDiag.warn(QuizDiagStage.result, '丢弃：低优先级来源不得覆盖已展示结果（悬浮窗保持原样）',
        fields: {'src': 'externalApi', 'fp': 'a1b2c3'});

    // 场景 D：引擎完全没命中
    QuizDiag.warn(QuizDiagStage.result, '无结果：引擎未命中，悬浮窗停在检索中');
  });
}
