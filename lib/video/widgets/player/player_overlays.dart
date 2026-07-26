import 'package:flutter/material.dart';

class PlayerBufferingOverlay extends StatelessWidget {
  const PlayerBufferingOverlay({super.key, this.label = '加载中…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        color: Colors.transparent,
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlayerErrorOverlay extends StatelessWidget {
  const PlayerErrorOverlay({
    super.key,
    required this.errorMessage,
    required this.onRetry,
    this.onFallbackLine,
  });

  final String errorMessage;
  final VoidCallback onRetry;
  final VoidCallback? onFallbackLine;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.videocam_off_rounded,
              color: Colors.white54,
              size: 46,
            ),
            const SizedBox(height: 12),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            if (onFallbackLine != null) ...[
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                ),
                onPressed: onFallbackLine,
                icon: const Icon(Icons.alt_route_rounded, size: 18),
                label: const Text('换线路重试'),
              ),
              const SizedBox(height: 8),
            ],
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试线路'),
            ),
          ],
        ),
      ),
    );
  }
}

class PlayerDebugOverlay extends StatelessWidget {
  const PlayerDebugOverlay({super.key, required this.info});

  final String info;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      top: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          info,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}
