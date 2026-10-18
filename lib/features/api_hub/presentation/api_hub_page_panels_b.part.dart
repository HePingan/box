part of './api_hub_page.dart';

// 内容 / 资讯类面板：每日英语、60s 资讯、历史上的今天、运势、必应壁纸、
// 热榜、今日运势、摸鱼日历。

mixin _ApiHubPagePanelsB on _ApiHubPageStateBase, _ApiHubPageActions, _ApiHubPageChrome {
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
            Text(
              '点「换一句」获取今日英文金句',
              style: TextStyle(color: AppTokens.textSecondary),
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
                style: TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: AppTokens.textSecondary,
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
            Text(
              '点「刷新资讯」拉取今日要闻',
              style: TextStyle(color: AppTokens.textSecondary),
            )
          else ...[
            Text(
              [
                if (news.date.isNotEmpty) news.date,
                if (news.dayOfWeek.isNotEmpty) news.dayOfWeek,
                if (news.lunarDate.isNotEmpty) news.lunarDate,
              ].join('  '),
              style: TextStyle(
                fontSize: 13,
                color: AppTokens.textSecondary,
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
              Text(
                '每日一句',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                news.tips.join('\n'),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.7,
                  color: AppTokens.textSecondary,
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
            Text(
              '点「刷新」拉取今日历史事件',
              style: TextStyle(color: AppTokens.textSecondary),
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
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.5,
                              color: AppTokens.textSecondary,
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
            Text(
              '点「查今日」获取今天的黄历',
              style: TextStyle(color: AppTokens.textSecondary),
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
                style: TextStyle(fontSize: 13, color: AppTokens.textSecondary),
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
            Text(
              '点「换一张」获取今日壁纸',
              style: TextStyle(color: AppTokens.textSecondary),
            )
          else ...[
            if (wall.url.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  wall.url,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (_, _, _) => SizedBox(
                    height: 120,
                    child: Center(
                      child: Text(
                        '图片加载失败',
                        style: TextStyle(color: AppTokens.textSecondary),
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
                style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
              ),
            ],
            if (wall.url.isNotEmpty) ...[
              const SizedBox(height: 10),
              SelectableText(
                wall.url,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppTokens.textTertiary,
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
            Text(
              '点「刷新榜单」拉取实时榜单',
              style: TextStyle(color: AppTokens.textSecondary),
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
                                  : AppTokens.textTertiary,
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
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppTokens.textTertiary,
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
            Text(
              '点上方按钮查看今日运势',
              style: TextStyle(color: AppTokens.textSecondary),
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
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTokens.textTertiary,
                ),
              ),
            if (fortune.zodiac.isNotEmpty)
              Text(
                '生肖：${fortune.zodiac}',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTokens.textTertiary,
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
            Text(
              '点上方按钮查看摸鱼日历',
              style: TextStyle(color: AppTokens.textSecondary),
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
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTokens.textTertiary,
                ),
              ),
            if (moyu.lunarDate.isNotEmpty)
              Text(
                '农历：${moyu.lunarDate}',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTokens.textTertiary,
                ),
              ),
            if (moyu.nextHolidayDate.isNotEmpty)
              Text(
                '下次放假：${moyu.nextHolidayDate}',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTokens.textTertiary,
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
}
