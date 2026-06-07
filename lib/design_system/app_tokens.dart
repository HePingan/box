import 'package:flutter/material.dart';

/// Centralized design tokens for the Box app.
///
/// Keep raw color/spacing/radius/elevation values here so feature pages can
/// move toward a shared visual language without duplicating magic numbers.
class AppTokens {
  const AppTokens._();

  // Brand colors.
  static const Color seed = Color(0xFF2563EB);
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color cyan = Color(0xFF06B6D4);
  static const Color violet = Color(0xFF7C3AED);
  static const Color emerald = Color(0xFF10B981);
  static const Color rose = Color(0xFFF43F5E);
  static const Color amber = Color(0xFFF59E0B);
  static const Color orange = Color(0xFFFF7A45);
  static const Color ink = Color(0xFF0F172A);

  // Surfaces and text.
  static const Color background = Color(0xFFF4F7FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF1F5F9);
  static const Color surfaceTint = Color(0xFFEFF6FF);
  static const Color textPrimary = Color(0xFF101828);
  static const Color textSecondary = Color(0xFF667085);
  static const Color textTertiary = Color(0xFF98A2B3);
  static const Color divider = Color(0xFFE6EAF2);
  static const Color success = Color(0xFF12B76A);
  static const Color warning = Color(0xFFF79009);
  static const Color danger = Color(0xFFF04438);
  static const Color info = Color(0xFF2E90FA);

  // Spacing.
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;
  static const double space2xl = 32;
  static const double space2Xl = 32;

  // Radius.
  static const double radiusXs = 8;
  static const double radiusSm = 12;
  static const double radiusMd = 18;
  static const double radiusLg = 24;
  static const double radiusXl = 30;
  static const double radius2Xl = 34;
  static const double radiusPill = 999;

  // Shell layout.
  static const double shellBottomNavHeight = 86;
  static const double pageBottomPadding = 112;

  static const double elevationLow = 0.5;
  static const double elevationNone = 0;

  static const LinearGradient blueGradient = LinearGradient(
    colors: [primaryBlue, cyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient auroraGradient = LinearGradient(
    colors: [Color(0xFF0F172A), violet, primaryBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient sunriseGradient = LinearGradient(
    colors: [rose, amber],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient violetGradient = LinearGradient(
    colors: [violet, primaryBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient emeraldGradient = LinearGradient(
    colors: [emerald, cyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient sunsetGradient = LinearGradient(
    colors: [orange, amber],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkOceanGradient = LinearGradient(
    colors: [Color(0xFF0F172A), primaryBlue, cyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient neonVioletGradient = LinearGradient(
    colors: [Color(0xFF111827), violet, rose],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static List<BoxShadow> cardShadow({Color color = ink, double alpha = 0.08}) {
    return [
      BoxShadow(
        color: color.withValues(alpha: alpha),
        blurRadius: 20,
        offset: const Offset(0, 10),
      ),
    ];
  }

  static List<BoxShadow> shadowSm({Color color = ink}) {
    return [
      BoxShadow(
        color: color.withValues(alpha: 0.05),
        blurRadius: 12,
        offset: const Offset(0, 6),
      ),
    ];
  }

  static List<BoxShadow> shadowMd({Color color = ink}) {
    return cardShadow(color: color, alpha: 0.08);
  }

  static List<BoxShadow> shadowLg({Color color = ink}) {
    return [
      BoxShadow(
        color: color.withValues(alpha: 0.12),
        blurRadius: 28,
        offset: const Offset(0, 14),
      ),
    ];
  }

  static List<BoxShadow> heroShadow({Color color = primaryBlue}) {
    return [
      BoxShadow(
        color: color.withValues(alpha: 0.24),
        blurRadius: 30,
        offset: const Offset(0, 16),
      ),
    ];
  }
}
