import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_bottom_sheet.dart';
import 'package:box/design_system/widgets/app_cards.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';

import '../application/public_api_registry.dart';
import '../data/public_api_client.dart';
import '../data/public_api_index_loader.dart';
import '../domain/public_api_models.dart';

import 'widgets/api_hub_widgets.dart';

class ApiHubPage extends StatefulWidget {
  const ApiHubPage({super.key, this.initialTool});

  final String? initialTool;

  @override
  State<ApiHubPage> createState() => _ApiHubPageState();
}

class _ApiHubPageState extends State<ApiHubPage> {
  final PublicApiClient _client = PublicApiClient();
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await run();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
      leading: IconButton.filledTonal(
        onPressed: () => Navigator.maybePop(context),
        icon: const Icon(Icons.arrow_back_rounded),
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
    final quickIds = const [
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
    final codes = const ['USD', 'CNY', 'EUR', 'JPY', 'HKD', 'GBP'];
    return ApiHubPanel(
      title: 'Frankfurter 汇率换算',
      subtitle: '免费外汇接口，适合工具页汇率能力',
      icon: Icons.currency_exchange_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '金额'),
                  onSubmitted: (_) => _loadCurrency(),
                ),
              ),
              const SizedBox(width: 8),
              ApiHubCurrencyDropDown(
                value: _from,
                codes: codes,
                onChanged: (v) => setState(() => _from = v),
              ),
              const SizedBox(width: 8),
              ApiHubCurrencyDropDown(
                value: _to,
                codes: codes,
                onChanged: (v) => setState(() => _to = v),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _loadCurrency,
            icon: const Icon(Icons.sync_alt_rounded),
            label: const Text('换算'),
          ),
          const SizedBox(height: 14),
          Text(
            _converted == null
                ? '暂无换算结果'
                : '${_amountController.text} $_from ≈ ${_converted!.toStringAsFixed(2)} $_to',
            style: const TextStyle(
              color: AppTokens.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _rates.entries
                .map(
                  (e) => AppStatusPill(
                    label: '${e.key} ${e.value.toStringAsFixed(2)}',
                    icon: Icons.trending_up_rounded,
                    color: AppTokens.emerald,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHolidayPanel() {
    final now = DateTime.now();
    final upcoming = _holidays.where((item) {
      final date = DateTime.tryParse(item.date);
      return date != null &&
          !date.isBefore(DateTime(now.year, now.month, now.day));
    }).toList();
    return ApiHubPanel(
      title: 'Nager.Date 节假日',
      subtitle: '${now.year} 年中国公开节假日，首页工作台可复用',
      icon: Icons.event_available_rounded,
      child: Column(
        children: [
          if (_holidays.isEmpty)
            const AppEmptyState(
              title: '暂无节假日数据',
              message: '接口可能暂未提供当前地区',
              icon: Icons.event_busy_rounded,
            )
          else
            ...(upcoming.isEmpty ? _holidays : upcoming).take(8).map((item) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppTokens.orange.withValues(alpha: 0.12),
                  child: const Icon(
                    Icons.event_available_rounded,
                    color: AppTokens.orange,
                  ),
                ),
                title: Text(item.localName),
                subtitle: Text('${item.date} · ${item.name}'),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildWeatherPanel() {
    final weather = _weather;
    return ApiHubPanel(
      title: 'Open-Meteo 天气预报',
      subtitle: '输入经纬度获取 3 天天气，默认上海',
      icon: Icons.wb_cloudy_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '纬度'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _lonController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '经度'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _loadWeather, child: const Text('查询')),
            ],
          ),
          const SizedBox(height: 12),
          if (weather == null)
            const AppEmptyState(
              title: '暂无天气',
              message: '输入坐标后查询',
              icon: Icons.wb_cloudy_rounded,
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppStatusPill(
                  label:
                      '当前 ${weather.currentTemperature?.toStringAsFixed(1) ?? '--'}°C',
                  icon: Icons.thermostat_rounded,
                  color: AppTokens.primaryBlue,
                ),
                AppStatusPill(
                  label:
                      '风速 ${weather.currentWindSpeed?.toStringAsFixed(1) ?? '--'} km/h',
                  icon: Icons.air_rounded,
                  color: AppTokens.emerald,
                ),
                AppStatusPill(
                  label: weather.timezone,
                  icon: Icons.public_rounded,
                  color: AppTokens.violet,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...weather.daily.map(ApiHubWeatherDailyTile.new),
          ],
        ],
      ),
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
    final result = _shortLink;
    return ApiHubPanel(
      title: 'CleanURI 短链接生成',
      subtitle: '把长链接压缩为短链，再一键转二维码，适合手机分享 Web/APK/API 地址',
      icon: Icons.link_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('public-apis'),
                avatar: const Icon(Icons.code_rounded, size: 16),
                onPressed: () {
                  setState(() {
                    _shortLinkController.text =
                        'https://github.com/public-apis/public-apis';
                  });
                  _shortenUrl();
                },
              ),
              ActionChip(
                label: const Text('本机 Web 预览'),
                avatar: const Icon(Icons.phone_android_rounded, size: 16),
                onPressed: () {
                  setState(() {
                    _shortLinkController.text = 'http://127.0.0.1:8080/';
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          ApiHubSearchRow(
            controller: _shortLinkController,
            label: '长链接，例如 https://example.com/path',
            buttonLabel: '生成短链',
            onSubmit: _shortenUrl,
          ),
          const SizedBox(height: 12),
          if (result == null)
            const AppEmptyState(
              title: '暂无短链接',
              message: '输入完整 URL 后生成短链；免费接口可能限流',
              icon: Icons.link_rounded,
            )
          else ...[
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
                  const Text(
                    '短链接',
                    style: TextStyle(
                      color: AppTokens.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  SelectableText(
                    result.shortUrl,
                    style: const TextStyle(
                      color: AppTokens.primaryBlue,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    result.originalUrl,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTokens.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _copyText(result.shortUrl, '短链接'),
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('复制短链'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      _applyQrPreset(result.shortUrl, size: '260x260'),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: const Text('转二维码'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQrPanel() {
    final result = _qrCode;
    return ApiHubPanel(
      title: 'QR Server 二维码生成',
      subtitle: '把文本、链接或 APK 下载地址生成二维码，适合手机扫码测试',
      icon: Icons.qr_code_2_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('220×220 标准'),
                avatar: const Icon(Icons.qr_code_rounded, size: 16),
                onPressed: () {
                  setState(() => _qrSizeController.text = '220x220');
                  _buildQrCode();
                },
              ),
              ActionChip(
                label: const Text('360×360 分享'),
                avatar: const Icon(Icons.ios_share_rounded, size: 16),
                onPressed: () {
                  setState(() => _qrSizeController.text = '360x360');
                  _buildQrCode();
                },
              ),
              ActionChip(
                label: const Text('public-apis'),
                avatar: const Icon(Icons.code_rounded, size: 16),
                onPressed: () => _applyQrPreset(
                  'https://github.com/public-apis/public-apis',
                  size: '260x260',
                ),
              ),
              ActionChip(
                label: const Text('本机 Web 预览'),
                avatar: const Icon(Icons.phone_android_rounded, size: 16),
                onPressed: () => _applyQrPreset('http://127.0.0.1:8080/'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _qrTextController,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '文本 / URL'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _qrSizeController,
                  decoration: const InputDecoration(labelText: '尺寸'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _buildQrCode, child: const Text('生成')),
            ],
          ),
          const SizedBox(height: 12),
          if (result == null)
            const AppEmptyState(
              title: '暂无二维码',
              message: '输入文本或链接后生成二维码图片',
              icon: Icons.qr_code_2_rounded,
            )
          else ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE7ECF5)),
                ),
                child: Image.network(
                  result.url,
                  width: 190,
                  height: 190,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox(
                    width: 190,
                    height: 190,
                    child: Center(child: Text('二维码预览加载失败')),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              result.url,
              style: const TextStyle(
                color: AppTokens.primaryBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _copyText(result.text, '二维码内容'),
                  icon: const Icon(Icons.copy_all_rounded),
                  label: const Text('复制内容'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _copyText(result.url, '二维码图片 URL'),
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('复制图片 URL'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatarPanel() {
    final result = _avatar;
    return ApiHubPanel(
      title: 'UI Avatars 头像生成',
      subtitle: '国内网络实测 1 秒左右可用，按名称生成 PNG 头像',
      icon: Icons.account_circle_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('蓝色 Box'),
                avatar: const Icon(Icons.person_rounded, size: 16),
                onPressed: () => _applyAvatarPreset(
                  name: 'Box API',
                  background: '2563eb',
                  foreground: 'ffffff',
                ),
              ),
              ActionChip(
                label: const Text('绿色 User'),
                avatar: const Icon(Icons.badge_rounded, size: 16),
                onPressed: () => _applyAvatarPreset(
                  name: 'Mock User',
                  background: '10b981',
                  foreground: 'ffffff',
                ),
              ),
              ActionChip(
                label: const Text('深色 Dev'),
                avatar: const Icon(Icons.terminal_rounded, size: 16),
                onPressed: () => _applyAvatarPreset(
                  name: 'Dev Tool',
                  background: '111827',
                  foreground: 'f8fafc',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _avatarNameController,
                  decoration: const InputDecoration(labelText: '名称 / Seed'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _avatarSizeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '尺寸'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _avatarBgController,
                  decoration: const InputDecoration(labelText: '背景 HEX'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _avatarFgController,
                  decoration: const InputDecoration(labelText: '文字 HEX'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _buildAvatar, child: const Text('生成')),
            ],
          ),
          const SizedBox(height: 12),
          if (result == null)
            const AppEmptyState(
              title: '暂无头像',
              message: '输入名称后生成头像 URL',
              icon: Icons.account_circle_rounded,
            )
          else ...[
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.network(
                  result.url,
                  width: 150,
                  height: 150,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 150,
                    height: 150,
                    alignment: Alignment.center,
                    color: const Color(0xFFF1F5F9),
                    child: const Text('头像预览加载失败'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              result.url,
              style: const TextStyle(
                color: AppTokens.primaryBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _copyText(result.url, '头像 URL'),
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('复制 URL'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _applyQrPreset(result.url, size: '260x260'),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: const Text('转二维码'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCoverPanel() {
    final result = _coverImage;
    return ApiHubPanel(
      title: 'Picsum 随机封面 / 测试封面',
      subtitle: '生成可复用的横图、竖图、内容封面 URL，适合 Flutter UI 占位',
      icon: Icons.photo_size_select_actual_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('横版 640×360'),
                avatar: const Icon(Icons.crop_landscape_rounded, size: 16),
                onPressed: () => _applyCoverPreset(
                  width: '640',
                  height: '360',
                  seed: 'box-landscape',
                ),
              ),
              ActionChip(
                label: const Text('封面 360×540'),
                avatar: const Icon(Icons.book_rounded, size: 16),
                onPressed: () => _applyCoverPreset(
                  width: '360',
                  height: '540',
                  seed: 'box-cover',
                ),
              ),
              ActionChip(
                label: const Text('头像背景 512×512'),
                avatar: const Icon(Icons.square_rounded, size: 16),
                onPressed: () => _applyCoverPreset(
                  width: '512',
                  height: '512',
                  seed: 'box-square',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _coverWidthController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '宽度'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _coverHeightController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '高度'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _coverSeedController,
                  decoration: const InputDecoration(labelText: 'Seed'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _buildCoverImage,
                child: const Text('生成'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (result == null)
            const AppEmptyState(
              title: '暂无随机封面',
              message: '选择预设或输入尺寸后生成测试封面图',
              icon: Icons.photo_size_select_actual_rounded,
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                result.url,
                width: double.infinity,
                height: 190,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  height: 150,
                  alignment: Alignment.center,
                  color: const Color(0xFFF1F5F9),
                  child: const Text('封面预览加载失败，可复制 URL 使用'),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              result.url,
              style: const TextStyle(
                color: AppTokens.primaryBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _copyText(result.url, '封面 URL'),
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('复制 URL'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _applyQrPreset(result.url, size: '260x260'),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: const Text('转二维码'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDummyImagePanel() {
    final result = _dummyImage;
    return ApiHubPanel(
      title: 'DummyImage 占位图生成器',
      subtitle: '生成可复制的占位图 URL，适合 UI 原型、封面占位和测试数据',
      icon: Icons.image_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('600×360 蓝底'),
                avatar: const Icon(Icons.aspect_ratio_rounded, size: 16),
                onPressed: () => _applyImagePreset(
                  size: '600x360',
                  background: '2563eb',
                  foreground: 'ffffff',
                ),
              ),
              ActionChip(
                label: const Text('800×450 黑底'),
                avatar: const Icon(Icons.movie_rounded, size: 16),
                onPressed: () => _applyImagePreset(
                  size: '800x450',
                  background: '111827',
                  foreground: 'ffffff',
                ),
              ),
              ActionChip(
                label: const Text('1080×1920 竖屏'),
                avatar: const Icon(Icons.phone_android_rounded, size: 16),
                onPressed: () => _applyImagePreset(
                  size: '1080x1920',
                  background: 'f1f5f9',
                  foreground: '0f172a',
                  text: 'Mobile Preview',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _imageSizeController,
                  decoration: const InputDecoration(labelText: '尺寸，如 600x360'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _imageTextController,
                  decoration: const InputDecoration(labelText: '图片文字'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _imageBgController,
                  decoration: const InputDecoration(labelText: '背景色 HEX'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _imageFgController,
                  decoration: const InputDecoration(labelText: '文字色 HEX'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _buildDummyImage,
                child: const Text('生成'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (result == null)
            const AppEmptyState(
              title: '暂无占位图',
              message: '输入尺寸和文字后生成图片 URL',
              icon: Icons.image_rounded,
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                result.url,
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  height: 120,
                  alignment: Alignment.center,
                  color: const Color(0xFFF1F5F9),
                  child: const Text('图片预览加载失败，可复制 URL 使用'),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              result.url,
              style: const TextStyle(
                color: AppTokens.primaryBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _copyText(result.url, '图片 URL'),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('复制 URL'),
            ),
          ],
        ],
      ),
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
    final categories = const [
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
