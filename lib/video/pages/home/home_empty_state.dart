import 'package:flutter/material.dart';

class HomeEmptyState extends StatelessWidget {
  const HomeEmptyState({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.inbox_rounded,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFE7ECF5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.055),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1D4ED8), Color(0xFF22D3EE)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1D4ED8).withValues(alpha: 0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(icon, size: 32, color: Colors.white),
              ),
              const SizedBox(height: 14),
              const Text(
                '暂时没有内容',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (onAction != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(actionLabel ?? '刷新'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
