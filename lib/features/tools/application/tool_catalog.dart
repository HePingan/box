import 'package:flutter/material.dart';

class ToolCategory {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconBgColor;
  final List<String> tools;
  bool isExpanded;

  ToolCategory({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconBgColor,
    required this.tools,
    this.isExpanded = false,
  });
}

/// 一个已接线工具的点击去向。
sealed class ToolTarget {
  const ToolTarget();
}

/// 打开 API 能力中心的某个面板。
///
/// [toolId] 必须是 `PublicApiRegistry` 里真实存在的 id；为 null 表示打开
/// API Hub 首页（不预选面板）。
class ApiHubToolTarget extends ToolTarget {
  const ApiHubToolTarget([this.toolId]);

  final String? toolId;
}

/// 在内置 WebView 里打开一个站点。
class WebToolTarget extends ToolTarget {
  const WebToolTarget({required this.title, required this.url});

  final String title;
  final String url;
}

/// 打开一个**纯本地**工具（不联网、不需要任何接口）。
///
/// 这类工具之前被错当成「未接线」摆在折叠区里 —— 但科学计算器、单位换算、
/// MD5、进制转换这些东西本来就该由 App 自己算，没有任何外部接口可接。
/// 用 [ApiHubToolTarget] 表示它们是错的（会去开一个并不存在的 API 面板），
/// 标成未接线也是错的（用户被告知「我们没有」，其实我们有这个能力）。
///
/// [localId] 是 `kLocalTools` 的键，由测试逐个核对是否真实注册。
class LocalToolTarget extends ToolTarget {
  const LocalToolTarget(this.localId);

  final String localId;
}

/// 工具名 → 点击去向。**这是可用性的唯一事实源。**
///
/// 之前这里是一份手抄的 `Set<String>`，派发逻辑另在 `tool_widgets.dart` 里写成
/// 按名字比对的 if 链，末尾还挂了个无条件 Photopea fallback。两份事实各自漂移，
/// 结果：
///
///   * 「图书搜索」派发到当时并不存在的 `books` id，API Hub 的面板 switch 没有
///     对应 case，落进 `default:` 打开天气面板 —— 用户点图书搜索，开出天气，
///     全程无报错（`byId` 的 orElse 还把分组高亮也算成了天气所在的「常用」）。
///   * registry 里已实现的英文词典 / 短链 / 头像 / 随机封面 / 占位图，目录里
///     没有任何入口，用户到不了。
///   * 任何进了名单但没写 if 分支的工具，都会掉进 fallback 打开 Photopea。
///
/// 现在只有这张表：进表即可用，表里写清去哪。新增工具只改这里，UI 徽标和点击
/// 派发都自动跟上，不会再漂。表里的 API Hub 目标由测试逐个核对是否真实存在。
const Map<String, ToolTarget> kToolTargets = {
  // —— API 能力中心（面板已实现）——
  '天气预报': ApiHubToolTarget('weather'),
  '汇率换算': ApiHubToolTarget('currency'),
  '节假日查询': ApiHubToolTarget('holidays'),
  '公网IP查询': ApiHubToolTarget('ip'),
  '短链接生成': ApiHubToolTarget('shortlink'),
  '英文词典': ApiHubToolTarget('dictionary'),
  '图书搜索': ApiHubToolTarget('books'),
  // 本轮接线：两个免密钥语录接口，curl 实测各 5/5 成功。
  // 「六十秒读世界」同批只有 3/5 且撞过 429 限流，故仍留占位区。
  '随机一言': ApiHubToolTarget('hitokoto'),
  '诗词一言': ApiHubToolTarget('poetry'),
  'DummyJSON测试数据': ApiHubToolTarget('mock'),
  '二维码生成': ApiHubToolTarget('qr'),
  '头像生成': ApiHubToolTarget('avatar'),
  '随机封面': ApiHubToolTarget('cover'),
  '占位图生成': ApiHubToolTarget('dummy_image'),
  '国内可用API': ApiHubToolTarget('directory'),
  'API能力中心': ApiHubToolTarget(),

  // —— A-1 本轮接线：全部经 tool/probe_60s.sh 实测（间隔 4s × 3 次）——
  // 60s.viki.moe/v2 系列 + 金山词霸 dsapi + 360 归属地 + MyMemory 翻译。
  '每日英语': ApiHubToolTarget('daily_english'),
  '六十秒读世界': ApiHubToolTarget('news60s'),
  '史上今日': ApiHubToolTarget('today_in_history'),
  '老黄历': ApiHubToolTarget('luck'),
  '必应壁纸': ApiHubToolTarget('bing_wallpaper'),
  '百度热搜': ApiHubToolTarget('baidu_hot'),
  '实时汇率': ApiHubToolTarget('exchange_rate'),
  'IP归属查询': ApiHubToolTarget('ip_query'),
  '归属地查询': ApiHubToolTarget('phone_area'),
  '翻译': ApiHubToolTarget('translate'),

  // —— A-2 本轮接线：tool/probe_public_apis.sh 实测（间隔 4s × 3 次，含内容级假成功校验）——
  // 60s.viki.moe/v2 热榜与资讯系列 + shadiao 语录系列。
  // 已实测失效（404/500/不可达），未接线：chengyu、dujitang、it、game、bullshit、
  // rubbish、tieba、sspai、ithome、bili(500)、hot、idiom；uomg 全站不可达。
  '微博热搜': ApiHubToolTarget('weibo_hot'),
  '知乎热榜': ApiHubToolTarget('zhihu_hot'),
  '抖音热点': ApiHubToolTarget('douyin_hot'),
  '头条热榜': ApiHubToolTarget('toutiao_hot'),
  '摸鱼日历': ApiHubToolTarget('moyu'),
  '今日运势': ApiHubToolTarget('fortune'),
  '毒鸡汤': ApiHubToolTarget('dujitang'),
  '随机彩虹屁': ApiHubToolTarget('chp'),
  // —— A-3 批次3接线：60s.viki.moe/v2 实测通过（间隔 4s × 3 次，含假成功校验）——
  '猫眼票房': ApiHubToolTarget('maoyan'),
  'Epic 免费游戏': ApiHubToolTarget('epic'),

  // —— 实测已失效，不得接线（留此备忘，勿接）——
  // 今日诗词（jinrishici 域名）→ 404 下线；
  // 某聚合站 oick 全系 → 返回「缺少 apikey」，非免密钥；
  // 境外 IP 归属站 ip-api → 国内直连 3/3 失败；60s 的成语/日报两个子路径 → 404。

  // —— 内置 WebView ——
  '在线PS': WebToolTarget(title: '在线PS', url: 'https://www.photopea.com/'),

  // —— 纯本地工具（批次 1，计算/转换 9 个）——
  // 这些不需要任何接口：零网络、零新依赖，逻辑在
  // features/local_tools/domain/local_tool_math.dart 里，单测全量覆盖。
  //
  // 之前它们被摆在「未接线」折叠区，因为旧逻辑把「可用」等同于
  // 「接了公开 API」。但计算器本来就不需要接口 —— 标成未接线等于
  // 告诉用户「我们没有」，是错的。
  //
  // 注意：id 必须与 kLocalTools 的键一致，有测试逐个核对。
  '科学计算器': LocalToolTarget('scientific_calculator'),
  '单位换算': LocalToolTarget('unit_convert'),
  '房贷计算器': LocalToolTarget('mortgage'),
  '日期计算': LocalToolTarget('date_calc'),
  '时间戳转换': LocalToolTarget('timestamp'),
  '进制转换': LocalToolTarget('radix'),
  '大小写转换': LocalToolTarget('case_convert'),
  '随机密码': LocalToolTarget('password_gen'),

  // ── 纯本地工具（批次 2，文本 / 编码 7 个）──
  'JSON格式化': LocalToolTarget('json'),
  '正则测试': LocalToolTarget('regex'),
  'Base64编解码': LocalToolTarget('base64'),
  'MD5加密': LocalToolTarget('hash'),
  'URL编码': LocalToolTarget('urlcodec'),
  '文本编辑器': LocalToolTarget('texted'),
  '颜文字': LocalToolTarget('kaomoji'),
  // ── 批次 3：计时 / 设备类 ──
  '秒表': LocalToolTarget('stopwatch'),
  '计时器': LocalToolTarget('countdown'),
  '全屏时钟': LocalToolTarget('clock'),
  '时间屏幕': LocalToolTarget('timescreen'),
  '随机数生成': LocalToolTarget('random'),
  '摩斯密码': LocalToolTarget('morse'),
  '刻度尺': LocalToolTarget('ruler'),
  '屏幕坏点检测': LocalToolTarget('deadpixel'),
  // ── 批次 4：传感器 ──
  '指南针': LocalToolTarget('compass'),
  '水平仪': LocalToolTarget('level'),
  '分贝仪': LocalToolTarget('decibel'),
  '亲戚称呼计算': LocalToolTarget('relation'),
};

/// 已接线工具名单。派生自 [kToolTargets]，不再手抄。
Set<String> get kAvailableToolNames => kToolTargets.keys.toSet();

/// 某个工具当前是否可用（已接线）。
bool isToolAvailable(String toolName) => kToolTargets.containsKey(toolName);

/// 某个工具的点击去向；未接线返回 null。
ToolTarget? toolTargetOf(String toolName) => kToolTargets[toolName];

/// 一个工具条目：名字 + 它属于哪一类 + 点下去去哪。
///
/// 之前目录条目只是 `String`，可用性要靠每个 UI 自己 `where(isToolAvailable)`
/// 现算，分类归属在平铺之后就丢了。升级成模型之后，条目自带这三件事，
/// [available] 由 [target] 派生 —— 不存第二份布尔值，就不会和映射表漂移。
class ToolEntry {
  const ToolEntry({
    required this.name,
    required this.category,
    required this.target,
  });

  /// 工具名，同时是 [kToolTargets] 的键。
  final String name;

  /// 所属分类标题。平铺到首屏后用来标注来源。
  final String category;

  /// 点击去向；null = 还没接线。
  final ToolTarget? target;

  /// 是否已接线。**派生自 [target]，不是独立字段。**
  bool get available => target != null;
}

/// 目录的忠实展开：按分类顺序、分类内顺序列出全部条目。
List<ToolEntry> allToolEntries() {
  final entries = <ToolEntry>[];
  for (final category in createDefaultToolCategories()) {
    for (final name in category.tools) {
      entries.add(
        ToolEntry(
          name: name,
          category: category.title,
          target: toolTargetOf(name),
        ),
      );
    }
  }
  return entries;
}

/// 已接线条目，保持目录顺序。首屏平铺区用这份。
List<ToolEntry> availableToolEntries() =>
    allToolEntries().where((e) => e.available).toList();

/// 未接线条目，仍按原分类分组；空分类会被丢掉。
///
/// 折叠区用这份：可用能力已经平铺在上面了，这里只留「计划中」的占位条目，
/// 避免同一个工具在两个区各出现一次。
List<ToolCategory> plannedToolCategories() {
  final planned = <ToolCategory>[];
  for (final category in createDefaultToolCategories()) {
    final rest = category.tools.where((t) => !isToolAvailable(t)).toList();
    if (rest.isEmpty) continue;
    planned.add(
      ToolCategory(
        title: category.title,
        subtitle: category.subtitle,
        icon: category.icon,
        iconBgColor: category.iconBgColor,
        tools: rest,
      ),
    );
  }
  return planned;
}

List<ToolCategory> createDefaultToolCategories() {
  return [
    ToolCategory(
      title: '日常工具',
      subtitle: '每日资讯、实用工具',
      icon: Icons.wb_sunny_outlined,
      iconBgColor: const Color(0xFF5A728D),
      isExpanded: true,
      tools: [
        '每日早报',
        '每日一文',
        '每日英语',
        '央视新闻',
        '步数修改',
        '在线翻译',
        '菜谱大全',
        '全国降水量',
        '历史上的今天',
        '节假日查询',
        '微博热搜',
        '知乎热榜',
        '抖音热点',
        '头条热榜',
        '摸鱼日历',
        '猫眼票房',
        'Epic 免费游戏',
      ],
    ),
    ToolCategory(
      title: '系统操作',
      subtitle: '涉及系统相关的工具',
      icon: Icons.settings_applications_outlined,
      iconBgColor: const Color(0xFF587A9A),
      tools: [
        'APK提取',
        'APK.1安装器',
        '系统界面调节',
        '系统字体调节',
        '屏幕坏点检测',
        '提取手机壁纸',
        '空文件夹清理',
        '扬声器清灰',
        '动态视频壁纸',
        '查看设备信息',
        '刻度尺',
        '指南针',
        '水平仪',
        '分贝仪',
        '秒表',
        '计时器',
        '时间屏幕',
      ],
    ),

    // 👉 图片工具里第一个加上了 “在线PS”
    ToolCategory(
      title: '图片工具',
      subtitle: '图片处理相关的工具',
      icon: Icons.image_outlined,
      iconBgColor: Colors.teal,
      tools: [
        '在线PS',
        '图片压缩',
        '格式转换',
        '九宫格切图',
        '水印添加',
        '老照片修复',
        '黑白上色',
        '图片拼接',
        '壁纸提取',
      ],
    ),

    ToolCategory(
      title: '查询工具',
      subtitle: '快递、天气、归属地等查询',
      icon: Icons.search_outlined,
      iconBgColor: const Color(0xFF4C5B99),
      tools: [
        // 图书搜索（OpenLibrary）原本挂在内容页的入口网格里，
        // 但它是「按书名查在线书目」而非本地收藏，归属工具页更合理。
        '图书搜索',
        '天气预报',
        '英文词典',
        '公网IP查询',
        '国内可用API',
        // 「Open-Meteo天气」「国内API清单」已删：它们和「天气预报」「国内可用API」
        // 指向同一个 API Hub 面板，一个能力两个入口只会让人以为是两个工具。
        '快递查询',
        '归属地查询',
        'IP归属查询',
        '老黄历',
        '成语词典',
        '近义词查询',
        '垃圾分类',
        // A-1：归属地查询已接 360 接口（映射表 key=归属地查询→phone_area），
        // IP归属查询接 60s（key=IP归属查询→ip_query）。这两个之前是纯占位，
        // 现在点进去有真实数据。
      ],
    ),
    ToolCategory(
      title: '提取工具',
      subtitle: '各大平台资源提取',
      icon: Icons.file_download_outlined,
      iconBgColor: Colors.blueAccent,
      tools: ['短视频去水印', '图集提取', '网页音频提取', 'B站封面提取', '文案提取', '图片文字识别'],
    ),
    ToolCategory(
      title: '开发工具',
      subtitle: '程序猿专属工具',
      icon: Icons.code,
      iconBgColor: Colors.deepPurple,
      tools: [
        'DummyJSON测试数据',
        '占位图生成',
        '头像生成',
        '随机封面',
        '短链接生成',
        'JSON格式化',
        '正则测试',
        'Base64编解码',
        'MD5加密',
        '时间戳转换',
        '网页源码获取',
        'URL编码',
        '进制转换',
      ],
    ),
    ToolCategory(
      title: '文本工具',
      subtitle: '文本处理与随机文案',
      icon: Icons.text_fields,
      iconBgColor: const Color(0xFF7A8CD0),
      tools: [
        '汉字查询',
        '颜文字',
        '文本编辑器',
        '随机密码',
        '随机一言',
        '诗词一言',
        '随机一文',
        '六十秒读世界',
        '史上今日',
        '百度热搜',
        '搜题',
        '翻译',
        '滚动弹幕',
        '藏头诗生成',
        '随机彩虹屁',
        '舔狗日记',
        '毒鸡汤',
        '笑话语录',
        '渣男语录',
        '随机弱智吧问答',
        '猜成语生成',
        '随机人设',
        '脑筋急转弯',
        '随机沙雕新闻',
      ],
    ),
    ToolCategory(
      title: 'API 能力中心',
      subtitle: '公共接口入口与面板导航',
      icon: Icons.api,
      iconBgColor: Colors.orange,
      tools: ['API能力中心'],
    ),
    ToolCategory(
      title: '计算工具',
      subtitle: '各类计算换算',
      icon: Icons.calculate_outlined,
      iconBgColor: Colors.orange,
      tools: [
        '科学计算器',
        '亲戚称呼计算',
        '汇率换算',
        '实时汇率',
        '房贷计算器',
        'BMI计算',
        '单位换算',
        '大小写转换',
        '日期计算',
      ],
    ),
    ToolCategory(
      title: '其他工具',
      subtitle: '更多好玩的应用',
      icon: Icons.grid_view,
      iconBgColor: Colors.blueGrey,
      tools: ['摩斯密码', '二维码生成', '条形码扫描', 'LED字幕', '随机数生成', '手持弹幕', '全屏时钟', '必应壁纸'],
    ),
    ToolCategory(
      title: '趣味游戏',
      subtitle: '休闲娱乐小游戏',
      icon: Icons.sports_esports_outlined,
      iconBgColor: Colors.redAccent,
      tools: ['扫雷', '2048', '数字华容道', '五子棋', '贪吃蛇', '迷宫', '数独', '今日运势'],
    ),
  ];
}
