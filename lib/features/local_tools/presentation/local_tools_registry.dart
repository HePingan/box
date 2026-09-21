import 'package:flutter/material.dart';

import '../../../design_system/app_tokens.dart';
import '../../../design_system/widgets/app_back_button.dart';
import 'local_tool_panels.dart';

/// 一个纯本地工具的定义。
class LocalToolDef {
  const LocalToolDef({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.builder,
  });

  /// 稳定标识 —— 目录里的 `LocalToolTarget(localId)` 靠它定位。
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;

  /// 构建工具主体（不含标题栏，外壳由 [LocalToolPage] 统一提供）。
  final Widget Function(BuildContext) builder;
}

/// **纯本地工具清单 —— 这是唯一事实源。**
///
/// 进这张表 = 目录里可点、点击有真实页面；测试逐个核对表里每个 id
/// 都能 build 出东西（不是空壳）。表外没有别的注册点。
///
/// 为什么要这张表：这些能力（科学计算器、单位换算、进制转换……）之前
/// 被摆在「未接线」折叠区，因为旧逻辑把「可用」等同于「接了公开 API」。
/// 但它们本来就不需要任何接口 —— 是 App 自己能算的。标成未接线，
/// 等于告诉用户「我们没有」，是错的。
final Map<String, LocalToolDef> kLocalTools = {
  'scientific_calculator': LocalToolDef(
    id: 'scientific_calculator',
    title: '科学计算器',
    subtitle: '四则运算、括号、乘方，纯本地计算',
    icon: Icons.calculate_rounded,
    builder: (_) => const _CalculatorBody(),
  ),
  'unit_convert': LocalToolDef(
    id: 'unit_convert',
    title: '单位换算',
    subtitle: '长度 / 重量 / 温度 / 面积 / 体积',
    icon: Icons.swap_horiz_rounded,
    builder: (_) => const _UnitConvertBody(),
  ),
  // 注意：没有 'bmi' —— 目录里不存在「BMI计算」这个条目。用户原则是
  // 「目录是全量清单，分类列表不得随意增删条目」，所以宁可先不接，也不
  // 自造一个目录里没有的入口。domain 层的 bmiValue/bmiCategory 和
  // BmiPanelBody 都已实现并通过单测，等哪天目录里加了条目，把 id 填回
  // 来即可（配一条 kToolTargets 的 'BMI计算': LocalToolTarget('bmi')）。
  'mortgage': LocalToolDef(
    id: 'mortgage',
    title: '房贷计算器',
    subtitle: '等额本息 / 等额本金，含利息总额',
    icon: Icons.home_work_rounded,
    builder: (_) => const _MortgageBody(),
  ),
  'date_calc': LocalToolDef(
    id: 'date_calc',
    title: '日期计算',
    subtitle: '日期相差天数、日期加减、闰年判断',
    icon: Icons.calendar_month_rounded,
    builder: (_) => const _DateCalcBody(),
  ),
  'timestamp': LocalToolDef(
    id: 'timestamp',
    title: '时间戳转换',
    subtitle: 'Unix 时间戳 ↔ 日期时间',
    icon: Icons.schedule_rounded,
    builder: (_) => const _TimestampBody(),
  ),
  'radix': LocalToolDef(
    id: 'radix',
    title: '进制转换',
    subtitle: '2 / 8 / 10 / 16 及任意进制互转',
    icon: Icons.pin_rounded,
    builder: (_) => const _RadixBody(),
  ),
  'case_convert': LocalToolDef(
    id: 'case_convert',
    title: '大小写转换',
    subtitle: '全大写 / 全小写 / 首字母大写',
    icon: Icons.text_fields_rounded,
    builder: (_) => const _CaseBody(),
  ),
  'password_gen': LocalToolDef(
    id: 'password_gen',
    title: '随机密码',
    subtitle: '本地生成强随机密码，可调长度与字符集',
    icon: Icons.key_rounded,
    builder: (_) => const _PasswordBody(),
  ),
  'relation': LocalToolDef(
    id: 'relation',
    title: '亲戚称呼计算',
    subtitle: '一路点关系，算出该怎么称呼',
    icon: Icons.family_restroom_rounded,
    builder: (_) => const _RelationBody(),
  ),

  // ── 批次 2：文本 / 编码类 ──
  'json': LocalToolDef(
    id: 'json',
    title: 'JSON 格式化',
    subtitle: '美化 / 压缩 / 校验，中文不会被转义',
    icon: Icons.data_object_rounded,
    builder: (_) => const JsonPanelBody(),
  ),
  'regex': LocalToolDef(
    id: 'regex',
    title: '正则测试',
    subtitle: '列出全部匹配、位置与捕获组',
    icon: Icons.code_rounded,
    builder: (_) => const RegexPanelBody(),
  ),
  'base64': LocalToolDef(
    id: 'base64',
    title: 'Base64 编解码',
    subtitle: '按 UTF-8 处理，中文和 emoji 都不会乱码',
    icon: Icons.swap_horiz_rounded,
    builder: (_) => const Base64PanelBody(),
  ),
  'hash': LocalToolDef(
    id: 'hash',
    title: 'MD5 / SHA 加密',
    subtitle: '摘要计算，输入按 UTF-8 编码',
    icon: Icons.fingerprint_rounded,
    builder: (_) => const HashPanelBody(),
  ),
  'urlcodec': LocalToolDef(
    id: 'urlcodec',
    title: 'URL 编码',
    subtitle: 'RFC 3986 百分号编码，空格用 %20',
    icon: Icons.link_rounded,
    builder: (_) => const UrlCodecPanelBody(),
  ),
  'texted': LocalToolDef(
    id: 'texted',
    title: '文本编辑器',
    subtitle: '随手记一段文字，实时统计字数',
    icon: Icons.edit_note_rounded,
    builder: (_) => const TextEditorPanelBody(),
  ),
  'kaomoji': LocalToolDef(
    id: 'kaomoji',
    title: '颜文字',
    subtitle: '随手挑一个，点一下就复制',
    icon: Icons.emoji_emotions_rounded,
    builder: (_) => const KaomojiPanelBody(),
  ),

  // ── 批次 3：计时 / 设备类 ──
  'stopwatch': LocalToolDef(
    id: 'stopwatch',
    title: '秒表',
    subtitle: '计次记录每段用时，本地计时不走网络',
    icon: Icons.timer_outlined,
    builder: (_) => const StopwatchPanelBody(),
  ),
  'countdown': LocalToolDef(
    id: 'countdown',
    title: '计时器',
    subtitle: '倒计时到点提示，格式 分:秒 或 时:分:秒',
    icon: Icons.hourglass_bottom_rounded,
    builder: (_) => const CountdownPanelBody(),
  ),
  'clock': LocalToolDef(
    id: 'clock',
    title: '全屏时钟',
    subtitle: '大字时钟，一秒一跳',
    icon: Icons.access_time_rounded,
    builder: (_) => const ClockPanelBody(
      title: '全屏时钟',
      subtitle: '大字时钟，一秒一跳',
      icon: Icons.access_time_rounded,
      compact: true,
    ),
  ),
  'timescreen': LocalToolDef(
    id: 'timescreen',
    title: '时间屏幕',
    subtitle: '时间加日期，放桌上当电子钟',
    icon: Icons.calendar_today_rounded,
    builder: (_) => const ClockPanelBody(
      title: '时间屏幕',
      subtitle: '时间加日期，放桌上当电子钟',
      icon: Icons.calendar_today_rounded,
      compact: false,
    ),
  ),
  'random': LocalToolDef(
    id: 'random',
    title: '随机数生成',
    subtitle: '指定范围抽整数，可要求不重复',
    icon: Icons.casino_rounded,
    builder: (_) => const RandomPanelBody(),
  ),
  'morse': LocalToolDef(
    id: 'morse',
    title: '摩斯密码',
    subtitle: '字母数字与摩斯码互转，词间用 / 分隔',
    icon: Icons.graphic_eq_rounded,
    builder: (_) => const MorsePanelBody(),
  ),
  'ruler': LocalToolDef(
    id: 'ruler',
    title: '刻度尺',
    subtitle: '屏幕上的尺子，按屏幕密度换算真实尺寸',
    icon: Icons.straighten_rounded,
    builder: (_) => const RulerPanelBody(),
  ),
  'deadpixel': LocalToolDef(
    id: 'deadpixel',
    title: '屏幕坏点检测',
    subtitle: '依次铺满纯色，亮点/暗点一眼看出来',
    icon: Icons.grid_on_rounded,
    builder: (_) => const DeadPixelPanelBody(),
  ),

  // ── 批次 4：传感器（需 sensors_plus / record 插件）──
  'compass': LocalToolDef(
    id: 'compass',
    title: '指南针',
    subtitle: '用磁力计测方位，手机请水平放置',
    icon: Icons.explore_rounded,
    builder: (_) => const CompassPanelBody(),
  ),
  'level': LocalToolDef(
    id: 'level',
    title: '水平仪',
    subtitle: '气泡居中就是水平，量程 ±15°',
    icon: Icons.straighten_rounded,
    builder: (_) => const LevelPanelBody(),
  ),
  'decibel': LocalToolDef(
    id: 'decibel',
    title: '分贝仪',
    subtitle: '用麦克风估环境噪音，数值是估算不是校准声压级',
    icon: Icons.graphic_eq_rounded,
    builder: (_) => const DecibelPanelBody(),
  ),
};

/// 纯本地工具的承载页。
///
/// 和 API Hub 的面板**刻意分开**：这条路径不加载任何网络索引、不碰
/// HTTP 客户端、没有 loading/error 态 —— 打开就是能用。混进 API Hub
/// 会让「本地工具」白等一次索引请求。
class LocalToolPage extends StatelessWidget {
  const LocalToolPage({super.key, required this.localId});

  final String localId;

  @override
  Widget build(BuildContext context) {
    final def = kLocalTools[localId];
    if (def == null) {
      // 正常到不了这里（kToolTargets 里的 id 有测试逐条核对）。真到了，
      // 给一个能退回的明确错误，而不是白屏或崩溃。
      return Scaffold(
        backgroundColor: AppTokens.background,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    AppBackButton(
                      onPressed: () => Navigator.maybePop(context),
                      label: '返回',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Text('未找到本地工具「$localId」'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTokens.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  AppBackButton(
                    onPressed: () => Navigator.maybePop(context),
                    label: def.title,
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: def.builder(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 各工具主体：只负责收输入、调 domain、画结果。逻辑全在 domain 层单测过。 ──

class _CalculatorBody extends StatelessWidget {
  const _CalculatorBody();

  @override
  Widget build(BuildContext context) => const CalculatorPanelBody();
}

class _UnitConvertBody extends StatelessWidget {
  const _UnitConvertBody();

  @override
  Widget build(BuildContext context) => const UnitConvertPanelBody();
}

class _MortgageBody extends StatelessWidget {
  const _MortgageBody();

  @override
  Widget build(BuildContext context) => const MortgagePanelBody();
}

class _DateCalcBody extends StatelessWidget {
  const _DateCalcBody();

  @override
  Widget build(BuildContext context) => const DateCalcPanelBody();
}

class _TimestampBody extends StatelessWidget {
  const _TimestampBody();

  @override
  Widget build(BuildContext context) => const TimestampPanelBody();
}

class _RadixBody extends StatelessWidget {
  const _RadixBody();

  @override
  Widget build(BuildContext context) => const RadixPanelBody();
}

class _CaseBody extends StatelessWidget {
  const _CaseBody();

  @override
  Widget build(BuildContext context) => const CaseConvertPanelBody();
}

class _PasswordBody extends StatelessWidget {
  const _PasswordBody();

  @override
  Widget build(BuildContext context) => const PasswordPanelBody();
}

class _RelationBody extends StatelessWidget {
  const _RelationBody();

  @override
  Widget build(BuildContext context) => const RelationPanelBody();
}

/// 错误文案只有一处实现（在 local_tool_panels.dart 里），这里转发一下，
/// 避免同一个函数两份副本各自漂移。
String localToolErrorText(Object e) => localToolErrorTextFor(e);
