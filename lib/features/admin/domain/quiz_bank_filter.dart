import 'quiz_bank_models.dart';
import 'quiz_thumb_image_source.dart';

/// 筛选维度。首屏的生效条件 chip 靠它知道叉掉时该清哪一项。
enum QuizFilterDimension { status, image, type, query }

/// 一条生效中的筛选条件，供首屏渲染成可删除 chip。
class QuizFilterLabel {
  const QuizFilterLabel(this.text, this.dimension);

  final String text;
  final QuizFilterDimension dimension;
}

/// 题库列表筛选条件。
enum QuizImageFilter {
  any('全部'),
  withImage('有图'),
  withoutImage('无图');

  const QuizImageFilter(this.label);

  final String label;
}

/// 题型筛选。
///
/// 服务端 `type` 字段取值不统一（`single_choice` / `single` / `判断题` 都出现过），
/// 所以按别名集合匹配，而不是字符串相等。
enum QuizTypeFilter {
  any('全部题型', {}),
  judge('判断', {'judge', 'judgement', 'judgment', 'true_false', 'boolean', '判断', '判断题'}),
  single('单选', {'single_choice', 'single', 'choice', 'radio', '单选', '单选题'}),
  multi('多选', {'multi_choice', 'multiple_choice', 'multi', 'checkbox', '多选', '多选题'}),
  sort('排序', {'sort', 'sorting', 'order', 'sequence', '排序', '排序题'}),
  fill('填空', {'fill', 'fill_blank', 'blank', '填空', '填空题'});

  const QuizTypeFilter(this.label, this.aliases);

  final String label;
  final Set<String> aliases;
}

/// 审核状态筛选。
enum QuizStatusFilter {
  any('全部状态', {}),
  approved('已通过', {'approved', 'active', 'published', 'ok'}),
  pending('待审核', {'pending', 'pending_review', 'review'}),
  rejected('已拒绝', {'rejected', 'denied'});

  const QuizStatusFilter(this.label, this.aliases);

  final String label;
  final Set<String> aliases;
}

/// 题库筛选器：纯函数，便于单测。
class QuizBankFilter {
  const QuizBankFilter({
    this.image = QuizImageFilter.any,
    this.type = QuizTypeFilter.any,
    this.status = QuizStatusFilter.any,
    this.query = '',
    this.base = '',
  });

  final QuizImageFilter image;
  final QuizTypeFilter type;
  final QuizStatusFilter status;
  final String query;

  /// 服务器地址，用于把相对路径题图解析成完整 URL 再判定有无图。
  /// 不参与 isActive / activeCount —— 它是解析上下文，不是筛选条件。
  final String base;

  bool get isActive =>
      image != QuizImageFilter.any ||
      type != QuizTypeFilter.any ||
      status != QuizStatusFilter.any;

  /// 当前生效了几个条件。首屏「筛选」按钮上的角标用它，
  /// 让人不点开就知道列表是被过滤过的。
  int get activeCount {
    var n = 0;
    if (status != QuizStatusFilter.any) n++;
    if (image != QuizImageFilter.any) n++;
    if (type != QuizTypeFilter.any) n++;
    if (query.trim().isNotEmpty) n++;
    return n;
  }

  /// 生效条件的可删除标签，顺序固定为 状态 → 图片 → 题型 → 搜索。
  /// 首屏把它们渲染成一行 chip，每个能单独叉掉，不用进弹层。
  List<QuizFilterLabel> get activeLabels => [
    if (status != QuizStatusFilter.any)
      QuizFilterLabel(status.label, QuizFilterDimension.status),
    if (image != QuizImageFilter.any)
      QuizFilterLabel(image.label, QuizFilterDimension.image),
    if (type != QuizTypeFilter.any)
      QuizFilterLabel(type.label, QuizFilterDimension.type),
    if (query.trim().isNotEmpty)
      QuizFilterLabel('搜索：${query.trim()}', QuizFilterDimension.query),
  ];

  /// 只清掉一个维度，其余保持不动。
  QuizBankFilter without(QuizFilterDimension dimension) => switch (dimension) {
    QuizFilterDimension.status => copyWith(status: QuizStatusFilter.any),
    QuizFilterDimension.image => copyWith(image: QuizImageFilter.any),
    QuizFilterDimension.type => copyWith(type: QuizTypeFilter.any),
    QuizFilterDimension.query => copyWith(query: ''),
  };

  QuizBankFilter clearAll() => QuizBankFilter(base: base);

  QuizBankFilter copyWith({
    QuizImageFilter? image,
    QuizTypeFilter? type,
    QuizStatusFilter? status,
    String? query,
    String? base,
  }) => QuizBankFilter(
    image: image ?? this.image,
    type: type ?? this.type,
    status: status ?? this.status,
    query: query ?? this.query,
    base: base ?? this.base,
  );

  /// 判断单题是否命中当前筛选。
  bool matches(QuizBankQuestion q) {
    if (!_matchesImage(q)) return false;
    if (!_matchesType(q)) return false;
    if (!_matchesStatus(q)) return false;
    return _matchesQuery(q);
  }

  List<QuizBankQuestion> apply(List<QuizBankQuestion> items) =>
      items.where(matches).toList(growable: false);

  bool _matchesImage(QuizBankQuestion q) {
    // 和 imageCounts 用同一套判定，否则「有图 (N)」点进去出来的条数对不上。
    final has = hasDisplayableImage(q.image, base: base);
    return switch (image) {
      QuizImageFilter.any => true,
      QuizImageFilter.withImage => has,
      QuizImageFilter.withoutImage => !has,
    };
  }

  /// 这张图最终能不能真的画出来（而不是降级成占位图）。
  ///
  /// [base] 是服务器地址，相对路径（生产库里的 `/api/quiz/images/xxx`）
  /// 必须靠它才能解析成完整 URL；不传就会被当成脏数据判成无图。
  static bool hasDisplayableImage(String image, {String base = ''}) {
    final kind = QuizThumbImageSource.parse(image, base: base).kind;
    return kind == QuizThumbKind.network || kind == QuizThumbKind.bytes;
  }

  bool _matchesType(QuizBankQuestion q) {
    if (type == QuizTypeFilter.any) return true;
    final raw = q.type.trim().toLowerCase();
    if (type.aliases.contains(raw)) return true;
    // 兜底：服务端没给可识别 type 时，用选项结构反推。
    if (raw.isEmpty || !_allKnownAliases.contains(raw)) {
      return _inferType(q) == type;
    }
    return false;
  }

  bool _matchesStatus(QuizBankQuestion q) {
    if (status == QuizStatusFilter.any) return true;
    return status.aliases.contains(q.status.trim().toLowerCase());
  }

  bool _matchesQuery(QuizBankQuestion q) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    if (q.question.toLowerCase().contains(needle)) return true;
    if (q.answer.toLowerCase().contains(needle)) return true;
    if (q.category.toLowerCase().contains(needle)) return true;
    if (q.explanation.toLowerCase().contains(needle)) return true;
    if (q.options.any((o) => o.toLowerCase().contains(needle))) return true;
    return q.tags.any((t) => t.toLowerCase().contains(needle));
  }

  static final _allKnownAliases = {
    for (final t in QuizTypeFilter.values) ...t.aliases,
  };

  /// 从选项结构反推题型：两个选项且为判断词 → 判断题；
  /// 答案含多个字母 → 多选；否则单选。
  static QuizTypeFilter _inferType(QuizBankQuestion q) {
    final opts = q.options.map((o) => o.trim()).toList();
    if (opts.length == 2) {
      const judgeWords = {'正确', '错误', '对', '错', '是', '否', 'true', 'false'};
      final normalized = opts.map((o) => o.toLowerCase()).toSet();
      if (normalized.every(
        (o) => judgeWords.contains(o) || judgeWords.any(o.contains),
      )) {
        return QuizTypeFilter.judge;
      }
    }
    final letters = RegExp(
      r'[A-Za-z]',
    ).allMatches(q.answer.replaceAll(RegExp(r'[^A-Za-z]'), '')).length;
    if (letters >= 2) return QuizTypeFilter.multi;
    return QuizTypeFilter.single;
  }

  /// 统计各筛选维度的命中数，用于在 UI 上显示徽标。
  static Map<QuizImageFilter, int> imageCounts(
    List<QuizBankQuestion> items, {
    String base = '',
  }) {
    var withImage = 0;
    for (final q in items) {
      // 只有真能画出来的才算「有图」：断链或脏 data URL 会让计数虚高。
      // base 必须传，否则生产库里的相对路径题图会被全判成无图。
      if (hasDisplayableImage(q.image, base: base)) {
        withImage++;
      }
    }
    return {
      QuizImageFilter.any: items.length,
      QuizImageFilter.withImage: withImage,
      QuizImageFilter.withoutImage: items.length - withImage,
    };
  }
}
