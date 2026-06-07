import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Standard bottom spacer for pages hosted by the floating shell nav.
class AppPageBottomSpacer extends StatelessWidget {
  const AppPageBottomSpacer({super.key, this.extra = 0});

  final double extra;

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: AppTokens.pageBottomPadding + extra);
  }
}
