import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart';
import 'live_session_screen.dart';

class SessionCalibrationScreen extends StatefulWidget {
  const SessionCalibrationScreen({super.key});

  @override
  State<SessionCalibrationScreen> createState() =>
      _SessionCalibrationScreenState();
}

class _SessionCalibrationScreenState extends State<SessionCalibrationScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController controller;

  bool completed = false;

  @override
  void initState() {
    super.initState();

    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
      lowerBound: 0.96,
      upperBound: 1.03,
    );

    controller.repeat(reverse: true);

    startPreparation();
  }

  Future<void> startPreparation() async {
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    setState(() {
      completed = true;
    });

    await Future.delayed(const Duration(milliseconds: 700));

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const LiveSessionScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          child: completed
              ? const _SuccessState()
              : ScaleTransition(
                  scale: controller,
                  child: Container(
                    key: const ValueKey('preparing'),
                    width: 440,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.035),
                          blurRadius: 30,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 118,
                          height: 118,
                          decoration: BoxDecoration(
                            color: AppTheme.focusGreen.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.blur_on_rounded,
                            size: 56,
                            color: AppTheme.focusGreen,
                          ),
                        ),
                        const SizedBox(height: 26),
                        Text(
                          'Oturum hazırlanıyor',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'FocusVision çalışma oturumunu başlatıyor. Kamera açıksa canlı odak analizi hazırlanacak.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 15,
                            height: 1.6,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 30),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: LinearProgressIndicator(
                            minHeight: 8,
                            backgroundColor: AppTheme.surfaceMuted,
                            valueColor: AlwaysStoppedAnimation(
                              AppTheme.focusGreen,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Oturum ayarları uygulanıyor...',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _SuccessState extends StatelessWidget {
  const _SuccessState();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('success'),
      width: 440,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 54,
            backgroundColor: AppTheme.focusGreen.withValues(alpha: 0.14),
            child: Icon(
              Icons.check_rounded,
              size: 56,
              color: AppTheme.focusGreen,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Oturum hazır',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Çalışma ekranına geçiliyor.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
