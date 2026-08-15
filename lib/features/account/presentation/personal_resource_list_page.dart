import 'package:flutter/material.dart';

import '../domain/personal_center_models.dart';

class PersonalResourceListPage extends StatelessWidget {
  const PersonalResourceListPage.quizzes({super.key, required this.items})
    : title = '我的题库',
      plugins = const [];

  const PersonalResourceListPage.plugins({super.key, required this.plugins})
    : title = '我的插件',
      items = const [];

  final String title;
  final List<PersonalQuizItem> items;
  final List<Map<String, dynamic>> plugins;

  @override
  Widget build(BuildContext context) {
    final isQuiz = title == '我的题库';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: (isQuiz ? items.isEmpty : plugins.isEmpty)
          ? const Center(child: Text('暂无数据'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: isQuiz ? items.length : plugins.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                if (isQuiz) {
                  final item = items[index];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.quiz_outlined),
                      title: Text(item.title.isEmpty ? '未命名题目' : item.title),
                      subtitle: Text(
                        '${item.statusLabel}${item.category.isEmpty ? '' : ' · ${item.category}'}',
                      ),
                    ),
                  );
                }
                final plugin = plugins[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.extension_outlined),
                    title: Text(
                      plugin['name']?.toString() ??
                          plugin['pluginId']?.toString() ??
                          '未命名插件',
                    ),
                    subtitle: Text(plugin['status']?.toString() ?? '已安装'),
                  ),
                );
              },
            ),
    );
  }
}
