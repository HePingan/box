part of './local_tool_panels.dart';

// 计时与设备类工具：秒表 / 计时器 / 时钟 / 随机数 / 摩斯 / 刻度尺 / 坏点检测。
//
// 刻度尺的换算在 local_tool_device.dart。

class StopwatchPanelBody extends StatefulWidget {
  const StopwatchPanelBody({super.key});
  @override
  State<StopwatchPanelBody> createState() => _StopwatchPanelBodyState();
}

class _StopwatchPanelBodyState extends State<StopwatchPanelBody> {
  final _sw = Stopwatch();
  Timer? _ticker;
  List<Duration> _laps = [];

  @override
  void dispose() {
    _ticker?.cancel();
    _sw.stop();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      if (_sw.isRunning) {
        _sw.stop();
        _ticker?.cancel();
        _ticker = null;
      } else {
        _sw.start();
        // 10ms 刷一次，百分位才跳得顺；比 16ms 一帧更跟手。
        _ticker = Timer.periodic(
          const Duration(milliseconds: 10),
          (_) => setState(() {}),
        );
      }
    });
  }

  void _lap() {
    if (_sw.elapsed == Duration.zero) return;
    setState(() => _laps = [..._laps, _sw.elapsed]);
  }

  void _reset() {
    _ticker?.cancel();
    _ticker = null;
    setState(() {
      _sw
        ..stop()
        ..reset();
      _laps = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final laps = dv.lapDiffs(_laps);
    return LocalToolCard(
      title: '秒表',
      subtitle: '计次记录每段用时，本地计时不走网络',
      icon: Icons.timer_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                dv.formatStopwatch(_sw.elapsed),
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: AppTokens.textPrimary,
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _toggle,
                  child: Text(_sw.isRunning ? '暂停' : '开始'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _sw.isRunning ? _lap : null,
                  child: const Text('计次'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _sw.elapsed == Duration.zero ? null : _reset,
                  child: const Text('归零'),
                ),
              ),
            ],
          ),
          if (laps.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final l in laps.reversed.take(20))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l.label,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTokens.textSecondary,
                      ),
                    ),
                    Text(
                      '+${dv.formatStopwatch(l.delta)}'
                      '   ${dv.formatStopwatch(l.total)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: AppTokens.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            if (laps.length > 20)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '只显示最近 20 次，共 ${laps.length} 次',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTokens.textSecondary,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────── 计时器 ───────────────────────────
class CountdownPanelBody extends StatefulWidget {
  const CountdownPanelBody({super.key});
  @override
  State<CountdownPanelBody> createState() => _CountdownPanelBodyState();
}

class _CountdownPanelBodyState extends State<CountdownPanelBody> {
  final _ctrl = TextEditingController(text: '05:00');
  Timer? _ticker;
  Duration _left = Duration.zero;
  Duration _total = Duration.zero;
  bool _running = false;
  String _err = '';
  bool _done = false;

  @override
  void dispose() {
    _ticker?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _start() {
    try {
      final d = dv.parseCountdown(_ctrl.text);
      _ticker?.cancel();
      setState(() {
        _total = d;
        _left = d;
        _running = true;
        _err = '';
        _done = false;
      });
      _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
        setState(() {
          _left = _left - const Duration(seconds: 1);
          if (_left <= Duration.zero) {
            _left = Duration.zero;
            _running = false;
            _done = true;
            t.cancel();
            _ticker = null;
          }
        });
      });
    } on dv.DeviceToolError catch (e) {
      setState(() => _err = e.message);
    }
  }

  void _pause() {
    _ticker?.cancel();
    _ticker = null;
    setState(() => _running = false);
  }

  void _reset() {
    _ticker?.cancel();
    _ticker = null;
    setState(() {
      _running = false;
      _done = false;
      _left = Duration.zero;
      _total = Duration.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total.inSeconds == 0
        ? 0.0
        : 1 - (_left.inSeconds / _total.inSeconds).clamp(0.0, 1.0);
    return LocalToolCard(
      title: '计时器',
      subtitle: '倒计时到点提示，格式 分:秒 或 时:分:秒',
      icon: Icons.hourglass_bottom_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_total.inSeconds > 0) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  dv.formatCountdown(_left),
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: AppTokens.textPrimary,
                  ),
                ),
              ),
            ),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _ctrl,
            enabled: !_running,
            decoration: InputDecoration(
              hintText: '倒计时时长，如 05:00',
              border: const OutlineInputBorder(),
              isDense: true,
              errorText: _err.isEmpty ? null : _err,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _running ? null : _start,
                  child: Text(_left > Duration.zero && !_running ? '继续' : '开始'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _running ? _pause : null,
                  child: const Text('暂停'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _total.inSeconds == 0 ? null : _reset,
                  child: const Text('重置'),
                ),
              ),
            ],
          ),
          if (_done) ...[
            const SizedBox(height: 10),
            const LocalToolResult(text: '⏰ 时间到了'),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────── 时钟 ───────────────────────────
/// 全屏时钟 / 时间屏幕共用同一份实现（两者差别只在副行内容）。
class ClockPanelBody extends StatefulWidget {
  const ClockPanelBody({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.compact,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  /// 只显示时间（全屏时钟）还是带日期（时间屏幕）。
  final bool compact;

  @override
  State<ClockPanelBody> createState() => _ClockPanelBodyState();
}

class _ClockPanelBodyState extends State<ClockPanelBody> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: widget.title,
      subtitle: widget.subtitle,
      icon: widget.icon,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Text(
                dv.formatClock(_now),
                style: TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: AppTokens.textPrimary,
                ),
              ),
              if (!widget.compact) ...[
                const SizedBox(height: 6),
                Text(
                  dv.formatClockDate(_now),
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTokens.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── 随机数 ───────────────────────────
class RandomPanelBody extends StatefulWidget {
  const RandomPanelBody({super.key});
  @override
  State<RandomPanelBody> createState() => _RandomPanelBodyState();
}

class _RandomPanelBodyState extends State<RandomPanelBody> {
  final _min = TextEditingController(text: '1');
  final _max = TextEditingController(text: '100');
  final _count = TextEditingController(text: '1');
  bool _unique = false;
  String _out = '';
  bool _error = false;

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    _count.dispose();
    super.dispose();
  }

  void _run() {
    try {
      final list = dv.randomInts(
        min: int.parse(_min.text.trim()),
        max: int.parse(_max.text.trim()),
        count: int.parse(_count.text.trim()),
        unique: _unique,
      );
      setState(() {
        _out = list.join('  ');
        _error = false;
      });
    } on FormatException {
      setState(() {
        _out = '最小值、最大值、个数都要填整数';
        _error = true;
      });
    } on dv.DeviceToolError catch (e) {
      setState(() {
        _out = e.message;
        _error = true;
      });
    }
  }

  Widget _numField(TextEditingController c, String label) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: '随机数生成',
      subtitle: '指定范围抽整数，可要求不重复',
      icon: Icons.casino_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _numField(_min, '最小'),
              const SizedBox(width: 8),
              _numField(_max, '最大'),
              const SizedBox(width: 8),
              _numField(_count, '个数'),
            ],
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('不重复', style: TextStyle(fontSize: 14)),
            value: _unique,
            onChanged: (v) => setState(() => _unique = v),
          ),
          FilledButton(onPressed: _run, child: const Text('生成')),
          if (_out.isNotEmpty) ...[
            const SizedBox(height: 10),
            LocalToolResult(text: _out, error: _error),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────── 摩斯密码 ───────────────────────────
class MorsePanelBody extends StatefulWidget {
  const MorsePanelBody({super.key});
  @override
  State<MorsePanelBody> createState() => _MorsePanelBodyState();
}

class _MorsePanelBodyState extends State<MorsePanelBody> {
  final _ctrl = TextEditingController();
  String _out = '';
  bool _error = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _run({required bool encode}) {
    try {
      final v = encode
          ? dv.textToMorse(_ctrl.text)
          : dv.morseToText(_ctrl.text);
      setState(() {
        _out = v;
        _error = false;
      });
    } on dv.DeviceToolError catch (e) {
      setState(() {
        _out = e.message;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: '摩斯密码',
      subtitle: '字母数字与摩斯码互转，词间用 / 分隔',
      icon: Icons.graphic_eq_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '文本 或 摩斯码，如 SOS / ... --- ...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _run(encode: true),
                  child: const Text('转摩斯'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _run(encode: false),
                  child: const Text('转文本'),
                ),
              ),
            ],
          ),
          if (_out.isNotEmpty) ...[
            const SizedBox(height: 10),
            LocalToolResult(text: _out, error: _error),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────── 刻度尺 ───────────────────────────
class RulerPanelBody extends StatefulWidget {
  const RulerPanelBody({super.key});
  @override
  State<RulerPanelBody> createState() => _RulerPanelBodyState();
}

class _RulerPanelBodyState extends State<RulerPanelBody> {
  static const _channel = MethodChannel(dv.kScreenMetricsChannel);

  String _out = '';
  bool _error = false;

  /// 平台报的真实屏幕参数；null = 还没拿到或通道不可用。
  dv.ScreenMetrics? _metrics;

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

  Future<void> _loadMetrics() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'getScreenMetrics',
      );
      if (raw == null) return;
      final m = dv.ScreenMetrics(
        widthPx: (raw['widthPx'] as num).toDouble(),
        heightPx: (raw['heightPx'] as num).toDouble(),
        xdpi: (raw['xdpi'] as num).toDouble(),
        ydpi: (raw['ydpi'] as num).toDouble(),
        densityDpi: (raw['densityDpi'] as num).toInt(),
      );
      // await 之后组件可能已被 dispose。
      if (!mounted) return;
      setState(() => _metrics = m);
    } on Object {
      // 拿不到就用估算值，resolveDpi 会标记 isReal=false 并在 UI 注明。
      if (!mounted) return;
      setState(() => _metrics = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final resolved = dv.resolveDpi(metrics: _metrics, fallbackDpr: dpr);

    return LocalToolCard(
      title: '刻度尺',
      subtitle: resolved.isReal
          ? '一毫米就是一毫米（用本机真实 xdpi 换算）'
          : '按屏幕密度估算，可能有几毫米偏差',
      icon: Icons.straighten_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 精度来源说明 —— 真实 / 估算必须让用户看得见，不能含糊。
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: resolved.isReal
                  ? AppTokens.success.withValues(alpha: 0.10)
                  : AppTokens.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  resolved.isReal
                      ? Icons.verified_rounded
                      : Icons.info_outline_rounded,
                  size: 15,
                  color: resolved.isReal
                      ? AppTokens.success
                      : AppTokens.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    resolved.isReal
                        ? '高精度：本机屏幕 ${resolved.dpi.toStringAsFixed(1)} dpi'
                        : '估算值：本机没报真实 dpi，用 '
                            '${resolved.dpi.toStringAsFixed(0)} dpi 近似'
                            '（可能偏几毫米）',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTokens.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 尺子本体：用 LayoutBuilder 把可用宽度画成厘米刻度。
          LayoutBuilder(
            builder: (context, c) {
              final widthPx = c.maxWidth;
              final mm = dv.pxToMillimetersWithDpi(widthPx, resolved.dpi);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '这一段宽度 ${resolved.isReal ? '=' : '≈'} '
                    '${mm.toStringAsFixed(1)} mm'
                    '（${dv.mmToCm(mm).toStringAsFixed(2)} cm）',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CustomPaint(
                    size: Size(widthPx, 46),
                    painter: _RulerPainter(millimeters: mm),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () {
              final size = MediaQuery.of(context).size;
              final mm = dv.pxToMillimetersWithDpi(size.width, resolved.dpi);
              final m = _metrics;
              setState(() {
                _out = '屏幕宽 ${size.width.toStringAsFixed(0)} 逻辑像素\n'
                    'dpi ${resolved.dpi.toStringAsFixed(1)}'
                    '${resolved.isReal ? '（本机真实值）' : '（估算，本机未报真实 dpi）'}'
                    '${m == null ? '' : '\nxdpi ${m.xdpi.toStringAsFixed(1)} / '
                        'ydpi ${m.ydpi.toStringAsFixed(1)} / '
                        'densityDpi ${m.densityDpi}'}'
                    '\n屏幕宽度 ${resolved.isReal ? '' : '约 '}'
                    '${dv.mmToCm(mm).toStringAsFixed(2)} cm';
                _error = false;
              });
            },
            child: const Text('估算屏幕尺寸'),
          ),
          if (_out.isNotEmpty) ...[
            const SizedBox(height: 10),
            LocalToolResult(text: _out, error: _error),
          ],
        ],
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({required this.millimeters});

  /// 尺子整体代表的毫米数（等于可用宽度对应的真实长度）。
  final double millimeters;

  @override
  void paint(Canvas canvas, Size size) {
    if (millimeters <= 0) return;
    final pxPerMm = size.width / millimeters;
    final line = Paint()
      ..color = AppTokens.textSecondary
      ..strokeWidth = 1;

    // 每毫米一根短线，每 5mm 中长线，每 10mm（1cm）长线 + 数字。
    for (var mm = 0; mm * pxPerMm <= size.width; mm++) {
      final x = mm * pxPerMm;
      final isCm = mm % 10 == 0;
      final isHalf = mm % 5 == 0;
      final h = isCm ? 26.0 : (isHalf ? 18.0 : 10.0);
      canvas.drawLine(Offset(x, 0), Offset(x, h), line);

      if (isCm) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${mm ~/ 10}',
            style: TextStyle(
              fontSize: 11,
              color: AppTokens.textSecondary,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 2, 28));
      }
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) => old.millimeters != millimeters;
}

// ─────────────────────────── 坏点检测 ───────────────────────────
class DeadPixelPanelBody extends StatefulWidget {
  const DeadPixelPanelBody({super.key});
  @override
  State<DeadPixelPanelBody> createState() => _DeadPixelPanelBodyState();
}

class _DeadPixelPanelBodyState extends State<DeadPixelPanelBody> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    final color = Color(dv.deadPixelColors[_idx % dv.deadPixelColors.length]);
    return LocalToolCard(
      title: '屏幕坏点检测',
      subtitle: '依次铺满纯色，亮点/暗点一眼看出来',
      icon: Icons.grid_on_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => setState(() => _idx++),
            child: Container(
              height: 160,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppTokens.radiusCard),
                border: Border.all(color: AppTokens.divider),
              ),
              child: Center(
                child: Text(
                  '点一下换下一种颜色\n（${_idx % dv.deadPixelColors.length + 1}'
                  ' / ${dv.deadPixelColors.length}）',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: color.computeLuminance() > 0.5
                        ? AppTokens.textSecondary
                        : Colors.white70,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    final n = dv.deadPixelColors.length;
                    setState(() => _idx = (_idx - 1 + n) % n);
                  },
                  child: const Text('上一种'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => setState(() => _idx++),
                  child: const Text('下一种'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── 指南针 ───────────────────────────
