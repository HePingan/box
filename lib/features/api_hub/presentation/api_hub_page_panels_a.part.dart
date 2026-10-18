part of './api_hub_page.dart';

// 工具 / 素材类面板：汇率、节假日、天气、IP、短链、二维码、头像、随机封面、
// 占位图、英文词典、图书、随机一言、今日诗词。

mixin _ApiHubPagePanelsA on _ApiHubPageStateBase, _ApiHubPageActions, _ApiHubPageChrome {
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
                color: AppTokens.surfaceMuted,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTokens.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.ip,
                    style: TextStyle(
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
              style: TextStyle(
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
            Text(
              '点「换一句」获取一条随机语录',
              style: TextStyle(color: AppTokens.textSecondary),
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
                  style: TextStyle(
                    color: AppTokens.textSecondary,
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
            Text(
              '点「换一首」获取一句随机诗词',
              style: TextStyle(color: AppTokens.textSecondary),
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
              style: TextStyle(color: AppTokens.textSecondary, fontSize: 13),
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
                      Text(
                        '白话翻译',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        poem.translation.join('\n'),
                        style: TextStyle(
                          height: 1.7,
                          fontSize: 13,
                          color: AppTokens.textSecondary,
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
}
