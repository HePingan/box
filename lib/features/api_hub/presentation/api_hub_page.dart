import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'package:box/core/load_generation.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_back_button.dart';
import 'package:box/design_system/widgets/app_bottom_sheet.dart';
import 'package:box/design_system/widgets/app_cards.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';

import 'package:box/features/tools/application/tool_catalog.dart';
import 'package:box/features/tools/application/tool_usage_store.dart';

import '../application/public_api_registry.dart';
import '../data/public_api_client.dart';
import '../data/public_api_index_loader.dart';
import '../domain/public_api_models.dart';

import 'widgets/api_hub_tool_panels.dart';
import 'widgets/api_hub_widgets.dart';

// 拆分（2026-10-18）：本文件一度 2904 行 / 82 个方法，改一个面板要在一整片里翻。
// 按用途切成 5 个 part（同一个库作用域，私有成员照旧可用，行为零变化）：
//   *_panels_a  工具/素材面板：汇率 节假日 天气 IP 短链 二维码 头像 封面 占位图 词典 图书 一言 诗词
//   *_panels_b  内容/资讯面板：每日英语 60s 资讯 历史上的今天 运势 必应壁纸 热榜 摸鱼
//   *_panels_c  榜单/杂项面板：票房 Epic 语录 热搜 汇率 IP 归属地 手机归属地 翻译 模拟用户 目录
//   *_actions   加载/动作方法：_runActiveTool + 各 _loadXxx / 本地构建动作 / 请求守卫
//   *_chrome    跨面板共用的辅助方法：复制/预置/最近使用/目录过滤
//
// 各组方法挂在 mixin 上。mixin 的 on 类型是本文件里的私有基类
// `_ApiHubPageStateBase` —— State 的 `setState` 是 protected 成员，只有
// 「State 子类 / 以它为 on 类型的 mixin」才允许调用；用 extension 挂在
// State 子类上会触发 invalid_use_of_protected_member。
part 'api_hub_page_panels_a.part.dart';
part 'api_hub_page_panels_b.part.dart';
part 'api_hub_page_panels_c.part.dart';
part 'api_hub_page_actions.part.dart';
part 'api_hub_page_chrome.part.dart';

class ApiHubPage extends StatefulWidget {
  const ApiHubPage({super.key, this.initialTool, this.httpClientForTesting});

  final String? initialTool;

  /// 仅测试用：注入可控的 HTTP 客户端（生产走 PublicApiClient 默认实现）。
  @visibleForTesting
  final http.Client? httpClientForTesting;

  @override
  State<ApiHubPage> createState() => _ApiHubPageState();
}

abstract class _ApiHubPageStateBase extends State<ApiHubPage> {
  late final PublicApiClient _client = PublicApiClient(
    client: widget.httpClientForTesting,
  );

  /// 请求身份守卫（intent = 当前工具），防旧工具响应串台到新工具。
  final LoadGeneration _requestGeneration = LoadGeneration();
  final TextEditingController _amountController = TextEditingController(
    text: '1',
  );
  final TextEditingController _latController = TextEditingController(
    text: '31.2304',
  );
  final TextEditingController _lonController = TextEditingController(
    text: '121.4737',
  );
  final TextEditingController _wordController = TextEditingController(
    text: 'future',
  );
  final TextEditingController _directoryController = TextEditingController();
  final TextEditingController _imageSizeController = TextEditingController(
    text: '600x360',
  );
  final TextEditingController _imageBgController = TextEditingController(
    text: '2563eb',
  );
  final TextEditingController _imageFgController = TextEditingController(
    text: 'ffffff',
  );
  final TextEditingController _imageTextController = TextEditingController(
    text: 'Box API Hub',
  );
  final TextEditingController _qrTextController = TextEditingController(
    text: 'https://github.com/public-apis/public-apis',
  );
  final TextEditingController _qrSizeController = TextEditingController(
    text: '220x220',
  );
  final TextEditingController _avatarNameController = TextEditingController(
    text: 'Box API',
  );
  final TextEditingController _avatarBgController = TextEditingController(
    text: '2563eb',
  );
  final TextEditingController _avatarFgController = TextEditingController(
    text: 'ffffff',
  );
  final TextEditingController _avatarSizeController = TextEditingController(
    text: '256',
  );
  final TextEditingController _coverWidthController = TextEditingController(
    text: '640',
  );
  final TextEditingController _coverHeightController = TextEditingController(
    text: '360',
  );
  final TextEditingController _coverSeedController = TextEditingController(
    text: 'box-cover',
  );
  final TextEditingController _shortLinkController = TextEditingController(
    text: 'https://github.com/public-apis/public-apis',
  );
  final TextEditingController _bookController = TextEditingController(
    text: 'clean code',
  );

  String _activeTool = 'weather';
  String _activeGroup = '常用';
  String _from = 'USD';
  String _to = 'CNY';
  bool _loading = false;
  String? _error;
  List<HolidayResult> _holidays = const [];
  WeatherForecastResult? _weather;
  DictionaryResult? _dictionary;
  List<MockUserResult> _mockUsers = const [];
  List<PublicApiDirectoryEntry> _directoryEntries = const [];
  IpInfoResult? _ipInfo;
  DummyImageResult? _dummyImage;
  QrCodeResult? _qrCode;
  AvatarResult? _avatar;
  CoverImageResult? _coverImage;
  ShortLinkResult? _shortLink;
  List<PublicBookResult> _books = const [];
  HitokotoResult? _hitokoto;
  PoetryResult? _poetry;
  String _directoryCategory = '全部';
  String _directoryStatus = '全部';
  double? _converted;
  Map<String, double> _rates = const {};

  // —— A-1 本轮接线的接口状态 ——
  DailyEnglishResult? _dailyEnglish;
  News60sResult? _news60s;
  List<HistoryEventResult> _historyEvents = const [];
  LuckResult? _luck;
  BingWallpaperResult? _bingWallpaper;
  List<HotSearchResult> _hotSearches = const [];

  // —— A-2 本轮接线 ——
  /// 热榜类面板共用一个列表，按当前 [_toolId] 区分平台。
  List<HotSearchResult> _hotList = const [];
  FortuneResult? _fortune;
  MoyuResult? _moyu;
  QuoteResult? _quote;
  // —— A-3 批次3接线 ——
  List<BoxOfficeItem> _boxOffice = const [];
  List<EpicFreeGame> _epicGames = const [];
  ExchangeRateResult? _exchangeRate;
  IpQueryResult? _ipQuery;
  PhoneAreaResult? _phoneArea;
  TranslateResult? _translation;
  final _phoneController = TextEditingController();
  final _translateController = TextEditingController();
  final _ipQueryController = TextEditingController();
  String _translateFrom = 'en';
  String _translateTo = 'zh';
}

/// API Hub 页面状态。
///
/// 字段与生命周期留在本文件；各工具面板、加载动作与共用辅助方法
/// 分散在同库的 5 个 part 里（见文件头的 part 声明）。
class _ApiHubPageState extends _ApiHubPageStateBase
    with
        _ApiHubPageActions,
        _ApiHubPageChrome,
        _ApiHubPagePanelsA,
        _ApiHubPagePanelsB,
        _ApiHubPagePanelsC {
  @override
  void initState() {
    super.initState();
    _activeTool = widget.initialTool ?? 'weather';
    _activeGroup = PublicApiRegistry.byId(_activeTool).group;
    WidgetsBinding.instance.addPostFrameCallback((_) => _runActiveTool());
    // 「最近使用」读的是共享的使用记录（工具页派发点也在往同一份里记）。
    // 刻意不 await：首屏不该等一次 prefs 读。
    ToolUsageStore.instance.addListener(_onUsageChanged);
    ToolUsageStore.instance.ensureLoaded().then((_) {
      if (!mounted) return;
      _onUsageChanged();
    });
  }

  @override
  void dispose() {
    ToolUsageStore.instance.removeListener(_onUsageChanged);
    // 作废在途请求，回来后直接丢弃。
    _requestGeneration.invalidate();
    _amountController.dispose();
    _latController.dispose();
    _lonController.dispose();
    _wordController.dispose();
    _directoryController.dispose();
    _imageSizeController.dispose();
    _imageBgController.dispose();
    _imageFgController.dispose();
    _imageTextController.dispose();
    _qrTextController.dispose();
    _qrSizeController.dispose();
    _avatarNameController.dispose();
    _avatarBgController.dispose();
    _avatarFgController.dispose();
    _avatarSizeController.dispose();
    _coverWidthController.dispose();
    _coverHeightController.dispose();
    _coverSeedController.dispose();
    _shortLinkController.dispose();
    _bookController.dispose();
    _phoneController.dispose();
    _translateController.dispose();
    _ipQueryController.dispose();
    super.dispose();
  }


  /// 仅测试用：切换工具（等价于点击工具卡片）。
  @visibleForTesting
  void switchToolForTesting(String id) => _switchTool(id);

  /// 仅测试用：当前错误态。
  @visibleForTesting
  String? get errorForTesting => _error;

  /// 仅测试用：当前加载态。
  @visibleForTesting
  bool get loadingForTesting => _loading;

  void _switchTool(String id) {
    final tool = PublicApiRegistry.byId(id);
    // 记一笔到共享记录：键是**工具名**，和工具页的派发点同一份数据。
    // 面板没有对应工具入口（`toolNameForApiHubPanel` 返回 null）就不记 ——
    // 不为了凑一条记录硬造一个名字。
    final toolName = toolNameForApiHubPanel(id);
    if (toolName != null) {
      unawaited(ToolUsageStore.instance.record(toolName));
    }
    setState(() {
      _activeTool = id;
      _activeGroup = tool.group;
    });
    _runActiveTool();
  }

  /// 是否「单工具模式」：从工具页点某个工具进来（initialTool 非空）。
  ///
  /// 用户反馈：点工具页的一个工具，进去后还要下滑才能看到工具。
  /// 根因是 sliver 顺序 —— 目标面板排在最后，前面还压着 63 条的工具网格。
  /// 这里记住来源，用于收起与目标无关的块（快捷区/最近/分组/网格）。
  late final bool _singleToolMode = widget.initialTool != null;

  /// 单工具模式下是否已展开「全部工具」目录。
  /// 默认收起是为了让第一屏就是工具本身；用户要换工具时再展开。
  bool _browseAllTools = false;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── 单工具模式：连 hero 总览卡一起收掉 ──
          //
          // 用户反馈（真机截图）：「上面也能不能隐藏，看着很丑」。
          // 方案 C 只收了快捷区/最近/分组/网格，hero 还留着 —— 但
          // `12 TOOLS` + `PUBLIC APIS` + 大标题 + 三个统计胶囊 + 两个属性胶囊
          // 全是**与当前工具无关的目录总览**，用户已经点明要哪个工具了。
          // 实测它占掉上方 247px（600px 屏的 40%），所以连它一起让位，
          // 只留一条紧凑返回条（否则用户出不去）。
          SliverToBoxAdapter(
            child: _singleToolMode ? _buildCompactBackBar() : _buildHero(),
          ),

          // ── 单工具模式：第一屏直接给工具本身 ──
          // 不渲染快捷区/最近使用/分组/网格 —— 它们在 800x600 的屏幕上
          // 合起来超过一屏，会把目标面板整个顶出去。
          if (_singleToolMode) ...[
            SliverToBoxAdapter(child: _buildActivePanel()),
            SliverToBoxAdapter(child: _buildBrowseAllTrigger()),
            if (_browseAllTools) ...[
              SliverToBoxAdapter(child: _buildQuickWorkbench()),
              SliverToBoxAdapter(child: _buildRecentTools()),
              SliverToBoxAdapter(child: _buildGroupSwitcher()),
              SliverToBoxAdapter(child: _buildToolGrid()),
            ],
          ] else ...[
            SliverToBoxAdapter(child: _buildQuickWorkbench()),
            SliverToBoxAdapter(child: _buildRecentTools()),
            SliverToBoxAdapter(child: _buildGroupSwitcher()),
            SliverToBoxAdapter(child: _buildToolGrid()),
            SliverToBoxAdapter(child: _buildActivePanel()),
          ],

          const SliverToBoxAdapter(
            child: SizedBox(height: AppTokens.pageBottomPadding + 28),
          ),
        ],
      ),
    );
  }

  /// 单工具模式的紧凑顶栏：只有返回按钮 + 当前工具名。
  ///
  /// 替代整块 hero 总览卡。hero 实测占 247px（600px 屏的 40%），而里面
  /// 的 `12 TOOLS` / `PUBLIC APIS` / 三个统计胶囊 / 两个属性胶囊全是
  /// 目录总览 —— 用户点了具体工具，这些跟他要看的东西无关。
  ///
  /// 保留的两样：返回（必须的出入口）+ 当前工具名（让用户知道自己在哪，
  /// 尤其在面板加载失败时，标题会显示工具名而不是「加载失败」）。
  Widget _buildCompactBackBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          AppBackButton(
            onPressed: () => Navigator.maybePop(context),
            label: '工具',
          ),
          const Spacer(),
          Flexible(
            child: Text(
              PublicApiRegistry.byId(_activeTool).title,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTokens.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 单工具模式下回到全量目录的入口。
  ///
  /// 收起网格换来「第一屏即工具」，代价是换工具要多点一下 ——
  /// 所以这个出口必须显眼，否则等于把 63 个工具藏死。
  Widget _buildBrowseAllTrigger() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: OutlinedButton.icon(
        onPressed: () => setState(() => _browseAllTools = !_browseAllTools),
        icon: Icon(
          _browseAllTools ? Icons.expand_less_rounded : Icons.grid_view_rounded,
          size: 18,
        ),
        label: Text(_browseAllTools ? '收起全部工具' : '切换其他工具'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          foregroundColor: AppTokens.textPrimary,
          side: BorderSide(color: AppTokens.cardBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    // 数字一律实时派生，不写死。
    //
    // 改前这里是 `badge: '12 TOOLS'` 和 `ApiHubMetric(value: '12', ...)`
    // —— 同一批数字在文件里存了三份字面量，且全部漂移（目录 124 条目、
    // 37 已接线，UI 却一直显示 12）。加一个工具就要有人记得改文案，
    // 没人记得，于是用户看到的能力数与 App 真实能力相差 25 个。
    //
    // 现在：接线数来自 [kToolTargets]，可用率来自 [availableToolEntries]，
    // 面板数来自 [PublicApiRegistry.all]。换来源，UI 自动跟。
    final wired = kToolTargets.length;
    final available = availableToolEntries().length;
    final total = allToolEntries().length;

    return AppLightHeroCard(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      eyebrow: 'PUBLIC APIS',
      title: 'API 能力中心',
      subtitle: '国内网络实测可用 · 短链 / 二维码 / 头像 / 随机封面 / API 清单',
      badge: '$wired TOOLS',
      accentGradient: AppTokens.blueGradient,
      // 同上：卡片标题已写「API 能力中心」。
      leading: AppBackButton(onPressed: () => Navigator.maybePop(context)),
      actions: const [
        AppStatusPill(
          label: '免密钥优先',
          icon: Icons.lock_open_rounded,
          color: AppTokens.emerald,
        ),
        AppStatusPill(
          label: '国内可用清单',
          icon: Icons.travel_explore_rounded,
          color: AppTokens.orange,
        ),
      ],
      metrics: [
        Expanded(
          child: ApiHubMetric(value: '$available', label: '可用工具'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ApiHubMetric(value: '$total', label: '目录条目'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ApiHubMetric(
            value: '${PublicApiRegistry.all.length}',
            label: '在线面板',
          ),
        ),
      ],
    );
  }

  Widget _buildQuickWorkbench() {
    const quickIds = [
      'weather',
      'currency',
      'ip',
      'shortlink',
      'qr',
      'avatar',
      'cover',
      'dummy_image',
      'directory',
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTokens.cardBorder),
        boxShadow: AppTokens.shadowSm(color: AppTokens.primaryBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: '常用 API 快捷区',
            subtitle: '天气 / 短链 / 二维码 / 头像 / 随机封面一键直达',
            icon: Icons.bolt_rounded,
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: quickIds.map((id) {
                final tool = PublicApiRegistry.byId(id);
                final selected = _activeTool == id;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ApiHubQuickChip(
                    tool: tool,
                    selected: selected,
                    onTap: () => _switchTool(id),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTools() {
    final recentTools = _recentTools;
    if (recentTools.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const AppStatusPill(
            label: '最近使用',
            icon: Icons.history_rounded,
            color: AppTokens.violet,
          ),
          ...recentTools.map(
            (tool) => ActionChip(
              label: Text(tool.title),
              avatar: Icon(tool.icon, size: 16, color: tool.color),
              onPressed: () => _switchTool(tool.id),
              side: BorderSide(color: tool.color.withValues(alpha: 0.28)),
              backgroundColor: tool.color.withValues(alpha: 0.08),
              labelStyle: TextStyle(
                color: tool.color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupSwitcher() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemBuilder: (context, index) {
          final group = PublicApiRegistry.groups[index];
          final selected = group == _activeGroup;
          return ChoiceChip(
            selected: selected,
            label: Text(group),
            onSelected: (_) => setState(() => _activeGroup = group),
            selectedColor: AppTokens.primaryBlue.withValues(alpha: 0.14),
            labelStyle: TextStyle(
              color: selected ? AppTokens.primaryBlue : AppTokens.textSecondary,
              fontWeight: FontWeight.w900,
            ),
            side: BorderSide(color: AppTokens.cardBorder),
            backgroundColor: AppTokens.surface,
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemCount: PublicApiRegistry.groups.length,
      ),
    );
  }

  Widget _buildToolGrid() {
    final tools = PublicApiRegistry.all
        .where((tool) => tool.group == _activeGroup)
        .toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: tools.map((tool) {
          return ApiHubToolCard(
            tool: tool,
            selected: _activeTool == tool.id,
            onTap: () => _switchTool(tool.id),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActivePanel() {
    // 失败/加载态也要带上工具名。
    //
    // 之前这里硬写成「加载失败」/「正在请求公开 API」，用户点「摸鱼日历」
    // 看到的是「加载失败」—— 不知道自己点的是哪个工具，也没有重试的锚点。
    // 单工具模式下更致命：整页只剩一句「加载失败」，连自己在哪都看不出来。
    final toolLabel = PublicApiRegistry.byId(_activeTool).title;

    if (_error != null) {
      return ApiHubPanel(
        // 标题只放工具身份，状态进 subtitle —— 标题是「我在哪」，
        // subtitle 才是「现在怎么了」。拼在一起会让精确匹配标题的
        // 既有测试全部落空，也让标题读起来不像名字。
        title: toolLabel,
        subtitle: '加载失败：$_error',
        icon: Icons.error_outline_rounded,
        child: FilledButton.icon(
          onPressed: _runActiveTool,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('重试'),
        ),
      );
    }

    if (_loading) {
      return ApiHubPanel(
        title: toolLabel,
        subtitle: '正在加载 · 首次加载可能受网络或免费接口限流影响',
        icon: Icons.cloud_sync_rounded,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    switch (_activeTool) {
      case 'currency':
        return _buildCurrencyPanel();
      case 'holidays':
        return _buildHolidayPanel();
      case 'ip':
        return _buildIpPanel();
      case 'shortlink':
        return _buildShortLinkPanel();
      case 'dictionary':
        return _buildDictionaryPanel();
      case 'dummy_image':
        return _buildDummyImagePanel();
      case 'qr':
        return _buildQrPanel();
      case 'avatar':
        return _buildAvatarPanel();
      case 'cover':
        return _buildCoverPanel();
      case 'mock':
        return _buildMockPanel();
      case 'directory':
        return _buildDirectoryPanel();
      case 'books':
        return _buildBooksPanel();
      case 'hitokoto':
        return _buildHitokotoPanel();
      case 'poetry':
        return _buildPoetryPanel();
      // ——— A-1 本轮接线 ———
      case 'daily_english':
        return _buildDailyEnglishPanel();
      case 'news60s':
        return _buildNews60sPanel();
      case 'today_in_history':
        return _buildTodayInHistoryPanel();
      case 'luck':
        return _buildLuckPanel();
      case 'bing_wallpaper':
        return _buildBingWallpaperPanel();
      case 'baidu_hot':
        return _buildBaiduHotPanel();
      case 'exchange_rate':
        return _buildExchangeRatePanel();
      case 'ip_query':
        return _buildIpQueryPanel();
      case 'phone_area':
        return _buildPhoneAreaPanel();
      case 'translate':
        return _buildTranslatePanel();
      case 'weibo_hot':
      case 'zhihu_hot':
      case 'douyin_hot':
      case 'toutiao_hot':
        return _buildHotListPanel(_activeTool);
      case 'fortune':
        return _buildFortunePanel();
      case 'moyu':
        return _buildMoyuPanel();
      case 'dujitang':
      case 'chp':
        return _buildQuotePanel(_activeTool);
      case 'maoyan':
        return _buildBoxOfficePanel();
      case 'epic':
        return _buildEpicPanel();
      case 'weather':
      default:
        return _buildWeatherPanel();
    }
  }
}
