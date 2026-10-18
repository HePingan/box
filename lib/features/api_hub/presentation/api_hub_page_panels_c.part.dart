part of './api_hub_page.dart';

// 榜单 / 杂项面板：票房、Epic 免费游戏、语录、百度热搜、汇率、IP 归属地、
// 手机归属地、翻译、模拟用户、公开 API 目录（含目录详情弹层）。

mixin _ApiHubPagePanelsC on _ApiHubPageStateBase, _ApiHubPageActions, _ApiHubPageChrome {
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
            Text(
              '点「刷新榜单」拉取票房总榜',
              style: TextStyle(color: AppTokens.textSecondary),
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
                              : AppTokens.textTertiary,
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
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppTokens.textTertiary,
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
            Text(
              '点「刷新本周免费」看看能白拿什么',
              style: TextStyle(color: AppTokens.textSecondary),
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
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTokens.textTertiary,
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
            Text('点上方按钮随机来一条', style: TextStyle(color: AppTokens.textSecondary))
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
            Text(
              '点「刷新榜单」拉取实时热搜',
              style: TextStyle(color: AppTokens.textSecondary),
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
                              : AppTokens.textTertiary,
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
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppTokens.textTertiary,
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
            Text(
              '点「刷新汇率」拉取最新汇率',
              style: TextStyle(color: AppTokens.textSecondary),
            )
          else ...[
            if (rate!.updated.isNotEmpty) ...[
              Text(
                '更新于 ${rate.updated}',
                style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
              ),
              const SizedBox(height: 10),
            ],
            Text(
              '1 ${rate.base} =',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTokens.textSecondary,
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
            Text('点「查询」获取归属地', style: TextStyle(color: AppTokens.textSecondary))
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
            Text(
              '点「查询归属地」获取结果',
              style: TextStyle(color: AppTokens.textSecondary),
            )
          else ...[
            if (result.province.isNotEmpty) _infoRow('省份', result.province),
            if (result.city.isNotEmpty) _infoRow('城市', result.city),
            if (result.carrier.isNotEmpty) _infoRow('运营商', result.carrier),
            if (result.province.isEmpty &&
                result.city.isEmpty &&
                result.carrier.isEmpty)
              Text(
                '接口没有返回该号段的归属信息，换个号码再试',
                style: TextStyle(color: AppTokens.textSecondary),
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
            Text('点「翻译」查看结果', style: TextStyle(color: AppTokens.textSecondary))
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
              style: TextStyle(
                fontSize: 13,
                color: AppTokens.textSecondary,
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
                    side: BorderSide(color: AppTokens.cardBorder),
                    backgroundColor: AppTokens.surface,
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
                side: BorderSide(color: AppTokens.cardBorder),
                backgroundColor: AppTokens.surface,
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
                  style: TextStyle(
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
                  style: TextStyle(
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
