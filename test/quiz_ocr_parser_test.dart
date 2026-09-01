import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/ocr_quiz_parser.dart';

void main() {
  group('OcrQuizParser 驾考无字母选项', () {
    test('题干+4个无前缀短选项（含噪点·×）', () {
      const raw = '''
·设置
·×驾驶这种机动车上路行驶属于什么行为?×
·违规行为
·违章行为
·违法行为
·犯罪行为
''';
      final r = OcrQuizParser.parse(raw);
      expect(r.question, contains('驾驶这种机动车上路行驶属于什么行为'));
      expect(r.question, isNot(contains('·')));
      expect(r.question, isNot(contains('×')));
      expect(r.options, hasLength(4));
      expect(r.options, contains('违规行为'));
      expect(r.options, contains('违章行为'));
      expect(r.options, contains('违法行为'));
      expect(r.options, contains('犯罪行为'));
      expect(r.questionType, 'single_choice');
    });

    test('传统 A. 选项仍正常', () {
      const raw = '''
驾驶机动车在道路上违反交通安全法规的行为属于什么？
A. 违规行为
B. 违章行为
C. 违法行为
D. 犯罪行为
答案：C
''';
      final r = OcrQuizParser.parse(raw);
      expect(r.options, hasLength(4));
      expect(r.correctAnswer, '违法行为');
    });

    test('判断题 A正确 B错误', () {
      const raw = '''
这种标线表示禁止长时停车。
A 正确
B 错误
''';
      final r = OcrQuizParser.parse(raw);
      expect(r.questionType, 'true_false');
      expect(r.options, contains('正确'));
      expect(r.options, contains('错误'));
    });

    test('图片题：·分隔+无字母前缀+选项黏行+末尾答案（真实试捕样本）', () {
      // 悬浮窗试捕预览原文：选项无 A/B/C/D（字母是图形圆圈），
      // 「·」当逻辑项分隔符，且「未立即排除故障」「未将车停到路边」黏成一行。
      const raw =
          '·x图中故障车辆的违法行为是()。\n'
          '·未设置警告标志·未立即排除故障未将车停到路边\n'
          '·未开启危险报警闪光灯·答案A';
      final r = OcrQuizParser.parse(raw);
      expect(r.question, contains('图中故障车辆的违法行为是'));
      expect(r.question, isNot(contains('·')));
      expect(r.options, hasLength(4));
      expect(r.options, contains('未设置警告标志'));
      expect(r.options, contains('未立即排除故障'));
      expect(r.options, contains('未将车停到路边'));
      expect(r.options, contains('未开启危险报警闪光灯'));
      // 答案 A → 第 0 个选项
      expect(r.correctAnswer, '未设置警告标志');
      expect(r.questionType, 'single_choice');
    });

    test('长选项无字母前缀：题干与选项不得黏在一起（真实试捕样本 记分题）', () {
      // 用户真实试捕：解析选项 0 个，四条选项全被当成题干续行。
      // 选项均超过 30 字符上限，且含中文逗号，此前被 _splitQa 拒收。
      const raw =
          '答题\n'
          '背题\n'
          '视频\n'
          '设置\n'
          'x 以下违法行为对应记分正确的是？x\n'
          '驾驶与准驾车型不符的机动车的，记9分\n'
          '未取得校车驾驶资格驾驶校车的，记1分\n'
          '驾驶机动车不按交通信号灯指示通行的，记3分\n'
          '驾驶机动车不按规定避让校车的，记6分\n'
          '答案 A\n'
          '速记口诀\n'
          '本题技巧\n'
          '准驾不符，扣9分。';
      final r = OcrQuizParser.parse(raw);
      expect(r.question, '以下违法行为对应记分正确的是？');
      expect(r.question, isNot(contains('准驾车型不符')));
      expect(r.options, hasLength(4));
      expect(r.options[0], '驾驶与准驾车型不符的机动车的，记9分');
      expect(r.options[1], '未取得校车驾驶资格驾驶校车的，记1分');
      expect(r.options[2], '驾驶机动车不按交通信号灯指示通行的，记3分');
      expect(r.options[3], '驾驶机动车不按规定避让校车的，记6分');
      expect(r.correctAnswer, '驾驶与准驾车型不符的机动车的，记9分');
      expect(r.questionType, 'single_choice');
    });

    test('无字母长选项不得被长度上限截断（真实试捕样本 记12分题）', () {
      // 用户真实试捕：原文 14 行 / 解析选项 0 个。
      // 四个无字母选项里第二条长 31 字，超过 _splitQa 的 30 字上限后
      // 直接 break，opts 只剩 1 条 → 判死 → 整组选项退回题干。
      const raw = '''
答题
背题
视频
设置
下列交通违法行为，一次记12分的是什么？
驾驶机动车在城市快速路上倒车的
连续驾驶中型以上载客汽车、危险物品运输车超过4小时未停车休息的
驾驶机动车在高速公路或者城市快速路上违法占用应急车道行驶的
机动车驾驶证被暂扣或者扣留期间驾驶机动车的
答案 A
速记口诀
本题技巧
适用于7道题
高倒逆12，普倒1逆3。
''';
      final r = OcrQuizParser.parse(raw);

      expect(r.question, '下列交通违法行为，一次记12分的是什么？');
      expect(r.options.length, 4);
      expect(r.options[0], '驾驶机动车在城市快速路上倒车的');
      expect(r.options[1], '连续驾驶中型以上载客汽车、危险物品运输车超过4小时未停车休息的');
      expect(r.options[2], '驾驶机动车在高速公路或者城市快速路上违法占用应急车道行驶的');
      expect(r.options[3], '机动车驾驶证被暂扣或者扣留期间驾驶机动车的');
      expect(r.correctAnswer, '驾驶机动车在城市快速路上倒车的');
    });

    test('圈码序列选项不得被首字切碎（真实试捕样本 排序题）', () {
      // 用户真实试捕：B 选项原文是「②①③④」，解析后只剩「②」，
      // 于是答案 B 也被映射成「②」。
      // 四条选项首字里「①」「②」各出现 2 次，黏连切分把序列在每个
      // 重复首字处切开，「②①③④」被拆成「②」「①③④」两段。
      const raw =
          '答题\n'
          '背题\n'
          '视频\n'
          '设置\n'
          'x 驾驶机动车停车后下车的操作，以下正确的做法顺序是什么？'
          '①观察后视镜并确认后视镜盲区安全②确保车辆停稳'
          '③确认安全后告知乘车人④开关车门不得妨碍其他车辆和行人通行x\n'
          '①③④\n'
          '②①③④\n'
          '①②\n'
          '②④\n'
          '答案 B\n'
          '速记口诀\n'
          '本题技巧';
      final r = OcrQuizParser.parse(raw);
      expect(r.options, hasLength(4));
      expect(r.options[0], '①③④');
      expect(r.options[1], '②①③④');
      expect(r.options[2], '①②');
      expect(r.options[3], '②④');
      // 答案 B → 第 1 个选项，必须是完整序列而非被切碎的首项。
      expect(r.correctAnswer, '②①③④');
      expect(r.questionType, 'single_choice');
    });

    test('选项数与原文行数一致时不得再做黏连切分（真实试捕样本 记12分题）', () {
      // 用户真实试捕：原文 4 条选项，解析出 5 条 —— B 被切成
      // 「代替实际机动车」+「驾驶人接受交通违法行为处罚和记分牟取经济利益的」，
      // 于是答案 B 只剩前半段「代替实际机动车」。
      // 根因：四条选项里「驾」作首字出现 3 次被选为切分标记，
      // 而 B 选项正文内部也含「驾」（…机动车驾驶人…），在那里被切开。
      // 每条选项各占一行、行数已经合法时，本来就不存在黏连，不该再切。
      const raw =
          '答题\n'
          '背题\n'
          '视频\n'
          '设置\n'
          'x x 下列交通违法行为，一次记12分的是什么？x\n'
          '驾驶货车运载爆炸物品，未按指定的时间、路线行驶的\n'
          '代替实际机动车驾驶人接受交通违法行为处罚和记分牟取经济利益的\n'
          '驾驶小型客车在高速公路上行驶超过规定时速百分之二十以上未达到百分之五十的\n'
          '驾驶机动车运载超限的不可解体的物品，未按指定时间、路线行驶的\n'
          '答案 B\n'
          '速记口诀\n'
          '本题技巧\n'
          '适用于4道题\n'
          '他人代扣牟利，三倍罚款12分.';
      final r = OcrQuizParser.parse(raw);
      expect(r.question, '下列交通违法行为，一次记12分的是什么？');
      expect(r.options, hasLength(4));
      expect(r.options[0], '驾驶货车运载爆炸物品，未按指定的时间、路线行驶的');
      expect(r.options[1], '代替实际机动车驾驶人接受交通违法行为处罚和记分牟取经济利益的');
      expect(r.options[2], '驾驶小型客车在高速公路上行驶超过规定时速百分之二十以上未达到百分之五十的');
      expect(r.options[3], '驾驶机动车运载超限的不可解体的物品，未按指定时间、路线行驶的');
      // 答案 B → 完整的第 1 条选项，不能只剩被切碎的前半段。
      expect(r.correctAnswer, '代替实际机动车驾驶人接受交通违法行为处罚和记分牟取经济利益的');
      expect(r.questionType, 'single_choice');
    });

    test('答案与解析被 OCR 合并为同一行时应分割', () {
      const raw = '''
夜间通过没有交通信号灯的路口应如何操作？
A. 加速通过
B. 减速观察
C. 鸣笛通过
D. 停车等待
答案：B 解析：夜间视线差，应减速观察。
''';
      final r = OcrQuizParser.parse(raw);
      expect(r.correctAnswer, '减速观察');
      expect(r.analysis, contains('夜间视线差'));
      expect(r.correctAnswer, isNot(contains('解析')));
    });
  });
}
