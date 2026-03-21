enum NovelChannel {
  male,
  female,
}

class DiscoverRoute {
  final String groupTitle;
  final String title;
  final String urlTemplate;

  const DiscoverRoute({
    required this.groupTitle,
    required this.title,
    required this.urlTemplate,
  });

  String buildPath(int page) {
    return urlTemplate.replaceAll('{{page}}', '$page');
  }

  String get key => '$groupTitle|$title|$urlTemplate';
}

class DiscoverGroup {
  final String title;
  final List<DiscoverRoute> routes;

  const DiscoverGroup({
    required this.title,
    required this.routes,
  });
}

class QmDiscoverCatalog {
  static const Map<String, int> _rankTypes = {
    '必读榜': 1,
    '潜力榜': 5,
    '完本榜': 2,
    '更新榜': 3,
    '搜索榜': 4,
    '评论榜': 6,
  };

  static const Map<String, String> _maleCategoryIds = {
    '玄幻': 'lejRej',
    '武侠': 'nel5aK',
    '都市': 'mbk5ez',
    '仙侠': 'vbmOeY',
    '军事': 'penRe7',
    '历史': 'xbojag',
    '游戏': 'mep2bM',
    '科幻': 'zbq2dp',
    '轻小说': 'YerEdO',
  };

  static const Map<String, String> _femaleCategoryIds = {
    '现代言情': '9avmeG',
    '古代言情': 'DdwRb1',
    '幻想言情': '7ax9by',
    '青春校园': 'Pdy7aQ',
    '唯美纯爱': 'kazYeJ',
    '同人衍生': '9aAOdv',
  };

  static final List<DiscoverGroup> _maleGroups = <DiscoverGroup>[
    _buildRankGroup(groupTitle: '男频榜单', channel: 1),
    _buildCategoryGroup(
      groupTitle: '男频全部',
      categories: _maleCategoryIds,
      isComplete: null,
    ),
    _buildCategoryGroup(
      groupTitle: '男频完结',
      categories: _maleCategoryIds,
      isComplete: 1,
    ),
    _buildCategoryGroup(
      groupTitle: '男频连载',
      categories: _maleCategoryIds,
      isComplete: 0,
    ),
  ];

  static final List<DiscoverGroup> _femaleGroups = <DiscoverGroup>[
    _buildRankGroup(groupTitle: '女频榜单', channel: 2),
    _buildCategoryGroup(
      groupTitle: '女频全部',
      categories: _femaleCategoryIds,
      isComplete: null,
    ),
    _buildCategoryGroup(
      groupTitle: '女频完结',
      categories: _femaleCategoryIds,
      isComplete: 1,
    ),
    _buildCategoryGroup(
      groupTitle: '女频连载',
      categories: _femaleCategoryIds,
      isComplete: 0,
    ),
  ];

  static DiscoverGroup _buildRankGroup({
    required String groupTitle,
    required int channel,
  }) {
    final routes = <DiscoverRoute>[];
    _rankTypes.forEach((title, type) {
      routes.add(
        DiscoverRoute(
          groupTitle: groupTitle,
          title: title,
          urlTemplate: '/module/rank?type=$type&channel=$channel&page={{page}}',
        ),
      );
    });

    return DiscoverGroup(title: groupTitle, routes: routes);
  }

  static DiscoverGroup _buildCategoryGroup({
    required String groupTitle,
    required Map<String, String> categories,
    required int? isComplete,
  }) {
    final routes = <DiscoverRoute>[];
    categories.forEach((title, categoryId) {
      final completePart = isComplete == null ? '' : '&isComplete=$isComplete';
      routes.add(
        DiscoverRoute(
          groupTitle: groupTitle,
          title: title,
          urlTemplate:
              '/novel?sort=1&page={{page}}&categoryId=$categoryId$completePart',
        ),
      );
    });

    return DiscoverGroup(title: groupTitle, routes: routes);
  }

  static List<DiscoverGroup> groupsOf(NovelChannel channel) {
    final source = channel == NovelChannel.male ? _maleGroups : _femaleGroups;
    return source
        .map(
          (g) => DiscoverGroup(
            title: g.title,
            routes: List<DiscoverRoute>.from(g.routes),
          ),
        )
        .toList();
  }

  static DiscoverRoute defaultRouteOf(NovelChannel channel) {
    final groups = groupsOf(channel);
    return groups.first.routes.first;
  }
}