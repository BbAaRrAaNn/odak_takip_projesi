import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/services/api_service.dart';
import '../theme/app_theme.dart';
import 'premium_card.dart';

class FocusCameraTile extends StatefulWidget {
  final bool isFocused;
  final bool cameraActive;
  final double focusScore;

  final VoidCallback? onClose;

  const FocusCameraTile({
    super.key,
    required this.isFocused,
    required this.cameraActive,
    required this.focusScore,
    this.onClose,
  });

  @override
  State<FocusCameraTile> createState() => _FocusCameraTileState();
}

class _FocusCameraTileState extends State<FocusCameraTile> {
  final ApiService apiService = ApiService();

  Uint8List? frameBytes;

  bool loading = true;
  bool requestInFlight = false;
  Timer? frameTimer;

  @override
  void initState() {
    super.initState();

    loadFrame();
    frameTimer = Timer.periodic(
      const Duration(milliseconds: 350),
      (_) => loadFrame(),
    );
  }

  Future<void> loadFrame() async {
    if (requestInFlight) return;

    if (!widget.cameraActive) {
      if (!mounted) return;

      setState(() {
        frameBytes = null;
        loading = false;
      });

      return;
    }

    requestInFlight = true;

    try {
      final frame = await apiService.getCameraFrame();

      if (!mounted) return;

      setState(() {
        frameBytes = frame;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });
    } finally {
      requestInFlight = false;
    }
  }

  @override
  void dispose() {
    frameTimer?.cancel();
    super.dispose();
  }

  Color get statusColor {
    if (!widget.cameraActive) {
      return AppTheme.textMuted;
    }

    if (widget.focusScore >= 85) {
      return AppTheme.focusStrongGreen;
    }

    if (widget.focusScore >= 70) {
      return AppTheme.focusGreen;
    }

    if (widget.focusScore >= 50) {
      return AppTheme.focusAmber;
    }

    if (widget.focusScore >= 30) {
      return AppTheme.focusOrange;
    }

    return AppTheme.dangerRed;
  }

  String get statusText {
    if (!widget.cameraActive) {
      return 'Kamera kapalı — süre takibi aktif';
    }

    if (widget.focusScore >= 85) return 'Odak çok iyi';
    if (widget.focusScore >= 70) return 'Odak dengeli';
    if (widget.focusScore >= 50) return 'Odak dalgalanıyor';
    if (widget.focusScore >= 30) return 'Odak düşüşü var';
    return 'Odak ciddi şekilde düştü';
  }

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.35),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),

              if (widget.onClose != null)
                GestureDetector(
                  onTap: widget.onClose,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceMuted,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 14),

          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: AspectRatio(
              aspectRatio: 0.82,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: AppTheme.surfaceMuted),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final scaleAnimation = Tween<double>(begin: 0.985, end: 1)
                          .animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          );

                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: scaleAnimation,
                          child: child,
                        ),
                      );
                    },
                    child: loading
                        ? const Center(
                            key: ValueKey('camera-loading'),
                            child: CircularProgressIndicator(),
                          )
                        : frameBytes != null
                        ? Image.memory(
                            frameBytes!,
                            key: const ValueKey('camera-frame'),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          )
                        : Center(
                            key: const ValueKey('camera-empty'),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.videocam_off_rounded,
                                  size: 42,
                                  color: AppTheme.textMuted,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Kamera görüntüsü alınamıyor',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),

                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.38),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: statusColor.withValues(alpha: 0.7),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),

                                const SizedBox(width: 8),

                                Expanded(
                                  child: Text(
                                    widget.cameraActive
                                        ? statusText
                                        : 'Kamera kapalı',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 18,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.40),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Canlı analiz',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),

                                const SizedBox(height: 5),

                                Text(
                                  '${widget.focusScore.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -1,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              widget.isFocused
                                  ? Icons.psychology_alt_rounded
                                  : Icons.visibility_rounded,
                              color: statusColor,
                              size: 28,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
