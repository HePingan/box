import 'package:box/features/about/data/legal_documents.dart';
import 'package:flutter_test/flutter_test.dart';

/// 协议稿「已定稿」守卫。
///
/// 由来：协议稿由运营者补充主体信息后定稿（isDraft 置 false）。补充时曾把
/// `false` 误写成 `fales`，那是个编译错误、幸好挡在构建之前；但更危险的一类是
/// **能编译过的**疏漏 —— 比如占位符没删干净、联系邮箱写错格式、
/// 或者改了条款却忘了给版本号 +1（导致老用户不会被要求重新同意）。
/// 这里把这些能自动查的点固定下来。
void main() {
  group('定稿状态', () {
    test('isDraft 为 false：应用内不再显示草稿提示条', () {
      expect(LegalDocuments.isDraft, isFalse);
    });

    test('正文里没有未填写的占位符', () {
      expect(LegalDocuments.hasUnfilledPlaceholders, isFalse);
    });

    test('主体信息三项都已填写且不是明显的假值', () {
      expect(kLegalOperator.trim(), isNotEmpty);
      expect(kLegalContact.trim(), isNotEmpty);
      expect(kLegalEffectiveDate.trim(), isNotEmpty);

      // 编出来的联系方式比留空更糟：用户按它联系不到人。
      for (final fake in ['example.com', 'test@', 'xxx', 'TODO', '待填写']) {
        expect(
          kLegalContact.toLowerCase(),
          isNot(contains(fake.toLowerCase())),
          reason: '联系方式不能是占位/示例值',
        );
      }
    });

    test('联系邮箱是合法邮箱格式', () {
      expect(
        RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(kLegalContact),
        isTrue,
        reason: '协议里的邮箱是用户唯一的申诉通道，格式错了等于没有通道：$kLegalContact',
      );
    });

    test('生效日期用 YYYY-MM-DD，避免 5月1日/1月5日 的跨地区歧义', () {
      expect(
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(kLegalEffectiveDate),
        isTrue,
        reason: '实际值：$kLegalEffectiveDate',
      );
    });
  });

  group('正文完整性', () {
    test('两份文档都有内容，且章节都非空', () {
      expect(LegalDocuments.userAgreement, isNotEmpty);
      expect(LegalDocuments.privacyPolicy, isNotEmpty);

      for (final clause in [
        ...LegalDocuments.userAgreement,
        ...LegalDocuments.privacyPolicy,
      ]) {
        expect(clause.heading.trim(), isNotEmpty);
        expect(
          clause.body,
          isNotEmpty,
          reason: '空章节会在页面上留下一个只有标题的空壳：${clause.heading}',
        );
        for (final line in clause.body) {
          expect(line.trim(), isNotEmpty, reason: '${clause.heading} 有空行条目');
        }
      }
    });

    test('隐私政策必须覆盖法定要点', () {
      final all = LegalDocuments.privacyPolicy
          .expand((c) => [c.heading, ...c.body])
          .join('\n');

      // 这几项是隐私政策的最低要求，缺哪项都容易在审核时被打回。
      for (final topic in ['权限', '账号', '联系', '儿童', '变更']) {
        expect(all, contains(topic), reason: '隐私政策缺少「$topic」相关说明');
      }
    });

    test('OCR 截图上传必须被如实披露', () {
      final all = LegalDocuments.privacyPolicy.expand((c) => c.body).join('\n');

      // 这是全篇最敏感的一条：开启 OCR 搜题后截图会离开设备，
      // 发往用户配置的服务。初稿曾错写成「不会上传」，必须锁住。
      expect(all, contains('OCR'));
      expect(
        all.contains('离开你的设备') || all.contains('上传'),
        isTrue,
        reason: 'OCR 截图会上传到用户配置的服务端，不得写成纯本地处理',
      );
    });

    test('不含"永久免费/绝对安全"这类兜不住的承诺', () {
      final all = [
        ...LegalDocuments.userAgreement.expand((c) => c.body),
        ...LegalDocuments.privacyPolicy.expand((c) => c.body),
      ].join('\n');

      for (final overclaim in ['永久免费', '绝对安全', '永不', '100%']) {
        expect(
          all,
          isNot(contains(overclaim)),
          reason: '协议里的绝对化承诺是要担责的：$overclaim',
        );
      }
    });
  });

  group('版本号', () {
    test('版本号为正数，否则闸门永不生效', () {
      expect(kLegalDocumentsVersion, greaterThan(0));
    });

    test('提醒：条款有实质变更时必须把版本号 +1', () {
      // 这个测试不检查内容哈希（那样每次改错别字都要动版本号，太吵），
      // 只把规则写在这里，让改协议的人在测试列表里看到它。
      expect(kLegalDocumentsVersion, 1,
          reason: '若你刚做了实质性条款变更，请把 kLegalDocumentsVersion +1 '
              '并同步更新此断言 —— 不改版本号，已同意的老用户不会被要求重新确认');
    });
  });
}
