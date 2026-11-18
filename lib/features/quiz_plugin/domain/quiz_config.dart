import 'dart:ui' show Color;


/// 答题插件配置模型
class QuizConfig {
  const QuizConfig({
    this.enabled = false,
    this.apiUrl = '',
    this.apiKey = '',
    this.apiModel = '',
    this.autoSearch = true,
    this.displayMode = 'accessibility',
    this.filterNoise = true,
    this.debugCapture = false,
    this.maxCaptureLines = 8,
    this.overlayWidth = 320.0,
    this.overlayHeight = 400.0,
    this.themeColorIndex = 0,
    this.bankEnabled = true,
    this.bankMaxMatches = 3,
    this.allowExternalApi = false,
    // 搜题方式开关：无障碍读屏 / OCR 截图，二者独立，任一开启即可工作
    this.accessibilityCapture = true,
    // 默认关闭：ocr.hpa888.top 目前无有效证书且无 vhost（实测 404），
    // 默认开启等于让每个新用户每道题先跑一次必然失败的 OCR。
    // 开启前会在配置页先探活 /api/ocr/health。
    this.ocrSearch = false,
    this.ocrEndpoint = 'https://ocr.hpa888.top',
    this.ocrToken = '',
    this.overlayOpacity = 1.0,

    /// 离开 box 进入第三方 App 时是否自动考试模式
    this.autoExamOnLeaveApp = true,

    /// 仅对这些包名自动考试模式（逗号/换行分隔）；空=对所有非系统 App 生效
    this.autoExamPackages = '',

    /// 考试模式悬浮窗尺寸：small / standard / large。
    this.examOverlaySize = 'standard',

    /// 题图比对区域（屏幕像素比例 0~1）；为空表示不启用图像消歧。
  });

  final bool enabled;
  final String apiUrl;
  final String apiKey;

  /// 自定义通道的**模型名**（留空 = 用内置默认，见 `QuizEngine.defaultVisionModel`）。
  ///
  /// ## 为什么模型名必须可配（2026-11-17 修）
  ///
  /// 模型名原先**硬编码** `deepseek`，那是 NewAPI 渠道（`newapi.hpa888.top/v1`）
  /// 时代的事 —— 该渠道只用渠道名掩盖真实上游，所以填 `deepseek` 能通。
  /// 2026-10-10 换到 flr 之后，**代理档**没问题（服务端用后台配置的
  /// `provider.model` 覆盖），可**手填 key 直连档**一直发着 `model: deepseek`：
  /// flr 的模型清单里没有这个名字 ⇒ 直连用户每次都是「模型不存在」。
  ///
  /// 直连档的模型由用户自己的通道决定，写死任何一个名字都迟早再次过期。
  final String apiModel;
  final bool autoSearch;

  /// 显示模式：accessibility=无障碍悬浮（默认，抗屏蔽），notification=通知栏，manual=手动。
  final String displayMode;
  final bool filterNoise;

  /// 调试捕获：显示无障碍原始/清洗后的屏幕文本，便于定位捕获或匹配问题。
  final bool debugCapture;
  final int maxCaptureLines;
  final double overlayWidth;
  final double overlayHeight;
  final int themeColorIndex;
  static const List<Color> themeColors = [
    Color(0xFF4F46E5), // 靛蓝
    Color(0xFF059669), // 翠绿
    Color(0xFFDC2626), // 红色
    Color(0xFF7C3AED), // 紫色
    Color(0xFF0891B2), // 青色
  ];

  final bool bankEnabled;
  final int bankMaxMatches;

  /// 是否允许把题目发送到第三方/自定义网络 API；默认关闭，仅使用本地题库。
  final bool allowExternalApi;

  /// 无障碍读屏搜题：由无障碍服务读取屏幕文本后搜题。默认开启。
  final bool accessibilityCapture;

  /// OCR 截图搜题：截屏识别区域→OCR→搜题，不依赖读屏文本。默认开启。
  final bool ocrSearch;

  /// OCR 服务地址（自建服务，POST /api/ocr/upload 上传 multipart file）。
  final String ocrEndpoint;

  /// OCR 服务 Bearer token（可选，留空则免密）。
  final String ocrToken;

  /// 答案悬浮窗整体透明度（0.3~1.0）。
  final double overlayOpacity;

  /// 切到第三方 App 时自动进入考试模式。
  final bool autoExamOnLeaveApp;

  /// 自动考试模式包名白名单；空表示除系统外全部。
  final String autoExamPackages;

  /// 考试模式悬浮窗尺寸：small / standard / large。
  final String examOverlaySize;

  /// 题图比对区域（屏幕像素比例 0~1）；为空表示不启用图像消歧。

  QuizConfig copyWith({
    bool? enabled,
    String? apiUrl,
    String? apiKey,
    String? apiModel,
    bool? autoSearch,
    String? displayMode,
    bool? filterNoise,
    bool? debugCapture,
    int? maxCaptureLines,
    double? overlayWidth,
    double? overlayHeight,
    int? themeColorIndex,
    bool? bankEnabled,
    int? bankMaxMatches,
    bool? allowExternalApi,
    bool? accessibilityCapture,
    bool? ocrSearch,
    String? ocrEndpoint,
    String? ocrToken,
    double? overlayOpacity,
    bool? autoExamOnLeaveApp,
    String? autoExamPackages,
    String? examOverlaySize,
  }) {
    return QuizConfig(
      enabled: enabled ?? this.enabled,
      apiUrl: apiUrl ?? this.apiUrl,
      apiModel: apiModel ?? this.apiModel,
      apiKey: apiKey ?? this.apiKey,
      autoSearch: autoSearch ?? this.autoSearch,
      displayMode: displayMode ?? this.displayMode,
      filterNoise: filterNoise ?? this.filterNoise,
      debugCapture: debugCapture ?? this.debugCapture,
      maxCaptureLines: maxCaptureLines ?? this.maxCaptureLines,
      overlayWidth: overlayWidth ?? this.overlayWidth,
      overlayHeight: overlayHeight ?? this.overlayHeight,
      themeColorIndex: themeColorIndex ?? this.themeColorIndex,
      bankEnabled: bankEnabled ?? this.bankEnabled,
      bankMaxMatches: bankMaxMatches ?? this.bankMaxMatches,
      allowExternalApi: allowExternalApi ?? this.allowExternalApi,
      accessibilityCapture: accessibilityCapture ?? this.accessibilityCapture,
      ocrSearch: ocrSearch ?? this.ocrSearch,
      ocrEndpoint: ocrEndpoint ?? this.ocrEndpoint,
      ocrToken: ocrToken ?? this.ocrToken,
      overlayOpacity: overlayOpacity ?? this.overlayOpacity,
      autoExamOnLeaveApp: autoExamOnLeaveApp ?? this.autoExamOnLeaveApp,
      autoExamPackages: autoExamPackages ?? this.autoExamPackages,
      examOverlaySize: examOverlaySize ?? this.examOverlaySize,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'apiUrl': apiUrl,
    'apiKey': apiKey,
    'apiModel': apiModel,
    'autoSearch': autoSearch,
    'displayMode': displayMode,
    'filterNoise': filterNoise,
    'debugCapture': debugCapture,
    'maxCaptureLines': maxCaptureLines,
    'overlayWidth': overlayWidth,
    'overlayHeight': overlayHeight,
    'themeColorIndex': themeColorIndex,
    'bankEnabled': bankEnabled,
    'bankMaxMatches': bankMaxMatches,
    'allowExternalApi': allowExternalApi,
    'accessibilityCapture': accessibilityCapture,
    'ocrSearch': ocrSearch,
    'ocrEndpoint': ocrEndpoint,
    'ocrToken': ocrToken,
    'overlayOpacity': overlayOpacity,
    'autoExamOnLeaveApp': autoExamOnLeaveApp,
    'autoExamPackages': autoExamPackages,
    'examOverlaySize': examOverlaySize,
  };

  factory QuizConfig.fromJson(Map<String, dynamic> json) {
    // 兼容旧字段：ocrEnabled -> ocrSearch
    final bool ocrSearch =
        (json['ocrSearch'] as bool?) ?? (json['ocrEnabled'] as bool?) ?? false;
    return QuizConfig(
      enabled: (json['enabled'] as bool?) ?? false,
      apiUrl: (json['apiUrl'] as String?) ?? '',
      // 旧配置没有这个键 ⇒ 空串 ⇒ 走内置默认（不做「把 deepseek 迁成新名字」
      // 的猜测式迁移：用户可能真的在用某个自建通道里的 deepseek）
      apiModel: (json['apiModel'] as String?) ?? '',
      apiKey: (json['apiKey'] as String?) ?? '',
      autoSearch: (json['autoSearch'] as bool?) ?? true,
      displayMode: _parseDisplayMode(json['displayMode'] as String?),
      filterNoise: (json['filterNoise'] as bool?) ?? true,
      debugCapture: (json['debugCapture'] as bool?) ?? false,
      maxCaptureLines: (json['maxCaptureLines'] as num?)?.toInt() ?? 8,
      overlayWidth: (json['overlayWidth'] as num?)?.toDouble() ?? 320.0,
      overlayHeight: (json['overlayHeight'] as num?)?.toDouble() ?? 400.0,
      // 旧版本主题色面板给过 6 个色块而色板只有 5 色，存量 index 可能是 5 ⇒ 收敛。
      themeColorIndex: ((json['themeColorIndex'] as num?)?.toInt() ?? 0)
          .clamp(0, themeColors.length - 1),
      bankEnabled: (json['bankEnabled'] as bool?) ?? true,
      bankMaxMatches: (json['bankMaxMatches'] as num?)?.toInt() ?? 3,
      allowExternalApi: (json['allowExternalApi'] as bool?) ?? false,
      accessibilityCapture: (json['accessibilityCapture'] as bool?) ?? true,
      ocrSearch: ocrSearch,
      ocrEndpoint: (json['ocrEndpoint'] as String?)?.trim().isNotEmpty == true
          ? (json['ocrEndpoint'] as String).trim()
          : 'https://ocr.hpa888.top',
      ocrToken: (json['ocrToken'] as String?) ?? '',
      overlayOpacity: ((json['overlayOpacity'] as num?)?.toDouble() ?? 1.0)
          .clamp(0.3, 1.0),
      autoExamOnLeaveApp: (json['autoExamOnLeaveApp'] as bool?) ?? true,
      autoExamPackages: (json['autoExamPackages'] as String?) ?? '',
      examOverlaySize:
          _parseExamOverlaySize(json['examOverlaySize'] as String?) ??
          'standard',
    );
  }

  static String? _parseExamOverlaySize(String? value) {
    switch (value) {
      case 'small':
      case 'standard':
      case 'large':
        return value;
      default:
        return null;
    }
  }

  static String _parseDisplayMode(String? value) {
    switch (value) {
      case 'accessibility':
      case 'notification':
      case 'manual':
        return value!;
      // 兼容旧配置值
      case 'accessibility_overlay':
      case 'overlay':
        return 'accessibility';
      default:
        return 'accessibility';
    }
  }
}
