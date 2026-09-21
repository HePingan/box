import 'package:flutter/material.dart';

class PublicApiToolDefinition {
  const PublicApiToolDefinition({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.provider,
    required this.group,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String provider;
  final String group;
}

class PublicApiRegistry {
  const PublicApiRegistry._();

  static const weather = PublicApiToolDefinition(
    id: 'weather',
    title: '天气预报',
    subtitle: '国内网络实测最快，免密钥天气接口',
    icon: Icons.wb_cloudy_rounded,
    color: Color(0xFF0EA5E9),
    provider: 'Open-Meteo',
    group: '常用',
  );

  static const currency = PublicApiToolDefinition(
    id: 'currency',
    title: '汇率换算',
    subtitle: '国内网络可用，偶尔响应偏慢',
    icon: Icons.currency_exchange_rounded,
    color: Color(0xFF10B981),
    provider: 'Frankfurter',
    group: '常用',
  );

  static const holidays = PublicApiToolDefinition(
    id: 'holidays',
    title: '节假日查询',
    subtitle: '中国节假日公开数据，国内网络可用',
    icon: Icons.event_available_rounded,
    color: Color(0xFFFF7A45),
    provider: 'Nager.Date',
    group: '常用',
  );

  static const dictionary = PublicApiToolDefinition(
    id: 'dictionary',
    title: '英文词典',
    subtitle: '国内网络实测可用的英文释义接口',
    icon: Icons.translate_rounded,
    color: Color(0xFF8B5CF6),
    provider: 'Free Dictionary',
    group: '文本',
  );

  static const mockData = PublicApiToolDefinition(
    id: 'mock',
    title: 'Mock 用户',
    subtitle: '国内网络实测可用，快速生成用户资料',
    icon: Icons.badge_rounded,
    color: Color(0xFF14B8A6),
    provider: 'DummyJSON Users',
    group: '开发',
  );

  static const qrCode = PublicApiToolDefinition(
    id: 'qr',
    title: '二维码生成',
    subtitle: '文本或链接一键转二维码图片',
    icon: Icons.qr_code_2_rounded,
    color: Color(0xFF7C3AED),
    provider: 'QR Server',
    group: '开发',
  );

  static const avatar = PublicApiToolDefinition(
    id: 'avatar',
    title: '头像生成',
    subtitle: '国内实测可用，按名称生成头像',
    icon: Icons.account_circle_rounded,
    color: Color(0xFF6366F1),
    provider: 'UI Avatars',
    group: '开发',
  );

  static const coverImage = PublicApiToolDefinition(
    id: 'cover',
    title: '随机封面',
    subtitle: '国内实测可用，生成测试封面图',
    icon: Icons.photo_size_select_actual_rounded,
    color: Color(0xFF0EA5E9),
    provider: 'Picsum',
    group: '开发',
  );

  static const shortLink = PublicApiToolDefinition(
    id: 'shortlink',
    title: '短链接生成',
    subtitle: '把长链接压缩为方便分享的短链',
    icon: Icons.link_rounded,
    color: Color(0xFF059669),
    provider: 'CleanURI',
    group: '网络',
  );

  static const ipLookup = PublicApiToolDefinition(
    id: 'ip',
    title: '公网 IP',
    subtitle: '查询当前出口 IP 与基础归属信息',
    icon: Icons.public_rounded,
    color: Color(0xFF2563EB),
    provider: 'IPinfo / IPify',
    group: '网络',
  );

  static const dummyImage = PublicApiToolDefinition(
    id: 'dummy_image',
    title: '占位图生成',
    subtitle: '快速生成设计/开发占位图 URL',
    icon: Icons.image_rounded,
    color: Color(0xFFEC4899),
    provider: 'DummyImage',
    group: '开发',
  );

  static const books = PublicApiToolDefinition(
    id: 'books',
    title: '图书搜索',
    subtitle: '按书名/作者查在线书目，带封面与首版年份',
    icon: Icons.menu_book_rounded,
    color: Color(0xFF9333EA),
    provider: 'OpenLibrary',
    group: '文本',
  );

  static const hitokoto = PublicApiToolDefinition(
    id: 'hitokoto',
    title: '随机一言',
    subtitle: '动漫/文学/诗词随机语录，免密钥',
    icon: Icons.format_quote_rounded,
    color: Color(0xFF7A8CD0),
    provider: 'Hitokoto',
    group: '文本',
  );

  static const poetry = PublicApiToolDefinition(
    id: 'poetry',
    title: '诗词一言',
    subtitle: '随机古诗词，带全诗与白话翻译',
    icon: Icons.auto_stories_rounded,
    color: Color(0xFFB45309),
    provider: '今日诗词',
    group: '文本',
  );

  static const directory = PublicApiToolDefinition(
    id: 'directory',
    title: '可用 API 清单',
    subtitle: '只展示本轮实测可用的免密钥接口',
    icon: Icons.travel_explore_rounded,
    color: Color(0xFFF59E0B),
    provider: 'local curated list',
    group: '目录',
  );

  // ——— A-1 本轮接线：以下 id 全部经 `tool/probe_60s.sh` 实测通过 ———
  // 证据：间隔 4s 各打 3 次，均 3/3 成功。

  static const dailyEnglish = PublicApiToolDefinition(
    id: 'daily_english',
    title: '每日英语',
    subtitle: '每日一句英文 + 中文翻译，免密钥',
    icon: Icons.translate_rounded,
    color: Color(0xFF22C55E),
    provider: '金山词霸 dsapi',
    group: '文本',
  );

  static const news60s = PublicApiToolDefinition(
    id: 'news60s',
    title: '每日60秒资讯',
    subtitle: '15 条要闻速览，免密钥',
    icon: Icons.newspaper_rounded,
    color: Color(0xFFEF4444),
    provider: '60s API',
    group: '资讯',
  );

  static const todayInHistory = PublicApiToolDefinition(
    id: 'today_in_history',
    title: '历史上的今天',
    subtitle: '当天历史事件条目，免密钥',
    icon: Icons.history_edu_rounded,
    color: Color(0xFFB45309),
    provider: '60s API',
    group: '资讯',
  );

  /// 老黄历。**两个源拼**：60s `/v2/luck` 给运程描述与等级，
  /// 宜忌/干支/节日的实时数据来自 wannianrili.bmcx.com（HTML 抓取，
  /// 无可用的免费 JSON 源 —— 2026-09 逐一验证约 15 个候选，全部下线或要密钥）。
  /// 万年历抓取失败会静默降级，只留 60s 部分，面板不会整块空掉。
  static const luck = PublicApiToolDefinition(
    id: 'luck',
    title: '老黄历',
    subtitle: '宜忌 / 吉凶 / 农历，免密钥',
    icon: Icons.calendar_month_rounded,
    color: Color(0xFFDC2626),
    provider: '60s API',
    group: '生活',
  );

  static const fortune = PublicApiToolDefinition(
    id: 'fortune',
    title: '今日运势',
    subtitle: '每日运程等级与宜忌提示，免密钥',
    icon: Icons.emoji_events_rounded,
    color: Color(0xFFF59E0B),
    provider: '60s API',
    group: '生活',
  );

  static const bingWallpaper = PublicApiToolDefinition(
    id: 'bing_wallpaper',
    title: '必应壁纸',
    subtitle: '必应每日高清壁纸与出处，免密钥',
    icon: Icons.wallpaper_rounded,
    color: Color(0xFF0EA5E9),
    provider: '60s API',
    group: '生活',
  );

  static const baiduHot = PublicApiToolDefinition(
    id: 'baidu_hot',
    title: '百度热搜',
    subtitle: '实时热搜榜，免密钥',
    icon: Icons.trending_up_rounded,
    color: Color(0xFFF97316),
    provider: '60s API',
    group: '资讯',
  );

  // —— A-3 批次3接线（实测通过）——

  static const maoyan = PublicApiToolDefinition(
    id: 'maoyan',
    title: '猫眼票房',
    subtitle: '影史票房总榜，免密钥',
    icon: Icons.movie_filter_rounded,
    color: Color(0xFFE11D48),
    provider: '60s API',
    group: '资讯',
  );

  static const epic = PublicApiToolDefinition(
    id: 'epic',
    title: 'Epic 免费游戏',
    subtitle: 'Epic 本周免费游戏，免密钥',
    icon: Icons.videogame_asset_rounded,
    color: Color(0xFF0EA5E9),
    provider: '60s API',
    group: '资讯',
  );

  static const exchangeRate = PublicApiToolDefinition(
    id: 'exchange_rate',
    title: '实时汇率',
    subtitle: '多币种对人民币中间价，免密钥',
    icon: Icons.currency_yen_rounded,
    color: Color(0xFF10B981),
    provider: '60s API',
    group: '生活',
  );

  static const ipQuery = PublicApiToolDefinition(
    id: 'ip_query',
    title: 'IP 归属查询',
    subtitle: '查询任一 IP 的国家省份运营商，免密钥',
    icon: Icons.public_rounded,
    color: Color(0xFF2563EB),
    provider: '60s API',
    group: '网络',
  );

  static const phoneArea = PublicApiToolDefinition(
    id: 'phone_area',
    title: '手机号归属地',
    subtitle: '按号码查省份与运营商，免密钥',
    icon: Icons.phone_android_rounded,
    color: Color(0xFF6366F1),
    provider: '360 手机归属地',
    group: '网络',
  );

  static const translate = PublicApiToolDefinition(
    id: 'translate',
    title: '中英互译',
    subtitle: '免密钥翻译，适合短句',
    icon: Icons.g_translate_rounded,
    color: Color(0xFF8B5CF6),
    provider: 'MyMemory',
    group: '文本',
  );

  // —— A-2 本轮接线：全部经 tool/probe_public_apis.sh 实测（间隔 4s × 3 次，
  // 含内容级假成功校验，剔除 HTTP 200 但载荷为错误文案的接口）。——

  static const weiboHot = PublicApiToolDefinition(
    id: 'weibo_hot',
    title: '微博热搜',
    subtitle: '实时微博热搜榜，免密钥',
    icon: Icons.local_fire_department_rounded,
    color: Color(0xFFE11D48),
    provider: '60s API',
    group: '资讯',
  );

  static const zhihuHot = PublicApiToolDefinition(
    id: 'zhihu_hot',
    title: '知乎热榜',
    subtitle: '实时知乎热榜，免密钥',
    icon: Icons.question_answer_rounded,
    color: Color(0xFF0EA5E9),
    provider: '60s API',
    group: '资讯',
  );

  static const douyinHot = PublicApiToolDefinition(
    id: 'douyin_hot',
    title: '抖音热点',
    subtitle: '实时抖音热点榜，免密钥',
    icon: Icons.music_note_rounded,
    color: Color(0xFF111827),
    provider: '60s API',
    group: '资讯',
  );

  static const toutiaoHot = PublicApiToolDefinition(
    id: 'toutiao_hot',
    title: '头条热榜',
    subtitle: '实时今日头条热榜，免密钥',
    icon: Icons.article_rounded,
    color: Color(0xFFDC2626),
    provider: '60s API',
    group: '资讯',
  );

  static const moyu = PublicApiToolDefinition(
    id: 'moyu',
    title: '摸鱼日历',
    subtitle: '距下个节假日还有几天，免密钥',
    icon: Icons.beach_access_rounded,
    color: Color(0xFF14B8A6),
    provider: '60s API',
    group: '生活',
  );

  static const dujitang = PublicApiToolDefinition(
    id: 'dujitang',
    title: '毒鸡汤',
    subtitle: '随机扎心语录，免密钥',
    icon: Icons.sentiment_very_dissatisfied_rounded,
    color: Color(0xFF64748B),
    provider: 'Shadiao API',
    group: '文本',
  );

  static const chp = PublicApiToolDefinition(
    id: 'chp',
    title: '随机彩虹屁',
    subtitle: '随机夸夸文案，免密钥',
    icon: Icons.auto_awesome_rounded,
    color: Color(0xFFEC4899),
    provider: 'Shadiao API',
    group: '文本',
  );

  static const all = [
    weather,
    currency,
    holidays,
    ipLookup,
    shortLink,
    dictionary,
    books,
    hitokoto,
    poetry,
    mockData,
    qrCode,
    avatar,
    coverImage,
    dummyImage,
    directory,
    // A-1 本轮接线（实测可用）
    dailyEnglish,
    news60s,
    todayInHistory,
    luck,
    bingWallpaper,
    baiduHot,
    exchangeRate,
    ipQuery,
    phoneArea,
    translate,
    // A-2 本轮接线（实测可用）
    weiboHot,
    zhihuHot,
    douyinHot,
    toutiaoHot,
    moyu,
    fortune,
    dujitang,
    chp,
    maoyan,
    epic,
  ];

  static const groups = ['常用', '网络', '文本', '开发', '资讯', '生活', '目录'];

  /// 按 id 查工具，查不到返回 null。
  ///
  /// 注意：这里**故意不做兜底**。旧实现只有 `byId(orElse: () => weather)`，
  /// 「图书搜索」传入当时并不存在的 `books` 时，分组高亮被静默算成天气所属的
  /// 「常用」组，看不出 id 是错的。拼错的 id 必须能被发现，不能被吞掉。
  ///
  /// （补充：当时真正把用户送到天气面板的是 `_buildActivePanel` 的
  /// `default:` 分支 —— `books` 没有对应 case。orElse 影响的是分组高亮。
  /// 两处都已修：这里不再吞错，那里补了 case。）
  static PublicApiToolDefinition? tryById(String id) {
    for (final tool in all) {
      if (tool.id == id) return tool;
    }
    return null;
  }

  /// 按 id 查工具，查不到回落到默认工具（天气）。
  ///
  /// 只给「id 来源不可信、且必须渲染出某个面板」的场景用（例如外部传入的
  /// initialTool）。需要判断 id 是否合法时用 [tryById]，别用这个。
  static PublicApiToolDefinition byId(String id) => tryById(id) ?? weather;
}
