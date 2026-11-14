import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/services/api_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/premium_card.dart';
import 'live_session_screen.dart';

class NewSessionScreen extends StatefulWidget {
  const NewSessionScreen({super.key});

  @override
  State<NewSessionScreen> createState() => _NewSessionScreenState();
}

class _NewSessionScreenState extends State<NewSessionScreen> {
  final ApiService apiService = ApiService();

  bool starting = false;
  bool loadingContext = true;
  bool planLoading = false;

  bool cameraEnabled = true;
  bool automaticCycles = true;

  String selectedMode = 'classic';

  double totalWorkMinutes = 120;
  double adaptiveTotalMinutes = 90;
  double flowMinutes = 60;

  int workMinutes = 25;
  int shortBreakMinutes = 5;
  int longBreakMinutes = 15;
  int longBreakEvery = 4;
  int manualCycles = 4;

  int adaptiveWorkMinutes = 45;
  int adaptiveShortBreakMinutes = 8;
  int adaptiveLongBreakMinutes = 18;
  int adaptiveLongBreakEvery = 4;
  int adaptiveCycles = 2;
  bool adaptivePlanEdited = false;

  int sessionCount = 0;
  Map<String, dynamic>? focusPlan;

  @override
  void initState() {
    super.initState();
    loadSessionContext();
  }

  Future<void> loadSessionContext() async {
    try {
      final result = await apiService.getSessions();

      if (!mounted) return;

      setState(() {
        sessionCount = result['session_count'] ?? 0;
        loadingContext = false;
      });

      await refreshFocusPlan();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        loadingContext = false;
      });
    }
  }

  Future<void> refreshFocusPlan() async {
    setState(() {
      planLoading = true;
    });

    try {
      final result = await apiService.getFocusPlan(
        plannedTotalMinutes: adaptiveTotalMinutes.round(),
      );

      if (!mounted) return;

      setState(() {
        focusPlan = result;
        if (!adaptivePlanEdited) {
          applyAdaptivePlan(result);
        }
        planLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        planLoading = false;
      });
    }
  }

  int get classicCycles {
    if (!automaticCycles) return manualCycles;

    return cyclesForWorkTarget(totalWorkMinutes, workMinutes);
  }

  _PlanMetrics get classicMetrics => buildPlanMetrics(
    cycles: classicCycles,
    workMinutes: workMinutes,
    shortBreakMinutes: shortBreakMinutes,
    longBreakMinutes: longBreakMinutes,
    longBreakEvery: longBreakEvery,
  );

  int get classicPlannedMinutes {
    return classicMetrics.totalWorkMinutes;
  }

  int get estimatedClassicTotalMinutes {
    return classicMetrics.estimatedTotalMinutes;
  }

  bool get effectiveCameraEnabled {
    if (selectedMode == 'flow') return true;
    return cameraEnabled;
  }

  int get plannedMinutes {
    if (selectedMode == 'classic') return classicPlannedMinutes;
    if (selectedMode == 'adaptive') return adaptiveMetrics.totalWorkMinutes;
    return flowMinutes.round();
  }

  Map<String, dynamic>? get pomodoroSettings {
    if (selectedMode == 'adaptive') {
      return {
        'work_minutes': adaptiveWorkMinutes,
        'short_break_minutes': adaptiveShortBreakMinutes,
        'long_break_minutes': adaptiveLongBreakMinutes,
        'long_break_every': adaptiveLongBreakEvery,
        'cycles': adaptiveCycles,
        'planned_work_minutes': adaptiveMetrics.totalWorkMinutes,
        'estimated_total_minutes': adaptiveMetrics.estimatedTotalMinutes,
        'short_break_count': adaptiveMetrics.shortBreakCount,
        'long_break_count': adaptiveMetrics.longBreakCount,
        'first_break_minute': adaptiveMetrics.firstBreakMinute,
        'first_long_break_minute': adaptiveMetrics.firstLongBreakMinute,
        'source': 'adaptive_ai',
        'data_quality': focusPlan?['data_quality'] ?? 'starter',
      };
    }

    if (selectedMode != 'classic') return null;

    return {
      'work_minutes': workMinutes,
      'short_break_minutes': shortBreakMinutes,
      'long_break_minutes': longBreakMinutes,
      'long_break_every': longBreakEvery,
      'cycles': classicCycles,
      'planned_work_minutes': classicMetrics.totalWorkMinutes,
      'estimated_total_minutes': classicMetrics.estimatedTotalMinutes,
      'short_break_count': classicMetrics.shortBreakCount,
      'long_break_count': classicMetrics.longBreakCount,
      'first_break_minute': classicMetrics.firstBreakMinute,
      'first_long_break_minute': classicMetrics.firstLongBreakMinute,
    };
  }

  _PlanMetrics get adaptiveMetrics => buildPlanMetrics(
    cycles: adaptiveCycles,
    workMinutes: adaptiveWorkMinutes,
    shortBreakMinutes: adaptiveShortBreakMinutes,
    longBreakMinutes: adaptiveLongBreakMinutes,
    longBreakEvery: adaptiveLongBreakEvery,
  );

  int get estimatedAdaptiveTotalMinutes {
    return adaptiveMetrics.estimatedTotalMinutes;
  }

  int? get adaptiveFirstLongBreakMinute {
    return adaptiveMetrics.firstLongBreakMinute;
  }

  int cyclesForWorkTarget(double targetMinutes, int blockMinutes) {
    final safeBlock = math.max(1, blockMinutes);
    return math.max(1, (targetMinutes / safeBlock).ceil()).clamp(1, 12);
  }

  _PlanMetrics buildPlanMetrics({
    required int cycles,
    required int workMinutes,
    required int shortBreakMinutes,
    required int longBreakMinutes,
    required int longBreakEvery,
  }) {
    var shortBreakCount = 0;
    var longBreakCount = 0;
    var elapsed = 0;
    int? firstLongBreakMinute;

    for (var cycle = 1; cycle <= cycles; cycle++) {
      elapsed += workMinutes;

      if (cycle >= cycles) continue;

      final isLongBreak = longBreakEvery > 0 && cycle % longBreakEvery == 0;

      if (isLongBreak) {
        longBreakCount += 1;
        firstLongBreakMinute ??= elapsed;
        elapsed += longBreakMinutes;
      } else {
        shortBreakCount += 1;
        elapsed += shortBreakMinutes;
      }
    }

    final totalBreakMinutes =
        shortBreakCount * shortBreakMinutes + longBreakCount * longBreakMinutes;

    return _PlanMetrics(
      cycles: cycles,
      workMinutes: workMinutes,
      totalWorkMinutes: cycles * workMinutes,
      shortBreakCount: shortBreakCount,
      longBreakCount: longBreakCount,
      totalBreakMinutes: totalBreakMinutes,
      estimatedTotalMinutes: cycles * workMinutes + totalBreakMinutes,
      firstBreakMinute: cycles > 1 ? workMinutes : null,
      firstLongBreakMinute: firstLongBreakMinute,
    );
  }

  void applyAdaptivePlan(Map<String, dynamic> plan) {
    adaptiveWorkMinutes = readPlanInt(
      plan,
      'work_minutes',
      fallback: (numberFromPlan(plan['recommended_work_block_seconds']) / 60)
          .round(),
      min: 20,
      max: 90,
    );
    adaptiveShortBreakMinutes = readPlanInt(
      plan,
      'short_break_minutes',
      fallback: (numberFromPlan(plan['recommended_break_seconds']) / 60)
          .round(),
      min: 3,
      max: 20,
    );
    adaptiveLongBreakMinutes = readPlanInt(
      plan,
      'long_break_minutes',
      fallback: math.max(15, adaptiveShortBreakMinutes + 10),
      min: 8,
      max: 40,
    );
    adaptiveLongBreakEvery = readPlanInt(
      plan,
      'long_break_every',
      fallback: 4,
      min: 2,
      max: 8,
    );
    adaptiveCycles = readPlanInt(
      plan,
      'cycles',
      fallback: cyclesForWorkTarget(adaptiveTotalMinutes, adaptiveWorkMinutes),
      min: 1,
      max: 12,
    );
  }

  int readPlanInt(
    Map<String, dynamic> plan,
    String key, {
    required int fallback,
    required int min,
    required int max,
  }) {
    final value = numberFromPlan(plan[key]).round();
    return (value <= 0 ? fallback : value).clamp(min, max);
  }

  String modeTitle(String id) {
    if (id == 'classic') return 'Klasik Pomodoro';
    if (id == 'adaptive') return 'Adaptif AI Modu';
    return 'Akış Modu';
  }

  String modeDescription(String id) {
    if (id == 'classic') {
      return 'Sabit çalışma ve mola bloklarıyla ilerler. Kamera açıksa odak öğrenilir, plan değişmez.';
    }

    if (id == 'adaptive') {
      return 'Toplam süreye göre AI çalışma ve mola blokları önerir. Kamera açıksa canlı düşüşlere göre esneyebilir.';
    }

    return 'Sabit plan yoktur. Süre belirlenir, kamera zorunludur ve odak düşüşlerinde mola önerisi üretir.';
  }

  void showModeInfo(String id) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(modeTitle(id)),
          content: Text(modeDescription(id), style: TextStyle(height: 1.5)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Tamam'),
            ),
          ],
        );
      },
    );
  }

  Future<void> startSession() async {
    if (starting) return;

    setState(() {
      starting = true;
    });

    try {
      final result = await apiService.startSession(
        sessionMode: selectedMode,
        plannedTotalMinutes: plannedMinutes,
        cameraEnabled: effectiveCameraEnabled,
        pomodoroSettings: pomodoroSettings,
      );

      if (!mounted) return;

      if (result['success'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${result['message'] ?? 'Oturum başlatılamadı.'}'),
          ),
        );
        setState(() {
          starting = false;
        });
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LiveSessionScreen()),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Oturum başlatılamadı.')));
    }

    if (!mounted) return;

    setState(() {
      starting = false;
    });
  }

  Widget modeCard({required String id, required IconData icon}) {
    final selected = selectedMode == id;
    final selectedFill = Color.lerp(
      AppTheme.surface,
      AppTheme.calmBlue,
      AppTheme.isDark ? 0.18 : 0.10,
    )!;
    final selectedForeground = AppTheme.textPrimary;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedMode = id;

            if (id == 'flow') {
              cameraEnabled = true;
            }

            if (id == 'adaptive' && focusPlan != null && !adaptivePlanEdited) {
              applyAdaptivePlan(focusPlan!);
            }
          });
        },
        child: AnimatedScale(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          scale: selected ? 1.012 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: selected ? selectedFill : AppTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? AppTheme.calmBlue.withValues(alpha: 0.62)
                    : AppTheme.border.withValues(alpha: 0.82),
                width: selected ? 1.4 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: selected
                        ? AppTheme.isDark
                              ? 0.30
                              : 0.070
                        : AppTheme.isDark
                        ? 0.20
                        : 0.030,
                  ),
                  blurRadius: selected ? 26 : 18,
                  offset: Offset(0, selected ? 15 : 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  height: 3,
                  width: selected ? 52 : 24,
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.calmBlue : AppTheme.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.calmBlue
                            : AppTheme.surfaceMuted,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: selected ? AppTheme.calmBlue : AppTheme.border,
                        ),
                      ),
                      child: Icon(
                        icon,
                        color: selected
                            ? AppTheme.foregroundFor(AppTheme.calmBlue)
                            : AppTheme.textPrimary,
                        size: 21,
                      ),
                    ),
                    const Spacer(),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: selected
                          ? Container(
                              key: const ValueKey('selected-check'),
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: AppTheme.textPrimary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.check_rounded,
                                color: AppTheme.onPrimary,
                                size: 17,
                              ),
                            )
                          : const SizedBox(
                              key: ValueKey('selected-check-empty'),
                              width: 28,
                              height: 28,
                            ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Mod bilgisi',
                      onPressed: () => showModeInfo(id),
                      icon: Icon(
                        Icons.info_outline_rounded,
                        color: AppTheme.textSecondary,
                        size: 19,
                      ),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(32, 32),
                        fixedSize: const Size(32, 32),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  modeTitle(id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? selectedForeground : AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  modeDescription(id),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? selectedForeground.withValues(alpha: 0.74)
                        : AppTheme.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget sliderRow({
    required String title,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              valueText,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: valueText,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }

  Widget numberStepper({
    required String title,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Azalt',
            onPressed: value <= min ? null : () => onChanged(value - 1),
            icon: Icon(Icons.remove_rounded, size: 18),
          ),
          SizedBox(
            width: 54,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Artır',
            onPressed: value >= max ? null : () => onChanged(value + 1),
            icon: Icon(Icons.add_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget classicSettings() {
    final metrics = classicMetrics;
    final firstLongBreak = metrics.firstLongBreakMinute;
    final breakSummary = metrics.totalBreakCount == 0
        ? 'mola yok'
        : '${metrics.shortBreakCount} kısa · ${metrics.longBreakCount} uzun mola';
    final targetText = automaticCycles
        ? 'Hedef ${totalWorkMinutes.round()} dk; $workMinutes dk bloklarla ${metrics.cycles} turda ${metrics.totalWorkMinutes} dk çalışma planlanır.'
        : '${metrics.cycles} tur x $workMinutes dk = ${metrics.totalWorkMinutes} dk çalışma.';
    final breakTiming = metrics.firstBreakMinute == null
        ? 'Tek tur olduğu için planlı mola yok.'
        : 'İlk mola ${metrics.firstBreakMinute}. dk${firstLongBreak == null ? '' : ', ilk uzun mola $firstLongBreak. dk'}.';

    return PremiumCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Klasik Pomodoro Ayarları',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              ChoiceChip(
                label: Text('Toplam süreye göre'),
                selected: automaticCycles,
                onSelected: (_) {
                  setState(() {
                    automaticCycles = true;
                  });
                },
              ),
              const SizedBox(width: 10),
              ChoiceChip(
                label: Text('Tur sayısına göre'),
                selected: !automaticCycles,
                onSelected: (_) {
                  setState(() {
                    automaticCycles = false;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (automaticCycles)
            sliderRow(
              title: 'Toplam çalışma hedefi',
              valueText: '${totalWorkMinutes.round()} dk',
              value: totalWorkMinutes,
              min: 25,
              max: 240,
              divisions: 43,
              onChanged: (value) {
                setState(() {
                  totalWorkMinutes = value;
                });
              },
            )
          else
            numberStepper(
              title: 'Tur sayısı',
              value: manualCycles,
              min: 1,
              max: 12,
              onChanged: (value) {
                setState(() {
                  manualCycles = value;
                });
              },
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 260,
                child: numberStepper(
                  title: 'Çalışma bloğu (dk)',
                  value: workMinutes,
                  min: 15,
                  max: 90,
                  onChanged: (value) {
                    setState(() {
                      workMinutes = value;
                    });
                  },
                ),
              ),
              SizedBox(
                width: 260,
                child: numberStepper(
                  title: 'Kısa mola (dk)',
                  value: shortBreakMinutes,
                  min: 3,
                  max: 20,
                  onChanged: (value) {
                    setState(() {
                      shortBreakMinutes = value;
                    });
                  },
                ),
              ),
              SizedBox(
                width: 260,
                child: numberStepper(
                  title: 'Uzun mola (dk)',
                  value: longBreakMinutes,
                  min: 8,
                  max: 40,
                  onChanged: (value) {
                    setState(() {
                      longBreakMinutes = value;
                    });
                  },
                ),
              ),
              SizedBox(
                width: 260,
                child: numberStepper(
                  title: 'Uzun mola turu',
                  value: longBreakEvery,
                  min: 2,
                  max: 8,
                  onChanged: (value) {
                    setState(() {
                      longBreakEvery = value;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          planSummary(
            title:
                '${metrics.cycles} tur · ${metrics.totalWorkMinutes} dk çalışma · $breakSummary',
            subtitle:
                '$targetText $breakTiming Toplam plan ${metrics.estimatedTotalMinutes} dk.',
          ),
        ],
      ),
    );
  }

  Widget adaptiveSettings() {
    final dataQuality = '${focusPlan?['data_quality'] ?? 'starter'}';
    final weak = dataQuality != 'personalized';
    final metrics = adaptiveMetrics;
    final firstLongBreak = metrics.firstLongBreakMinute;
    final firstBreak = metrics.firstBreakMinute;

    return PremiumCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Adaptif AI Planı',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
              if (loadingContext || planLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 18),
          sliderRow(
            title: 'Toplam çalışma süresi',
            valueText: '${adaptiveTotalMinutes.round()} dk',
            value: adaptiveTotalMinutes,
            min: 30,
            max: 240,
            divisions: 42,
            onChanged: (value) {
              setState(() {
                adaptiveTotalMinutes = value;
                adaptivePlanEdited = false;
                adaptiveCycles = cyclesForWorkTarget(
                  adaptiveTotalMinutes,
                  adaptiveWorkMinutes,
                );
              });
            },
            onChangeEnd: (_) => refreshFocusPlan(),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              recommendationPill(
                label: 'Çalışma bloğu',
                value: '$adaptiveWorkMinutes dk',
              ),
              recommendationPill(
                label: 'Kısa mola',
                value: '$adaptiveShortBreakMinutes dk',
              ),
              recommendationPill(
                label: 'Uzun mola',
                value: '$adaptiveLongBreakMinutes dk',
              ),
              recommendationPill(
                label: 'Uzun mola turu',
                value: '$adaptiveLongBreakEvery turda bir',
              ),
              recommendationPill(
                label: 'Tur sayısı',
                value: '${metrics.cycles} tur',
              ),
              recommendationPill(
                label: 'Toplam çalışma',
                value: '${metrics.totalWorkMinutes} dk',
              ),
              recommendationPill(
                label: 'Toplam plan',
                value: '${metrics.estimatedTotalMinutes} dk',
              ),
              recommendationPill(
                label: 'Molalar',
                value:
                    '${metrics.shortBreakCount} kısa · ${metrics.longBreakCount} uzun',
              ),
              recommendationPill(
                label: 'Toplam mola',
                value: '${metrics.totalBreakMinutes} dk',
              ),
              recommendationPill(
                label: 'İlk mola',
                value: firstBreak == null ? 'Plan dışında' : '$firstBreak. dk',
              ),
              recommendationPill(
                label: 'İlk uzun mola',
                value: firstLongBreak == null
                    ? 'Plan dışında'
                    : '$firstLongBreak. dk',
              ),
              recommendationPill(
                label: 'Geçmiş',
                value: '$sessionCount oturum',
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 260,
                child: numberStepper(
                  title: 'Çalışma bloğu (dk)',
                  value: adaptiveWorkMinutes,
                  min: 20,
                  max: 90,
                  onChanged: (value) {
                    setState(() {
                      adaptivePlanEdited = true;
                      adaptiveWorkMinutes = value;
                      adaptiveCycles = cyclesForWorkTarget(
                        adaptiveTotalMinutes,
                        adaptiveWorkMinutes,
                      );
                    });
                  },
                ),
              ),
              SizedBox(
                width: 260,
                child: numberStepper(
                  title: 'Kısa mola (dk)',
                  value: adaptiveShortBreakMinutes,
                  min: 3,
                  max: 20,
                  onChanged: (value) {
                    setState(() {
                      adaptivePlanEdited = true;
                      adaptiveShortBreakMinutes = value;
                    });
                  },
                ),
              ),
              SizedBox(
                width: 260,
                child: numberStepper(
                  title: 'Uzun mola (dk)',
                  value: adaptiveLongBreakMinutes,
                  min: 8,
                  max: 40,
                  onChanged: (value) {
                    setState(() {
                      adaptivePlanEdited = true;
                      adaptiveLongBreakMinutes = value;
                    });
                  },
                ),
              ),
              SizedBox(
                width: 260,
                child: numberStepper(
                  title: 'Uzun mola turu',
                  value: adaptiveLongBreakEvery,
                  min: 2,
                  max: 8,
                  onChanged: (value) {
                    setState(() {
                      adaptivePlanEdited = true;
                      adaptiveLongBreakEvery = value;
                    });
                  },
                ),
              ),
              SizedBox(
                width: 260,
                child: numberStepper(
                  title: 'Tur sayısı',
                  value: adaptiveCycles,
                  min: 1,
                  max: 12,
                  onChanged: (value) {
                    setState(() {
                      adaptivePlanEdited = true;
                      adaptiveCycles = value;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          planSummary(
            title: weak
                ? 'Öneriler başlangıç seviyesinde'
                : 'Kişiselleştirilmiş Pomodoro planı',
            subtitle: weak
                ? 'Hedef ${adaptiveTotalMinutes.round()} dk; plan ${metrics.totalWorkMinutes} dk çalışma ve ${metrics.totalBreakMinutes} dk mola içeriyor. Veri az olduğu için güvenli başlangıç heuristiği kullanılıyor.'
                : '${focusPlan?['reason'] ?? 'Geçmiş oturumlarına göre çalışma ve mola blokları öneriliyor.'} Plan ${metrics.totalWorkMinutes} dk çalışma ve ${metrics.totalBreakMinutes} dk mola içeriyor.',
          ),
        ],
      ),
    );
  }

  double numberFromPlan(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  Widget flowSettings() {
    return PremiumCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Akış Modu',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 18),
          sliderRow(
            title: 'Akış süresi',
            valueText: '${flowMinutes.round()} dk',
            value: flowMinutes,
            min: 20,
            max: 180,
            divisions: 32,
            onChanged: (value) {
              setState(() {
                flowMinutes = value;
              });
            },
          ),
          const SizedBox(height: 14),
          planSummary(
            title: 'Kamera zorunlu',
            subtitle:
                'Bu modda sabit Pomodoro planı yok. FocusVision canlı odak düşüşlerine göre mola paneli üretir.',
          ),
        ],
      ),
    );
  }

  Widget recommendationPill({required String label, required String value}) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget planSummary({required String title, required String subtitle}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.calmBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.calmBlue.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_rounded, color: AppTheme.calmBlue, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget modeSettings() {
    if (selectedMode == 'adaptive') return adaptiveSettings();
    if (selectedMode == 'flow') return flowSettings();
    return classicSettings();
  }

  Widget cameraCard() {
    final locked = selectedMode == 'flow';

    return PremiumCard(
      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: effectiveCameraEnabled
                  ? AppTheme.focusGreen.withValues(alpha: 0.12)
                  : AppTheme.surfaceMuted,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              effectiveCameraEnabled
                  ? Icons.videocam_rounded
                  : Icons.videocam_off_rounded,
              color: effectiveCameraEnabled
                  ? AppTheme.focusGreen
                  : AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kamera Analizi',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  locked
                      ? 'Akış modu canlı odak takibi için kamerayı zorunlu kullanır.'
                      : 'Kapalıysa oturum yalnızca süre ve mola takibi yapar.',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: effectiveCameraEnabled,
            onChanged: locked
                ? null
                : (value) {
                    setState(() {
                      cameraEnabled = value;
                    });
                  },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ListView(
            children: [
              Text(
                'Yeni Oturum',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Çalışma biçimini seç, süre ve mola ayarlarını netleştir.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 15,
                  height: 1.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  modeCard(id: 'classic', icon: Icons.timer_rounded),
                  const SizedBox(width: 14),
                  modeCard(id: 'adaptive', icon: Icons.psychology_rounded),
                  const SizedBox(width: 14),
                  modeCard(id: 'flow', icon: Icons.bolt_rounded),
                ],
              ),
              const SizedBox(height: 22),
              modeSettings(),
              const SizedBox(height: 18),
              cameraCard(),
              const SizedBox(height: 24),
              SizedBox(
                height: 58,
                child: ElevatedButton.icon(
                  onPressed: starting ? null : startSession,
                  icon: Icon(Icons.play_arrow_rounded),
                  label: Text(
                    starting ? 'Başlatılıyor...' : 'Oturumu Başlat',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanMetrics {
  final int cycles;
  final int workMinutes;
  final int totalWorkMinutes;
  final int shortBreakCount;
  final int longBreakCount;
  final int totalBreakMinutes;
  final int estimatedTotalMinutes;
  final int? firstBreakMinute;
  final int? firstLongBreakMinute;

  const _PlanMetrics({
    required this.cycles,
    required this.workMinutes,
    required this.totalWorkMinutes,
    required this.shortBreakCount,
    required this.longBreakCount,
    required this.totalBreakMinutes,
    required this.estimatedTotalMinutes,
    required this.firstBreakMinute,
    required this.firstLongBreakMinute,
  });

  int get totalBreakCount => shortBreakCount + longBreakCount;
}
