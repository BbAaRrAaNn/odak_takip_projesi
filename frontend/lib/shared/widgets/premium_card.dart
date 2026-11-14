import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const PremiumCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.78)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: AppTheme.isDark ? 0.28 : 0.045,
            ),
            blurRadius: AppTheme.isDark ? 24 : 28,
            offset: const Offset(0, 14),
          ),
          if (!AppTheme.isDark)
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.58),
              blurRadius: 10,
              offset: const Offset(0, -1),
            ),
        ],
      ),
      child: child,
    );
  }
}
