import 'package:flutter/material.dart';

import '../../core/services/api_service.dart';
import '../../core/services/user_profile_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/premium_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiService apiService = ApiService();

  bool loading = true;
  String? errorMessage;

  Map<String, dynamic>? trendData;
  List<dynamic> sessions = [];

  @override
  void initState() {
    super.initState();
    loadDashboard();
  }

  Future<void> loadDashboard() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });

    try {
      final trend = await apiService.getTrendAnalysis();
      final history = await apiService.getSessions();

      if (!mounted) return;

      setState(() {
        trendData = trend;
        sessions = List<dynamic>.from(history['sessions'] ?? []);
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        loading = false;
        errorMessage = 'Ana sayfa verileri yüklenemedi.';
      });
    }
  }

  double numberValue(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  String minutes(dynamic seconds) {
    return (numberValue(seconds) / 60).toStringAsFixed(0);
  }

  String hours(dynamic seconds) {
    return (numberValue(seconds) / 3600).toStringAsFixed(1);
  }

  String modeName(dynamic mode) {
    if (mode == 'classic') return 'Klasik';
    if (mode == 'adaptive') return 'Adaptif';
    if (mode == 'flow') return 'Akış';
    return 'Oturum';
  }

  Color focusColor(double score) {
    if (score >= 75) return AppTheme.focusGreen;
    if (score >= 45) return AppTheme.warningOrange;
    return AppTheme.dangerRed;
  }

  List<Map<String, dynamic>> lastThreeSessions() {
    return sessions.reversed
        .take(3)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  double averageActiveSeconds() {
    if (sessions.isEmpty) return 0;

    final total = sessions.fold<double>(0, (sum, item) {
      final session = Map<String, dynamic>.from(item);
      return sum + numberValue(session['active_seconds']);
    });

    return total / sessions.length;
  }

  int? sessionHour(Map<String, dynamic> session) {
    final dateText = '${session['date'] ?? ''}';
    final parts = dateText.split(' ');

    if (parts.length < 2) return null;

    final timeParts = parts[1].split(':');

    if (timeParts.isEmpty) return null;

    return int.tryParse(timeParts.first);
  }

  String hourRange(int hour) {
    final next = (hour + 1) % 24;
    final startText = hour.toString().padLeft(2, '0');
    final endText = next.toString().padLeft(2, '0');

    return '$startText:00-$endText:00';
  }

  String mainInsight() {
    final count = sessions.length;
    final averageFocus = numberValue(trendData?['average_focus_score']);

    if (count == 0) {
      return 'Henüz kayıtlı oturum yok. İlk oturumdan sonra çalışma ritmin burada görünmeye başlayacak.';
    }

    if (count == 1) {
      return 'İlk oturumun kaydedildi. Birkaç oturumdan sonra karşılaştırmalı çıkarımlar oluşacak.';
    }

    if (count < 3) {
      return 'İlk çalışma verilerin oluşuyor. Daha net trend için birkaç oturum daha gerekiyor.';
    }

    if (averageFocus >= 75) {
      return 'Yerel verilerine göre çalışma düzenin güçlü ilerliyor; son oturumları ve ritim önerilerini aşağıda toparladım.';
    }

    return 'Yerel JSON kayıtlarına göre çalışma, mola ve kamera kullanım ritmin oluşuyor.';
  }

  String lastThreeInsight() {
    final last = lastThreeSessions();

    if (last.length < 3) {
      return 'Veri az: Son 3 oturumu karşılaştırmak için birkaç kayıt daha gerekiyor.';
    }

    final cameraDisabledCount = last
        .where((item) => item['camera_enabled'] != true)
        .length;

    if (cameraDisabledCount >= 2) {
      return 'Kamera kapalı oturum ağırlıklı: Süre ve mola ritmin izleniyor, odak analizi için daha fazla kameralı oturum gerekiyor.';
    }

    final scores = last
        .where((item) => item['camera_enabled'] == true)
        .map((item) => numberValue(item['focus_score']))
        .toList();

    if (scores.length < 2) {
      return 'Kamera kapalı oturum ağırlıklı: Son kayıtlar süre takibini öne çıkarıyor.';
    }

    final first = scores.last;
    final latest = scores.first;
    final diff = latest - first;

    if (diff >= 5) {
      return 'Odak artıyor: Son 3 oturumda odak skorun yukarı yönlü.';
    }

    if (diff <= -5) {
      return 'Odak düşüyor: Son 3 oturumda dikkat dalgalanması artmış görünüyor.';
    }

    return 'Odak stabil: Son 3 oturumda belirgin bir kırılma görünmüyor.';
  }

  String dynamicSuggestion() {
    if (sessions.length < 2) {
      return 'Dinamik öneri için henüz yeterli veri yok. Birkaç oturumdan sonra sık çalıştığın ve en verimli olduğun saat aralıkları burada görünecek.';
    }

    final hourCounts = <int, int>{};
    final focusByHour = <int, List<double>>{};

    for (final item in sessions) {
      final session = Map<String, dynamic>.from(item);
      final hour = sessionHour(session);

      if (hour == null) continue;

      hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;

      if (session['camera_enabled'] == true) {
        focusByHour
            .putIfAbsent(hour, () => [])
            .add(numberValue(session['focus_score']));
      }
    }

    if (hourCounts.isEmpty) {
      return 'Dinamik öneri için oturum saatleri okunamadı. Yeni kayıtlarla bu alan otomatik toparlanacak.';
    }

    final busiest = hourCounts.entries.reduce(
      (best, item) => item.value > best.value ? item : best,
    );

    var text = 'Çalışmaların çoğunlukla ${hourRange(busiest.key)} aralığında.';

    if (focusByHour.isEmpty) {
      return '$text En verimli saat aralığını hesaplamak için kameralı odak verisi gerekiyor.';
    }

    final bestFocus = focusByHour.entries.reduce((best, item) {
      final bestAverage =
          best.value.reduce((a, b) => a + b) / best.value.length;
      final itemAverage =
          item.value.reduce((a, b) => a + b) / item.value.length;

      return itemAverage > bestAverage ? item : best;
    });

    text += ' En verimli saat aralığın ${hourRange(bestFocus.key)} görünüyor.';

    return text;
  }

  String rhythmInsight() {
    if (sessions.length < 3) {
      return 'Çalışma ritmini analiz etmek için birkaç oturum daha gerekiyor.';
    }

    final focusDrops = <double>[];
    final breakDurations = <double>[];
    final activeDurations = <double>[];

    for (final item in sessions) {
      final session = Map<String, dynamic>.from(item);
      final drop = session['first_focus_drop_second'];

      if (drop is num && session['camera_enabled'] == true) {
        focusDrops.add(drop.toDouble());
      }

      activeDurations.add(numberValue(session['active_seconds']));

      final breakSegments = List<dynamic>.from(session['break_segments'] ?? []);

      for (final breakItem in breakSegments) {
        final breakMap = Map<String, dynamic>.from(breakItem);
        final duration = breakMap['actual_duration'];

        if (duration is num) {
          breakDurations.add(duration.toDouble());
        }
      }
    }

    if (focusDrops.isNotEmpty) {
      final averageDrop =
          focusDrops.reduce((a, b) => a + b) / focusDrops.length;

      return 'Dikkat düşüşlerin çoğunlukla ${minutes(averageDrop)}. dakika civarında oluşmaya başlıyor.';
    }

    if (breakDurations.isNotEmpty) {
      final averageBreak =
          breakDurations.reduce((a, b) => a + b) / breakDurations.length;

      return 'Ortalama mola süren ${minutes(averageBreak)} dakika civarında. Bu veri toparlanma analizini besliyor.';
    }

    final averageActive =
        activeDurations.reduce((a, b) => a + b) / activeDurations.length;

    return 'Ortalama çalışma süren ${minutes(averageActive)} dakika civarında ilerliyor.';
  }

  Widget sectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.7,
      ),
    );
  }

  Widget summaryMetric({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      width: 158,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(height: 18),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 23,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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

  Widget sessionPreviewCard(Map<String, dynamic> session, double width) {
    final cameraEnabled = session['camera_enabled'] == true;
    final focusScore = numberValue(session['focus_score']);
    final color = cameraEnabled ? focusColor(focusScore) : AppTheme.calmBlue;

    return SizedBox(
      width: width,
      child: PremiumCard(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          height: 176,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      modeName(session['session_mode']),
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      cameraEnabled
                          ? '${focusScore.toStringAsFixed(0)}%'
                          : 'Odak yok',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${session['date'] ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${minutes(session['active_seconds'])} dk',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                cameraEnabled
                    ? '${minutes(session['break_seconds'])} dk mola · ${session['distraction_count'] ?? 0} dikkat düşüşü'
                    : '${minutes(session['break_seconds'])} dk mola · kamera kapalı',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget emptySessionCard() {
    return PremiumCard(
      padding: EdgeInsets.all(24),
      child: Text(
        'Henüz kayıtlı oturum yok. İlk oturumunu başlattığında burada son çalışmaların görünecek.',
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 14,
          height: 1.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget insightTile({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return PremiumCard(
      padding: const EdgeInsets.all(26),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 15,
                height: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget lastSessionsLayout(List<Map<String, dynamic>> lastSessions) {
    if (lastSessions.isEmpty) {
      return emptySessionCard();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 860;
        final cardWidth = compact
            ? constraints.maxWidth
            : (constraints.maxWidth - 32) / 3;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final session in lastSessions)
              sessionPreviewCard(session, cardWidth),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionCount = trendData?['session_count'] ?? sessions.length;
    final averageFocus = numberValue(trendData?['average_focus_score']);

    final dashboardSummary = Map<String, dynamic>.from(
      trendData?['dashboard_summary'] ?? {},
    );

    final totalActiveSeconds = dashboardSummary['total_active_seconds'] ?? 0;
    final totalBreakSeconds = dashboardSummary['total_break_seconds'] ?? 0;
    final lastSessions = lastThreeSessions();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: loadDashboard,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ListView(
              children: [
                ValueListenableBuilder<UserProfile>(
                  valueListenable: UserProfileService.profile,
                  builder: (context, profile, _) {
                    final hasName = profile.displayName.trim().isNotEmpty;

                    return Text(
                      hasName
                          ? 'Hoş geldin ${profile.visibleName}'
                          : 'Hoş geldin',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  mainInsight(),
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 16,
                    height: 1.6,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 30),
                if (loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (errorMessage != null)
                  PremiumCard(
                    padding: const EdgeInsets.all(22),
                    child: Text(
                      errorMessage!,
                      style: TextStyle(
                        color: AppTheme.dangerRed,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else ...[
                  sectionTitle('Son 3 Oturum'),
                  const SizedBox(height: 14),
                  lastSessionsLayout(lastSessions),
                  const SizedBox(height: 16),
                  insightTile(
                    icon: Icons.trending_up_rounded,
                    color: AppTheme.focusGreen,
                    text: lastThreeInsight(),
                  ),
                  const SizedBox(height: 28),
                  sectionTitle('Genel Özet'),
                  const SizedBox(height: 14),
                  PremiumCard(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            summaryMetric(
                              label: 'Toplam oturum',
                              value: '$sessionCount',
                              color: AppTheme.calmBlue,
                            ),
                            summaryMetric(
                              label: 'Ortalama odak',
                              value: sessions.isEmpty
                                  ? '-'
                                  : '${averageFocus.toStringAsFixed(0)}%',
                              color: AppTheme.warningOrange,
                            ),
                            summaryMetric(
                              label: 'Ortalama süre',
                              value: '${minutes(averageActiveSeconds())} dk',
                              color: AppTheme.textPrimary,
                            ),
                            summaryMetric(
                              label: 'Toplam çalışma',
                              value: '${hours(totalActiveSeconds)} sa',
                              color: AppTheme.focusGreen,
                            ),
                            summaryMetric(
                              label: 'Toplam mola',
                              value: '${minutes(totalBreakSeconds)} dk',
                              color: AppTheme.calmBlue,
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Text(
                          trendData?['trend_message'] ??
                              'Daha fazla oturumdan sonra genel çalışma eğilimin burada daha net özetlenecek.',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 15,
                            height: 1.6,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  sectionTitle('Dinamik Öneri'),
                  const SizedBox(height: 14),
                  insightTile(
                    icon: Icons.schedule_rounded,
                    color: AppTheme.calmBlue,
                    text: dynamicSuggestion(),
                  ),
                  const SizedBox(height: 28),
                  sectionTitle('Çalışma Ritmi'),
                  const SizedBox(height: 14),
                  insightTile(
                    icon: Icons.auto_awesome_rounded,
                    color: AppTheme.focusGreen,
                    text: rhythmInsight(),
                  ),
                  const SizedBox(height: 36),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
