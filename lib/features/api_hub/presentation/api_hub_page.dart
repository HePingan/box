import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'package:box/core/load_generation.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_back_button.dart';
import 'package:box/design_system/widgets/app_bottom_sheet.dart';
import 'package:box/design_system/widgets/app_cards.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';

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

  Future<void> _loadMockUsers() async {
    await _guard(() async {
      _mockUsers = await _client.mockUsers(limit: 8);
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

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildHero()),
          SliverToBoxAdapter(child: _buildQuickWorkbench()),
          SliverToBoxAdapter(child: _buildRecentTools()),
          SliverToBoxAdapter(child: _buildGroupSwitcher()),
          SliverToBoxAdapter(child: _buildToolGrid()),
          SliverToBoxAdapter(child: _buildActivePanel()),
          const SliverToBoxAdapter(
            child: SizedBox(height: AppTokens.pageBottomPadding + 28),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return AppLightHeroCard(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      eyebrow: 'PUBLIC APIS',
      title: 'API 能力中心',
      subtitle: '国内网络实测可用 · 短链 / 二维码 / 头像 / 随机封面 / API 清单',
      badge: '12 TOOLS',
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
      metrics: const [
        Expanded(
          child: ApiHubMetric(value: '12', label: '保留能力'),
        ),
        SizedBox(width: 8),
        Expanded(
          child: ApiHubMetric(value: '5', label: '在线可测'),
        ),
        SizedBox(width: 8),
        Expanded(
          child: ApiHubMetric(value: 'Web', label: '可预览'),
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
    if (_error != null) {
      return ApiHubPanel(
        title: '加载失败',
        subtitle: _error!,
        icon: Icons.error_outline_rounded,
        child: FilledButton.icon(
          onPressed: _runActiveTool,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('重试'),
        ),
      );
    }

    if (_loading) {
      return const ApiHubPanel(
        title: '正在请求公开 API',
        subtitle: '首次加载可能受网络或免费接口限流影响',
        icon: Icons.cloud_sync_rounded,
        child: Center(
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
