part of './quiz_plugin_entry.dart';

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
    QuizPluginEntry._regionPreviewNotifier.addListener(_onPreview);
  }

  @override
  void dispose() {
    QuizPluginEntry._regionPreviewNotifier.removeListener(_onPreview);
    super.dispose();
  }

  void _onPreview() {
    final r = QuizPluginEntry._regionPreviewNotifier.value;
    if (r != null && mounted) {
      // 原生框选拖动时实时联动数字（仅在没有正在编辑文本时覆盖）
      setState(() => _region = r);
    }
  }

  Future<void> _syncToNative() async {
    await QuizPluginEntry.updateRegion(_region);
  }

  Future<void> _openNativeSelector() async {
    await QuizPluginEntry.openRegionSelector();
  }

  void _applyPreset(Rect rectF) {
    setState(
      () => _region = Rect.fromLTWH(
        rectF.left * _screenW,
        rectF.top * _screenH,
        (rectF.right - rectF.left) * _screenW,
        (rectF.bottom - rectF.top) * _screenH,
      ),
    );
    QuizPluginEntry.applyRegionPreset(rectF);
    _syncToNative();
  }

  double get _screenW => MediaQuery.of(context).size.width;
  double get _screenH => MediaQuery.of(context).size.height;

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
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已同步到原生悬浮窗')));
              }
            },
            icon: const Icon(Icons.check),
            tooltip: '同步',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = constraints.maxHeight;
                // 预览按屏幕真实比例映射，所见即所得
                final scaleX = width / _screenW;
                final scaleY = height / _screenH;
                final previewRect = Rect.fromLTRB(
                  _region.left * scaleX,
                  _region.top * scaleY,
                  _region.right * scaleX,
                  _region.bottom * scaleY,
                );
                return RepaintBoundary(
                  child: CustomPaint(
                    size: Size(width, height),
                    painter: _RegionPainter(
                      region: previewRect,
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
                  color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: () => _applyPreset(
                          const Rect.fromLTRB(0.02, 0.04, 0.98, 0.55),
                        ),
                        child: const Text('题干带'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _applyPreset(
                          const Rect.fromLTRB(0.04, 0.28, 0.96, 0.72),
                        ),
                        child: const Text('中部'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _applyPreset(
                          const Rect.fromLTRB(0.02, 0.04, 0.98, 0.96),
                        ),
                        child: const Text('全屏'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: 'Left',
                          value: _region.left.toInt(),
                          onChanged: (v) {
                            setState(
                              () => _region = Rect.fromLTWH(
                                v.toDouble(),
                                _region.top,
                                _region.width,
                                _region.height,
                              ),
                            );
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
                            setState(
                              () => _region = Rect.fromLTWH(
                                _region.left,
                                v.toDouble(),
                                _region.width,
                                _region.height,
                              ),
                            );
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
                            setState(
                              () => _region = Rect.fromLTWH(
                                _region.left,
                                _region.top,
                                v.toDouble(),
                                _region.height,
                              ),
                            );
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
                            setState(
                              () => _region = Rect.fromLTWH(
                                _region.left,
                                _region.top,
                                _region.width,
                                v.toDouble(),
                              ),
                            );
                            _syncToNative();
                          },
                        ),
                      ),
                    ],
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
      'w: ${region.width.toInt()}, h: ${region.height.toInt()}',
    ];
    final hintPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Colors.black, Colors.transparent],
      ).createShader(region)
      ..style = PaintingStyle.fill;
    final textPaint = TextPainter(
      text: const TextSpan(
        text: '',
        style: TextStyle(color: Colors.white, fontSize: 13),
      ),
      textDirection: TextDirection.ltr,
    );

    canvas.drawRect(
      Rect.fromLTWH(region.left, region.top, region.width, 48),
      hintPaint,
    );
    texts.asMap().forEach((i, line) {
      textPaint.text = TextSpan(
        text: line,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      );
      textPaint.layout();
      textPaint.paint(
        canvas,
        Offset(region.left + 12, region.top + 8 + i * 18),
      );
    });
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _OverlayDimensionSlider extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _OverlayDimensionSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          SizedBox(width: 36, child: Text(label)),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: ((max - min) / 10).round(),
              label: '${value.round()}dp',
              onChanged: onChanged,
            ),
          ),
          SizedBox(width: 54, child: Text('${value.round()}dp')),
        ],
      );
}

class _Field extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _Field({
    required this.label,
    required this.value,
    required this.onChanged,
  });

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
        ..selection = TextSelection.fromPosition(
          TextPosition(offset: value.toString().length),
        ),
      onChanged: (v) {
        final n = int.tryParse(v);
        if (n != null) onChanged(n);
      },
    );
  }
}


