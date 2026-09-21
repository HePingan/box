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

import '../application/public_api_registry.dart';
import '../data/public_api_client.dart';
import '../data/public_api_index_loader.dart';
import '../domain/public_api_models.dart';

import 'widgets/api_hub_tool_panels.dart';
import 'widgets/api_hub_widgets.dart';

class ApiHubPage extends StatefulWidget {
  const ApiHubPage({super.key, this.initialTool, this.httpClientForTesting});

  final String? initialTool;

  /// 仅测试用：注入可控的 HTTP 客户端（生产走 PublicApiClient 默认实现）。
  @visibleForTesting
  final http.Client? httpClientForTesting;

  @override
  State<ApiHubPage> createState() => _ApiHubPageState();
}

class _ApiHubPageState extends State<ApiHubPage> {
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
  final List<String> _recentToolIds = [
    'qr',
    'shortlink',
    'cover',
    'avatar',
    'dummy_image',
    'currency',
  ];
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

  @override
  void initState() {
    super.initState();
    _activeTool = widget.initialTool ?? 'weather';
    _activeGroup = PublicApiRegistry.byId(_activeTool).group;
    WidgetsBinding.instance.addPostFrameCallback((_) => _runActiveTool());
  }

  @override
  void dispose() {
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

  Future<void> _runActiveTool() async {
    switch (_activeTool) {
      case 'currency':
        await _loadCurrency();
        return;
      case 'holidays':
        await _loadHolidays();
        return;
      case 'ip':
        await _loadIpInfo();
        return;
      case 'shortlink':
        return;
      case 'dictionary':
        await _loadDictionary();
        return;
      case 'books':
        await _searchBooks();
        return;
      case 'hitokoto':
        await _loadHitokoto();
        return;
      case 'poetry':
        await _loadPoetry();
        return;
      case 'dummy_image':
        _buildDummyImage();
        return;
      case 'qr':
        _buildQrCode();
        return;
      case 'avatar':
        _buildAvatar();
        return;
      case 'cover':
        _buildCoverImage();
        return;
      case 'mock':
        await _loadMockUsers();
        return;
      case 'directory':
        await _searchDirectory();
        return;
      // ——— A-1 本轮接线 ———
      case 'daily_english':
        await _loadDailyEnglish();
        return;
      case 'news60s':
        await _loadNews60s();
        return;
      case 'today_in_history':
        await _loadTodayInHistory();
        return;
      case 'luck':
        await _loadLuck();
        return;
      case 'bing_wallpaper':
        await _loadBingWallpaper();
        return;
      case 'baidu_hot':
        await _loadBaiduHot();
        return;
      case 'exchange_rate':
        await _loadExchangeRate();
        return;
      case 'ip_query':
        await _loadIpQuery();
        return;
      case 'phone_area':
        // 归属地必须由用户输入号码才有意义，不自动请求。
        return;
      case 'translate':
        // 翻译同理，等用户点「翻译」。
        return;
      case 'weibo_hot':
        await _loadHotList('weibo_hot');
        return;
      case 'zhihu_hot':
        await _loadHotList('zhihu_hot');
        return;
      case 'douyin_hot':
        await _loadHotList('douyin_hot');
        return;
      case 'toutiao_hot':
        await _loadHotList('toutiao_hot');
        return;
      case 'fortune':
        await _loadFortune();
        return;
      case 'moyu':
        await _loadMoyu();
        return;
      case 'dujitang':
        await _loadQuote('dujitang');
        return;
      case 'chp':
        await _loadQuote('chp');
        return;
      case 'maoyan':
        await _loadBoxOffice();
        return;
      case 'epic':
        await _loadEpicGames();
        return;
      case 'weather':
      default:
        await _loadWeather();
        return;
    }
  }

  Future<void> _loadCurrency() async {
    await _guard(() async {
      final amount = double.tryParse(_amountController.text.trim()) ?? 1;
      _converted = await _client.convertCurrency(
        amount: amount,
        from: _from,
        to: _to,
      );
      _rates = await _client.latestRates(base: _from);
    });
  }

  Future<void> _loadHolidays() async {
    await _guard(() async {
      _holidays = await _client.publicHolidays(
        year: DateTime.now().year,
        countryCode: 'CN',
      );
    });
  }

  Future<void> _loadWeather() async {
    await _guard(() async {
      _weather = await _client.weatherForecast(
        latitude: double.tryParse(_latController.text.trim()) ?? 31.2304,
        longitude: double.tryParse(_lonController.text.trim()) ?? 121.4737,
        days: 3,
      );
    });
  }

  Future<void> _loadDictionary() async {
    await _guard(() async {
      _dictionary = await _client.dictionaryLookup(_wordController.text);
    });
  }

  Future<void> _loadIpInfo() async {
    await _guard(() async {
      _ipInfo = await _client.currentIpInfo();
    });
  }

  Future<void> _shortenUrl() async {
    await _guard(() async {
      _shortLink = await _client.shortenUrl(_shortLinkController.text);
    });
  }

  void _buildDummyImage() {
    setState(() {
      _error = null;
      _dummyImage = _client.buildDummyImage(
        size: _imageSizeController.text,
        background: _imageBgController.text,
        foreground: _imageFgController.text,
        text: _imageTextController.text,
      );
    });
  }

  void _buildQrCode() {
    setState(() {
      _error = null;
      _qrCode = _client.buildQrCode(
        text: _qrTextController.text,
        size: _qrSizeController.text,
      );
    });
  }

  void _buildAvatar() {
    setState(() {
      _error = null;
      _avatar = _client.buildAvatar(
        name: _avatarNameController.text,
        background: _avatarBgController.text,
        foreground: _avatarFgController.text,
        size: _avatarSizeController.text,
      );
    });
  }

  void _buildCoverImage() {
    setState(() {
      _error = null;
      _coverImage = _client.buildCoverImage(
        width: _coverWidthController.text,
        height: _coverHeightController.text,
        seed: _coverSeedController.text,
      );
    });
  }

  Future<void> _searchBooks() async {
    await _guard(() async {
      _books = await _client.searchOpenLibrary(_bookController.text);
    });
  }

  Future<void> _loadHitokoto() async {
    await _guard(() async {
      _hitokoto = await _client.randomHitokoto();
    });
  }

  Future<void> _loadPoetry() async {
    await _guard(() async {
      _poetry = await _client.randomPoetry();
    });
  }

  Future<void> _loadMockUsers() async {
    await _guard(() async {
      _mockUsers = await _client.mockUsers(limit: 8);
    });
  }

  // ——— A-1 本轮接线的加载方法 ———

  Future<void> _loadDailyEnglish() async {
    await _guard(() async {
      _dailyEnglish = await _client.dailyEnglish();
    });
  }

  Future<void> _loadNews60s() async {
    await _guard(() async {
      _news60s = await _client.news60s();
    });
  }

  Future<void> _loadTodayInHistory() async {
    await _guard(() async {
      _historyEvents = await _client.todayInHistory();
    });
  }

  Future<void> _loadLuck() async {
    await _guard(() async {
      _luck = await _client.dailyLuck();
    });
  }

  Future<void> _loadBingWallpaper() async {
    await _guard(() async {
      _bingWallpaper = await _client.bingWallpaper();
    });
  }

  Future<void> _loadBaiduHot() async {
    await _guard(() async {
      _hotSearches = await _client.baiduHotSearch(limit: 30);
    });
  }

  // —— A-2 本轮接线：热榜 / 运势 / 摸鱼 / 语录 ——

  /// 热榜类统一加载，按 id 选平台。四个接口同源同构，只有路径不同。
  Future<void> _loadHotList(String id) async {
    await _guard(() async {
      switch (id) {
        case 'weibo_hot':
          _hotList = await _client.weiboHotSearch(limit: 30);
          return;
        case 'zhihu_hot':
          _hotList = await _client.zhihuHotSearch(limit: 30);
          return;
        case 'douyin_hot':
          _hotList = await _client.douyinHotSearch(limit: 30);
          return;
        case 'toutiao_hot':
          _hotList = await _client.toutiaoHotSearch(limit: 30);
          return;
      }
    });
  }

  Future<void> _loadFortune() async {
    await _guard(() async {
      _fortune = await _client.dailyFortune();
    });
  }

  Future<void> _loadMoyu() async {
    await _guard(() async {
      _moyu = await _client.moyuCalendar();
    });
  }

  Future<void> _loadBoxOffice() async {
    await _guard(() async {
      _boxOffice = await _client.boxOfficeRank(limit: 30);
    });
  }

  Future<void> _loadEpicGames() async {
    await _guard(() async {
      _epicGames = await _client.epicFreeGames();
    });
  }

  /// 语录类统一加载，按 id 选接口。
  Future<void> _loadQuote(String id) async {
    await _guard(() async {
      _quote = id == 'dujitang'
          ? await _client.dujitang()
          : await _client.rainbowFart();
    });
  }

  Future<void> _loadExchangeRate() async {
    await _guard(() async {
      _exchangeRate = await _client.exchangeRates(currency: 'CNY');
    });
  }

  Future<void> _loadIpQuery() async {
    await _guard(() async {
      _ipQuery = await _client.queryIp(ip: _ipQueryController.text.trim());
    });
  }

  Future<void> _loadPhoneArea() async {
    final number = _phoneController.text.trim();
    if (number.isEmpty) {
      setState(() => _error = '请输入手机号');
      return;
    }
    await _guard(() async {
      _phoneArea = await _client.phoneArea(number);
    });
  }

  Future<void> _runTranslate() async {
    final text = _translateController.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '请输入要翻译的内容');
      return;
    }
    await _guard(() async {
      _translation = await _client.translate(
        text: text,
        from: _translateFrom,
        to: _translateTo,
      );
    });
  }

  Future<void> _searchDirectory() async {
    await _guard(() async {
      _directoryEntries = await PublicApiIndexLoader.search(
        query: _directoryController.text,
        category: _directoryCategory == '全部' ? null : _directoryCategory,
        noAuthOnly: true,
        httpsOnly: true,
        domesticOnly: true,
        limit: 80,
      );
    });
  }

  Future<void> _guard(Future<void> Function() run) async {
    // intent 用当前工具：切换工具后，旧工具的慢响应/报错不得再写状态，
    // 否则会出现「已经在看 IP，却弹天气接口的错误」这种串台。
    final token = _requestGeneration.begin(_activeTool);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await run();
    } catch (e) {
      // 原来是裸赋值：既没判过期，也没 setState —— 错误压根刷不到界面上。
      if (!mounted || !_requestGeneration.isCurrent(token)) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted && _requestGeneration.isCurrent(token)) {
        setState(() => _loading = false);
      }
    }
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
    setState(() {
      _activeTool = id;
      _activeGroup = tool.group;
      _recentToolIds.remove(id);
      _recentToolIds.insert(0, id);
      if (_recentToolIds.length > 5) {
        _recentToolIds.removeRange(5, _recentToolIds.length);
      }
    });
    _runActiveTool();
  }

  Future<void> _copyText(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制$label'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _ipInfoText(IpInfoResult info) {
    return [
      'IP: ${info.ip}',
      if (info.city.isNotEmpty ||
          info.region.isNotEmpty ||
          info.country.isNotEmpty)
        '位置: ${[info.city, info.region, info.country].where((e) => e.isNotEmpty).join(' / ')}',
      if (info.org.isNotEmpty) '组织: ${info.org}',
      if (info.timezone.isNotEmpty) '时区: ${info.timezone}',
    ].join('\n');
  }

  void _applyImagePreset({
    required String size,
    required String background,
    required String foreground,
    String? text,
  }) {
    setState(() {
      _imageSizeController.text = size;
      _imageBgController.text = background;
      _imageFgController.text = foreground;
      if (text != null) _imageTextController.text = text;
    });
    _buildDummyImage();
  }

  void _applyQrPreset(String text, {String size = '220x220'}) {
    setState(() {
      _qrTextController.text = text;
      _qrSizeController.text = size;
    });
    _buildQrCode();
  }

  void _applyAvatarPreset({
    required String name,
    required String background,
    required String foreground,
  }) {
    setState(() {
      _avatarNameController.text = name;
      _avatarBgController.text = background;
      _avatarFgController.text = foreground;
    });
    _buildAvatar();
  }

  void _applyCoverPreset({
    required String width,
    required String height,
    required String seed,
  }) {
    setState(() {
      _coverWidthController.text = width;
      _coverHeightController.text = height;
      _coverSeedController.text = seed;
    });
    _buildCoverImage();
  }

  List<PublicApiDirectoryEntry> _filteredDirectoryEntries() {
    return _directoryEntries.where((entry) {
      return switch (_directoryStatus) {
        '已接入' => entry.isIntegrated,
        '推荐接入' => entry.isRecommended && !entry.isIntegrated,
        '待接入' => !entry.isIntegrated,
        _ => true,
      };
    }).toList();
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
              style: const TextStyle(
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
          _browseAllTools
              ? Icons.expand_less_rounded
              : Icons.grid_view_rounded,
          size: 18,
        ),
        label: Text(_browseAllTools ? '收起全部工具' : '切换其他工具'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          foregroundColor: AppTokens.textPrimary,
          side: const BorderSide(color: Color(0xFFE7ECF5)),
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
      leading: AppBackButton(
        onPressed: () => Navigator.maybePop(context),
        label: 'API 能力中心',
      ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7ECF5)),
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
    final recentTools = _recentToolIds.map(PublicApiRegistry.byId).toList();
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
            side: const BorderSide(color: Color(0xFFE7ECF5)),
            backgroundColor: Colors.white,
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

  Widget _buildCurrencyPanel() {
    return ApiHubCurrencyPanel(
      amountController: _amountController,
      from: _from,
      to: _to,
      converted: _converted,
      rates: _rates,
      onFromChanged: (v) => setState(() => _from = v),
      onToChanged: (v) => setState(() => _to = v),
      onSubmit: _loadCurrency,
    );
  }

  Widget _buildHolidayPanel() {
    return ApiHubHolidayPanel(holidays: _holidays);
  }

  Widget _buildWeatherPanel() {
    return ApiHubWeatherPanel(
      latController: _latController,
      lonController: _lonController,
      weather: _weather,
      onSubmit: _loadWeather,
    );
  }

  Widget _buildIpPanel() {
    final info = _ipInfo;
    return ApiHubPanel(
      title: 'IPinfo 当前公网 IP',
      subtitle: '查询当前网络出口 IP、地区、运营商/组织信息',
      icon: Icons.public_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _loadIpInfo,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新查询'),
            ),
          ),
          const SizedBox(height: 12),
          if (info == null)
            const AppEmptyState(
              title: '暂无 IP 信息',
              message: '点击重新查询获取当前公网 IP',
              icon: Icons.public_rounded,
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE7ECF5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.ip,
                    style: const TextStyle(
                      color: AppTokens.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _copyText(info.ip, ' IP'),
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('复制 IP'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _copyText(_ipInfoText(info), '完整信息'),
                        icon: const Icon(Icons.copy_all_rounded, size: 16),
                        label: const Text('复制完整信息'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AppStatusPill(
                        label: [
                          info.city,
                          info.region,
                          info.country,
                        ].where((e) => e.isNotEmpty).join(' / '),
                        icon: Icons.place_rounded,
                        color: AppTokens.primaryBlue,
                      ),
                      if (info.org.isNotEmpty)
                        AppStatusPill(
                          label: info.org,
                          icon: Icons.business_rounded,
                          color: AppTokens.emerald,
                        ),
                      if (info.timezone.isNotEmpty)
                        AppStatusPill(
                          label: info.timezone,
                          icon: Icons.schedule_rounded,
                          color: AppTokens.violet,
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildShortLinkPanel() {
    return ApiHubShortLinkPanel(
      controller: _shortLinkController,
      result: _shortLink,
      onSubmit: _shortenUrl,
      onApplyPublicApisPreset: () {
        setState(() {
          _shortLinkController.text =
              'https://github.com/public-apis/public-apis';
        });
        _shortenUrl();
      },
      onApplyLocalPreviewPreset: () {
        setState(() {
          _shortLinkController.text = 'http://127.0.0.1:8080/';
        });
      },
      onCopy: (url) => _copyText(url, '短链接'),
      onApplyQrPreset: (url) => _applyQrPreset(url, size: '260x260'),
    );
  }

  Widget _buildQrPanel() {
    return ApiHubQrPanel(
      textController: _qrTextController,
      sizeController: _qrSizeController,
      result: _qrCode,
      onSubmit: _buildQrCode,
      onApplySizePreset: (size) {
        setState(() => _qrSizeController.text = size);
        _buildQrCode();
      },
      onApplyTextPreset: (text, {size}) =>
          _applyQrPreset(text, size: size ?? '220x220'),
      onCopyContent: (text) => _copyText(text, '二维码内容'),
      onCopyUrl: (url) => _copyText(url, '二维码图片 URL'),
    );
  }

  Widget _buildAvatarPanel() {
    return ApiHubAvatarPanel(
      nameController: _avatarNameController,
      sizeController: _avatarSizeController,
      bgController: _avatarBgController,
      fgController: _avatarFgController,
      result: _avatar,
      onSubmit: _buildAvatar,
      onApplyPreset: _applyAvatarPreset,
      onCopy: (url) => _copyText(url, '头像 URL'),
      onApplyQrPreset: (url) => _applyQrPreset(url, size: '260x260'),
    );
  }

  Widget _buildCoverPanel() {
    return ApiHubCoverPanel(
      widthController: _coverWidthController,
      heightController: _coverHeightController,
      seedController: _coverSeedController,
      result: _coverImage,
      onSubmit: _buildCoverImage,
      onApplyPreset: _applyCoverPreset,
      onCopy: (url) => _copyText(url, '封面 URL'),
      onApplyQrPreset: (url) => _applyQrPreset(url, size: '260x260'),
    );
  }

  Widget _buildDummyImagePanel() {
    return ApiHubDummyImagePanel(
      sizeController: _imageSizeController,
      textController: _imageTextController,
      bgController: _imageBgController,
      fgController: _imageFgController,
      result: _dummyImage,
      onSubmit: _buildDummyImage,
      onApplyPreset: _applyImagePreset,
      onCopy: (url) => _copyText(url, '图片 URL'),
    );
  }

  Widget _buildDictionaryPanel() {
    final result = _dictionary;
    return ApiHubPanel(
      title: 'Free Dictionary 英文词典',
      subtitle: '查询释义、词性和例句',
      icon: Icons.translate_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ApiHubSearchRow(
            controller: _wordController,
            label: '英文单词',
            buttonLabel: '查询',
            onSubmit: _loadDictionary,
          ),
          const SizedBox(height: 12),
          if (result == null)
            const AppEmptyState(
              title: '暂无释义',
              message: '输入英文单词后查询',
              icon: Icons.translate_rounded,
            )
          else ...[
            Text(
              '${result.word}${result.phonetic.isEmpty ? '' : ' · ${result.phonetic}'}',
              style: const TextStyle(
                color: AppTokens.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            ...result.meanings.map(ApiHubDictionaryMeaningTile.new),
          ],
        ],
      ),
    );
  }

  Widget _buildBooksPanel() {
    return ApiHubBooksPanel(
      controller: _bookController,
      books: _books,
      onSubmit: _searchBooks,
    );
  }

  Widget _buildHitokotoPanel() {
    final quote = _hitokoto;
    return ApiHubPanel(
      title: 'Hitokoto 随机一言',
      subtitle: '动漫、文学、诗词随机语录，免密钥无配额',
      icon: Icons.format_quote_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _loadHitokoto,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('换一句'),
            ),
          ),
          const SizedBox(height: 12),
          if (quote == null)
            const Text(
              '点「换一句」获取一条随机语录',
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else ...[
            SelectableText(
              quote.text,
              style: const TextStyle(
                fontSize: 17,
                height: 1.6,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (quote.sourceLabel.isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '—— ${quote.sourceLabel}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildPoetryPanel() {
    final poem = _poetry;
    return ApiHubPanel(
      title: '今日诗词 诗词一言',
      subtitle: '随机古诗词，附全诗与白话翻译',
      icon: Icons.auto_stories_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _loadPoetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('换一首'),
            ),
          ),
          const SizedBox(height: 12),
          if (poem == null)
            const Text(
              '点「换一首」获取一句随机诗词',
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else ...[
            SelectableText(
              poem.content,
              style: const TextStyle(
                fontSize: 18,
                height: 1.7,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              [
                if (poem.title.isNotEmpty) '《${poem.title}》',
                if (poem.attribution.isNotEmpty) poem.attribution,
              ].join('  '),
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
            if (poem.fullPoem.isNotEmpty) ...[
              const SizedBox(height: 14),
              // 全诗可能很长（《春江花月夜》18 句），折叠起来免得把面板撑爆。
              // 水波纹语境由 ApiHubPanel 外壳的 Material 提供，这里不用再包。
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: const Text(
                    '查看全诗',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  children: [
                    SelectableText(
                      poem.fullPoem.join('\n'),
                      style: const TextStyle(height: 1.8, fontSize: 14),
                    ),
                    if (poem.translation.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '白话翻译',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        poem.translation.join('\n'),
                        style: const TextStyle(
                          height: 1.7,
                          fontSize: 13,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // A-1 本轮接线引入的 10 个面板。
  // ══════════════════════════════════════════════════════════════

  Widget _buildDailyEnglishPanel() {
    final daily = _dailyEnglish;
    return ApiHubPanel(
      title: '每日英语',
      subtitle: '金山词霸每日一句，免密钥',
      icon: Icons.translate_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _loadDailyEnglish,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('换一句'),
            ),
          ),
          const SizedBox(height: 12),
          if (daily == null)
            const Text(
              '点「换一句」获取今日英文金句',
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else ...[
            SelectableText(
              daily.content,
              style: const TextStyle(
                fontSize: 17,
                height: 1.6,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (daily.displayTranslation.isNotEmpty) ...[
              const SizedBox(height: 10),
              SelectableText(
                daily.displayTranslation,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildNews60sPanel() {
    final news = _news60s;
    return ApiHubPanel(
      title: '每日 60 秒资讯',
      subtitle: '每天 15 条国内外要闻，免密钥',
      icon: Icons.newspaper_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _loadNews60s,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('刷新资讯'),
            ),
          ),
          const SizedBox(height: 12),
          if (news == null)
            const Text(
              '点「刷新资讯」拉取今日要闻',
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else ...[
            Text(
              [
                if (news.date.isNotEmpty) news.date,
                if (news.dayOfWeek.isNotEmpty) news.dayOfWeek,
                if (news.lunarDate.isNotEmpty) news.lunarDate,
              ].join('  '),
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < news.items.length; i++) ...[
              SelectableText(
                '${i + 1}. ${news.items[i]}',
                style: const TextStyle(fontSize: 14, height: 1.7),
              ),
              const SizedBox(height: 8),
            ],
            if (news.tips.isNotEmpty) ...[
              const SizedBox(height: 4),
              const Text(
                '每日一句',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                news.tips.join('\n'),
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.7,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildTodayInHistoryPanel() {
    return ApiHubPanel(
      title: '历史上的今天',
      subtitle: '同日发生的历史事件，免密钥',
      icon: Icons.history_edu_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _loadTodayInHistory,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('刷新'),
            ),
          ),
          const SizedBox(height: 12),
          if (_historyEvents.isEmpty)
            const Text(
              '点「刷新」拉取今日历史事件',
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else
            for (final e in _historyEvents) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(
                      e.year,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          e.title,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (e.description.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            e.description,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.5,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  Widget _buildLuckPanel() {
    final luck = _luck;
    return ApiHubPanel(
      title: '老黄历',
      subtitle: '农历、宜忌、干支生肖，免密钥',
      icon: Icons.calendar_month_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _loadLuck,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('查今日'),
            ),
          ),
          const SizedBox(height: 12),
          if (luck == null)
            const Text(
              '点「查今日」获取今天的黄历',
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else ...[
            Text(
              [
                if (luck.date.isNotEmpty) luck.date,
                if (luck.lunarDate.isNotEmpty) luck.lunarDate,
              ].join('  '),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            if (luck.ganZhiYear.isNotEmpty || luck.zodiac.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                [
                  // 干支串本身已含「年」字（如「丙午年 【马年】 丁酉月 己丑日」），
                  // 不能再拼一个「年」；生肖同理（zodiac 已是「马年」）。
                  if (luck.ganZhiYear.isNotEmpty) luck.ganZhiYear,
                  if (luck.zodiac.isNotEmpty) '属$luck.zodiac',
                ].join('  '),
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
            ],
            if (luck.luckDesc.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                luck.luckDesc,
                style: const TextStyle(fontSize: 14, height: 1.6),
              ),
            ],
            if (luck.suit.isNotEmpty || luck.avoid.isNotEmpty) ...[
              const SizedBox(height: 12),
              if (luck.suit.isNotEmpty)
                _luckRow('宜', luck.suit, const Color(0xFF16A34A)),
              if (luck.avoid.isNotEmpty) ...[
                const SizedBox(height: 6),
                _luckRow('忌', luck.avoid, const Color(0xFFDC2626)),
              ],
            ],
          ],
        ],
      ),
    );
  }

  Widget _luckRow(String label, List<String> values, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            values.join('、'),
            style: const TextStyle(fontSize: 13.5, height: 1.6),
          ),
        ),
      ],
    );
  }

  Widget _buildBingWallpaperPanel() {
    final wall = _bingWallpaper;
    return ApiHubPanel(
      title: '必应每日壁纸',
      subtitle: '每日一张必应首页图，免密钥',
      icon: Icons.wallpaper_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _loadBingWallpaper,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('换一张'),
            ),
          ),
          const SizedBox(height: 12),
          if (wall == null)
            const Text(
              '点「换一张」获取今日壁纸',
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else ...[
            if (wall.url.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  wall.url,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 120,
                    child: Center(
                      child: Text(
                        '图片加载失败',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            if (wall.title.isNotEmpty)
              SelectableText(
                wall.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (wall.copyright.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                wall.copyright,
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
            if (wall.url.isNotEmpty) ...[
              const SizedBox(height: 10),
              SelectableText(
                wall.url,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // —— A-2 本轮接线：热榜 / 运势 / 摸鱼 / 语录面板 ——

  /// 热榜面板：四个平台共用一个布局，标题按 id 取。
  Widget _buildHotListPanel(String id) {
    const meta = <String, (String, String, IconData)>{
      'weibo_hot': ('微博热搜', '60s API，免密钥', Icons.local_fire_department_rounded),
      'zhihu_hot': ('知乎热榜', '60s API，免密钥', Icons.question_answer_rounded),
      'douyin_hot': ('抖音热点', '60s API，免密钥', Icons.music_note_rounded),
      'toutiao_hot': ('头条热榜', '60s API，免密钥', Icons.article_rounded),
    };
    final info = meta[id] ?? meta['weibo_hot']!;
    return ApiHubPanel(
      title: info.$1,
      subtitle: info.$2,
      icon: info.$3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => _loadHotList(id),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('刷新榜单'),
            ),
          ),
          const SizedBox(height: 12),
          if (_hotList.isEmpty)
            const Text(
              '点「刷新榜单」拉取实时榜单',
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else
            for (var i = 0; i < _hotList.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: InkWell(
                  // 项目没有 url_launcher 依赖（见 announcement_popup.dart 的
                  // 说明），沿用既有先例：点一下把链接复制到剪贴板。
                  onTap: _hotList[i].url.isEmpty
                      ? null
                      : () => _copyText(_hotList[i].url, '链接'),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 26,
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: i < 3
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 用 Text 而非 SelectableText：后者会抢占 tap 手势，
                              // 外层 InkWell 的「点一下复制链接」永远收不到点击。
                              Text(
                                _hotList[i].title,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.45,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (_hotList[i].hot.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  _hotList[i].hot,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                              if (_hotList[i].url.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                const Text(
                                  '点击复制链接',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFFCBD5E1),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildFortunePanel() {
    final fortune = _fortune;
    return ApiHubPanel(
      title: '今日运势',
      subtitle: '60s API，免密钥',
      icon: Icons.emoji_events_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _loadFortune,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('查看今日运势'),
            ),
          ),
          const SizedBox(height: 12),
          if (fortune == null)
            const Text(
              '点上方按钮查看今日运势',
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else ...[
            if (fortune.luckDesc.isNotEmpty)
              Text(
                fortune.luckDesc,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFF59E0B),
                ),
              ),
            const SizedBox(height: 6),
            if (fortune.date.isNotEmpty)
              Text(
                '日期：${fortune.date}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF94A3B8),
                ),
              ),
            if (fortune.zodiac.isNotEmpty)
              Text(
                '生肖：${fortune.zodiac}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF94A3B8),
                ),
              ),
            if (fortune.luckTip.isNotEmpty) ...[
              const SizedBox(height: 10),
              SelectableText(
                fortune.luckTip,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildMoyuPanel() {
    final moyu = _moyu;
    return ApiHubPanel(
      title: '摸鱼日历',
      subtitle: '60s API，免密钥',
      icon: Icons.beach_access_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _loadMoyu,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('看看离放假还有几天'),
            ),
          ),
          const SizedBox(height: 12),
          if (moyu == null)
            const Text(
              '点上方按钮查看摸鱼日历',
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else ...[
            if (moyu.daysLeft > 0)
              Text(
                '距${moyu.nextHolidayName.isEmpty ? '下个节假日' : moyu.nextHolidayName}还有 ${moyu.daysLeft} 天',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF14B8A6),
                ),
              ),
            const SizedBox(height: 6),
            if (moyu.gregorianDate.isNotEmpty)
              Text(
                '今天：${moyu.gregorianDate}'
                '${moyu.weekday.isEmpty ? '' : ' ${moyu.weekday}'}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF94A3B8),
                ),
              ),
            if (moyu.lunarDate.isNotEmpty)
              Text(
                '农历：${moyu.lunarDate}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF94A3B8),
                ),
              ),
            if (moyu.nextHolidayDate.isNotEmpty)
              Text(
                '下次放假：${moyu.nextHolidayDate}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF94A3B8),
                ),
              ),
            if (moyu.description.isNotEmpty) ...[
              const SizedBox(height: 10),
              SelectableText(
                moyu.description,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // —— A-3 批次3接线：票房 / Epic 面板 ——

  Widget _buildBoxOfficePanel() {
    return ApiHubPanel(
      title: '猫眼票房',
      subtitle: '影史票房总榜，60s API 免密钥',
      icon: Icons.movie_filter_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _loadBoxOffice,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('刷新榜单'),
            ),
          ),
          const SizedBox(height: 12),
          if (_boxOffice.isEmpty)
            const Text(
              '点「刷新榜单」拉取票房总榜',
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else
            for (final item in _boxOffice)
              Padding(
                padding: const EdgeInsets.only(bottom: 11),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${item.rank}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: item.rank <= 3
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            item.movieName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (item.boxOfficeDesc.isNotEmpty ||
                              item.releaseYear.isNotEmpty)
                            Text(
                              [
                                if (item.releaseYear.isNotEmpty)
                                  item.releaseYear,
                                if (item.boxOfficeDesc.isNotEmpty)
                                  item.boxOfficeDesc,
                              ].join(' · '),
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildEpicPanel() {
    return ApiHubPanel(
      title: 'Epic 免费游戏',
      subtitle: 'Epic 本周免费，60s API 免密钥',
      icon: Icons.videogame_asset_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _loadEpicGames,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('刷新本周免费'),
            ),
          ),
          const SizedBox(height: 12),
          if (_epicGames.isEmpty)
            const Text(
              '点「刷新本周免费」看看能白拿什么',
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else
            for (final game in _epicGames)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      game.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      [
                        if (game.originalPriceDesc.isNotEmpty)
                          '原价 ${game.originalPriceDesc}',
                        if (game.seller.isNotEmpty) game.seller,
                        if (game.freeEnd.isNotEmpty) '截至 ${game.freeEnd}',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  /// 语录面板：毒鸡汤与彩虹屁同构，只有标题和按钮文案不同。
  Widget _buildQuotePanel(String id) {
    final isDujitang = id == 'dujitang';
    final quote = _quote;
    return ApiHubPanel(
      title: isDujitang ? '毒鸡汤' : '随机彩虹屁',
      subtitle: 'Shadiao API，免密钥',
      icon: isDujitang
          ? Icons.sentiment_very_dissatisfied_rounded
          : Icons.auto_awesome_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => _loadQuote(id),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(isDujitang ? '换一条扎心的' : '再夸我一句'),
            ),
          ),
          const SizedBox(height: 12),
          if (quote == null)
            const Text('点上方按钮随机来一条', style: TextStyle(color: Color(0xFF64748B)))
          else
            SelectableText(
              quote.text,
              style: const TextStyle(fontSize: 15, height: 1.6),
            ),
        ],
      ),
    );
  }

  Widget _buildBaiduHotPanel() {
    return ApiHubPanel(
      title: '百度实时热搜',
      subtitle: '当前热搜榜，免密钥',
      icon: Icons.local_fire_department_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _loadBaiduHot,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('刷新榜单'),
            ),
          ),
          const SizedBox(height: 12),
          if (_hotSearches.isEmpty)
            const Text(
              '点「刷新榜单」拉取实时热搜',
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else
            for (var i = 0; i < _hotSearches.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: i < 3
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            _hotSearches[i].title,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.45,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (_hotSearches[i].hot.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              _hotSearches[i].hot,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildExchangeRatePanel() {
    final rate = _exchangeRate;
    final entries = rate == null
        ? const <MapEntry<String, double>>[]
        : (rate.rates.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
    return ApiHubPanel(
      title: '实时汇率',
      subtitle: '以人民币为基准的最新汇率，免密钥',
      icon: Icons.currency_exchange_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _loadExchangeRate,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('刷新汇率'),
            ),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const Text(
              '点「刷新汇率」拉取最新汇率',
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else ...[
            if (rate!.updated.isNotEmpty) ...[
              Text(
                '更新于 ${rate.updated}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 10),
            ],
            Text(
              '1 ${rate.base} =',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 8),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 62,
                      child: Text(
                        e.key,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        e.value.toStringAsFixed(4),
                        style: const TextStyle(fontSize: 13.5),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildIpQueryPanel() {
    final result = _ipQuery;
    return ApiHubPanel(
      title: 'IP 归属查询',
      subtitle: '留空则查本机出口 IP，免密钥',
      icon: Icons.public_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ApiHubSearchRow(
            controller: _ipQueryController,
            label: 'IP 地址（留空查本机）',
            buttonLabel: '查询',
            onSubmit: _loadIpQuery,
          ),
          const SizedBox(height: 12),
          if (result == null)
            const Text('点「查询」获取归属地', style: TextStyle(color: Color(0xFF64748B)))
          else ...[
            _infoRow('IP', result.ip),
            if (result.location.isNotEmpty) _infoRow('归属地', result.location),
            if (result.isp.isNotEmpty) _infoRow('运营商', result.isp),
          ],
        ],
      ),
    );
  }

  Widget _buildPhoneAreaPanel() {
    final result = _phoneArea;
    return ApiHubPanel(
      title: '手机号归属地',
      subtitle: '查询号段所属省份、城市与运营商，免密钥',
      icon: Icons.phone_android_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ApiHubSearchRow(
            controller: _phoneController,
            label: '手机号，例如 13800138000',
            buttonLabel: '查询归属地',
            onSubmit: _loadPhoneArea,
          ),
          const SizedBox(height: 12),
          if (result == null)
            const Text(
              '点「查询归属地」获取结果',
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else ...[
            if (result.province.isNotEmpty) _infoRow('省份', result.province),
            if (result.city.isNotEmpty) _infoRow('城市', result.city),
            if (result.carrier.isNotEmpty) _infoRow('运营商', result.carrier),
            if (result.province.isEmpty &&
                result.city.isEmpty &&
                result.carrier.isEmpty)
              const Text(
                '接口没有返回该号段的归属信息，换个号码再试',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildTranslatePanel() {
    final result = _translation;
    return ApiHubPanel(
      title: '中英互译',
      subtitle: 'MyMemory 翻译，免密钥（有每日额度）',
      icon: Icons.g_translate_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _translateFrom,
                  decoration: const InputDecoration(
                    labelText: '源语言',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('英语')),
                    DropdownMenuItem(value: 'zh', child: Text('中文')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _translateFrom = v);
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward_rounded, size: 18),
              ),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _translateTo,
                  decoration: const InputDecoration(
                    labelText: '目标语言',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'zh', child: Text('中文')),
                    DropdownMenuItem(value: 'en', child: Text('英语')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _translateTo = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ApiHubSearchRow(
            controller: _translateController,
            label: '要翻译的内容',
            buttonLabel: '翻译',
            onSubmit: _runTranslate,
          ),
          const SizedBox(height: 12),
          if (result == null)
            const Text('点「翻译」查看结果', style: TextStyle(color: Color(0xFF64748B)))
          else
            SelectableText(
              result.translatedText,
              style: const TextStyle(fontSize: 15, height: 1.6),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 13.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMockPanel() {
    return ApiHubPanel(
      title: 'DummyJSON Mock 用户',
      subtitle: '快速获取头像、姓名、邮箱、地区等用户资料，适合列表和资料卡测试',
      icon: Icons.badge_rounded,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _loadMockUsers,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('刷新用户'),
            ),
          ),
          const SizedBox(height: 10),
          if (_mockUsers.isEmpty)
            const AppEmptyState(
              title: '暂无用户资料',
              message: '点击刷新用户获取 DummyJSON 数据',
              icon: Icons.badge_rounded,
            )
          else
            ..._mockUsers.map(
              (user) => ApiHubMockUserTile(
                user,
                onCopy: () => _copyText(user.copyText, '用户资料'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDirectoryPanel() {
    const categories = [
      '全部',
      'Weather',
      'Development',
      'Geocoding',
      'Art & Design',
      'Food & Drink',
      'Environment',
      'Government',
      'Games & Comics',
    ];
    final visibleEntries = _filteredDirectoryEntries();
    return ApiHubPanel(
      title: '国内可用 API 清单',
      subtitle: '从免密钥 HTTPS 候选中实测筛出 80 个可用接口，按分类继续接入工具',
      icon: Icons.travel_explore_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((category) {
                final selected = _directoryCategory == category;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: selected,
                    label: Text(category),
                    onSelected: (_) {
                      setState(() => _directoryCategory = category);
                      _searchDirectory();
                    },
                    selectedColor: AppTokens.orange.withValues(alpha: 0.14),
                    labelStyle: TextStyle(
                      color: selected
                          ? AppTokens.orange
                          : AppTokens.textSecondary,
                      fontWeight: FontWeight.w900,
                    ),
                    side: const BorderSide(color: Color(0xFFE7ECF5)),
                    backgroundColor: Colors.white,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['全部', '已接入', '推荐接入', '待接入'].map((status) {
              final selected = _directoryStatus == status;
              return ChoiceChip(
                selected: selected,
                label: Text(status),
                onSelected: (_) => setState(() => _directoryStatus = status),
                selectedColor: AppTokens.violet.withValues(alpha: 0.14),
                labelStyle: TextStyle(
                  color: selected ? AppTokens.violet : AppTokens.textSecondary,
                  fontWeight: FontWeight.w900,
                ),
                side: const BorderSide(color: Color(0xFFE7ECF5)),
                backgroundColor: Colors.white,
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          ApiHubSearchRow(
            controller: _directoryController,
            label: '筛选：weather / ip / food / game / government',
            buttonLabel: '筛选',
            onSubmit: _searchDirectory,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppStatusPill(
                label: '当前 ${visibleEntries.length} 条',
                icon: Icons.cloud_done_rounded,
                color: AppTokens.emerald,
              ),
              const AppStatusPill(
                label: '仅免密钥 HTTPS',
                icon: Icons.lock_open_rounded,
                color: AppTokens.primaryBlue,
              ),
              AppStatusPill(
                label: _directoryCategory,
                icon: Icons.category_rounded,
                color: AppTokens.orange,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (visibleEntries.isEmpty)
            const AppEmptyState(
              title: '暂无可用 API',
              message: '换个关键词，或切回“全部”查看清单',
              icon: Icons.travel_explore_rounded,
            )
          else
            ...visibleEntries
                .take(30)
                .map(
                  (entry) => ApiHubDirectoryEntryTile(
                    entry,
                    onTap: () => _showDirectoryDetail(entry),
                  ),
                ),
        ],
      ),
    );
  }

  void _showDirectoryDetail(PublicApiDirectoryEntry entry) {
    showAppModalBottomSheet<void>(
      context: context,
      title: entry.name,
      subtitle: '${entry.category} · ${entry.method} · ${entry.auth}',
      builder: (context) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppStatusPill(
                    label: entry.isIntegrated ? '已接入' : '待接入',
                    icon: entry.isIntegrated
                        ? Icons.check_circle_rounded
                        : Icons.add_task_rounded,
                    color: entry.isIntegrated
                        ? AppTokens.emerald
                        : AppTokens.orange,
                  ),
                  if (entry.isRecommended)
                    const AppStatusPill(
                      label: '推荐接入',
                      icon: Icons.star_rounded,
                      color: AppTokens.violet,
                    ),
                  AppStatusPill(
                    label: entry.latencyMs == null
                        ? '耗时未知'
                        : '${entry.latencyMs}ms',
                    icon: Icons.speed_rounded,
                    color: AppTokens.primaryBlue,
                  ),
                  AppStatusPill(
                    label: 'HTTP ${entry.httpStatus ?? '--'}',
                    icon: Icons.http_rounded,
                    color: AppTokens.emerald,
                  ),
                  AppStatusPill(
                    label: entry.https ? 'HTTPS' : 'HTTP',
                    icon: Icons.lock_open_rounded,
                    color: entry.https ? AppTokens.emerald : AppTokens.orange,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ApiHubDirectoryDetailBlock(
                title: '用途说明',
                child: Text(
                  entry.description,
                  style: const TextStyle(
                    color: AppTokens.textPrimary,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ApiHubDirectoryDetailBlock(
                title: '接口地址',
                child: SelectableText(
                  entry.url,
                  style: const TextStyle(
                    color: AppTokens.primaryBlue,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ApiHubDirectoryDetailBlock(
                title: '接入建议',
                child: Text(
                  entry.isIntegrated
                      ? '已经作为 Box 工具接入，可继续打磨交互和错误状态。'
                      : entry.isRecommended
                      ? '适合作为下一批轻量工具接入，建议先验证具体接口文档和返回结构。'
                      : '暂时保留为目录展示，后续按具体使用场景再接入。',
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _copyText(entry.url, ' API URL'),
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('复制 URL'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _applyQrPreset(entry.url, size: '260x260');
                    },
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: const Text('转二维码'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
