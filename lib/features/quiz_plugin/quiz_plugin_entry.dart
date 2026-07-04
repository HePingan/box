import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design_system/app_tokens.dart';
import 'quiz_config.dart';
import 'quiz_engine.dart';

/// 答题插件 - MethodChannel 名称
const String _kChannel = 'com.example.box/quiz_plugin';

/// 答题插件入口
///
/// 功能：
/// 1. 配置页：开启/关闭、设置 API、主题色
/// 2. 控制原生无障碍服务 + 悬浮窗
/// 3. 手动搜题预览
class QuizPluginEntry {
  QuizPluginEntry._();

  static const MethodChannel _channel = MethodChannel(_kChannel);

  // 自动搜题状态
  static bool _autoSearchInitialized = false;
  static QuizEngine? _engineForAutoSearch;

  // 配置持久化
  static const String _configKey = 'quiz_plugin_config';

  static Future<QuizConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_configKey);
    if (raw == null || raw.isEmpty) return const QuizConfig();
    try {
      final decoded = jsonDecode(raw);
      return QuizConfig.fromJson(decoded as Map<String, dynamic>);
    } catch (_) {
      return const QuizConfig();
    }
  }

  static Future<void> saveConfig(QuizConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(config.toJson()));
  }

  // 原生交互
  static Future<bool> isAccessibilityEnabled() async {
    try {
      return await _channel.invokeMethod('isAccessibilityEnabled') as bool;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestAccessibility() async {
    try {
      await _channel.invokeMethod('requestAccessibility');
    } catch (_) {}
  }

  static Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (_) {}
  }

  static Future<void> setOverlayVisible(bool visible) async {
    try {
      await _channel.invokeMethod('setOverlayVisible', {'visible': visible});
    } catch (_) {}
  }

  static Future<void> showFallbackActivity({required String question, required String answers}) async {
    try {
      await _channel.invokeMethod('showFallbackActivity', {
        'question': question,
        'answers': answers,
      });
    } catch (_) {}
  }

  static Future<void> hideFallbackActivity() async {
    try {
      await _channel.invokeMethod('hideFallbackActivity');
    } catch (_) {}
  }

  static Future<bool> isOverlayVisible() async {
    try {
      return await _channel.invokeMethod('isOverlayVisible') as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasOverlayPermission() async {
    try {
      return await _channel.invokeMethod('hasOverlayPermission') as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> updateOverlayContent({
    required String question,
    String? answers,
    bool? isSearching,
  }) async {
    try {
      await _channel.invokeMethod('updateOverlayContent', {
        'question': question,
        if (answers != null) 'answers': answers,
        if (isSearching != null) 'isSearching': isSearching,
      });
    } catch (_) {}
  }

  static Future<void> sendResultToOverlay(String jsonResult) async {
    try {
      await _channel.invokeMethod('sendResult', {'result': jsonResult});
    } catch (_) {}
  }

  static Future<void> openRegionSelector() async {
    try {
      await _channel.invokeMethod('openRegionSelector');
    } catch (_) {}
  }

  static Future<void> updateRegion(Rect region) async {
    try {
      await _channel.invokeMethod('updateRegion', {
        'left': region.left.toDouble(),
        'top': region.top.toDouble(),
        'right': region.right.toDouble(),
        'bottom': region.bottom.toDouble(),
      });
    } catch (_) {}
  }

  /// 初始化自动搜题监听（接收无障碍服务捕获的题目）
  static Future<void> initAutoSearch() async {
    if (_autoSearchInitialized) return;
    _autoSearchInitialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onQuestionCaptured') {
        final question = (call.arguments as Map<String, dynamic>?)?['question'] as String? ?? '';
        if (question.isEmpty) return null;
        try {
          final config = await loadConfig();
          if (config.autoSearch) {
            final engine = _engineForAutoSearch ??= QuizEngine(config: config);
            final result = await engine.search(question);
            await updateOverlayContent(
              question: question,
              answers: result.answers.map((a) => a.text).join('\n'),
              isSearching: false,
            );
          }
        } catch (_) {
          // 自动搜题失败不影响主流程
        }
      }
      return null;
    });
  }

  // 配置页
  static Future<void> showConfigSheet(BuildContext context) async {
    final config = await loadConfig();
    if (!context.mounted) return;

    QuizConfig? result;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _QuizConfigSheet(
        initial: config,
        onResult: (c) => result = c,
      ),
    );

    if (result != null && context.mounted) {
      await saveConfig(result!);
      try {
        if (result!.enabled) {
          await setOverlayVisible(true);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已启用悬浮窗，请查看屏幕'), duration: Duration(seconds: 2)),
            );
          }
        } else {
          await setOverlayVisible(false);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已关闭悬浮窗'), duration: Duration(seconds: 2)),
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('悬浮窗控制失败：$e'), duration: const Duration(seconds: 3)),
          );
        }
      }
    }
  }

  // 识别区域调节页入口
  static Future<void> showRegionSheet(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _RegionSheetPage()),
    );
  }
}

// ================================================
// 配置 Sheet
// ================================================

class _AccessibilityStatusCard extends StatefulWidget {
  final Future<void> Function() onRequestAccessibility;

  const _AccessibilityStatusCard({required this.onRequestAccessibility});

  @override
  State<_AccessibilityStatusCard> createState() => _AccessibilityStatusCardState();
}

class _AccessibilityStatusCardState extends State<_AccessibilityStatusCard> {
  bool _enabled = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant _AccessibilityStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refresh();
  }

  Future<void> _refresh() async {
    _enabled = await QuizPluginEntry.isAccessibilityEnabled();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final label = _checking
        ? '正在检测无障碍权限...'
        : _enabled
            ? '无障碍服务已启用'
            : '无障碍服务未启用';
    final color = _checking
        ? Colors.grey
        : _enabled
            ? AppTokens.success
            : AppTokens.danger;
    final action = _checking
        ? null
        : _enabled
            ? null
            : TextButton.icon(
                onPressed: () async {
                  await widget.onRequestAccessibility();
                  await _refresh();
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('去开启'),
              );

    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: AppTokens.divider),
      ),
      child: Row(
        children: [
          Icon(Icons.support_agent_rounded, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          if (action != null) action,
        ],
      ),
    );
  }
}

class _OverlayStatusCard extends StatefulWidget {
  final Future<void> Function() onRequestOverlay;

  const _OverlayStatusCard({required this.onRequestOverlay});

  @override
  State<_OverlayStatusCard> createState() => _OverlayStatusCardState();
}

class _OverlayStatusCardState extends State<_OverlayStatusCard> {
  bool _hasPermission = false;
  bool _isVisible = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant _OverlayStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refresh();
  }

  Future<void> _refresh() async {
    final hasPermission = await QuizPluginEntry.hasOverlayPermission();
    final isVisible = await QuizPluginEntry.isOverlayVisible();
    if (mounted) {
      setState(() {
        _hasPermission = hasPermission;
        _isVisible = isVisible;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _checking
        ? '正在检测悬浮窗状态...'
        : !_hasPermission
            ? '悬浮窗权限未开启'
            : _isVisible
                ? '悬浮窗已显示'
                : '悬浮窗未显示';
    final color = _checking
        ? Colors.grey
        : !_hasPermission
            ? AppTokens.danger
            : _isVisible
                ? AppTokens.success
                : AppTokens.warning;
    final action = _checking
        ? null
        : !_hasPermission
            ? TextButton.icon(
                onPressed: () async {
                  await widget.onRequestOverlay();
                  await _refresh();
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('去开启'),
              )
            : _isVisible
                ? null
                : TextButton.icon(
                    onPressed: () async {
                      await QuizPluginEntry.setOverlayVisible(true);
                      await _refresh();
                    },
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('显示'),
                  );

    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: AppTokens.divider),
      ),
      child: Row(
        children: [
          Icon(Icons.layers_rounded, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          if (action != null) action,
        ],
      ),
    );
  }
}

class _QuizConfigSheet extends StatefulWidget {
  final QuizConfig initial;
  final ValueChanged<QuizConfig> onResult;

  const _QuizConfigSheet({required this.initial, required this.onResult});

  @override
  State<_QuizConfigSheet> createState() => _QuizConfigSheetState();
}

class _QuizConfigSheetState extends State<_QuizConfigSheet> {
  late QuizConfig _cfg;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _cfg = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = QuizConfig.themeColors;
    final colorOptions = [
      Colors.red,
      Colors.purple,
      Colors.blue,
      Colors.teal,
      Colors.orange,
      Colors.green,
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: MediaQuery.of(context).viewInsets + const EdgeInsets.all(AppTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('答题助手设置', style: Theme.of(context).textTheme.titleMedium),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))
              ],
            ),
            const SizedBox(height: AppTokens.spaceLg),
            _AccessibilityStatusCard(
                onRequestAccessibility: () => QuizPluginEntry.requestAccessibility()),
            const SizedBox(height: AppTokens.spaceLg),
            _OverlayStatusCard(
                onRequestOverlay: () => QuizPluginEntry.requestOverlayPermission()),
            const SizedBox(height: AppTokens.spaceLg),
            SwitchListTile(
              title: const Text('启用自动搜题'),
              subtitle: const Text('只在无障碍服务授权后生效'),
              value: _cfg.enabled,
              onChanged: (v) => setState(() => _cfg = _cfg.copyWith(enabled: v)),
            ),
            SwitchListTile(
              title: const Text('收到题目自动搜题'),
              subtitle: const Text('关闭后仅展示悬浮窗手动搜题'),
              value: _cfg.autoSearch,
              onChanged: (v) => setState(() => _cfg = _cfg.copyWith(autoSearch: v)),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            Text('主题色', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: colorOptions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final selected = themeColors.isNotEmpty &&
                      themeColors[_cfg.themeColorIndex % themeColors.length].value ==
                          colorOptions[i].value;
                  return GestureDetector(
                    onTap: () => setState(() => _cfg = _cfg.copyWith(themeColorIndex: i)),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colorOptions[i],
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: selected ? AppTokens.textPrimary : Colors.transparent,
                            width: 3),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppTokens.spaceLg),
            Text('API 地址', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                  hintText: 'https://example.com/search', border: OutlineInputBorder()),
              controller: TextEditingController(text: _cfg.apiUrl)
                ..selection = TextSelection.fromPosition(
                    TextPosition(offset: _cfg.apiUrl.length)),
              onChanged: (v) => _cfg = _cfg.copyWith(apiUrl: v),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            TextField(
              decoration: const InputDecoration(
                  hintText: 'API Key', border: OutlineInputBorder()),
              obscureText: true,
              controller: TextEditingController(text: _cfg.apiKey)
                ..selection = TextSelection.fromPosition(
                    TextPosition(offset: _cfg.apiKey.length)),
              onChanged: (v) => _cfg = _cfg.copyWith(apiKey: v),
            ),
            const SizedBox(height: AppTokens.spaceXl),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            setState(() => _saving = true);
                            await QuizPluginEntry.showRegionSheet(context);
                            await QuizPluginEntry.saveConfig(_cfg);
                            if (mounted) {
                              Navigator.pop(context);
                              widget.onResult(_cfg);
                            }
                            setState(() => _saving = false);
                          },
                    child: const Text('设置识别区域'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _saving
                        ? null
                        : () async {
                            await QuizPluginEntry.saveConfig(_cfg);
                            if (mounted) {
                              Navigator.pop(context);
                              widget.onResult(_cfg);
                            }
                          },
                    child: Text(_saving ? '保存中...' : '保存'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceXl),
          ],
        ),
      ),
    );
  }
}

// ================================================
// 识别区域调节 Page
// ================================================

class _RegionSheetPage extends StatefulWidget {
  const _RegionSheetPage();

  @override
  State<_RegionSheetPage> createState() => _RegionSheetPageState();
}

class _RegionSheetPageState extends State<_RegionSheetPage> {
  Rect _region = const Rect.fromLTWH(50, 300, 400, 300);

  @override
  void initState() {
    super.initState();
    _syncToNative();
  }

  Future<void> _syncToNative() async {
    await QuizPluginEntry.updateRegion(_region);
  }

  Future<void> _openNativeSelector() async {
    await QuizPluginEntry.openRegionSelector();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('识别区域调节'),
        actions: [
          IconButton(
            onPressed: _openNativeSelector,
            icon: const Icon(Icons.crop_free_rounded),
            tooltip: '在悬浮窗中调节',
          ),
          IconButton(
            onPressed: () async {
              await _syncToNative();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已同步到原生悬浮窗')),
                );
              }
            },
            icon: const Icon(Icons.check),
            tooltip: '同步',
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = constraints.maxHeight;
                return RepaintBoundary(
                  child: CustomPaint(
                    size: Size(width, height),
                    painter: _RegionPainter(
                      region: _region,
                      maxSize: Size(width, height),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(AppTokens.spaceXl),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  blurRadius: 12,
                  color: Theme.of(context).shadowColor.withOpacity(0.1),
                )
              ],
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: 'Left',
                          value: _region.left.toInt(),
                          onChanged: (v) {
                            setState(() => _region = Rect.fromLTWH(
                                v.toDouble(), _region.top, _region.width, _region.height));
                            _syncToNative();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: 'Top',
                          value: _region.top.toInt(),
                          onChanged: (v) {
                            setState(() => _region = Rect.fromLTWH(
                                _region.left, v.toDouble(), _region.width, _region.height));
                            _syncToNative();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: 'Width',
                          value: _region.width.toInt(),
                          onChanged: (v) {
                            setState(() => _region =
                                Rect.fromLTWH(_region.left, _region.top, v.toDouble(), _region.height));
                            _syncToNative();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: 'Height',
                          value: _region.height.toInt(),
                          onChanged: (v) {
                            setState(() => _region = Rect.fromLTWH(
                                _region.left, _region.top, _region.width, v.toDouble()));
                            _syncToNative();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  FilledButton.icon(
                    onPressed: () async {
                      final next = _region.translate(0, -10);
                      final top = next.top >= 0 ? next.top : _region.top;
                      setState(() => _region = Rect.fromLTWH(
                          _region.left, top, _region.width, _region.height));
                      await _syncToNative();
                    },
                    icon: const Icon(Icons.arrow_upward),
                    label: const Text('上移'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegionPainter extends CustomPainter {
  final Rect region;
  final Size maxSize;

  _RegionPainter({required this.region, required this.maxSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x33000000)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = const Color(0xFF4F46E5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..isAntiAlias = true;

    canvas.drawRect(Offset.zero & maxSize, paint);
    canvas.drawRect(region, border);

    final texts = [
      '识别区域',
      'x: ${region.left.toInt()}, y: ${region.top.toInt()}',
      'w: ${region.width.toInt()}, h: ${region.height.toInt()}'
    ];
    final hintPaint = Paint()
      ..shader = LinearGradient(colors: [Colors.black, Colors.transparent]).createShader(region)
      ..style = PaintingStyle.fill;
    final textPaint = TextPainter(
      text: const TextSpan(text: '', style: TextStyle(color: Colors.white, fontSize: 13)),
      textDirection: TextDirection.ltr,
    );

    canvas.drawRect(
        Rect.fromLTWH(region.left, region.top, region.width, 48), hintPaint);
    texts.asMap().forEach((i, line) {
      textPaint.text = TextSpan(text: line, style: const TextStyle(color: Colors.white, fontSize: 13));
      textPaint.layout();
      textPaint.paint(
          canvas, Offset(region.left + 12, region.top + 8 + i * 18));
    });
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _Field extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _Field({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      controller: TextEditingController(text: value.toString())
        ..selection = TextSelection.fromPosition(TextPosition(offset: value.toString().length)),
      onChanged: (v) {
        final n = int.tryParse(v);
        if (n != null) onChanged(n);
      },
    );
  }
}