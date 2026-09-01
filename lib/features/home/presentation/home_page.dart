import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:box/daily_news_page.dart';
import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';
import 'package:box/globals.dart';
import 'package:box/novel/core/models.dart' show NovelBook;
import 'package:box/novel/novel_module.dart';
import 'package:box/plugin_manager.dart';
import 'package:box/video_module.dart';
import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:box/features/home/data/ai_hot_models.dart';
import 'package:box/features/home/data/ai_hot_service.dart';
import 'package:box/core/load_generation.dart';
import 'package:box/features/home/data/continue_item.dart';
import 'package:box/features/home/data/daily_news_service.dart';
import 'package:box/features/home/data/continue_repository.dart';
import 'package:box/features/home/data/home_quick_action_prefs.dart';
import 'package:box/features/home/presentation/quick_action_picker_page.dart';
import 'package:box/features/home/presentation/widgets/ai_hot_section.dart';
import 'package:box/features/home/presentation/widgets/continue_rail.dart';

import 'widgets/home_widgets.dart';

/// 首页热闻预览条数。
///
/// 此前抓取写 `take(4)`、渲染写 `take(3)`，第 4 条永远抓到又永远不显示。
/// 收敛成一个常量，避免两处再次漂移。想看全部走「更多」进 DailyNewsPage。
const int _homeNewsPreviewCount = 3;

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.onSwitchTab,
    this.quickActionPrefs,
    this.continueRepository,
    this.newsService,
    this.aiHotService,
  });

  final ValueChanged<int>? onSwitchTab;

  /// 快捷入口存储。生产环境留空用默认实现；
  /// 测试注入 in-memory 版本，避免碰 SharedPreferences 平台通道。
  final HomeQuickActionPrefs? quickActionPrefs;

  /// 「继续使用」数据源。生产环境留空走真实的 Hive + SharedPreferences；
  /// 测试注入假实现，避免碰平台通道。
  final ContinueRepository? continueRepository;

  /// 今日热闻数据源。生产留空走真实网络；测试注入桩，避免打外网。
  final DailyNewsService? newsService;

  /// AI HOT 数据源。同上：此前是字段里直接 new，widget 测试没法阻止它
  /// 打真实网络，pumpAndSettle 会一直等不到静止。
  final AiHotService? aiHotService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _todayDateStr = '';
  bool _isLoadingNews = true;

  /// 只装真新闻。错误态走 _newsError，不再往列表里塞提示文案（A4）。
  List<DailyNewsItem> _newsItems = const <DailyNewsItem>[];

  /// 拿不到任何内容时的提示文案；正常时为空串。
  String _newsError = '';

  /// 热闻加载的代号守卫。
  ///
  /// 首页有两条路径会触发拉取：initState 和下拉刷新。快速下拉两次时，
  /// 先发的请求可能后返回，把新结果覆盖成旧结果（mounted 挡不住这个）。
  final LoadGeneration _newsGeneration = LoadGeneration();

  /// 用户自选的快捷入口 id（顺序即展示顺序）。
  List<String> _quickActionIds = <String>[];

  late final HomeQuickActionPrefs _quickActionPrefs =
      widget.quickActionPrefs ?? HomeQuickActionPrefs();

  late final AiHotService _aiHotService =
      widget.aiHotService ?? AiHotService();
  AiHotFeed? _aiHotFeed;
  bool _isLoadingAiHot = true;

  /// 「继续使用」的真实进度条目。
  List<ContinueItem> _continueItems = const <ContinueItem>[];

  /// 影视历史控制器。
  ///
  /// 与 _createContinueRepository 内部共用同一实例：续播时要按 storageKey
  /// 回查 HistoryItem 拿 episodeUrl/position，用两个实例会读到空列表。
  final HistoryController _historyController = HistoryController();

  late final ContinueRepository _continueRepository =
      widget.continueRepository ?? _createContinueRepository();

  late final DailyNewsService _newsService =
      widget.newsService ?? DailyNewsService();

  @override
  void initState() {
    super.initState();
    _initDate();
    _fetchDailyNews();
    _loadQuickActions();
    _fetchAiHot();
    _loadContinueItems();
    // 确保插件主机初始化，这样插件卡片才能拿到数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HomePluginHost.instance.bootstrap();
    });
  }

  Future<void> _loadQuickActions() async {
    final ids = await _quickActionPrefs.readSelectedIds();
    if (!mounted) return;
    setState(() => _quickActionIds = ids);
  }

  /// 创建「继续使用」的数据源。
  ///
  /// 影视历史走 HistoryController（Hive），小说要书架（拿书名/封面）加
  /// 逐本进度（拿章节名/时间）两处拼合。测试可通过 widget.continueRepository
  /// 注入假数据，避开 Hive 与 SharedPreferences 平台通道。
  ContinueRepository _createContinueRepository() {
    return ContinueRepository(
      loadVideoHistory: () async {
        await _historyController.loadHistory();
        return _historyController.historyList;
      },
      loadBookshelf: () => NovelModule.bookshelf.getBookshelf(),
      loadNovelProgress: (bookId) =>
          NovelModule.repository.getProgress(bookId),
    );
  }

  /// 载入真实进度。
  ///
  /// 失败时保留已有列表而不是清空：进度是本地数据，读一次失败通常是瞬时的，
  /// 把已经显示出来的卡片抹掉只会让用户以为记录丢了。
  Future<void> _loadContinueItems() async {
    List<ContinueItem> items;
    try {
      items = await _continueRepository.load();
    } catch (_) {
      // 本地存储读不出来（Hive 未初始化、盒子损坏、书架 JSON 坏了）不该让
      // 首页整块崩掉 —— 这个区块是锦上添花，读不到就维持现状。
      return;
    }
    if (!mounted) return;
    if (items.isEmpty && _continueItems.isNotEmpty) return;
    setState(() => _continueItems = items);
  }

  /// 点开一条「继续使用」，回到上次位置。
  Future<void> _openContinueItem(ContinueItem item) async {
    switch (item.kind) {
      case ContinueKind.video:
        await _resumeVideo(item);
      case ContinueKind.novel:
        await _resumeNovel(item);
    }
    // 从播放器/阅读器回来，进度已经变了，重读一次让卡片跟上。
    await _loadContinueItems();
  }

  Future<void> _resumeVideo(ContinueItem item) async {
    final history = _findHistory(item.id);
    if (history == null) {
      _toast('这条记录已失效');
      return;
    }

    // 续播需要 VideoSource 对象，只有 id 不够；片源被用户删掉后无法续播。
    final sources = context.read<VideoController>().sources;
    VideoSource? target;
    for (final source in sources) {
      if (source.id == history.sourceId) {
        target = source;
        break;
      }
    }
    if (target == null) {
      _toast('该视频的片源已失效或被移除');
      return;
    }

    final vodId = int.tryParse(history.vodId) ?? 0;
    if (vodId <= 0) {
      _toast('历史记录中的视频ID无效');
      return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => VideoDetailPage(
          source: target!,
          vodId: vodId,
          initialEpisodeUrl: history.episodeUrl,
          initialPosition: history.position,
        ),
      ),
    );
  }

  HistoryItem? _findHistory(String storageKey) {
    for (final entry in _historyController.historyList) {
      if (entry.storageKey == storageKey) return entry;
    }
    return null;
  }

  Future<void> _resumeNovel(ContinueItem item) async {
    final books = await NovelModule.bookshelf.getBookshelf();
    NovelBook? target;
    for (final book in books) {
      final id = book.id.isNotEmpty ? book.id : book.detailUrl;
      if (id == item.id) {
        target = book;
        break;
      }
    }
    if (target == null) {
      _toast('这本书已不在书架');
      return;
    }

    if (!mounted) return;
    // 走详情页而不是直接进 ReaderPage：ReaderPage 要求 detail.chapters 非空，
    // 而书架只存 NovelBook（无章节）。详情页会自己加载章节，并已有
    // 「续读上次位置」的逻辑。
    final book = target;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => NovelDetailController(entryBook: book),
          child: NovelDetailPage(entryBook: book),
        ),
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 拉 AI 热点。
  ///
  /// 失败不弹错、不清空已有内容：service 内部会回落到上次缓存，
  /// 真的什么都没有时区块自己显示空态 + 重试。
  Future<void> _fetchAiHot({bool forceRefresh = false}) async {
    if (mounted && _aiHotFeed == null) {
      setState(() => _isLoadingAiHot = true);
    }
    final feed = await _aiHotService.fetchSelected(
      take: kAiHotPreviewCount + 2,
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    setState(() {
      _aiHotFeed = feed;
      _isLoadingAiHot = false;
    });
  }

  Future<void> _openQuickActionPicker() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        // 传同一个 prefs 实例：否则测试注入的 in-memory 存储和管理页
        // 各写一份，改完回来首页读不到。
        builder: (_) => QuickActionPickerPage(prefs: _quickActionPrefs),
      ),
    );
    // 从管理页回来要重读，否则首页还是旧的那几个。
    await _loadQuickActions();
  }

  void _initDate() {
    final now = DateTime.now();
    final hour = now.hour;
    String greeting;
    if (hour < 6) {
      greeting = '夜深了，注意休息';
    } else if (hour < 12) {
      greeting = '早上好，新的一天';
    } else if (hour < 14) {
      greeting = '中午好，吃午饭了吗';
    } else if (hour < 18) {
      greeting = '下午好，继续加油';
    } else {
      greeting = '晚上好，欢迎回来';
    }
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    _todayDateStr = '$month月$day日 · $greeting';
  }

  /// 拉取热闻。
  ///
  /// [showSpinner] 为 false 时不切到 loading 态——下拉刷新场景下
  /// RefreshIndicator 自己有转圈，再把列表换成 spinner 会让已有内容闪一下。
  Future<void> _fetchDailyNews({bool showSpinner = true}) async {
    // 每次拉取先领一个代号，作废所有在途请求（A3）。
    // 症状：连续两次下拉，先发的请求若后返回会把新结果盖成旧结果。
    final token = _newsGeneration.begin('news');

    if (showSpinner) {
      setState(() => _isLoadingNews = true);
    }

    // 下拉刷新要绕过 5 分钟缓存，否则用户下拉了却什么都没变。
    final feed = await _newsService.fetch(
      take: _homeNewsPreviewCount,
      forceRefresh: !showSpinner,
    );

    if (!mounted) return;
    // 过期的请求整段丢弃，连错误态也不写。
    if (!_newsGeneration.isCurrent(token)) return;

    setState(() {
      _newsItems = feed.items;
      _newsError = feed.errorMessage;
      _isLoadingNews = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return AppPageScaffold(
      maxContentWidth: AppTokens.shellMaxContentWidth,
      shellInset: true,
      // 兜底文案一直写着「下拉刷新重试」，但此前页面没挂 RefreshIndicator，
      // 用户下拉不会有任何反应。补上，让那句提示名副其实。
      child: RefreshIndicator(
        onRefresh: () => Future.wait<void>(<Future<void>>[
          _fetchDailyNews(showSpinner: false),
          _fetchAiHot(forceRefresh: true),
          _loadContinueItems(),
        ]),
        color: AppTokens.primaryBlue,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(child: _buildGreetingBar()),
            SliverToBoxAdapter(child: _buildQuickActions()),
            SliverToBoxAdapter(child: _buildPluginSection()),
            SliverToBoxAdapter(child: _buildContinueRail()),
            SliverToBoxAdapter(child: _buildDailyNewsCard()),
            // AI 热点接在「今日热闻」下面（用户指定的位置）。
            SliverToBoxAdapter(
              child: AiHotSection(
                isLoading: _isLoadingAiHot,
                feed: _aiHotFeed,
                onOpenItem: _openAiHotItem,
                onOpenAll: _openAiHotSite,
                onRetry: () => _fetchAiHot(forceRefresh: true),
              ),
            ),
            // 底部留白给悬浮胶囊导航栏避让。数值由 AppPageScaffold
            // (shellInset: true) 统一下发，四个主页面共用同一算法。
            SliverToBoxAdapter(
              child: SizedBox(
                height: AppPageScaffold.bottomInsetOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 统一的分区标题。
  ///
  /// 改版前三个分区各自手写 `Text(fontSize: 14.5, w900)`，
  /// 且「今日热闻」还额外带渐变图标，视觉重量和另两个分区不一致。
  /// 收敛成一个组件：左侧 3px 色条 + 标题 + 可选尾部操作。
  Widget _buildSectionHeader({
    required String title,
    Color accent = AppTokens.primaryBlue,
    List<Widget> actions = const [],
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppTokens.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }

  // ── 顶部问候栏（单行紧凑） ─────────────────
  Widget _buildGreetingBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        10,
        8,
        AppTokens.shellPageGutter,
        6,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '菜单',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            icon: const Icon(
              Icons.menu_rounded,
              color: AppTokens.textSecondary,
              size: 22,
            ),
            onPressed: () => appScaffoldKey.currentState?.openDrawer(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _todayDateStr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTokens.textPrimary,
                fontSize: 15.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 快捷入口 2×2 网格 ─────────────────────
  /// 快捷入口。
  ///
  /// 改版：原先是 4 个硬编码卡片（工具/内容/AI 生图/扩展），用户改不了。
  /// 现在由用户从已注册插件里自选（见 QuickActionPickerPage），
  /// 这里只负责把「选中的 id」映射回插件并渲染。
  ///
  /// 只存 id 不存标题/图标：插件更名或被卸载时首页不会显示脏数据 ——
  /// 找不到对应插件的 id 直接跳过，不占位、不显示空白卡。
  Widget _buildQuickActions() {
    return SafeValueListenableBuilder<List<HomePlugin>>(
      valueListenable: HomePluginHost.instance.listenable,
      builder: (context, plugins, child) {
        final byId = <String, HomePlugin>{
          for (final p in plugins)
            if (p.enabled) p.id: p,
        };

        final actions = <HomeQuickAction>[
          for (final id in _quickActionIds)
            if (byId[id] != null)
              HomeQuickAction(
                title: byId[id]!.title,
                subtitle: byId[id]!.subtitle,
                icon: byId[id]!.icon,
                accent: byId[id]!.color,
                onTap: () => byId[id]!.onTap(context),
              ),
        ];

        return _buildQuickActionsBody(actions);
      },
    );
  }

  Widget _buildQuickActionsBody(List<HomeQuickAction> actions) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.shellPageGutter,
        0,
        AppTokens.shellPageGutter,
        14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: '快捷入口',
            actions: [
              GestureDetector(
                onTap: _openQuickActionPicker,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        Icons.tune_rounded,
                        size: 13,
                        color: AppTokens.textSecondary,
                      ),
                      SizedBox(width: 3),
                      Text(
                        '管理',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (actions.isEmpty) _buildQuickActionsEmpty(),
          // 不用 GridView + childAspectRatio：任何固定/推算的高度都要跟
          // padding、1px 边框、字体缩放和字形度量赛跑，实测差 3~10px 就
          // 触发 RenderFlex overflow 黄条。改成两行 Row + Expanded，
          // 行高由内容自己决定，彻底不需要算高度。
          for (var row = 0; row < actions.length; row += 2) ...[
            if (row > 0) const SizedBox(height: 10),
            // IntrinsicHeight 让同一行两张卡等高（否则文字长短不同会高矮不齐），
            // 高度仍由内容决定，不是我们算出来的。
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: HomeQuickActionCard(action: actions[row])),
                  const SizedBox(width: 10),
                  if (row + 1 < actions.length)
                    Expanded(
                      child: HomeQuickActionCard(action: actions[row + 1]),
                    )
                  else
                    const Expanded(child: SizedBox()),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 插件横向滚动卡片 ─────────────────────
  Widget _buildPluginSection() {
    return SafeValueListenableBuilder<List<HomePlugin>>(
      valueListenable: HomePluginHost.instance.listenable,
      builder: (context, plugins, child) {
        final customPlugins = plugins
            .where((p) => !p.builtIn && p.enabled)
            .toList();

        if (customPlugins.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.shellPageGutter,
            0,
            AppTokens.shellPageGutter,
            14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                title: '已安装插件',
                accent: AppTokens.violet,
              ),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: customPlugins.length,
                  separatorBuilder: (_, sep) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final plugin = customPlugins[index];
                    return _PluginCard(plugin: plugin);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 继续上次 ───────────────────────────────
  /// 「继续使用」区块。
  ///
  /// 此前这里是两张硬编码卡（「小说书架」「影视搜索」），挂在「继续使用」
  /// 标题下但跟用户真实进度无关，点进去只是打开列表页。现在读真实的
  /// 播放历史 / 阅读进度，点击直接回到上次位置。
  Widget _buildContinueRail() {
    return ContinueRail(
      items: _continueItems,
      onOpen: _openContinueItem,
      onBrowseNovel: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NovelListPageWithProvider()),
      ),
      onBrowseVideo: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const VideoListPage()),
      ),
    );
  }

  // ── 每日新闻 ───────────────────────────────
  Widget _buildDailyNewsCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.shellPageGutter,
        0,
        AppTokens.shellPageGutter,
        8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行提到卡片外，和「快捷入口 / 已安装插件 / 继续使用」
          // 保持同一套分区标题样式（此前这里是渐变图标 + 卡内标题，重量不一致）。
          _buildSectionHeader(
            title: '今日热闻',
            accent: AppTokens.orange,
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppTokens.primaryBlue,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DailyNewsPage()),
                  );
                },
                child: const Text(
                  '更多',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppTokens.surface,
              borderRadius: BorderRadius.circular(AppTokens.radiusCard),
              border: Border.all(color: AppTokens.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isLoadingNews)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (_newsError.isNotEmpty)
                  // 错误态是独立分支，不再混进数据列表（A4）。
                  HomeNewsLine(
                    text: _newsError,
                    showDivider: false,
                    isPlaceholder: true,
                  )
                else
                  ..._newsItems.asMap().entries.map((entry) {
                    final item = entry.value;
                    final line = HomeNewsLine(
                      text: item.title,
                      // 最后一条不画分隔线，避免卡片底部出现悬空的线。
                      showDivider: entry.key != _newsItems.length - 1,
                    );
                    // 上游偶尔给不出 url，这种条目点开会是空白详情页，
                    // 所以不挂手势也不显示箭头。
                    if (!item.isOpenable) {
                      return HomeNewsLine(
                        text: item.title,
                        showDivider: entry.key != _newsItems.length - 1,
                        isPlaceholder: true,
                      );
                    }
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DailyNewsPage(initialUrl: item.url),
                          ),
                        );
                      },
                      child: line,
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 快捷入口一个都没选时的占位。
  ///
  /// 不显示空白：给一句话 + 直达管理页，否则用户清空后会以为首页坏了。
  Widget _buildQuickActionsEmpty() {
    return GestureDetector(
      onTap: _openQuickActionPicker,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          border: Border.all(color: AppTokens.divider),
        ),
        child: Row(
          children: const [
            Icon(
              Icons.add_circle_outline_rounded,
              size: 18,
              color: AppTokens.primaryBlue,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '还没有快捷入口，点这里从插件里挑几个',
                style: TextStyle(fontSize: 13, color: AppTokens.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开某条 AI 热点。
  ///
  /// 走站内 WebView（DailyNewsPage）而不是外部浏览器：和「今日热闻」
  /// 的行为保持一致，用户返回时还在 App 里。
  void _openAiHotItem(AiHotItem item) {
    final url = item.openUrl;
    if (url == null) {
      // 理论上不会发生（模型层保证至少有 permalink 或 url），
      // 但真出现时给提示而不是打开一个空白页。
      showSnack(context, '这条热点没有可打开的链接');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DailyNewsPage(initialUrl: url),
      ),
    );
  }

  void _openAiHotSite() {
    final canonical = _aiHotFeed?.attributionCanonical;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DailyNewsPage(
          initialUrl: canonical ?? AiHotService.siteUrl,
        ),
      ),
    );
  }

  /// 切到指定底部 Tab。
  ///
  /// 快捷入口改成插件自选后，首页自己不再有硬编码的「工具/内容/扩展」卡片，
  /// 所以这里目前没有内部调用方。保留它 + `widget.onSwitchTab`：
  /// AppShell 仍在传这个回调，插件将来要跳 Tab 也走这条路，
  /// 删了等于把外部契约一起删掉。
  @visibleForTesting
  void switchToTab(int index, String label) {
    if (widget.onSwitchTab != null) {
      widget.onSwitchTab!(index);
      return;
    }
    // 原文是「$label』——开合引号不成对（「 配 』），是笔误。
    showSnack(context, '请在底部进入「$label」');
  }
}

// ── 快捷入口卡片 ──────────────────────────────
class HomeQuickAction {
  const HomeQuickAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;

  /// 品牌强调色。只用于图标底片和图标本身，不铺满整卡。
  final Color accent;
  final VoidCallback onTap;
}

/// 快捷入口卡片。
///
/// 改版原因：原设计四张卡各自铺满饱和渐变 + 彩色投影，2×2 排在首屏
/// 顶部会盖过下方「已安装插件 / 继续使用 / 今日热闻」的真实内容，
/// 视觉层级是倒挂的。现在改成白底卡 + 描边 + 彩色图标底片，
/// 颜色只做「区分」不做「抢眼」，标题恢复深色文字提升可读性。
class HomeQuickActionCard extends StatelessWidget {
  const HomeQuickActionCard({super.key, required this.action});
  final HomeQuickAction action;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTokens.surface,
      borderRadius: BorderRadius.circular(AppTokens.radiusCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        onTap: action.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusCard),
            border: Border.all(color: AppTokens.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: action.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.radiusChip),
                ),
                child: Icon(action.icon, color: action.accent, size: 18),
              ),
              const SizedBox(width: 10),
              // Flexible 而不是 Expanded：格子宽度已由 GridView 定死，
              // 用 Flexible 让文字列在窄屏时能收缩而不是强撑溢出。
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  // 只占内容所需高度。父级给的高度若略小于两行文字，
                  // 不加这行会直接报 RenderFlex overflow（实测差 4px 就炸）。
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      action.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTokens.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      action.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTokens.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 已安装插件卡片 ────────────────────────────
/// 已安装插件卡片。
///
/// 和 HomeQuickActionCard 一起从「铺满渐变」改成白底 + 描边 + 彩色图标底片：
/// 插件颜色是用户/作者定的，铺满整卡时四五张排一行会花掉整个首屏，
/// 而且白字压在浅色插件主题色上对比度不够。
class _PluginCard extends StatelessWidget {
  const _PluginCard({required this.plugin});
  final HomePlugin plugin;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radiusCard),
      onTap: () => plugin.onTap(context),
      child: Container(
        width: 132,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          border: Border.all(color: AppTokens.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: plugin.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTokens.radiusChip),
              ),
              child: Icon(plugin.icon, color: plugin.color, size: 17),
            ),
            const SizedBox(height: 8),
            Text(
              plugin.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTokens.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              plugin.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTokens.textTertiary,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showSnack(BuildContext context, String text) async {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
