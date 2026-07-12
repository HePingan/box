import 'dart:ui';

/// 答题插件配置模型
class QuizConfig {
  const QuizConfig({
    this.enabled = false,
    this.apiUrl = '',
    this.apiKey = '',
    this.autoSearch = true,
    this.displayMode = 'accessibility',
    this.filterNoise = true,
    this.debugCapture = false,
    this.maxCaptureLines = 8,
    this.overlayX = 0.0,
    this.overlayY = 0.0,
    this.overlayWidth = 320.0,
    this.overlayHeight = 400.0,
    this.themeColorIndex = 0,
    this.bankEnabled = true,
    this.bankPriority = true,
    this.bankMaxMatches = 3,
    this.allowExternalApi = false,
  });

  final bool enabled;
  final String apiUrl;
  final String apiKey;
  final bool autoSearch;

  /// 显示模式：accessibility=无障碍悬浮（默认，抗屏蔽），notification=通知栏，manual=手动。
  final String displayMode;
  final bool filterNoise;

  /// 调试捕获：显示无障碍原始/清洗后的屏幕文本，便于定位捕获或匹配问题。
  final bool debugCapture;
  final int maxCaptureLines;
  final double overlayX;
  final double overlayY;
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
  final bool bankPriority;
  final int bankMaxMatches;

  /// 是否允许把题目发送到第三方/自定义网络 API；默认关闭，仅使用本地题库。
  final bool allowExternalApi;

  QuizConfig copyWith({
    bool? enabled,
    String? apiUrl,
    String? apiKey,
    bool? autoSearch,
    String? displayMode,
    bool? filterNoise,
    bool? debugCapture,
    int? maxCaptureLines,
    double? overlayX,
    double? overlayY,
    double? overlayWidth,
    double? overlayHeight,
    int? themeColorIndex,
    bool? bankEnabled,
    bool? bankPriority,
    int? bankMaxMatches,
    bool? allowExternalApi,
  }) {
    return QuizConfig(
      enabled: enabled ?? this.enabled,
      apiUrl: apiUrl ?? this.apiUrl,
      apiKey: apiKey ?? this.apiKey,
      autoSearch: autoSearch ?? this.autoSearch,
      displayMode: displayMode ?? this.displayMode,
      filterNoise: filterNoise ?? this.filterNoise,
      debugCapture: debugCapture ?? this.debugCapture,
      maxCaptureLines: maxCaptureLines ?? this.maxCaptureLines,
      overlayX: overlayX ?? this.overlayX,
      overlayY: overlayY ?? this.overlayY,
      overlayWidth: overlayWidth ?? this.overlayWidth,
      overlayHeight: overlayHeight ?? this.overlayHeight,
      themeColorIndex: themeColorIndex ?? this.themeColorIndex,
      bankEnabled: bankEnabled ?? this.bankEnabled,
      bankPriority: bankPriority ?? this.bankPriority,
      bankMaxMatches: bankMaxMatches ?? this.bankMaxMatches,
      allowExternalApi: allowExternalApi ?? this.allowExternalApi,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'apiUrl': apiUrl,
    'apiKey': apiKey,
    'autoSearch': autoSearch,
    'displayMode': displayMode,
    'filterNoise': filterNoise,
    'debugCapture': debugCapture,
    'maxCaptureLines': maxCaptureLines,
    'overlayX': overlayX,
    'overlayY': overlayY,
    'overlayWidth': overlayWidth,
    'overlayHeight': overlayHeight,
    'themeColorIndex': themeColorIndex,
    'bankEnabled': bankEnabled,
    'bankPriority': bankPriority,
    'bankMaxMatches': bankMaxMatches,
    'allowExternalApi': allowExternalApi,
  };

  factory QuizConfig.fromJson(Map<String, dynamic> json) => QuizConfig(
    enabled: (json['enabled'] as bool?) ?? false,
    apiUrl: (json['apiUrl'] as String?) ?? '',
    apiKey: (json['apiKey'] as String?) ?? '',
    autoSearch: (json['autoSearch'] as bool?) ?? true,
    displayMode: _parseDisplayMode(json['displayMode'] as String?),
    filterNoise: (json['filterNoise'] as bool?) ?? true,
    debugCapture: (json['debugCapture'] as bool?) ?? false,
    maxCaptureLines: (json['maxCaptureLines'] as num?)?.toInt() ?? 8,
    overlayX: (json['overlayX'] as num?)?.toDouble() ?? 0.0,
    overlayY: (json['overlayY'] as num?)?.toDouble() ?? 0.0,
    overlayWidth: (json['overlayWidth'] as num?)?.toDouble() ?? 320.0,
    overlayHeight: (json['overlayHeight'] as num?)?.toDouble() ?? 400.0,
    themeColorIndex: (json['themeColorIndex'] as num?)?.toInt() ?? 0,
    bankEnabled: (json['bankEnabled'] as bool?) ?? true,
    bankPriority: (json['bankPriority'] as bool?) ?? true,
    bankMaxMatches: (json['bankMaxMatches'] as num?)?.toInt() ?? 3,
    allowExternalApi: (json['allowExternalApi'] as bool?) ?? false,
  );

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
