/// 阅读器词典服务
///
/// 支持中英文查词。优先调用在线 API，失败时回退到内置常用词表。
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

/// 查询结果
class WordDefinition {
  final String word;
  final String phonetic;
  final List<DefinitionItem> definitions;
  final String source;

  const WordDefinition({
    required this.word,
    this.phonetic = '',
    this.definitions = const [],
    this.source = '',
  });

  bool get isEmpty => definitions.isEmpty && phonetic.isEmpty;
}

class DefinitionItem {
  final String partOfSpeech;
  final String definition;
  final String? example;

  const DefinitionItem({
    this.partOfSpeech = '',
    required this.definition,
    this.example,
  });
}

/// 词典服务
class ReaderDictionaryService {
  const ReaderDictionaryService();

  static const _builtInWords = <String, List<String>>{
    // 常用文言/生僻字
    '觊觎': ['jì yú', '希望得到（不该得到的东西）'],
    '龃龉': ['jǔ yǔ', '上下牙齿不齐；比喻意见不合'],
    '囹圄': ['líng yǔ', '监狱'],
    '魑魅': ['chī mèi', '传说中山林里害人的怪物；比喻坏人'],
    '蹉跎': ['cuō tuó', '虚度光阴；把时光白白耽误过去'],
    '旖旎': ['yǐ nǐ', '柔和美好；多形容景物'],
    '迤逦': ['yǐ lǐ', '曲折连绵'],
    '澎湃': ['péng pài', '形容波浪互相撞击；比喻声势浩大'],
    '踌躇': ['chóu chú', '犹豫不决；得意的样子'],
    '徘徊': ['pái huái', '在一个地方来回地走；比喻犹豫不决'],
    '激湍': ['jī tuān', '急流'],
    '氤氲': ['yīn yūn', '形容烟或云气浓郁'],
    '缱绻': ['qiǎn quǎn', '形容情意缠绵，难舍难分'],
    '颟顸': ['mān hān', '糊涂；不明事理'],
    '纨绔': ['wán kù', '富贵人家子弟穿的细绢做成的裤子；指游手好闲的富家子弟'],
    '簪缨': ['zān yīng', '古代达官贵人的冠饰；借指显贵'],
    '耄耋': ['mào dié', '八九十岁；指老年'],
    '饕餮': ['tāo tiè', '传说中的凶恶贪食的野兽；比喻贪吃或凶恶的人'],
    '睥睨': ['pì nì', '眼睛斜着看，表示傲视或厌恶'],
    '羸弱': ['léi ruò', '瘦弱'],
    '姝': ['shū', '形容女子美丽；美女'],
    '嫣': ['yān', '形容笑容美好'],
    '婀娜': ['ē nuó', '形容姿态柔美轻盈'],
    '娉婷': ['pīng tíng', '形容女子的姿态美'],
    '虬': ['qiú', '古代传说中的有角的小龙；形容盘曲'],
    '麟': ['lín', '麒麟，传说中的神兽'],
    '鸾': ['luán', '传说中凤凰一类的鸟'],
    '瑾': ['jǐn', '美玉；比喻美德'],
    '珏': ['jué', '合在一起的两块玉'],
    '晗': ['hán', '天将明；天色将亮'],
    '曦': ['xī', '晨光；阳光'],
    '寰': ['huán', '广大的地域；宇宙'],
    '穹': ['qióng', '隆起的样子；天空'],
    '谧': ['mì', '安宁；平静'],
    '煦': ['xù', '温暖；和乐的样子'],
    '飒': ['sà', '形容风声；豪迈矫健'],
    '弈': ['yì', '下棋；博弈'],
    '戮': ['lù', '杀；合、并'],
    '弑': ['shì', '臣杀君；子杀父'],
    '殁': ['mò', '死；去世'],
    '殇': ['shāng', '未成年而死；为国战死者'],
    '惘': ['wǎng', '失意；迷惑'],
    '怏': ['yàng', '不满意；不高兴'],
    '愠': ['yùn', '含怒；怨恨'],
    '恸': ['tòng', '极悲哀；大哭'],
    '忡': ['chōng', '忧愁；忧虑的样子'],
    '恪': ['kè', '恭敬；谨慎'],
    '笃': ['dǔ', '忠实；专一；深厚'],
    '睿': ['ruì', '有智慧；看得深远'],
    '懿': ['yì', '美好；多指品德'],
    '桀': ['jié', '凶暴；古同"杰"'],
    '纣': ['zhòu', '商代最后一个君主；泛指暴君'],
    '尧': ['yáo', '传说中上古帝王名'],
    '舜': ['shùn', '传说中上古帝王名'],
    '禹': ['yǔ', '传说中夏代第一位君主'],
  };

  /// 查词
  Future<WordDefinition> lookup(String word) async {
    final trimmed = word.trim();
    if (trimmed.isEmpty) {
      return const WordDefinition(word: '', source: '');
    }

    // 1. 尝试在线 API（有道词典）
    try {
      final result = await _lookupOnline(trimmed);
      if (!result.isEmpty) return result;
    } catch (_) {
      // 静默失败，走内置
    }

    // 2. 内置词表
    final builtIn = _builtInWords[trimmed];
    if (builtIn != null) {
      return WordDefinition(
        word: trimmed,
        phonetic: builtIn[0],
        definitions: [
          DefinitionItem(partOfSpeech: '', definition: builtIn[1]),
        ],
        source: '内置词表',
      );
    }

    // 3. 单字处理
    if (trimmed.length == 1) {
      final charResult = _builtInWords.entries
          .where((e) => e.key.startsWith(trimmed))
          .toList();
      if (charResult.isNotEmpty) {
        final entry = charResult.first;
        return WordDefinition(
          word: trimmed,
          phonetic: entry.value[0].split(' ').firstOrNull ?? '',
          definitions: [
            DefinitionItem(partOfSpeech: '', definition: entry.value[1]),
          ],
          source: '内置词表',
        );
      }
    }

    // 4. 无匹配
    return WordDefinition(
      word: trimmed,
      source: '',
    );
  }

  /// 在线查词（有道词典公开接口）
  Future<WordDefinition> _lookupOnline(String word) async {
    final uri = Uri.parse(
      'https://dict.youdao.com/suggest?le=eng&num=1&ver=3.0&q=${Uri.encodeComponent(word)}',
    );
    final resp = await http.get(uri, headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    }).timeout(const Duration(seconds: 5));

    if (resp.statusCode != 200) {
      return const WordDefinition(word: '', source: '');
    }

    try {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final entries = body['data']?['entries'] as List?;
      if (entries == null || entries.isEmpty) {
        return const WordDefinition(word: '', source: '');
      }

      final entry = entries[0] as Map<String, dynamic>;
      final explain = entry['explain'] as String? ?? '';
      final entryWord = entry['entry'] as String? ?? word;

      final definitions = explain.isNotEmpty
          ? explain.split('；').map((e) {
              final parts = e.trim().split('　');
              if (parts.length >= 2) {
                return DefinitionItem(
                  partOfSpeech: parts[0],
                  definition: parts.sublist(1).join('　'),
                );
              }
              return DefinitionItem(definition: e.trim());
            }).toList()
          : <DefinitionItem>[];

      // 尝试获取音标（有道 suggest 不直接返回，略过）

      return WordDefinition(
        word: entryWord,
        definitions: definitions,
        source: '有道词典',
      );
    } catch (_) {
      return const WordDefinition(word: '', source: '');
    }
  }
}
