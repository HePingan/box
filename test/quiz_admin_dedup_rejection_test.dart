import 'package:box/features/admin/domain/quiz_dedup_rejection.dart';
import 'package:flutter_test/flutter_test.dart';

/// 服务端把「更新已有题目」当成「新建题目」校验唯一性，
/// 补图与重建两条路都被同一套查重封死：
///   PATCH -> 题干与完整选项集已存在，不能合并覆盖
///   POST  -> 题干与完整选项集已存在，不能重复创建
///
/// 客户端无法绕过（PATCH 只发 image 一个字段也照样被拒），
/// 所以只需准确识别这类拒绝，给出「这是服务端限制」的提示，
/// 不要让用户白点第二次。
void main() {
  group('识别查重拒绝', () {
    test('PATCH 合并覆盖被拒', () {
      expect(
        QuizDedupRejection.matches('题干与完整选项集已存在，不能合并覆盖'),
        isTrue,
      );
    });

    test('POST 重复创建被拒', () {
      expect(
        QuizDedupRejection.matches('题干与完整选项集已存在，不能重复创建'),
        isTrue,
      );
    });

    test('少「集」字的旧文案也认', () {
      expect(
        QuizDedupRejection.matches('题干与完整选项已存在，不能合并覆盖'),
        isTrue,
      );
    });

    test('包在 Exception 里也认', () {
      expect(
        QuizDedupRejection.matches(
          Exception('请求失败(409)：题干与完整选项集已存在，不能合并覆盖').toString(),
        ),
        isTrue,
      );
    });

    test('网络错误不算查重', () {
      expect(QuizDedupRejection.matches('SocketException: 连接超时'), isFalse);
    });

    test('鉴权失败不算查重', () {
      expect(QuizDedupRejection.matches('请使用管理员账号登录后操作。'), isFalse);
    });

    test('其它 409 不算查重', () {
      expect(QuizDedupRejection.matches('分类名已存在'), isFalse);
    });
  });

  group('提示文案', () {
    test('说明是服务端限制并给出修复点', () {
      final text = QuizDedupRejection.explain('题干与完整选项集已存在，不能合并覆盖');
      expect(text, contains('服务端'));
      expect(text, contains('PATCH /admin/quiz/questions/:id'));
      expect(
        text,
        contains('排除'),
        reason: '要讲清后端该怎么修：查重排除自身那条记录',
      );
    });

    test('原始报错保留在文案里，便于转给后端', () {
      const raw = '题干与完整选项集已存在，不能合并覆盖';
      expect(QuizDedupRejection.explain(raw), contains(raw));
    });

    test('不再暗示用户重试或重建', () {
      final text = QuizDedupRejection.explain('题干与完整选项集已存在，不能合并覆盖');
      expect(text, isNot(contains('重试')));
      expect(text, isNot(contains('重建')));
    });
  });
}
