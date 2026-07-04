/// 内置词表词典源
library;

import '../models/dictionary_definition.dart';
import '../models/dictionary_source.dart';

/// 内置常用生僻字词表（~60 条，含拼音+释义）
class BuiltInDictionarySource extends DictionarySource {
  BuiltInDictionarySource();

  @override
  String get name => '内置词表';

  @override
  String get id => 'built_in';

  static const _words = <String, String>{
    // 双字词
    '觊觎': 'jì yú | 希望得到（不该得到的东西）',
    '龃龉': 'jǔ yǔ | 上下牙齿不齐；比喻意见不合',
    '囹圄': 'líng yǔ | 监狱',
    '魑魅': 'chī mèi | 传说中山林里害人的怪物；比喻坏人',
    '蹉跎': 'cuō tuó | 虚度光阴；把时光白白耽误过去',
    '旖旎': 'yǐ nǐ | 柔和美好；多形容景物',
    '迤逦': 'yǐ lǐ | 曲折连绵',
    '澎湃': 'péng pài | 形容波浪互相撞击；比喻声势浩大',
    '踌躇': 'chóu chú | 犹豫不决；得意的样子',
    '徘徊': 'pái huái | 在一个地方来回地走；比喻犹豫不决',
    '激湍': 'jī tuān | 急流',
    '氤氲': 'yīn yūn | 形容烟或云气浓郁',
    '缱绻': 'qiǎn quǎn | 形容情意缠绵，难舍难分',
    '颟顸': 'mān hān | 糊涂；不明事理',
    '纨绔': 'wán kù | 富贵人家子弟穿的细绢做的裤子；指游手好闲的富家子弟',
    '簪缨': 'zān yīng | 古代达官贵人的冠饰；借指显贵',
    '耄耋': 'mào dié | 八九十岁；指老年',
    '饕餮': 'tāo tiè | 传说中的凶恶贪食的野兽；比喻贪吃或凶恶的人',
    '睥睨': 'pì nì | 眼睛斜着看，表示傲视或厌恶',
    '羸弱': 'léi ruò | 瘦弱',
    '婀娜': 'ē nuó | 形容姿态柔美轻盈',
    '娉婷': 'pīng tíng | 形容女子的姿态美',
    '虬龙': 'qiú lóng | 古代传说中有角的小龙',
    '麒麟': 'qí lín | 传说中的神兽',
    '鸾凤': 'luán fèng | 传说中凤凰一类的鸟',
    '寰宇': 'huán yǔ | 广大的地域；宇宙',
    '穹顶': 'qióng dǐng | 隆起如天空的顶部',
    '静谧': 'jìng mì | 安宁；平静',
    '和煦': 'hé xù | 温暖；和乐的样子',
    '博弈': 'bó yì | 下棋；比喻为谋取利益而竞争',
    '杀戮': 'shā lù | 杀害（多指大量地）',
    '殇殁': 'shāng mò | 死亡（多指非正常死亡）',
    '恪守': 'kè shǒu | 严格遵守',
    '笃行': 'dǔ xíng | 忠实地践行',
    '睿智': 'ruì zhì | 有智慧；看得深远',
    '懿德': 'yì dé | 美德',
    '桀骜': 'jié ào | 凶暴倔强；不驯服',

    // 单字
    '姝': 'shū | 形容女子美丽；美女',
    '嫣': 'yān | 形容笑容美好',
    '瑾': 'jǐn | 美玉；比喻美德',
    '珏': 'jué | 合在一起的两块玉',
    '晗': 'hán | 天将明；天色将亮',
    '曦': 'xī | 晨光；阳光',
    '谧': 'mì | 安宁；平静',
    '煦': 'xù | 温暖；和乐的样子',
    '飒': 'sà | 形容风声；豪迈矫健',
    '弈': 'yì | 下棋；博弈',
    '戮': 'lù | 杀；合、并',
    '弑': 'shì | 臣杀君；子杀父',
    '殇': 'shāng | 未成年而死；为国战死者',
    '怏': 'yàng | 不满意；不高兴',
    '愠': 'yùn | 含怒；怨恨',
    '恸': 'tòng | 极悲哀；大哭',
    '忡': 'chōng | 忧愁；忧虑的样子',
    '恪': 'kè | 恭敬；谨慎',
    '笃': 'dǔ | 忠实；专一；深厚',
    '睿': 'ruì | 有智慧；看得深远',
    '懿': 'yì | 美好；多指品德',
  };

  @override
  Future<DictionaryDefinition> lookup(String word) async {
    final trimmed = word.trim();
    if (trimmed.isEmpty) {
      return DictionaryDefinition(word: '', source: name);
    }

    // 精确匹配
    final exact = _words[trimmed];
    if (exact != null) {
      return _parse(trimmed, exact);
    }

    // 单字前缀匹配
    if (trimmed.length == 1) {
      for (final entry in _words.entries) {
        if (entry.key.startsWith(trimmed)) {
          final parts = entry.value.split(' | ');
          return DictionaryDefinition(
            word: trimmed,
            phonetic: parts.isNotEmpty ? parts[0].split(' ').firstOrNull ?? '' : '',
            senses: [
              DictionarySense(definition: parts.length > 1 ? parts[1] : entry.value),
            ],
            source: name,
          );
        }
      }
    }

    return DictionaryDefinition(word: trimmed, source: name);
  }

  DictionaryDefinition _parse(String word, String raw) {
    final parts = raw.split(' | ');
    return DictionaryDefinition(
      word: word,
      phonetic: parts.isNotEmpty ? parts[0] : '',
      senses: [
        DictionarySense(definition: parts.length > 1 ? parts[1] : raw),
      ],
      source: name,
    );
  }
}
