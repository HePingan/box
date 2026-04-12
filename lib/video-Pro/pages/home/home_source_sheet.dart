import 'package:flutter/material.dart';

import '../../controller/video_controller.dart';

Future<void> showHomeSourcePickerSheet(
  BuildContext context,
  VideoController controller,
) async {
  if (controller.sources.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('暂无可切换的片源')),
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    useSafeArea: true,
    builder: (sheetContext) {
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: controller.sources.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: Colors.grey.shade200,
        ),
        itemBuilder: (context, index) {
          final source = controller.sources[index];
          final selected = source.id == controller.currentSource?.id;
          final subtitle =
              source.detailUrl.trim().isNotEmpty ? source.detailUrl : source.url;

          return ListTile(
            leading: Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              color: selected ? Colors.blue : Colors.grey,
            ),
            title: Text(
              source.name,
              style: TextStyle(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              Navigator.pop(sheetContext);
              controller.setCurrentSource(source);
            },
          );
        },
      );
    },
  );
}