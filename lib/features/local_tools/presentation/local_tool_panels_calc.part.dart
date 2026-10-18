part of './local_tool_panels.dart';

// 计算类工具：计算器 / 单位换算 / BMI / 房贷 / 日期 / 时间戳 / 进制 / 大小写 / 密码 / 亲戚称呼。
//
// 全是纯计算 + 表单，domain 逻辑在 local_tool_math.dart。

// ───────────────────────────── 科学计算器 ─────────────────────────────

class CalculatorPanelBody extends StatefulWidget {
  const CalculatorPanelBody({super.key});

  @override
  State<CalculatorPanelBody> createState() => _CalculatorPanelBodyState();
}

class _CalculatorPanelBodyState extends State<CalculatorPanelBody> {
  final _ctrl = TextEditingController();
  String _result = '';
  bool _error = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _calc(String expr) {
    setState(() {
      _ctrl.text = expr;
      try {
        final v = m.evalArithmetic(expr);
        // 浮点误差：0.1+0.2 显示成 0.30000000000000004 会被当成 bug。
        _result = _formatNumber(v);
        _error = false;
      } catch (e) {
        _result = localToolErrorTextFor(e);
        _error = true;
      }
    });
  }

  /// 去掉浮点毛刺：整数补 .0 之外的精度收干净，最多留 10 位有效小数。
  static String _formatNumber(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e15) {
      return v.toInt().toString();
    }
    var s = v.toStringAsFixed(10);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  @override
  Widget build(BuildContext context) {
    const keys = [
      '7', '8', '9', '/',
      '4', '5', '6', '*',
      '1', '2', '3', '-',
      '0', '.', '(', '+',
      ')', '^', 'C', '=',
    ];
    return LocalToolCard(
      title: '科学计算器',
      subtitle: '支持 + - * / ^ 与括号，结果本地计算',
      icon: Icons.calculate_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: false,
            decoration: const InputDecoration(
              hintText: '输入表达式，如 (1+2)*3',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: _calc,
          ),
          const SizedBox(height: 10),
          if (_result.isNotEmpty) ...[
            LocalToolResult(text: _result, error: _error),
            const SizedBox(height: 10),
          ],
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.9,
            children: [
              for (final k in keys)
                _CalcKey(
                  label: k,
                  onTap: () {
                    if (k == 'C') {
                      setState(() {
                        _ctrl.clear();
                        _result = '';
                        _error = false;
                      });
                    } else if (k == '=') {
                      _calc(_ctrl.text);
                    } else {
                      _ctrl.text = _ctrl.text + k;
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CalcKey extends StatelessWidget {
  const _CalcKey({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isEq = label == '=';
    final isOp = '+-*/^()'.contains(label);
    return Material(
      color: isEq
          ? AppTokens.primaryBlue
          : isOp
              ? AppTokens.primaryBlue.withValues(alpha: 0.10)
              : AppTokens.surfaceMuted,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: isEq ? Colors.white : AppTokens.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── 单位换算 ─────────────────────────────

class UnitConvertPanelBody extends StatefulWidget {
  const UnitConvertPanelBody({super.key});

  @override
  State<UnitConvertPanelBody> createState() => _UnitConvertPanelBodyState();
}

class _UnitConvertPanelBodyState extends State<UnitConvertPanelBody> {
  final _ctrl = TextEditingController(text: '1');
  m.UnitCategory _cat = m.UnitCategory.length;
  late String _from = m.unitsOf(_cat).first;
  late String _to = m.unitsOf(_cat)[1];
  String _result = '';
  bool _error = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _convert() {
    setState(() {
      try {
        final v = double.parse(_ctrl.text.trim());
        final r = m.convertUnit(v, _from, _to, _cat);
        _result = '${_fmt(v)} $_from = ${_fmt(r)} $_to';
        _error = false;
      } catch (e) {
        _result = e is FormatException ? '请输入数字' : localToolErrorTextFor(e);
        _error = true;
      }
    });
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
    var s = v.toStringAsFixed(6);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final units = m.unitsOf(_cat);
    return LocalToolCard(
      title: '单位换算',
      subtitle: '长度 / 重量 / 温度 / 面积 / 体积',
      icon: Icons.swap_horiz_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final c in m.UnitCategory.values)
                ChoiceChip(
                  label: Text(_catName(c)),
                  selected: _cat == c,
                  onSelected: (_) => setState(() {
                    _cat = c;
                    final u = m.unitsOf(c);
                    _from = u.first;
                    _to = u.length > 1 ? u[1] : u.first;
                    _result = '';
                    _error = false;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '数值',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _convert(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _UnitDropdown(
                  value: _from,
                  units: units,
                  onChanged: (v) => setState(() => _from = v),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward_rounded, size: 18),
              ),
              Expanded(
                child: _UnitDropdown(
                  value: _to,
                  units: units,
                  onChanged: (v) => setState(() => _to = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton(onPressed: _convert, child: const Text('换算')),
          if (_result.isNotEmpty) ...[
            const SizedBox(height: 10),
            LocalToolResult(text: _result, error: _error),
          ],
        ],
      ),
    );
  }

  static String _catName(m.UnitCategory c) => switch (c) {
        m.UnitCategory.length => '长度',
        m.UnitCategory.weight => '重量',
        m.UnitCategory.temperature => '温度',
        m.UnitCategory.area => '面积',
        m.UnitCategory.volume => '体积',
      };
}

class _UnitDropdown extends StatelessWidget {
  const _UnitDropdown({
    required this.value,
    required this.units,
    required this.onChanged,
  });

  final String value;
  final List<String> units;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isDense: true,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      items: [
        for (final u in units)
          DropdownMenuItem(value: u, child: Text(unitLabel(u))),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

/// 单位英文键 → 中文显示名（下拉里给用户看英文缩写不友好）。
String unitLabel(String key) => switch (key) {
      'mm' => '毫米',
      'cm' => '厘米',
      'm' => '米',
      'km' => '千米',
      'inch' => '英寸',
      'ft' => '英尺',
      'mile' => '英里',
      '里' => '里',
      '尺' => '尺',
      '寸' => '寸',
      'mg' => '毫克',
      'g' => '克',
      'kg' => '千克',
      't' => '吨',
      'jin' => '斤',
      'liang' => '两',
      'lb' => '磅',
      'oz' => '盎司',
      'c' => '摄氏度',
      'f' => '华氏度',
      'k' => '开尔文',
      'm2' => '平方米',
      'cm2' => '平方厘米',
      'km2' => '平方千米',
      '亩' => '亩',
      'ha' => '公顷',
      'ft2' => '平方英尺',
      'ml' => '毫升',
      'l' => '升',
      'm3' => '立方米',
      'gal' => '加仑',
      _ => key,
    };

// ───────────────────────────── BMI ─────────────────────────────

class BmiPanelBody extends StatefulWidget {
  const BmiPanelBody({super.key});

  @override
  State<BmiPanelBody> createState() => _BmiPanelBodyState();
}

class _BmiPanelBodyState extends State<BmiPanelBody> {
  final _w = TextEditingController();
  final _h = TextEditingController();
  String _result = '';
  bool _error = false;

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    super.dispose();
  }

  void _calc() {
    setState(() {
      try {
        final w = double.parse(_w.text.trim());
        final h = double.parse(_h.text.trim());
        final bmi = m.bmiValue(w, h);
        _result = 'BMI ${bmi.toStringAsFixed(1)} · ${m.bmiCategory(bmi)}';
        _error = false;
      } catch (e) {
        _result = e is FormatException ? '请输入数字' : localToolErrorTextFor(e);
        _error = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: 'BMI 计算',
      subtitle: '按中国成人标准：偏瘦 / 正常 / 超重 / 肥胖',
      icon: Icons.monitor_weight_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _w,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '体重（kg）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _h,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '身高（cm）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _calc(),
          ),
          const SizedBox(height: 10),
          FilledButton(onPressed: _calc, child: const Text('计算')),
          if (_result.isNotEmpty) ...[
            const SizedBox(height: 10),
            LocalToolResult(text: _result, error: _error),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────────── 房贷 ─────────────────────────────

class MortgagePanelBody extends StatefulWidget {
  const MortgagePanelBody({super.key});

  @override
  State<MortgagePanelBody> createState() => _MortgagePanelBodyState();
}

class _MortgagePanelBodyState extends State<MortgagePanelBody> {
  final _p = TextEditingController(text: '1000000');
  final _rate = TextEditingController(text: '4.9');
  final _years = TextEditingController(text: '30');
  bool _equalInstallment = true;
  List<String> _lines = [];
  bool _error = false;

  @override
  void dispose() {
    _p.dispose();
    _rate.dispose();
    _years.dispose();
    super.dispose();
  }

  void _calc() {
    setState(() {
      try {
        final principal = double.parse(_p.text.trim());
        final rate = double.parse(_rate.text.trim());
        final months = (double.parse(_years.text.trim()) * 12).round();
        if (_equalInstallment) {
          final r = m.mortgageEqualInstallment(
            principal: principal,
            annualRatePercent: rate,
            months: months,
          );
          _lines = [
            '每月还款 ${_money(r.monthlyPayment)}',
            '利息总额 ${_money(r.totalInterest)}',
            '还款总额 ${_money(r.totalPayment)}',
          ];
        } else {
          final r = m.mortgageEqualPrincipal(
            principal: principal,
            annualRatePercent: rate,
            months: months,
          );
          _lines = [
            '首月还款 ${_money(r.firstMonthPayment)}',
            '末月还款 ${_money(r.lastMonthPayment)}',
            '利息总额 ${_money(r.totalInterest)}',
            '还款总额 ${_money(r.totalPayment)}',
          ];
        }
        _error = false;
      } catch (e) {
        _lines = [
          e is FormatException ? '请输入数字' : localToolErrorTextFor(e),
        ];
        _error = true;
      }
    });
  }

  static String _money(double v) {
    final s = v.toStringAsFixed(2);
    final dot = s.indexOf('.');
    final intPart = s.substring(0, dot);
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    return '¥$buf${s.substring(dot)}';
  }

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: '房贷计算器',
      subtitle: '等额本息 / 等额本金',
      icon: Icons.home_work_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _p,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '贷款总额（元）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _rate,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '年利率（%）',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _years,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '年限（年）',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('等额本息')),
              ButtonSegment(value: false, label: Text('等额本金')),
            ],
            selected: {_equalInstallment},
            onSelectionChanged: (s) =>
                setState(() => _equalInstallment = s.first),
          ),
          const SizedBox(height: 10),
          FilledButton(onPressed: _calc, child: const Text('计算')),
          if (_lines.isNotEmpty) ...[
            const SizedBox(height: 10),
            LocalToolResult(
              text: _lines.join('\n'),
              error: _error,
              selectable: false,
            ),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────────── 日期计算 ─────────────────────────────

class DateCalcPanelBody extends StatefulWidget {
  const DateCalcPanelBody({super.key});

  @override
  State<DateCalcPanelBody> createState() => _DateCalcPanelBodyState();
}

class _DateCalcPanelBodyState extends State<DateCalcPanelBody> {
  DateTime _a = DateTime.now();
  DateTime _b = DateTime.now();
  int _addDaysValue = 30;
  String _result = '';

  Future<void> _pick(bool isA) async {
    final base = isA ? _a : _b;
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (picked != null) {
      setState(() => isA ? _a = picked : _b = picked);
    }
  }

  void _diff() {
    setState(() {
      final d = m.daysBetween(_a, _b);
      _result = d >= 0 ? '相差 $d 天' : '早 ${-d} 天';
    });
  }

  void _add() {
    setState(() {
      final r = m.addDays(_a, _addDaysValue);
      _result = '${_d(_a)} 加 $_addDaysValue 天 = ${_d(r)}';
    });
  }

  static String _d(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: '日期计算',
      subtitle: '相差天数 / 日期加减 / 闰年判断',
      icon: Icons.calendar_month_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DateRow(label: '开始日期', value: _d(_a), onTap: () => _pick(true)),
          const SizedBox(height: 8),
          _DateRow(label: '结束日期', value: _d(_b), onTap: () => _pick(false)),
          const SizedBox(height: 10),
          FilledButton(onPressed: _diff, child: const Text('计算相差天数')),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '加/减天数',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      _addDaysValue = int.tryParse(v.trim()) ?? _addDaysValue,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _add,
                child: const Text('用开始日期算'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_a.year} 年是${m.isLeapYear(_a.year) ? '' : '不'}闰年',
            style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
          ),
          if (_result.isNotEmpty) ...[
            const SizedBox(height: 10),
            LocalToolResult(text: _result, selectable: false),
          ],
        ],
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: AppTokens.cardBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppTokens.primaryBlue,
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── 时间戳 ─────────────────────────────

class TimestampPanelBody extends StatefulWidget {
  const TimestampPanelBody({super.key});

  @override
  State<TimestampPanelBody> createState() => _TimestampPanelBodyState();
}

class _TimestampPanelBodyState extends State<TimestampPanelBody> {
  final _ts = TextEditingController();
  final _dt = TextEditingController();
  String _result = '';
  bool _error = false;

  @override
  void initState() {
    super.initState();
    // 用当前时间秒数预填，省得用户自己去别处找。
    _ts.text = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
  }

  @override
  void dispose() {
    _ts.dispose();
    _dt.dispose();
    super.dispose();
  }

  void _tsToDate() {
    setState(() {
      try {
        final raw = int.parse(_ts.text.trim());
        final secs = m.normalizeTimestampToSeconds(raw);
        _result = '${m.formatTimestamp(secs, utc: true)} (UTC)\n'
            '${m.formatTimestamp(secs)} (本地)';
        _error = false;
      } catch (e) {
        _result = e is FormatException ? '请输入数字时间戳' : localToolErrorTextFor(e);
        _error = true;
      }
    });
  }

  void _dateToTs() {
    setState(() {
      try {
        final secs = m.parseTimestamp(_dt.text.trim(), utc: true);
        _result = '${m.formatTimestamp(secs, utc: true)} (UTC) = $secs 秒';
        _error = false;
      } catch (e) {
        _result = localToolErrorTextFor(e);
        _error = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: '时间戳转换',
      subtitle: 'Unix 时间戳 ↔ 日期时间（秒/毫秒自动识别）',
      icon: Icons.schedule_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ts,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Unix 时间戳（秒或毫秒）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _tsToDate, child: const Text('转成日期')),
          const SizedBox(height: 12),
          TextField(
            controller: _dt,
            decoration: const InputDecoration(
              labelText: '日期时间（yyyy-MM-dd HH:mm:ss）',
              hintText: '2026-09-12 00:00:00',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _dateToTs,
            child: const Text('转成时间戳（按 UTC）'),
          ),
          if (_result.isNotEmpty) ...[
            const SizedBox(height: 10),
            LocalToolResult(text: _result, error: _error, selectable: false),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────────── 进制转换 ─────────────────────────────

class RadixPanelBody extends StatefulWidget {
  const RadixPanelBody({super.key});

  @override
  State<RadixPanelBody> createState() => _RadixPanelBodyState();
}

class _RadixPanelBodyState extends State<RadixPanelBody> {
  final _ctrl = TextEditingController();
  int _from = 10;
  int _to = 16;
  String _result = '';
  bool _error = false;

  static const _radixes = [2, 8, 10, 16, 32, 36];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _convert() {
    setState(() {
      try {
        _result = m.convertRadix(_ctrl.text, _from, _to);
        _error = false;
      } catch (e) {
        _result = localToolErrorTextFor(e);
        _error = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: '进制转换',
      subtitle: '2 / 8 / 10 / 16 / 32 / 36 互转',
      icon: Icons.pin_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            decoration: const InputDecoration(
              labelText: '要转换的数字',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _convert(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _from,
                  decoration: const InputDecoration(
                    labelText: '来源进制',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final r in _radixes)
                      DropdownMenuItem(value: r, child: Text('$r 进制')),
                  ],
                  onChanged: (v) => setState(() => _from = v ?? _from),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _to,
                  decoration: const InputDecoration(
                    labelText: '目标进制',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final r in _radixes)
                      DropdownMenuItem(value: r, child: Text('$r 进制')),
                  ],
                  onChanged: (v) => setState(() => _to = v ?? _to),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton(onPressed: _convert, child: const Text('转换')),
          if (_result.isNotEmpty) ...[
            const SizedBox(height: 10),
            LocalToolResult(text: _result, error: _error),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────────── 大小写 ─────────────────────────────

class CaseConvertPanelBody extends StatefulWidget {
  const CaseConvertPanelBody({super.key});

  @override
  State<CaseConvertPanelBody> createState() => _CaseConvertPanelBodyState();
}

class _CaseConvertPanelBodyState extends State<CaseConvertPanelBody> {
  final _ctrl = TextEditingController();
  String _result = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: '大小写转换',
      subtitle: '全大写 / 全小写 / 首字母大写',
      icon: Icons.text_fields_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '输入文本',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _result = ''),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(
                      () => _result = m.toUpperCaseText(_ctrl.text)),
                  child: const Text('全大写'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(
                      () => _result = m.toLowerCaseText(_ctrl.text)),
                  child: const Text('全小写'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      setState(() => _result = m.toTitleCase(_ctrl.text)),
                  child: const Text('首字母大写'),
                ),
              ),
            ],
          ),
          if (_result.isNotEmpty) ...[
            const SizedBox(height: 10),
            LocalToolResult(text: _result),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────────── 随机密码 ─────────────────────────────

class PasswordPanelBody extends StatefulWidget {
  const PasswordPanelBody({super.key});

  @override
  State<PasswordPanelBody> createState() => _PasswordPanelBodyState();
}

class _PasswordPanelBodyState extends State<PasswordPanelBody> {
  double _length = 16;
  bool _symbols = false;
  bool _digits = true;
  String _result = '';
  bool _error = false;

  void _gen() {
    setState(() {
      try {
        _result = m.generatePassword(
          length: _length.round(),
          symbols: _symbols,
          digits: _digits,
        );
        _error = false;
      } catch (e) {
        _result = localToolErrorTextFor(e);
        _error = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: '随机密码',
      subtitle: '本地生成，不走网络（源码里用的是密码学安全随机源）',
      icon: Icons.key_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('长度：${_length.round()}'),
          Slider(
            value: _length,
            min: 4,
            max: 64,
            divisions: 60,
            label: '${_length.round()}',
            onChanged: (v) => setState(() => _length = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('包含数字'),
            value: _digits,
            onChanged: (v) => setState(() => _digits = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('包含符号'),
            value: _symbols,
            onChanged: (v) => setState(() => _symbols = v),
          ),
          const SizedBox(height: 6),
          FilledButton(onPressed: _gen, child: const Text('生成密码')),
          if (_result.isNotEmpty) ...[
            const SizedBox(height: 10),
            LocalToolResult(text: _result, error: _error),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                // 先抓住 messenger，再 await —— 避免跨 async gap 用
                // State.context（analyzer 的 use_build_context_synchronously）。
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: _result));
                messenger.showSnackBar(
                  const SnackBar(content: Text('已复制到剪贴板')),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('复制'),
            ),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────────── 亲戚称呼 ─────────────────────────────
