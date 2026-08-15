part of './quiz_plugin_entry.dart';

// 识别区域调节已统一走原生悬浮窗框选（拖四角 + 保存并搜题），
// 应用内盲填坐标页（_RegionSheetPage / _RegionPainter / _Field）已废弃删除。
// 此文件保留悬浮窗尺寸微调滑块，供配置面板复用。

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
