part of './quiz_plugin_entry.dart';

class _AccessibilityStatusCard extends StatefulWidget {
  final Future<void> Function() onRequestAccessibility;

  const _AccessibilityStatusCard({required this.onRequestAccessibility});

  @override
  State<_AccessibilityStatusCard> createState() =>
      _AccessibilityStatusCardState();
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
          ?action,
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
  String? _remoteDenial;
  late final TextEditingController _ocrEndpointController;
  late final TextEditingController _ocrTokenController;
  late final TextEditingController _apiUrlController;
  late final TextEditingController _apiKeyController;

  @override
  void initState() {
    super.initState();
    _cfg = widget.initial;
    _ocrEndpointController = TextEditingController(text: _cfg.ocrEndpoint);
    _ocrTokenController = TextEditingController(text: _cfg.ocrToken);
    _apiUrlController = TextEditingController(text: _cfg.apiUrl);
    _apiKeyController = TextEditingController(text: _cfg.apiKey);
    _loadRemoteDenial();
  }

  Future<void> _loadRemoteDenial() async {
    final denial = await PluginGate.denial(
      PluginIds.quizAnswer,
      highRisk: false,
    );
    if (mounted) setState(() => _remoteDenial = denial);
  }

  Widget _overlayPresetButton(String label, double width, double height) {
    final selected = _cfg.overlayWidth == width && _cfg.overlayHeight == height;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(
          () =>
              _cfg = _cfg.copyWith(overlayWidth: width, overlayHeight: height),
        );
        QuizPluginEntry.setOverlaySize(width, height);
      },
    );
  }

  /// 折叠分区：把平铺的十几项设置收进可展开卡片，默认收起，减少滚动。
  Widget _section(
    BuildContext context, {
    required String title,
    required IconData icon,
    bool initiallyExpanded = false,
    required List<Widget> children,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTokens.spaceSm),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          border: Border.all(color: AppTokens.divider),
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          leading: Icon(icon, size: 20, color: AppTokens.textSecondary),
          title: Text(title, style: Theme.of(context).textTheme.titleSmall),
          children: children,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ocrEndpointController.dispose();
    _ocrTokenController.dispose();
    _apiUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const themeColors = QuizConfig.themeColors;
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
        padding:
            MediaQuery.of(context).viewInsets +
            const EdgeInsets.all(AppTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部固定：标题 + 无障碍状态 + 主开关（最常用，不折叠）
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('答题助手设置', style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceMd),
            _AccessibilityStatusCard(
              onRequestAccessibility: () =>
                  QuizPluginEntry.requestAccessibility(),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用答题助手'),
              subtitle: Text(
                _remoteDenial == null
                    ? '开启至少一种搜题方式即生效'
                    : '远程已禁用：$_remoteDenial',
              ),
              value: _cfg.enabled && _remoteDenial == null,
              onChanged: _remoteDenial != null
                  ? null
                  : (v) => setState(
                      () => _cfg = _cfg.copyWith(
                        enabled: v,
                        accessibilityCapture: v
                            ? true
                            : _cfg.accessibilityCapture,
                      ),
                    ),
            ),
            const SizedBox(height: AppTokens.spaceSm),

            // 折叠区 1：题库与搜题方式（默认展开，最核心）
            _section(
              context,
              title: '题库与搜题方式',
              icon: Icons.search_rounded,
              initiallyExpanded: true,
              children: [
                const _CloudQuizBankCard(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('收到题目自动搜题'),
                  subtitle: const Text('关闭后仅展示当前捕获内容，手动触发搜题'),
                  value: _cfg.autoSearch,
                  onChanged: (v) =>
                      setState(() => _cfg = _cfg.copyWith(autoSearch: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('无障碍读屏搜题'),
                  subtitle: const Text(
                    '由无障碍服务读取屏幕题目文本后搜题（抗屏蔽，推荐）。关闭后改用 OCR 截图搜题。',
                  ),
                  value: _cfg.accessibilityCapture,
                  onChanged: (v) => setState(
                    () => _cfg = _cfg.copyWith(
                      accessibilityCapture: v,
                      enabled: v || _cfg.ocrSearch,
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('OCR 截图搜题'),
                  subtitle: const Text(
                    '截屏识别区域→OCR→搜题，不依赖读屏文本，有些人觉得更快。需 Android 11+，对加密/防截屏页面无效。',
                  ),
                  value: _cfg.ocrSearch,
                  onChanged: (v) => setState(
                    () => _cfg = _cfg.copyWith(
                      ocrSearch: v,
                      enabled: v || _cfg.accessibilityCapture,
                    ),
                  ),
                ),
                if (_cfg.ocrSearch) ...[
                  const SizedBox(height: AppTokens.spaceSm),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'OCR 服务地址',
                      hintText: 'https://ocr.hpa888.top',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    controller: _ocrEndpointController,
                    onChanged: (v) => _cfg = _cfg.copyWith(ocrEndpoint: v),
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'OCR Token（可选）',
                      hintText: '留空则免密',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    obscureText: true,
                    controller: _ocrTokenController,
                    onChanged: (v) => _cfg = _cfg.copyWith(ocrToken: v),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('允许外部网络搜题'),
                  subtitle: const Text('默认关闭：关闭时只查本地题库，避免把题目发送到第三方 API'),
                  value: _cfg.allowExternalApi,
                  onChanged: (v) =>
                      setState(() => _cfg = _cfg.copyWith(allowExternalApi: v)),
                ),
                const SizedBox(height: AppTokens.spaceSm),
                TextField(
                  enabled: _cfg.allowExternalApi,
                  decoration: const InputDecoration(
                    labelText: 'API 地址',
                    hintText: 'https://example.com/search',
                    helperText: '需先开启“允许外部网络搜题”',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  controller: _apiUrlController,
                  onChanged: (v) => _cfg = _cfg.copyWith(apiUrl: v),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                TextField(
                  enabled: _cfg.allowExternalApi,
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  obscureText: true,
                  controller: _apiKeyController,
                  onChanged: (v) => _cfg = _cfg.copyWith(apiKey: v),
                ),
              ],
            ),

            // 折叠区 2：捕获与考试模式
            _section(
              context,
              title: '捕获与考试模式',
              icon: Icons.tune_rounded,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('离开 App 自动考试模式'),
                  subtitle: const Text(
                    '切到其他 App 时自动缩小为「仅答案+相似度」；回到 box 恢复。改完点保存立即生效。',
                  ),
                  value: _cfg.autoExamOnLeaveApp,
                  onChanged: (v) async {
                    setState(() => _cfg = _cfg.copyWith(autoExamOnLeaveApp: v));
                    // 立即落盘并通知原生，悬浮窗马上按新规则重算
                    await QuizPluginEntry.saveConfig(_cfg);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            v ? '已开启：离开 App 自动进入考试模式' : '已关闭：不再自动进入考试模式',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
                if (_cfg.autoExamOnLeaveApp) ...[
                  TextFormField(
                    initialValue: _cfg.autoExamPackages,
                    decoration: const InputDecoration(
                      labelText: '自动考试模式包名白名单（可选）',
                      hintText: '空=全部第三方；多包用逗号或换行，如 com.xxx.driver',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    maxLines: 2,
                    onChanged: (v) => setState(
                      () => _cfg = _cfg.copyWith(autoExamPackages: v),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('考试模式悬浮窗大小'),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'small', label: Text('小')),
                      ButtonSegment(value: 'standard', label: Text('标准')),
                      ButtonSegment(value: 'large', label: Text('大')),
                    ],
                    selected: {_cfg.examOverlaySize},
                    onSelectionChanged: (value) async {
                      final size = value.first;
                      setState(
                        () => _cfg = _cfg.copyWith(examOverlaySize: size),
                      );
                      // 立即落盘并通知原生：当前考试窗立刻换尺寸。
                      await QuizPluginEntry.saveConfig(_cfg);
                    },
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      '标准：兼顾不挡题与答案可读性；考试窗仍只显示答案与相似度。',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('调试捕获文本'),
                  subtitle: const Text(
                    '开启后会把无障碍捕获到的屏幕文本先显示到通知/悬浮窗，用来判断是捕获问题还是题库匹配问题',
                  ),
                  value: _cfg.debugCapture,
                  onChanged: (v) =>
                      setState(() => _cfg = _cfg.copyWith(debugCapture: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('过滤无关文本'),
                  subtitle: const Text('过滤设置、广告、上一题/下一题等界面噪声；调试时可临时关闭'),
                  value: _cfg.filterNoise,
                  onChanged: (v) =>
                      setState(() => _cfg = _cfg.copyWith(filterNoise: v)),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('最大捕获行数'),
                  subtitle: Slider(
                    min: 1,
                    max: 20,
                    divisions: 19,
                    label: '${_cfg.maxCaptureLines} 行',
                    value: _cfg.maxCaptureLines.clamp(1, 20).toDouble(),
                    onChanged: (v) => setState(
                      () => _cfg = _cfg.copyWith(maxCaptureLines: v.round()),
                    ),
                  ),
                  trailing: Text('${_cfg.maxCaptureLines.clamp(1, 20)} 行'),
                ),
              ],
            ),

            // 折叠区 3：外观与显示
            _section(
              context,
              title: '外观与显示',
              icon: Icons.palette_outlined,
              children: [
                Text('显示模式', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'accessibility',
                      label: Text('无障碍悬浮'),
                      icon: Icon(Icons.accessibility_new),
                    ),
                    ButtonSegment(
                      value: 'notification',
                      label: Text('通知'),
                      icon: Icon(Icons.notifications),
                    ),
                    ButtonSegment(
                      value: 'manual',
                      label: Text('手动'),
                      icon: Icon(Icons.edit_note),
                    ),
                  ],
                  selected: {_cfg.displayMode},
                  onSelectionChanged: (values) {
                    setState(
                      () => _cfg = _cfg.copyWith(displayMode: values.first),
                    );
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  _displayModeHint(_cfg.displayMode),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                Text('主题色', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: colorOptions.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) {
                      final selected =
                          themeColors.isNotEmpty &&
                          themeColors[_cfg.themeColorIndex % themeColors.length]
                                  .toARGB32() ==
                              colorOptions[i].toARGB32();
                      return GestureDetector(
                        onTap: () => setState(
                          () => _cfg = _cfg.copyWith(themeColorIndex: i),
                        ),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: colorOptions[i],
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? AppTokens.textPrimary
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppTokens.spaceLg),
                Text('悬浮窗外观', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.opacity, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: _cfg.overlayOpacity,
                        min: 0.3,
                        max: 1.0,
                        divisions: 14,
                        label: '${(_cfg.overlayOpacity * 100).round()}%',
                        onChanged: (v) {
                          setState(
                            () => _cfg = _cfg.copyWith(overlayOpacity: v),
                          );
                          QuizPluginEntry.setOverlayOpacity(v);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${(_cfg.overlayOpacity * 100).round()}%',
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.spaceSm),
                _OverlayDimensionSlider(
                  icon: Icons.width_normal_rounded,
                  label: '宽度',
                  value: _cfg.overlayWidth.clamp(240, 480),
                  min: 240,
                  max: 480,
                  onChanged: (v) {
                    setState(() => _cfg = _cfg.copyWith(overlayWidth: v));
                    QuizPluginEntry.setOverlaySize(v, _cfg.overlayHeight);
                  },
                ),
                _OverlayDimensionSlider(
                  icon: Icons.height_rounded,
                  label: '高度',
                  value: _cfg.overlayHeight.clamp(180, 520),
                  min: 180,
                  max: 520,
                  onChanged: (v) {
                    setState(() => _cfg = _cfg.copyWith(overlayHeight: v));
                    QuizPluginEntry.setOverlaySize(_cfg.overlayWidth, v);
                  },
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _overlayPresetButton('紧凑卡片', 280, 230),
                    _overlayPresetButton('标准', 320, 300),
                    _overlayPresetButton('大窗', 400, 380),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await QuizPluginEntry.resetOverlaySize();
                        if (mounted) {
                          setState(
                            () => _cfg = _cfg.copyWith(
                              overlayWidth: 320,
                              overlayHeight: 300,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.restart_alt, size: 16),
                      label: const Text('恢复推荐尺寸'),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.spaceSm),
                Text(
                  '标题栏可拖动；右下角手柄可微调长宽。眼睛按钮可把整个悬浮窗隐藏为可拖动的半透明小圆点，点圆点立即恢复。宽高、位置和透明度会记住。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTokens.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceMd),

            // 底部固定：操作按钮
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            setState(() => _saving = true);
                            await QuizPluginEntry.saveConfig(_cfg);
                            final opened =
                                await QuizPluginEntry.openRegionSelector();
                            if (context.mounted) {
                              if (opened) {
                                // 框选浮层已在目标界面上打开：收起设置，让用户直接拖框保存。
                                Navigator.pop(context);
                                widget.onResult(_cfg);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('请先开启无障碍服务，再框选识别区域'),
                                  ),
                                );
                              }
                            }
                            if (mounted) setState(() => _saving = false);
                          },
                    child: const Text('框选识别区域'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _saving
                        ? null
                        : () async {
                            await QuizPluginEntry.saveConfig(_cfg);
                            if (_cfg.displayMode == 'notification') {
                              await QuizPluginEntry.requestNotificationPermission();
                            }
                            if (context.mounted) {
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

String _displayModeHint(String mode) {
  switch (mode) {
    case 'accessibility':
      return '推荐：由无障碍服务创建系统级悬浮窗展示答案，可绕过驾考宝典等 App 的悬浮窗屏蔽/考试模式限制；无需单独的悬浮窗权限，只要开启无障碍服务即可。无障碍未开启时自动降级为通知栏。';
    case 'manual':
      return '不主动弹出悬浮窗或通知，只保留应用内手动搜题。';
    default:
      return '用通知栏显示结果，稳定但需要下拉查看；适合无法开启无障碍服务时使用。';
  }
}
