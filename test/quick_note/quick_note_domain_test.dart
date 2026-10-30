import 'package:box/features/extensions/plugins/quick_note/domain/quick_note.dart';
import 'package:flutter_test/flutter_test.dart';

/// 便签的命名/解析规则。这些纯函数决定了「远程存储里长什么样」，
/// 一旦写歪，用户会在文件管理器里看到一堆认不出来的文件名。
void main() {
  group('quickNoteSlug', () {
    test('保留中文，空白折叠成连字符', () {
      expect(quickNoteSlug('买 牛奶'), '买-牛奶');
      expect(quickNoteSlug('  前后空格  '), '前后空格');
      expect(quickNoteSlug('a   b'), 'a-b');
    });

    test('路径分隔符与非法字符被替换（绝不能在文件名里造出目录）', () {
      expect(quickNoteSlug('a/b'), 'a-b');
      expect(quickNoteSlug('a\\b'), 'a-b');
      expect(quickNoteSlug('a:b*c?d"e<f>g|h'), 'a-b-c-d-e-f-g-h');
      expect(quickNoteSlug('a/b'.replaceAll('/', '-')), 'a-b');
      expect(quickNoteSlug('../etc/passwd'), 'etc-passwd');
    });

    test('连续连字符折叠、首尾连字符与点去掉', () {
      expect(quickNoteSlug('a--b'), 'a-b');
      expect(quickNoteSlug('-abc-'), 'abc');
      expect(quickNoteSlug('.hidden'), 'hidden');
    });

    test('超长截断到上限（按字符不是按字节，中文别被切一半）', () {
      final long = '一' * 40;
      final slug = quickNoteSlug(long);
      expect(slug.runes.length, kQuickNoteTitleMaxChars);
      expect(slug, '一' * kQuickNoteTitleMaxChars);
    });

    test('全是非法字符 → 空串（由上层兜「便签」）', () {
      expect(quickNoteSlug('///'), '');
    });
  });

  group('buildQuickNoteFileName', () {
    final at = DateTime(2026, 10, 30, 21, 5);

    test('格式：时间前缀 + 标题 + .md', () {
      expect(
        buildQuickNoteFileName(title: '买牛奶', at: at),
        '2026-10-30-2105-买牛奶.md',
      );
    });

    test('标题为空时用「便签」兜底，不留纯时间戳文件名', () {
      expect(
        buildQuickNoteFileName(title: '   ', at: at),
        '2026-10-30-2105-便签.md',
      );
    });

    test('同分钟连写多条：-2、-3 递增，不覆盖前一条', () {
      final first = buildQuickNoteFileName(title: '想法', at: at);
      final second = buildQuickNoteFileName(
        title: '想法',
        at: at,
        existing: {first},
      );
      final third = buildQuickNoteFileName(
        title: '想法',
        at: at,
        existing: {first, second},
      );
      expect(second, '2026-10-30-2105-想法-2.md');
      expect(third, '2026-10-30-2105-想法-3.md');
    });
  });

  group('quickNoteTitleFromBody', () {
    test('取第一段非空文本的首行', () {
      expect(quickNoteTitleFromBody('\n\n  买牛奶  \n顺路取快递'), '买牛奶');
    });

    test('去掉 markdown 标题井号', () {
      expect(quickNoteTitleFromBody('### 待办'), '待办');
    });

    test('超长按上限截断', () {
      final title = quickNoteTitleFromBody('字' * 50);
      expect(title.runes.length, kQuickNoteTitleMaxChars);
    });

    test('全空白 → fallback（空便签不该被保存，但函数自身要稳）', () {
      expect(quickNoteTitleFromBody('   \n\n  '), '无标题');
      expect(quickNoteTitleFromBody('', fallback: '空'), '空');
    });
  });

  group('quickNoteTitleFromFileName', () {
    test('去掉时间前缀与扩展名，连字符还原成空格', () {
      expect(
        quickNoteTitleFromFileName('2026-10-30-2105-买牛奶.md'),
        '买牛奶',
      );
      expect(
        quickNoteTitleFromFileName('2026-10-30-2105-买-牛奶.md'),
        '买 牛奶',
        reason: 'slug 里的连字符还原成空格（有损，仅影响列表展示）',
      );
    });

    test('没有时间前缀也能读（用户手放的 .md 也算便签）', () {
      expect(quickNoteTitleFromFileName('随手记.md'), '随手记');
    });

    test('.txt 同样认，且大小写不敏感', () {
      expect(quickNoteTitleFromFileName('2026-10-30-2105-Note.TXT'), 'Note');
    });

    test('解析不出东西时给「无标题」，不返回空串', () {
      expect(quickNoteTitleFromFileName('2026-10-30-2105-.md'), '无标题');
    });
  });

  group('其它辅助', () {
    test('isQuickNoteFileName 只认 .md / .txt', () {
      expect(isQuickNoteFileName('a.md'), isTrue);
      expect(isQuickNoteFileName('a.MD'), isTrue);
      expect(isQuickNoteFileName('a.txt'), isTrue);
      expect(isQuickNoteFileName('a.jpg'), isFalse);
      expect(isQuickNoteFileName('md'), isFalse);
    });

    test('排序按文件名倒序 = 最新在前', () {
      final names = [
        '2026-10-30-0900-a.md',
        '2026-10-31-1200-b.md',
        '2026-10-30-2100-c.md',
      ]..sort(compareQuickNoteNames);
      expect(names.first, startsWith('2026-10-31-1200'));
      expect(names.last, startsWith('2026-10-30-0900'));
    });

    test('大小文案', () {
      expect(formatQuickNoteSize(0), '空');
      expect(formatQuickNoteSize(512), '512 B');
      expect(formatQuickNoteSize(2048), '2.0 KB');
      expect(formatQuickNoteSize(20480), '20 KB');
    });

    test('便签目录固定为 box-notes（用户能在远程存储里一眼找到）', () {
      expect(kQuickNoteDir, 'box-notes');
    });
  });
}
