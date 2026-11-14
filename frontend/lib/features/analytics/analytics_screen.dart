import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/services/api_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/premium_card.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final ApiService apiService = ApiService();

  bool loading = true;
  String selectedFilter = 'all';

  List<Map<String, dynamic>> sessions = [];

  final filters = const [
    ('all', 'Tümü'),
    ('classic', 'Klasik'),
    ('adaptive', 'Adaptif'),
    ('flow', 'Akış'),
    ('camera_on', 'Kamera Açık'),
    ('camera_off', 'Kamerasız'),
  ];

  final chartTypes = <String, String>{
    'focus': 'line',
    'work': 'bar',
    'break': 'bar',
    'mode': 'donut',
    'camera': 'donut',
    'hour': 'bar',
    'drops': 'bar',
  };

  @override
  void initState() {
    super.initState();
    loadAnalytics();
  }

  Future<void> loadAnalytics() async {
    try {
      final result = await apiService.getSessions();

      if (!mounted) return;

      setState(() {
        sessions = List<dynamic>.from(
          result['sessions'] ?? [],
        ).map((item) => Map<String, dynamic>.from(item)).toList();
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get filteredSessions {
    return sessions.where((session) {
      if (selectedFilter == 'all') {
        return true;
      }

      if (selectedFilter == 'camera_on') {
        return session['camera_enabled'] == true;
      }

      if (selectedFilter == 'camera_off') {
        return session['camera_enabled'] != true;
      }

      return session['session_mode'] == selectedFilter;
    }).toList();
  }

  double number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  String minuteText(dynamic seconds) {
    return (number(seconds) / 60).toStringAsFixed(0);
  }

  int? sessionHour(Map<String, dynamic> session) {
    final dateText = '${session['date'] ?? ''}';
    final parts = dateText.split(' ');

    if (parts.length < 2) return null;

    final hour = int.tryParse(parts[1].split(':').first);
    return hour;
  }

  String modeName(dynamic mode) {
    if (mode == 'classic') return 'Klasik';
    if (mode == 'adaptive') return 'Adaptif';
    if (mode == 'flow') return 'Akış';
    return 'Bilinmiyor';
  }

  List<_SeriesPoint> focusSeries() {
    final cameraSessions = filteredSessions
        .where((session) => session['camera_enabled'] == true)
        .toList();

    return [
      for (var i = 0; i < cameraSessions.length; i++)
        _SeriesPoint(
          label: '${i + 1}',
          value: number(cameraSessions[i]['focus_score']),
        ),
    ];
  }

  List<_SeriesPoint> durationSeries(String key) {
    return [
      for (var i = 0; i < filteredSessions.length; i++)
        _SeriesPoint(
          label: '${i + 1}',
          value: number(filteredSessions[i][key]) / 60,
        ),
    ];
  }

  List<_SeriesPoint> distractionSeries() {
    return [
      for (var i = 0; i < filteredSessions.length; i++)
        _SeriesPoint(
          label: '${i + 1}',
          value: number(filteredSessions[i]['distraction_count']),
        ),
    ];
  }

  List<_SeriesPoint> hourlyFocusSeries() {
    final values = <int, List<double>>{};

    for (final session in filteredSessions) {
      if (session['camera_enabled'] != true) continue;

      final hour = sessionHour(session);

      if (hour == null) continue;

      values.putIfAbsent(hour, () => []).add(number(session['focus_score']));
    }

    final entries = values.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return [
      for (final entry in entries)
        _SeriesPoint(
          label: '${entry.key}:00',
          value: entry.value.reduce((a, b) => a + b) / entry.value.length,
        ),
    ];
  }

  Map<String, double> modeDistribution() {
    final data = <String, double>{};

    for (final session in filteredSessions) {
      final key = modeName(session['session_mode']);
      data[key] = (data[key] ?? 0) + 1;
    }

    return data;
  }

  Map<String, double> cameraDistribution() {
    final data = <String, double>{'Kamera Açık': 0, 'Kamerasız': 0};

    for (final session in filteredSessions) {
      if (session['camera_enabled'] == true) {
        data['Kamera Açık'] = data['Kamera Açık']! + 1;
      } else {
        data['Kamerasız'] = data['Kamerasız']! + 1;
      }
    }

    data.removeWhere((key, value) => value <= 0);
    return data;
  }

  double average(List<_SeriesPoint> points) {
    if (points.isEmpty) return 0;
    return points.fold<double>(0, (sum, point) => sum + point.value) /
        points.length;
  }

  Widget filterBar() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final filter in filters)
          ChoiceChip(
            label: Text(filter.$2),
            selected: selectedFilter == filter.$1,
            onSelected: (_) {
              setState(() {
                selectedFilter = filter.$1;
              });
            },
          ),
      ],
    );
  }

  Widget chartTypeSelector(String key, {bool distribution = false}) {
    final options = distribution
        ? [('bar', 'Sütun'), ('donut', 'Donut')]
        : [('line', 'Çizgi'), ('bar', 'Sütun')];

    return Wrap(
      spacing: 8,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(option.$2),
            selected: chartTypes[key] == option.$1,
            onSelected: (_) {
              setState(() {
                chartTypes[key] = option.$1;
              });
            },
          ),
      ],
    );
  }

  Widget seriesChart({
    required String keyName,
    required String title,
    required String emptyText,
    required String summary,
    required List<_SeriesPoint> points,
    required Color color,
    double maxY = 100,
  }) {
    final type = chartTypes[keyName] ?? 'bar';

    return PremiumCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          chartHeader(title, chartTypeSelector(keyName)),
          const SizedBox(height: 18),
          if (points.isEmpty)
            emptyChart(emptyText)
          else
            SizedBox(
              height: 260,
              child: type == 'line'
                  ? lineChart(points, color, maxY)
                  : barChart(points, color, maxY),
            ),
          const SizedBox(height: 16),
          summaryText(summary),
        ],
      ),
    );
  }

  Widget distributionChart({
    required String keyName,
    required String title,
    required String emptyText,
    required String summary,
    required Map<String, double> data,
  }) {
    final type = chartTypes[keyName] ?? 'donut';
    final points = data.entries
        .map((entry) => _SeriesPoint(label: entry.key, value: entry.value))
        .toList();

    return PremiumCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          chartHeader(title, chartTypeSelector(keyName, distribution: true)),
          const SizedBox(height: 18),
          if (points.isEmpty)
            emptyChart(emptyText)
          else
            SizedBox(
              height: 260,
              child: type == 'donut'
                  ? donutChart(points)
                  : barChart(points, AppTheme.calmBlue, maxDistribution(data)),
            ),
          const SizedBox(height: 16),
          legend(points),
          const SizedBox(height: 12),
          summaryText(summary),
        ],
      ),
    );
  }

  Widget chartHeader(String title, Widget selector) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
            ),
          ),
        ),
        selector,
      ],
    );
  }

  Widget emptyChart(String text) {
    return Container(
      height: 190,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget summaryText(String text) {
    return Text(
      text,
      style: TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 14,
        height: 1.55,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget lineChart(List<_SeriesPoint> points, Color color, double maxY) {
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: normalizedMax(points, maxY),
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: chartTitles(points),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), points[i].value),
            ],
            isCurved: true,
            barWidth: 3,
            color: color,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget barChart(List<_SeriesPoint> points, Color color, double maxY) {
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: normalizedMax(points, maxY),
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: chartTitles(points),
        barGroups: [
          for (var i = 0; i < points.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: points[i].value,
                  width: 14,
                  borderRadius: BorderRadius.circular(5),
                  color: color,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget donutChart(List<_SeriesPoint> points) {
    final colors = [
      AppTheme.calmBlue,
      AppTheme.focusGreen,
      AppTheme.warningOrange,
      AppTheme.dangerRed,
      AppTheme.textPrimary,
    ];

    return PieChart(
      PieChartData(
        centerSpaceRadius: 58,
        sectionsSpace: 3,
        sections: [
          for (var i = 0; i < points.length; i++)
            PieChartSectionData(
              value: points[i].value,
              title: points[i].value.toStringAsFixed(0),
              color: colors[i % colors.length],
              radius: 78,
              titleStyle: TextStyle(
                color: AppTheme.foregroundFor(colors[i % colors.length]),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }

  Widget legend(List<_SeriesPoint> points) {
    final colors = [
      AppTheme.calmBlue,
      AppTheme.focusGreen,
      AppTheme.warningOrange,
      AppTheme.dangerRed,
      AppTheme.textPrimary,
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        for (var i = 0; i < points.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colors[i % colors.length],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                points[i].label,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
      ],
    );
  }

  FlTitlesData chartTitles(List<_SeriesPoint> points) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          getTitlesWidget: (value, meta) {
            return Text(
              value.toInt().toString(),
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            );
          },
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 30,
          interval: math.max(1, (points.length / 6).ceil()).toDouble(),
          getTitlesWidget: (value, meta) {
            final index = value.toInt();

            if (index < 0 || index >= points.length) {
              return const SizedBox.shrink();
            }

            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                points[index].label,
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  double normalizedMax(List<_SeriesPoint> points, double fallback) {
    if (points.isEmpty) return fallback;

    final maxValue = points.map((point) => point.value).reduce(math.max);
    return math.max(fallback, maxValue * 1.22);
  }

  double maxDistribution(Map<String, double> data) {
    if (data.isEmpty) return 10;
    return math.max(5, data.values.reduce(math.max) * 1.25);
  }

  String focusSummary(List<_SeriesPoint> points) {
    if (points.isEmpty) {
      return 'Kamera kapalı oturumlar focus grafiğine dahil edilmedi.';
    }

    return 'Kameralı oturumlarda ortalama odak ${average(points).toStringAsFixed(0)}%.';
  }

  String durationSummary(List<_SeriesPoint> points, String label) {
    if (points.isEmpty) return 'Bu grafik için yeterli veri yok.';

    return 'Ortalama $label ${average(points).toStringAsFixed(0)} dakika.';
  }

  String distributionSummary(Map<String, double> data, String label) {
    if (data.isEmpty) return 'Bu dağılım için yeterli veri yok.';

    final top = data.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return '$label dağılımında en yüksek pay ${top.key}.';
  }

  @override
  Widget build(BuildContext context) {
    final focus = focusSeries();
    final work = durationSeries('active_seconds');
    final breaks = durationSeries('break_seconds');
    final modes = modeDistribution();
    final cameras = cameraDistribution();
    final hours = hourlyFocusSeries();
    final drops = distractionSeries();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(32),
                child: RefreshIndicator(
                  onRefresh: loadAnalytics,
                  child: ListView(
                    children: [
                      Text(
                        'Analitik',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${filteredSessions.length} oturum analiz ediliyor. Focus grafikleri yalnızca kameralı oturumları kullanır.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 15,
                          height: 1.55,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 22),
                      filterBar(),
                      const SizedBox(height: 24),
                      seriesChart(
                        keyName: 'focus',
                        title: 'Oturumlara Göre Focus Score',
                        emptyText: 'Bu grafik için yeterli kameralı veri yok.',
                        summary: focusSummary(focus),
                        points: focus,
                        color: AppTheme.focusGreen,
                        maxY: 100,
                      ),
                      const SizedBox(height: 18),
                      seriesChart(
                        keyName: 'work',
                        title: 'Oturumlara Göre Çalışma Süresi',
                        emptyText: 'Bu grafik için yeterli veri yok.',
                        summary: durationSummary(work, 'çalışma süresi'),
                        points: work,
                        color: AppTheme.calmBlue,
                        maxY: 60,
                      ),
                      const SizedBox(height: 18),
                      seriesChart(
                        keyName: 'break',
                        title: 'Oturumlara Göre Mola Süresi',
                        emptyText: 'Bu grafik için yeterli veri yok.',
                        summary: durationSummary(breaks, 'mola süresi'),
                        points: breaks,
                        color: AppTheme.textMuted,
                        maxY: 20,
                      ),
                      const SizedBox(height: 18),
                      distributionChart(
                        keyName: 'mode',
                        title: 'Mod Dağılımı',
                        emptyText: 'Mod dağılımı için yeterli veri yok.',
                        summary: distributionSummary(modes, 'Mod'),
                        data: modes,
                      ),
                      const SizedBox(height: 18),
                      distributionChart(
                        keyName: 'camera',
                        title: 'Kamera Açık/Kapalı Dağılımı',
                        emptyText: 'Kamera dağılımı için yeterli veri yok.',
                        summary: distributionSummary(cameras, 'Kamera'),
                        data: cameras,
                      ),
                      const SizedBox(height: 18),
                      seriesChart(
                        keyName: 'hour',
                        title: 'Saatlere Göre Ortalama Focus',
                        emptyText: 'Bu grafik için yeterli kameralı veri yok.',
                        summary: focusSummary(hours),
                        points: hours,
                        color: AppTheme.warningOrange,
                        maxY: 100,
                      ),
                      const SizedBox(height: 18),
                      seriesChart(
                        keyName: 'drops',
                        title: 'Dikkat Düşüşü Sayısı',
                        emptyText: 'Bu grafik için yeterli veri yok.',
                        summary: durationSummary(drops, 'dikkat düşüşü'),
                        points: drops,
                        color: AppTheme.dangerRed,
                        maxY: 5,
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _SeriesPoint {
  final String label;
  final double value;

  const _SeriesPoint({required this.label, required this.value});
}
