import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/features/home/application/home_models.dart';

class HomeGlassIconButton extends StatelessWidget {
  const HomeGlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}

class HomeNewsLine extends StatelessWidget {
  const HomeNewsLine({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F9FD),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.fiber_manual_record_rounded,
                color: Color(0xFF3D7CFF),
                size: 8,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
  }
}

class HomeMiniPill extends StatelessWidget {
  const HomeMiniPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppTokens.primaryBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(
          color: AppTokens.primaryBlue.withValues(alpha: 0.16),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppTokens.primaryBlue,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class HomeQuickDockCard extends StatelessWidget {
  const HomeQuickDockCard({super.key, required this.action});

  final HomeQuickAction action;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: action.onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE7ECF5)),
          boxShadow: [
            BoxShadow(
              color: AppTokens.ink.withValues(alpha: 0.045),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: action.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(action.icon, color: action.color, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              action.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTokens.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              action.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTokens.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeFeatureCard extends StatelessWidget {
  const HomeFeatureCard({super.key, required this.item});

  final HomeFeatureCardItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: () async {
        if (item.onTap != null) {
          await item.onTap!(context);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: item.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: item.gradient.first.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -16,
              bottom: -18,
              child: Icon(
                item.icon,
                color: Colors.white.withValues(alpha: 0.18),
                size: 92,
              ),
            ),
            if (item.status != null)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Text(
                    item.status!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Icon(item.icon, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 11,
                    height: 1.18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
