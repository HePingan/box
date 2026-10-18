// 集名拆解：序号 vs 其余文字。
//
// 这层是纯函数，专门提出来测 —— 因为站点的集名格式完全不可控，
// 而"抽错序号"比"显示原名"更糟：用户点第 4 集得到的可能是第 40 集。
import 'package:box/video/pages/detail/episode_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('标准形状', () {
    test('第04集 → 04，无副注', () {
      final p = parseEpisodeLabel('第04集');
      expect(p.number, '04');
      expect(p.rest, '');
    });

    test('第4集 → 04（补零，与第04集统一）', () {
      expect(parseEpisodeLabel('第4集').number, '04');
      expect(parseEpisodeLabel('第4话').number, '04');
      expect(parseEpisodeLabel('第4期').number, '04');
    });

    test('纯数字 04 → 04', () {
      expect(parseEpisodeLabel('04').number, '04');
      expect(parseEpisodeLabel('4').number, '04');
    });

    test('三位数不补零：104 → 104', () {
      expect(parseEpisodeLabel('第104集').number, '104');
    });
  });

  group('带副注', () {
    test('第04集 高清 → 04 / 高清', () {
      final p = parseEpisodeLabel('第04集 高清');
      expect(p.number, '04');
      expect(p.rest, '高清');
    });

    test('第4集-中字 → 04 / 中字（剥掉前导横线）', () {
      final p = parseEpisodeLabel('第4集-中字');
      expect(p.number, '04');
      expect(p.rest, '中字');
    });

    test('天才女友 第04集 → 04 / 天才女友', () {
      final p = parseEpisodeLabel('天才女友 第04集');
      expect(p.number, '04');
      expect(p.rest, '天才女友');
    });

    test('04-HD → 04 / HD', () {
      final p = parseEpisodeLabel('04-HD');
      expect(p.number, '04');
      expect(p.rest, 'HD');
    });

    test('只取第一个数字段（第04集 第2部分 → 04）', () {
      expect(parseEpisodeLabel('第04集 第2部分').number, '04');
    });
  });

  group('不该误判为集号的', () {
    test('年份 2026 不当集号', () {
      final p = parseEpisodeLabel('2026 高清');
      expect(p.number, isNull, reason: '4 位数且 ≥1900 视为年份');
    });

    test('1900 以上都不当集号', () {
      expect(parseEpisodeLabel('1900').number, isNull);
      expect(parseEpisodeLabel('2049').number, isNull);
    });

    test('1899 仍当集号（虽然现实中不会有）', () {
      expect(parseEpisodeLabel('1899').number, '1899');
    });
  });

  group('抽不到序号时', () {
    test('纯文字 → number 为 null，rest 是原名', () {
      final p = parseEpisodeLabel('先导片');
      expect(p.number, isNull);
      expect(p.rest, '先导片');
    });

    test('空串', () {
      final p = parseEpisodeLabel('');
      expect(p.number, isNull);
      expect(p.rest, '');
    });

    test('只有空白', () {
      final p = parseEpisodeLabel('   ');
      expect(p.number, isNull);
      expect(p.rest, '');
    });
  });

  group('清洗', () {
    test('多余空白被压缩', () {
      expect(parseEpisodeLabel('第04集   高清   版').rest, '高清 版');
    });

    test('首尾分隔符被剥掉', () {
      expect(parseEpisodeLabel('第04集：').rest, '');
      expect(parseEpisodeLabel('第04集 |').rest, '');
    });

    test('括号内容保留（那是有效信息）', () {
      expect(parseEpisodeLabel('第04集（高清）').rest, '（高清）');
    });
  });

  group('hasNumber', () {
    test('抽到时为 true，否则 false', () {
      expect(parseEpisodeLabel('第04集').hasNumber, isTrue);
      expect(parseEpisodeLabel('先导片').hasNumber, isFalse);
    });
  });

  group('线路名：技术名识别', () {
    test('lzm3u8 / liangzi / quantum 判为技术名', () {
      expect(looksLikeTechnicalLineName('lzm3u8'), isTrue);
      expect(looksLikeTechnicalLineName('liangzi'), isTrue);
      expect(looksLikeTechnicalLineName('quantum'), isTrue);
      expect(looksLikeTechnicalLineName('line1'), isTrue);
    });

    test('中文名判为人话（不该被改掉）', () {
      expect(looksLikeTechnicalLineName('量子资源'), isFalse);
      expect(looksLikeTechnicalLineName('量子影视'), isFalse);
      expect(looksLikeTechnicalLineName('备用线路'), isFalse);
    });

    test('清晰度标记也算人话', () {
      expect(looksLikeTechnicalLineName('HD'), isFalse);
      expect(looksLikeTechnicalLineName('1080P'), isFalse);
      expect(looksLikeTechnicalLineName('4K'), isFalse);
    });

    test('空串不算技术名', () {
      expect(looksLikeTechnicalLineName(''), isFalse);
      expect(looksLikeTechnicalLineName('   '), isFalse);
    });
  });

  group('线路名：显示名与副注', () {
    test('技术名 → 线路 N + 原名副注', () {
      expect(lineDisplayName('lzm3u8', 0), '线路 1');
      expect(lineDisplayName('liangzi', 1), '线路 2');
      expect(lineSubName('lzm3u8'), 'lzm3u8');
      expect(lineSubName('liangzi'), 'liangzi');
    });

    test('中文名 → 原样显示，无副注', () {
      expect(lineDisplayName('量子资源', 0), '量子资源');
      expect(lineSubName('量子资源'), '');
    });

    test('空名给个兜底编号', () {
      expect(lineDisplayName('', 2), '线路 3');
      expect(lineSubName(''), '');
    });
  });
}
