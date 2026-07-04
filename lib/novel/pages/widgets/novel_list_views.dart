import 'package:flutter/material.dart';

import '../../../design_system/app_tokens.dart';

/// 加载中视图
class NovelLoadingView extends StatelessWidget {
  const NovelLoadingView({super.key, this.topPadding = 180});

  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: topPadding),
        const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}

/// 未配置书源时的视图
class NovelNotConfiguredView extends StatelessWidget {
  const NovelNotConfiguredView({
    super.key,
    required this.message,
    required this.onConfigurePressed,
  });

  final String message;
  final VoidCallback onConfigurePressed;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        24,
        40,
        24,
        AppTokens.pageBottomPadding + 32,
      ),
      children: [
        const SizedBox(height: 80),
        const Icon(
          Icons.auto_stories_outlined,
          size: 60,
          color: Colors.black26,
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            '未配置规则书源',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.redAccent,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            message.isNotEmpty ? message : '请先导入并启用一个小说书源。',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black54,
              height: 1.6,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: ElevatedButton.icon(
            onPressed: onConfigurePressed,
            icon: const Icon(Icons.tune),
            label: const Text('去配置书源'),
          ),
        ),
      ],
    );
  }
}

/// 空数据视图
class NovelEmptyView extends StatelessWidget {
  const NovelEmptyView({
    super.key,
    required this.message,
    this.isError = false,
    this.topPadding = 180,
  });

  final String message;
  final bool isError;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: isError ? Colors.redAccent : Colors.black54,
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: topPadding),
        Center(child: Text(message, style: style)),
        const SizedBox(height: AppTokens.pageBottomPadding + 32),
      ],
    );
  }
}

/// 网络/加载错误提示条
class NovelErrorBanner extends StatelessWidget {
  const NovelErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: Colors.red.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12.5, color: Colors.red.shade800),
            ),
          ),
        ],
      ),
    );
  }
}
