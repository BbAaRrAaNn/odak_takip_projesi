import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'premium_card.dart';

class FocusGuidanceCard extends StatelessWidget {
  final bool warningActive;
  final bool sessionPaused;
  final String message;

  final VoidCallback onBreak;
  final VoidCallback onSnooze;
  final VoidCallback onDismiss;

  const FocusGuidanceCard({
    super.key,
    required this.warningActive,
    required this.sessionPaused,
    required this.message,
    required this.onBreak,
    required this.onSnooze,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    Color accentColor;

    if (sessionPaused) {
      accentColor = AppTheme.warningOrange;
    } else if (warningActive) {
      accentColor = AppTheme.warningOrange;
    } else {
      accentColor = AppTheme.focusGreen;
    }

    final title = sessionPaused
        ? 'Mola devam ediyor'
        : warningActive
        ? 'Odak önerisi'
        : 'Odak dengeli';

    final primaryButtonText = sessionPaused ? 'Çalışmaya dön' : 'Mola ver';

    final secondaryButtonText = sessionPaused ? '5 dk uzat' : '5 dk sonra';

    return PremiumCard(
      padding: const EdgeInsets.all(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.35),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              message,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
                height: 1.55,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: onBreak,
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: sessionPaused
                            ? AppTheme.focusGreen
                            : AppTheme.warningOrange,
                        foregroundColor: AppTheme.foregroundFor(
                          sessionPaused
                              ? AppTheme.focusGreen
                              : AppTheme.warningOrange,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        primaryButtonText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: onSnooze,
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: AppTheme.surface,
                        foregroundColor: AppTheme.textPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: AppTheme.border),
                        ),
                      ),
                      child: Text(
                        secondaryButtonText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                if (!sessionPaused) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 54,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: onDismiss,
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: AppTheme.surface,
                        foregroundColor: AppTheme.textMuted,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: AppTheme.border),
                        ),
                      ),
                      child: Icon(Icons.close_rounded, size: 18),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
