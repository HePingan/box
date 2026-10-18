part of './local_tool_panels.dart';

// 传感器类工具：指南针 / 水平仪 / 分贝仪（需 sensors_plus / record 插件）。
//
// 数学在 local_tool_sensor.dart：这里只负责订阅流、画表盘与气泡。

class CompassPanelBody extends StatefulWidget {
  const CompassPanelBody({super.key});
  @override
  State<CompassPanelBody> createState() => _CompassPanelBodyState();
}

class _CompassPanelBodyState extends State<CompassPanelBody> {
  StreamSubscription<MagnetometerEvent>? _sub;
  double? _heading;
  String _err = '';

  @override
  void initState() {
    super.initState();
    _sub = magnetometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen(
      (e) {
        if (!mounted) return;
        try {
          setState(() {
            // 指南针只要水平面分量；z 拿来做「是否平放」的提示。
            _heading = sv.headingFromMagnetometer(x: e.x, y: e.y);
            _err = '';
          });
        } on sv.SensorToolError catch (ex) {
          setState(() => _err = ex.message);
        }
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _err = '读不到磁力计：$e');
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _heading;
    return LocalToolCard(
      title: '指南针',
      subtitle: '用磁力计测方位，手机请水平放置',
      icon: Icons.explore_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_err.isNotEmpty)
            LocalToolResult(text: _err, error: true)
          else if (h == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            const SizedBox(height: 6),
            Center(
              child: _CompassDial(
                heading: h,
                // 盘面占满卡片可用宽度（外壳左右各 16、卡片左右各 14），
                // 上限 300 —— 以前写死 180，一屏 360 的手机上盘面只占一半宽。
                size: (MediaQuery.sizeOf(context).width - 76).clamp(200.0, 300.0),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                '${h.toStringAsFixed(0)}°  ${sv.headingLabel(h)}',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: AppTokens.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '手机里是磁力计不是真指南针，附近有磁铁、金属桌面或扬声器时会偏，'
              '转个「8」字校准后更准。',
              style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// 罗盘盘面：**盘面转、顶部指标固定** —— 真指南针就是这么转的。
/// 以前是指针转、盘面不动，看着像个电子罗盘图标，不像罗盘。
class _CompassDial extends StatelessWidget {
  const _CompassDial({required this.heading, required this.size});

  final double heading;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: -heading * math.pi / 180,
            child: CustomPaint(
              size: Size.square(size),
              painter: _CompassFacePainter(),
            ),
          ),
          // 顶部固定指标：手机正前方对着盘上哪一格。
          Positioned(
            top: 0,
            child: CustomPaint(
              size: const Size(18, 13),
              painter: _CompassIndexPainter(),
            ),
          ),
          // 中心读数：角度 + 八方位名。
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${heading.round()}°',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: AppTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sv.headingLabel(heading),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.primaryBlue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 顶部固定指标：向下的红色小三角。
class _CompassIndexPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = AppTokens.danger);
  }

  @override
  bool shouldRepaint(_CompassIndexPainter old) => false;
}

class _CompassFacePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 6;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppTokens.divider;
    canvas.drawCircle(c, r, ring);

    // 内圈：让盘面看着像罗盘而不是一个圆。
    canvas.drawCircle(
      c,
      r * 0.72,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppTokens.divider,
    );

    // 刻度：每 15° 一小格，每 45° 一长格；长度随盘面大小缩放。
    for (var deg = 0; deg < 360; deg += 15) {
      final rad = (deg - 90) * math.pi / 180;
      final isMajor = deg % 45 == 0;
      final len = isMajor ? r * 0.11 : r * 0.055;
      final p1 = c + Offset(math.cos(rad), math.sin(rad)) * (r - len);
      final p2 = c + Offset(math.cos(rad), math.sin(rad)) * r;
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..strokeWidth = isMajor ? 2 : 1
          ..color = isMajor ? AppTokens.textSecondary : AppTokens.divider,
      );
    }

    // 四方位文字
    const marks = {'北': -90.0, '东': 0.0, '南': 90.0, '西': 180.0};
    marks.forEach((label, deg) {
      final rad = deg * math.pi / 180;
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          // 「北」标红：所有罗盘的惯例。
          style: TextStyle(
            fontSize: size.width * 0.075,
            fontWeight: FontWeight.w700,
            color: label == '北' ? AppTokens.danger : AppTokens.textSecondary,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final pos = c +
          Offset(math.cos(rad), math.sin(rad)) * (r - 26) -
          Offset(tp.width / 2, tp.height / 2);
      tp.paint(canvas, pos);
    });
  }

  @override
  bool shouldRepaint(CustomPainter old) => false;
}

// ─────────────────────────── 水平仪 ───────────────────────────
class LevelPanelBody extends StatefulWidget {
  const LevelPanelBody({super.key});
  @override
  State<LevelPanelBody> createState() => _LevelPanelBodyState();
}

class _LevelPanelBodyState extends State<LevelPanelBody> {
  StreamSubscription<AccelerometerEvent>? _sub;
  double _pitch = 0;
  double _roll = 0;
  bool _got = false;
  String _err = '';

  @override
  void initState() {
    super.initState();
    _sub = accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(
      (e) {
        if (!mounted) return;
        try {
          final t = sv.tiltFromAccelerometer(x: e.x, y: e.y, z: e.z);
          setState(() {
            _pitch = t.pitch;
            _roll = t.roll;
            _got = true;
            _err = '';
          });
        } on sv.SensorToolError catch (ex) {
          setState(() => _err = ex.message);
        }
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _err = '读不到加速度计：$e');
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = _got && sv.isLevel(pitch: _pitch, roll: _roll);
    // 气泡直径跟着屏宽走（外壳左右 16、卡片左右 14），上限 300 ——
    // 以前写死 200，360 宽的手机上下面空掉一大截。
    final dial = (MediaQuery.sizeOf(context).width - 76).clamp(200.0, 300.0);
    return LocalToolCard(
      title: '水平仪',
      subtitle: '气泡居中就是水平，量程 ±15°',
      icon: Icons.straighten_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_err.isNotEmpty)
            LocalToolResult(text: _err, error: true)
          else if (!_got)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            const SizedBox(height: 6),
            Center(
              child: SizedBox(
                width: dial,
                height: dial,
                child: CustomPaint(
                  painter: _BubblePainter(
                    pitch: _pitch,
                    roll: _roll,
                    level: level,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 两个轴分开给数：合成一个气泡只能看"偏了多少"，说不出往哪偏。
            Row(
              children: [
                Expanded(child: _TiltTile(label: '前后倾', value: _pitch, ok: level)),
                const SizedBox(width: 10),
                Expanded(child: _TiltTile(label: '左右倾', value: _roll, ok: level)),
              ],
            ),
            const SizedBox(height: 12),
            _LevelHint(level: level),
            const SizedBox(height: 10),
            Text(
              '气泡进中圈就算水平（±0.5°）。手机里的加速度计有零点误差，'
              '要更准就把它平放在你已经确认水平的台面上，记住这时候的读数再减掉。',
              style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单个轴的读数块（前后 / 左右）。
class _TiltTile extends StatelessWidget {
  const _TiltTile({required this.label, required this.value, required this.ok});

  final String label;
  final double value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: ok
            ? AppTokens.success.withValues(alpha: 0.08)
            : AppTokens.primaryBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: AppTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${value.toStringAsFixed(1)}°',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: ok ? AppTokens.success : AppTokens.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 水平与否的提示条。没水平时说清"怎么才算水平"，别只丢一句"未水平"。
class _LevelHint extends StatelessWidget {
  const _LevelHint({required this.level});

  final bool level;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: level
            ? AppTokens.success.withValues(alpha: 0.08)
            : AppTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            level ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            size: 17,
            color: level ? AppTokens.success : AppTokens.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              level ? '已水平：气泡落在中圈里' : '把手机平放，气泡进中圈就算水平',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: level ? FontWeight.w600 : FontWeight.w400,
                color: level ? AppTokens.success : AppTokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter({
    required this.pitch,
    required this.roll,
    required this.level,
  });

  final double pitch;
  final double roll;
  final bool level;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 8;

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppTokens.divider,
    );
    // 外圈内再画一圈，气泡贴边时看得出"出界"。
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppTokens.divider,
    );
    // 居中目标圈（气泡进这里算水平）
    canvas.drawCircle(
      c,
      r * 0.3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = level ? AppTokens.success : AppTokens.divider,
    );
    // 十字线
    final cross = Paint()
      ..strokeWidth = 1
      ..color = AppTokens.divider;
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), cross);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), cross);

    final off = sv.bubbleOffset(pitch: pitch, roll: roll);
    final bubbleCenter = c +
        Offset(off.dx * (r - 16), off.dy * (r - 16));
    canvas.drawCircle(
      bubbleCenter,
      16,
      Paint()..color = level ? AppTokens.success : AppTokens.primaryBlue,
    );
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.pitch != pitch || old.roll != roll || old.level != level;
}

// ─────────────────────────── 分贝仪 ───────────────────────────
class DecibelPanelBody extends StatefulWidget {
  const DecibelPanelBody({super.key});
  @override
  State<DecibelPanelBody> createState() => _DecibelPanelBodyState();
}

class _DecibelPanelBodyState extends State<DecibelPanelBody> {
  final _rec = AudioRecorder();
  StreamSubscription<Amplitude>? _sub;
  bool _running = false;
  double _db = 0;
  double _peak = 0;
  String _err = '';
  /// 录音落到的临时文件路径。
  ///
  /// 分贝仪只要振幅，但 record 7.x 的 `start()` **必须给一个真实路径**
  /// （签名就是 `{required String path}`）。以前传的是空串 `path: ''`，
  /// 安卓侧一路走到 `MediaRecorder.setOutputFile("")` —— 真机上点「开始测量」
  /// 直接闪退（原生崩溃，Dart 侧 catch 不住）。所以录到临时文件，停的时候删掉。
  String? _tmpPath;
  // 平均要留样本。上限 600 条（200ms 一条 ≈ 2 分钟），长跑不吃内存。
  final List<double> _samples = [];

  /// 样本平均；一条有效样本都没有时返回 null（界面显示 `--`，
  /// 不给 0 冒充读数）。
  double? get _avg {
    if (_samples.isEmpty) return null;
    try {
      return sv.averageDb(_samples);
    } on sv.SensorToolError {
      return null;
    }
  }

  Future<void> _start() async {
    try {
      final ok = await _rec.hasPermission();
      // await 之后组件可能已经被 dispose（用户切走页面），必须先查 mounted。
      if (!mounted) return;
      if (!ok) {
        setState(
          () => _err = '没拿到麦克风权限。到系统设置 → 应用 → 找到本应用'
              '（列表里显示的名字是 极客匣）→ 权限，允许使用麦克风。',
        );
        return;
      }
      // 真起一个录音会话才拿得到 amplitude；但路径必须是**真实文件路径**
      // （空串 = 原生崩溃，见 _tmpPath 注释）。录到临时目录，停时删除。
      final dir = await getTemporaryDirectory();
      // 同上：await 之后组件可能已经不在树上。
      if (!mounted) return;
      final tmpPath = '${dir.path}/box_db_meter.m4a';
      await _rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: tmpPath,
      );
      // 同上：start() 也是异步的，回来时可能已经不在树上了。
      if (!mounted) return;
      _tmpPath = tmpPath;
      setState(() {
        _running = true;
        _err = '';
        // 重新开始就重新记：峰值和平均都要归零，否则混着上次的读数。
        _peak = 0;
        _samples.clear();
      });
      _sub = _rec
          .onAmplitudeChanged(const Duration(milliseconds: 200))
          .listen((a) {
        if (!mounted) return;
        // record 给的 current 是 dBFS（0 = 满幅，负数），换算成相对声压级。
        final db = sv.amplitudeToDb(
          math.pow(10, a.current / 20).toDouble(),
          offset: 94,
        );
        setState(() {
          _db = db;
          if (db > _peak) _peak = db;
          _samples.add(db);
          if (_samples.length > 600) _samples.removeAt(0);
        });
      });
    } on Object catch (e) {
      // 起不来就把状态复位（否则「开始测量」一直是灰的），并清掉可能建了的临时文件。
      _removeTempFile();
      if (mounted) {
        setState(() {
          _running = false;
          _err = '启动失败：$e';
        });
      }
    }
  }

  Future<void> _stop() async {
    _sub?.cancel();
    _sub = null;
    try {
      await _rec.stop();
    } on Object {
      // 停不下来也不影响 UI 复位。
    }
    _removeTempFile();
    if (mounted) setState(() => _running = false);
  }

  /// 删掉录音临时文件 —— 分贝仪不该在手机上留任何录音。
  /// 用同步 API：调用点在 `_stop()` 与 `dispose()`，都不方便 await。
  void _removeTempFile() {
    final p = _tmpPath;
    _tmpPath = null;
    if (p == null) return;
    try {
      final f = File(p);
      if (f.existsSync()) f.deleteSync();
    } on Object {
      // 删不掉不影响测量：文件名固定，下次启动会覆盖。
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _rec.dispose();
    _removeTempFile();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = _running ? _db : null;
    return LocalToolCard(
      title: '分贝仪',
      subtitle: '用麦克风估环境噪音，数值是估算不是校准声压级',
      icon: Icons.graphic_eq_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 6),
          // 读数：大号等宽数字 + 分档颜色。没在测就明说「--」，
          // 峰值/平均一起留空 —— 不拿 0 或上次的读数冒充。
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                db == null ? '--' : db.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 64,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: db == null ? AppTokens.textTertiary : _dbColor(db),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'dB',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            db == null ? '点下面「开始测量」，用麦克风估环境噪音' : sv.dbLabel(db),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: AppTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          _DbScaleBar(db: db, peak: _running ? _peak : null),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _DbStatTile(
                  label: '峰值',
                  text: _running ? _peak.toStringAsFixed(1) : '--',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DbStatTile(
                  label: '平均',
                  text: _avg?.toStringAsFixed(1) ?? '--',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _DbReferenceTable(db: db),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _running ? null : _start,
                  child: const Text('开始测量'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _running ? _stop : null,
                  child: const Text('停止'),
                ),
              ),
            ],
          ),
          if (_err.isNotEmpty) ...[
            const SizedBox(height: 10),
            LocalToolResult(text: _err, error: true),
          ],
          const SizedBox(height: 8),
          Text(
            '手机麦克风没有绝对声压标定，不同机型可能差 10dB 以上；这个数适合'
            '做前后对比（「关窗后安静了多少」），别当专业仪器用。',
            style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ───────────── 分贝仪的展示件（色带 / 数值块 / 参考表） ─────────────

/// 分贝 → 颜色。分档口径与 `sv.dbLabel` 一致（30/50/70/85/100）。
Color _dbColor(double db) {
  if (db < 50) return AppTokens.success;
  if (db < 70) return AppTokens.primaryBlue;
  if (db < 85) return AppTokens.warning;
  if (db < 100) return AppTokens.orange;
  return AppTokens.danger;
}

/// 0~120 dB 色带：绿/蓝/橙/红四段 + 当前读数指针 + 峰值刻线。
///
/// 用一个细进度条表示分贝是说不清的（0~120 里 60 和 90 在条上只差四分之一），
/// 所以画成带分区和刻度的色带，一眼能看出"落在哪一档"。
class _DbScaleBar extends StatelessWidget {
  const _DbScaleBar({required this.db, required this.peak});

  final double? db;
  final double? peak;

  static const double _max = 120;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        double x(double v) => (v.clamp(0, _max) / _max) * w;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 30,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      // flex 按分贝区间宽度给：0~50 / 50~70 / 70~85 / 85~120。
                      child: const Row(
                        children: [
                          Expanded(
                            flex: 50,
                            child: SizedBox(
                              height: 22,
                              child: ColoredBox(color: AppTokens.success),
                            ),
                          ),
                          Expanded(
                            flex: 20,
                            child: SizedBox(
                              height: 22,
                              child: ColoredBox(color: AppTokens.primaryBlue),
                            ),
                          ),
                          Expanded(
                            flex: 15,
                            child: SizedBox(
                              height: 22,
                              child: ColoredBox(color: AppTokens.warning),
                            ),
                          ),
                          Expanded(
                            flex: 35,
                            child: SizedBox(
                              height: 22,
                              child: ColoredBox(color: AppTokens.danger),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (peak != null)
                    Positioned(
                      left: (x(peak!) - 1).clamp(0.0, w - 2),
                      top: 1,
                      child: Container(
                        width: 2,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppTokens.textPrimary.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  if (db != null)
                    Positioned(
                      left: (x(db!) - 1.5).clamp(0.0, w - 3),
                      top: 0,
                      child: Container(
                        width: 3,
                        height: 30,
                        decoration: BoxDecoration(
                          color: AppTokens.surface,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: AppTokens.textPrimary,
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // 0/30/60/90/120 五等分，spaceBetween 正好是等值刻度。
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final v in const [0, 30, 60, 90, 120])
                  Text(
                    '$v',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: AppTokens.textTertiary,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// 一个数值块（峰值 / 平均）。没有读数时显示 `--`，不显示 0。
class _DbStatTile extends StatelessWidget {
  const _DbStatTile({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppTokens.primaryBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: AppTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                text,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: AppTokens.textPrimary,
                ),
              ),
              if (text != '--')
                Text(
                  ' dB',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTokens.textSecondary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 常见噪音参考表：把读数放进常识里（"60 就是正常交谈的音量"）。
class _DbReferenceTable extends StatelessWidget {
  const _DbReferenceTable({required this.db});

  /// 当前读数；null = 没在测，不高亮任何一行。
  final double? db;

  static const List<({String name, double db})> _rows = [
    (name: '树叶沙沙', db: 20),
    (name: '冰箱嗡嗡', db: 40),
    (name: '正常交谈', db: 60),
    (name: '吸尘器', db: 75),
    (name: '电钻', db: 100),
  ];

  @override
  Widget build(BuildContext context) {
    // 高亮"环境已经比它吵"的最大那一行 —— 讲的是"你现在相当于站在哪儿"。
    final hit =
        db == null ? -1 : _rows.lastIndexWhere((r) => r.db <= db!.clamp(0, 120));
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 9),
      decoration: BoxDecoration(
        color: AppTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '常见噪音参考',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                hit < 0 ? '测了就能对上' : '已超过「${_rows[hit].name}」',
                style: TextStyle(
                  fontSize: 11.5,
                  color: hit < 0 ? AppTokens.textTertiary : AppTokens.warning,
                  fontWeight: hit < 0 ? FontWeight.w400 : FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      _rows[i].name,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            i == hit ? FontWeight.w700 : FontWeight.w400,
                        color: i == hit
                            ? AppTokens.primaryBlue
                            : AppTokens.textSecondary,
                      ),
                    ),
                  ),
                  // 进度槽用 Row + flex，不用 Stack + FractionallySizedBox：
                  // 后者的底衬 `Container(height: 6, color:)` 没有宽度，在 Stack
                  // 的 loose 约束下 ColoredBox 无子节点会取 constraints.smallest
                  // = 0 宽 —— 槽整条看不见，只剩填充段浮在灰底上。
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 6,
                        child: Row(
                          children: [
                            Expanded(
                              flex: _rows[i].db.round(),
                              child: ColoredBox(color: _dbColor(_rows[i].db)),
                            ),
                            Expanded(
                              flex: 120 - _rows[i].db.round(),
                              child: ColoredBox(color: AppTokens.divider),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${_rows[i].db.toInt()} dB',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: AppTokens.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
