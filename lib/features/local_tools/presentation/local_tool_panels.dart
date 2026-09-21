import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter/services.dart';

import '../../../design_system/app_tokens.dart';
import '../domain/local_tool_math.dart' as m;
import '../domain/local_tool_text.dart' as tt;
import '../domain/local_tool_device.dart' as dv;
import '../domain/local_tool_sensor.dart' as sv;

/// 10 个纯本地工具的界面主体。
///
/// 这一层刻意只做三件事：收输入 → 调 `local_tool_math.dart` → 画结果。
/// 所有可出错、可验证的逻辑都在 domain 层，这里不重复实现一份
/// （否则会出现「UI 算对了但单测测的是另一个实现」）。
///
/// 错误处理统一走 [localToolErrorTextFor]，把 [m.LocalToolError] 显示成
/// 红条；这样每个工具不用各写一遍 try/catch。

/// 从任意异常取用户可读文案。
String localToolErrorTextFor(Object e) =>
    e is m.LocalToolError ? e.message : '内部错误：$e';

/// 本地工具页面统一的外壳卡片（标题 + 说明 + 主体）。
class LocalToolCard extends StatelessWidget {
  const LocalToolCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 外壳用 Material 而不是 Container+BoxDecoration —— 和 ApiHubPanel 同因：
    // 视觉一致（白底 + 26 圆角 + 描边 + 阴影），但 ListTile/SwitchListTile/
    // InkWell 会把背景与水波纹画到最近的 Material 祖先上。之前的白底
    // Container 会把它们盖掉，framework 直接抛
    // 「ListTile background color or ink splashes may be invisible」——
    // 随机密码那两个开关就撞上了。修在外壳上，所有本地工具一次受益。
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        elevation: 1.5,
        shadowColor: AppTokens.primaryBlue.withValues(alpha: 0.06),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFFE9EEF7)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppTokens.primaryBlue.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 19, color: AppTokens.primaryBlue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 结果展示条（本地工具到处在用：输入 → 结果）。
class LocalToolResult extends StatelessWidget {
  const LocalToolResult({
    super.key,
    required this.text,
    this.error = false,
    this.selectable = true,
  });

  final String text;
  final bool error;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final color = error ? const Color(0xFFD14343) : AppTokens.textPrimary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: error
            ? const Color(0xFFFDECEC)
            : AppTokens.primaryBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: selectable
          ? SelectableText(
              text,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            )
          : Text(
              text,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
    );
  }
}


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
              : const Color(0xFFF4F6FB),
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
            style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary),
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
          border: Border.all(color: const Color(0xFFDCE3F0)),
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

class RelationPanelBody extends StatefulWidget {
  const RelationPanelBody({super.key});

  @override
  State<RelationPanelBody> createState() => _RelationPanelBodyState();
}

class _RelationPanelBodyState extends State<RelationPanelBody> {
  final List<String> _path = [];

  static const _steps = [
    '爸爸', '妈妈', '哥哥', '弟弟', '姐姐', '妹妹',
    '丈夫', '妻子', '儿子', '女儿',
  ];

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: '亲戚称呼计算',
      subtitle: '从「我」出发，按顺序点关系，算出该怎么称呼',
      icon: Icons.family_restroom_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTokens.primaryBlue.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _path.isEmpty ? '我' : '我 → ${_path.join(' → ')}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _steps)
                ActionChip(
                  label: Text(s),
                  onPressed: () => setState(() => _path.add(s)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LocalToolResult(text: m.relationTitle(_path)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _path.isEmpty
                      ? null
                      : () => setState(_path.removeLast),
                  child: const Text('退一步'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _path.isEmpty ? null : () => setState(_path.clear),
                  child: const Text('重来'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── JSON 格式化 ───────────────────────────
class JsonPanelBody extends StatefulWidget {
  const JsonPanelBody({super.key});
  @override
  State<JsonPanelBody> createState() => _JsonPanelBodyState();
}

class _JsonPanelBodyState extends State<JsonPanelBody> {
  final _ctrl = TextEditingController();
  String _out = '';
  bool _error = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _run({required bool minify}) {
    try {
      final v = minify ? tt.minifyJson(_ctrl.text) : tt.formatJson(_ctrl.text);
      setState(() {
        _out = v;
        _error = false;
      });
    } on tt.TextToolError catch (e) {
      setState(() {
        _out = e.message;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: 'JSON 格式化',
      subtitle: '美化 / 压缩 / 校验，中文不会被转义',
      icon: Icons.data_object_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: '粘贴 JSON，如 {"a":1,"中文":"值"}',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _run(minify: false),
                  child: const Text('美化'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _run(minify: true),
                  child: const Text('压缩'),
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

// ─────────────────────────── 正则测试 ───────────────────────────
class RegexPanelBody extends StatefulWidget {
  const RegexPanelBody({super.key});
  @override
  State<RegexPanelBody> createState() => _RegexPanelBodyState();
}

class _RegexPanelBodyState extends State<RegexPanelBody> {
  final _pat = TextEditingController();
  final _src = TextEditingController();
  String _out = '';
  bool _error = false;

  @override
  void dispose() {
    _pat.dispose();
    _src.dispose();
    super.dispose();
  }

  void _run() {
    try {
      final r = tt.testRegex(_pat.text, _src.text);
      final buf = StringBuffer();
      if (r.isEmpty) {
        buf.write('没有匹配到任何内容');
      } else {
        buf.write('匹配到 ');
        buf.write(r.count);
        buf.write(' 处（耗时 ');
        buf.write(r.elapsedMicros);
        buf.write(' 微秒）：');
        for (final m in r.matches.take(50)) {
          buf.write('\n  [');
          buf.write(m.start);
          buf.write('-');
          buf.write(m.end);
          buf.write('] ');
          buf.write(m.text);
          if (m.groups.isNotEmpty) {
            buf.write('   组: ');
            buf.write(m.groups.map((g) => g ?? '(未匹配)').join(' | '));
          }
        }
        if (r.matches.length > 50) {
          buf.write('\n  …… 还有 ');
          buf.write(r.matches.length - 50);
          buf.write(' 处');
        }
      }
      setState(() {
        _out = buf.toString();
        _error = false;
      });
    } on tt.TextToolError catch (e) {
      setState(() {
        _out = e.message;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: '正则测试',
      subtitle: '列出全部匹配、位置与捕获组',
      icon: Icons.code_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _pat,
            decoration: const InputDecoration(
              hintText: r'正则，如 (\w+)@(\w+)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _src,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '要匹配的文本',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(onPressed: _run, child: const Text('开始匹配')),
          if (_out.isNotEmpty) ...[
            const SizedBox(height: 10),
            LocalToolResult(text: _out, error: _error),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────── Base64 ───────────────────────────
class Base64PanelBody extends StatefulWidget {
  const Base64PanelBody({super.key});
  @override
  State<Base64PanelBody> createState() => _Base64PanelBodyState();
}

class _Base64PanelBodyState extends State<Base64PanelBody> {
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
          ? tt.base64EncodeText(_ctrl.text)
          : tt.base64DecodeText(_ctrl.text);
      setState(() {
        _out = v;
        _error = false;
      });
    } on tt.TextToolError catch (e) {
      setState(() {
        _out = e.message;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: 'Base64 编解码',
      subtitle: '按 UTF-8 处理，中文和 emoji 都不会乱码',
      icon: Icons.swap_horiz_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: '输入文本或 Base64',
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
                  child: const Text('编码'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _run(encode: false),
                  child: const Text('解码'),
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

// ─────────────────────────── 哈希 ───────────────────────────
class HashPanelBody extends StatefulWidget {
  const HashPanelBody({super.key});
  @override
  State<HashPanelBody> createState() => _HashPanelBodyState();
}

class _HashPanelBodyState extends State<HashPanelBody> {
  final _ctrl = TextEditingController();
  tt.HashAlgo _algo = tt.HashAlgo.md5;
  String _out = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: 'MD5 / SHA 加密',
      subtitle: '摘要计算，输入按 UTF-8 编码',
      icon: Icons.fingerprint_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '要计算摘要的文本',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final a in tt.HashAlgo.values)
                ChoiceChip(
                  label: Text(a.label),
                  selected: _algo == a,
                  onSelected: (_) => setState(() => _algo = a),
                ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () => setState(
              () => _out = tt.hashText(_ctrl.text, _algo),
            ),
            child: const Text('计算'),
          ),
          if (_out.isNotEmpty) ...[
            const SizedBox(height: 10),
            LocalToolResult(text: _out),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────── URL 编码 ───────────────────────────
class UrlCodecPanelBody extends StatefulWidget {
  const UrlCodecPanelBody({super.key});
  @override
  State<UrlCodecPanelBody> createState() => _UrlCodecPanelBodyState();
}

class _UrlCodecPanelBodyState extends State<UrlCodecPanelBody> {
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
          ? tt.urlEncodeText(_ctrl.text)
          : tt.urlDecodeText(_ctrl.text);
      setState(() {
        _out = v;
        _error = false;
      });
    } on tt.TextToolError catch (e) {
      setState(() {
        _out = e.message;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: 'URL 编码',
      subtitle: 'RFC 3986 百分号编码，空格用 %20',
      icon: Icons.link_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '输入 URL 或要编码的文本',
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
                  child: const Text('编码'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _run(encode: false),
                  child: const Text('解码'),
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

// ─────────────────────────── 文本编辑器 ───────────────────────────
class TextEditorPanelBody extends StatefulWidget {
  const TextEditorPanelBody({super.key});
  @override
  State<TextEditorPanelBody> createState() => _TextEditorPanelBodyState();
}

class _TextEditorPanelBodyState extends State<TextEditorPanelBody> {
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 统计要随着输入实时变，所以监听而不是只在按钮按下时算。
    _ctrl.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _ctrl.removeListener(_onChanged);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = tt.textStats(_ctrl.text);
    return LocalToolCard(
      title: '文本编辑器',
      subtitle: '随手记一段文字，实时统计字数',
      icon: Icons.edit_note_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: '在这里写点什么……',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatChip(label: '字符', value: s.chars.toString()),
              _StatChip(label: '不含空白', value: s.charsNoSpace.toString()),
              _StatChip(label: '行数', value: s.lines.toString()),
              _StatChip(label: '词数', value: s.words.toString()),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final m = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: _ctrl.text));
                    m.showSnackBar(
                      const SnackBar(content: Text('已复制到剪贴板')),
                    );
                  },
                  child: const Text('复制全文'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(_ctrl.clear),
                  child: const Text('清空'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTokens.radiusChip),
      ),
      child: Text(
        '$label $value',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTokens.textSecondary,
        ),
      ),
    );
  }
}

// ─────────────────────────── 颜文字 ───────────────────────────
class KaomojiPanelBody extends StatefulWidget {
  const KaomojiPanelBody({super.key});
  @override
  State<KaomojiPanelBody> createState() => _KaomojiPanelBodyState();
}

class _KaomojiPanelBodyState extends State<KaomojiPanelBody> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    final current = tt.pickKaomoji(_idx);
    return LocalToolCard(
      title: '颜文字',
      subtitle: '随手挑一个，点一下就复制',
      icon: Icons.emoji_emotions_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                current,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => setState(
                    () => _idx = (_idx + 1) % tt.kaomojiList.length,
                  ),
                  child: const Text('换一个'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final m = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: current));
                    m.showSnackBar(
                      const SnackBar(content: Text('已复制到剪贴板')),
                    );
                  },
                  child: const Text('复制'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final k in tt.kaomojiList)
                GestureDetector(
                  onTap: () async {
                    final m = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: k));
                    m.showSnackBar(SnackBar(content: Text('已复制 $k')));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTokens.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppTokens.radiusChip),
                    ),
                    child: Text(k, style: const TextStyle(fontSize: 14)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── 秒表 ───────────────────────────
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
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
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
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTokens.textSecondary,
                      ),
                    ),
                    Text(
                      '+${dv.formatStopwatch(l.delta)}'
                      '   ${dv.formatStopwatch(l.total)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
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
                  style: const TextStyle(
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
                  style: const TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
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
                style: const TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: AppTokens.textPrimary,
                ),
              ),
              if (!widget.compact) ...[
                const SizedBox(height: 6),
                Text(
                  dv.formatClockDate(_now),
                  style: const TextStyle(
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
                    style: const TextStyle(
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
                    style: const TextStyle(
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
            style: const TextStyle(
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
                        ? Colors.black54
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
            Center(
              child: SizedBox(
                width: 180,
                height: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(180, 180),
                      painter: _CompassFacePainter(),
                    ),
                    Transform.rotate(
                      angle: -h * math.pi / 180,
                      child: const Icon(
                        Icons.navigation_rounded,
                        size: 44,
                        color: AppTokens.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                '${h.toStringAsFixed(0)}°  ${sv.headingLabel(h)}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: AppTokens.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
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

    // 刻度：每 15° 一小格，每 45° 一长格。
    for (var deg = 0; deg < 360; deg += 15) {
      final rad = (deg - 90) * math.pi / 180;
      final isMajor = deg % 45 == 0;
      final len = isMajor ? 12.0 : 6.0;
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
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTokens.textSecondary,
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
            Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: CustomPaint(
                  painter: _BubblePainter(
                    pitch: _pitch,
                    roll: _roll,
                    level: level,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '前后 ${_pitch.toStringAsFixed(1)}°   左右 ${_roll.toStringAsFixed(1)}°',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: level ? AppTokens.success : AppTokens.textPrimary,
                ),
              ),
            ),
            if (level)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  '✓ 已水平',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.success,
                  ),
                ),
              ),
          ],
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
    // 居中目标圈
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

  Future<void> _start() async {
    try {
      final ok = await _rec.hasPermission();
      // await 之后组件可能已经被 dispose（用户切走页面），必须先查 mounted。
      if (!mounted) return;
      if (!ok) {
        setState(() => _err = '没拿到麦克风权限。到系统设置里给「盒子」开一下录音权限。');
        return;
      }
      // 分贝仪只需要振幅，但还是得真起一个录音会话，否则拿不到 amplitude。
      await _rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: '',
      );
      // 同上：start() 也是异步的，回来时可能已经不在树上了。
      if (!mounted) return;
      setState(() {
        _running = true;
        _err = '';
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
        });
      });
    } on Object catch (e) {
      setState(() => _err = '启动失败：$e');
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
    if (mounted) setState(() => _running = false);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _rec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: '分贝仪',
      subtitle: '用麦克风估环境噪音，数值是估算不是校准声压级',
      icon: Icons.graphic_eq_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _running ? '${_db.toStringAsFixed(1)} dB' : '-- dB',
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: AppTokens.textPrimary,
                ),
              ),
            ),
          ),
          if (_running) ...[
            LinearProgressIndicator(
              value: (_db.clamp(0, 120)) / 120,
            ),
            const SizedBox(height: 8),
            Text(
              sv.dbLabel(_db),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '峰值 ${_peak.toStringAsFixed(1)} dB',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppTokens.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 10),
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
          const Text(
            '手机麦克风没有绝对声压标定，不同机型可能差 10dB 以上；这个数适合'
            '做前后对比（「关窗后安静了多少」），别当专业仪器用。',
            style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
          ),
        ],
      ),
    );
  }
}
