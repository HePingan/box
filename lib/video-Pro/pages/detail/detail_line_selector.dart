import 'package:flutter/material.dart';

import 'detail_models.dart';

class DetailLineSelector extends StatelessWidget {
  const DetailLineSelector({
    super.key,
    required this.playLines,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<DetailPlayLine> playLines;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    if (playLines.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '播放线路',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(playLines.length, (index) {
              final line = playLines[index];
              final selected = index == selectedIndex;

              return Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 8),
                child: ChoiceChip(
                  label: Text(
                    line.name,
                    style: TextStyle(
                      fontSize: 13,
                      color: selected ? Colors.white : Colors.black87,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: selected,
                  selectedColor: Theme.of(context).colorScheme.primary,
                  backgroundColor: Colors.grey.shade100,
                  side: BorderSide.none,
                  showCheckmark: false,
                  onSelected: (_) => onSelected(index),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}