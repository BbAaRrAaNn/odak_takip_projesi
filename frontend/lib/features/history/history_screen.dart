import 'package:flutter/material.dart';

import '../../core/services/api_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/premium_card.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
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

  @override
  void initState() {
    super.initState();
    loadSessions();
  }

  Future<void> loadSessions() async {
    try {
      final result = await apiService.getSessions();

      if (!mounted) return;

      setState(() {
        sessions = List<dynamic>.from(result['sessions'] ?? [])
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
            .reversed
            .toList();
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
      if (selectedFilter == 'all') return true;
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

  String modeName(dynamic mode) {
    if (mode == 'classic') return 'Klasik';
    if (mode == 'adaptive') return 'Adaptif';
    if (mode == 'flow') return 'Akış';
    return 'Oturum';
  }

  Color scoreColor(double score) {
    return categoryColor(categoryForScore(score));
  }

  String scoreLabel(double score) {
    return categoryLabel(categoryForScore(score));
  }

  String categoryForScore(double score) {
    if (score >= 85) return 'excellent';
    if (score >= 70) return 'balanced';
    if (score >= 50) return 'fluctuating';
    if (score >= 30) return 'drop';
    return 'severe_drop';
  }

  String categoryFromData(
    Map<String, dynamic> data, {
    double fallbackScore = 0,
    String fallbackCategory = 'balanced',
  }) {
    final raw = '${data['focus_category'] ?? data['focus_state'] ?? ''}';

    if (raw == 'low' || raw == 'not_focused') return 'drop';
    if (raw == 'stable' || raw == 'focused') return 'balanced';

    if (raw.isNotEmpty && raw != 'null') return raw;

    final score = number(data['focus_score']);

    if (score > 0) return categoryForScore(score);

    if (fallbackScore > 0) return categoryForScore(fallbackScore);

    return fallbackCategory;
  }

  Color categoryColor(String category) {
    if (category == 'excellent') return AppTheme.focusStrongGreen;
    if (category == 'balanced') return AppTheme.focusGreen;
    if (category == 'fluctuating') return AppTheme.focusAmber;
    if (category == 'drop') return AppTheme.focusOrange;
    if (category == 'severe_drop') return AppTheme.dangerRed;
    if (category == 'camera_off') return AppTheme.calmBlue;
    if (category == 'break') return AppTheme.textMuted;
    if (category == 'away' || category == 'no_face') {
      return AppTheme.textMuted.withValues(alpha: 0.72);
    }

    return AppTheme.focusGreen;
  }

  String categoryLabel(String category) {
    if (category == 'excellent') return 'Odak çok iyi';
    if (category == 'balanced') return 'Odak dengeli';
    if (category == 'fluctuating') return 'Odak dalgalanıyor';
    if (category == 'drop') return 'Odak düşüşü';
    if (category == 'severe_drop') return 'Ciddi odak düşüşü';
    if (category == 'camera_off') return 'Çalışma';
    if (category == 'break') return 'Mola';
    if (category == 'away') return 'Ekran başında değil';
    if (category == 'no_face') return 'Kişi algılanmadı';

    return 'Odak dengeli';
  }

  List<_TimelineSegment> workTimelineSegments({
    required Map<String, dynamic> session,
    required Map<String, dynamic> data,
    required bool cameraEnabled,
  }) {
    final start = number(data['start_second']);
    final explicitEnd = number(data['end_second']);
    final duration = number(data['duration']);
    final end = explicitEnd > start ? explicitEnd : start + duration;
    final workDuration = end - start;

    if (workDuration <= 0) return [];

    if (!cameraEnabled) {
      return [
        _TimelineSegment(
          label: 'Çalışma',
          seconds: workDuration,
          color: AppTheme.calmBlue,
        ),
      ];
    }

    final sessionScore = number(session['focus_score']);
    final segmentScore = number(data['focus_score']);
    final score = segmentScore > 0 ? segmentScore : sessionScore;
    final category = categoryFromData(
      data,
      fallbackScore: score,
      fallbackCategory: categoryForScore(score),
    );
    final normal = _TimelineSegment(
      label: categoryLabel(category),
      seconds: workDuration,
      color: categoryColor(category),
    );
    final drops =
        focusDropRanges(
            session,
          ).where((range) => range.end > start && range.start < end).toList()
          ..sort((a, b) => a.start.compareTo(b.start));

    if (drops.isEmpty) return [normal];

    final segments = <_TimelineSegment>[];
    var cursor = start;

    for (final drop in drops) {
      final dropStart = mathMax(drop.start, start);
      final dropEnd = mathMin(drop.end, end);

      if (dropEnd <= dropStart) continue;

      if (dropStart > cursor) {
        segments.add(
          _TimelineSegment(
            label: categoryLabel(category),
            seconds: dropStart - cursor,
            color: categoryColor(category),
          ),
        );
      }

      segments.add(
        _TimelineSegment(
          label: categoryLabel(drop.category),
          seconds: dropEnd - dropStart,
          color: categoryColor(drop.category),
          striped: drop.category == 'no_face',
        ),
      );

      cursor = dropEnd > cursor ? dropEnd : cursor;
    }

    if (cursor < end) {
      segments.add(
        _TimelineSegment(
          label: categoryLabel(category),
          seconds: end - cursor,
          color: categoryColor(category),
        ),
      );
    }

    return segments.where((item) => item.seconds > 0).toList();
  }

  List<_FocusDropRange> focusDropRanges(Map<String, dynamic> session) {
    final drops = List<dynamic>.from(session['focus_drop_events'] ?? []);

    return drops
        .map((item) {
          final data = Map<String, dynamic>.from(item);
          final duration = number(data['duration']);
          final end = number(data['end_second']) > 0
              ? number(data['end_second'])
              : number(data['time_second']);
          final start = number(data['start_second']) > 0
              ? number(data['start_second'])
              : mathMax(0, end - duration);

          final rawCategory =
              '${data['focus_category'] ?? data['focus_state'] ?? ''}';
          final eventScore = number(data['focus_score']);
          var category = rawCategory.isNotEmpty && rawCategory != 'null'
              ? rawCategory
              : eventScore > 0 && eventScore < 70
              ? categoryForScore(eventScore)
              : 'drop';

          if (category == 'excellent' ||
              category == 'balanced' ||
              category == 'camera_off') {
            category = 'drop';
          }

          return _FocusDropRange(
            start: start,
            end: end,
            score: eventScore,
            category: category,
          );
        })
        .where((range) => range.end > range.start)
        .toList();
  }

  double mathMin(double a, double b) => a < b ? a : b;

  double mathMax(double a, double b) => a > b ? a : b;

  bool hasDetailedRange(Map<String, dynamic> data) {
    if (!data.containsKey('start_second') || !data.containsKey('end_second')) {
      return false;
    }

    return number(data['end_second']) > number(data['start_second']);
  }

  bool timelineIsEstimated(Map<String, dynamic> session) {
    final timeline = List<dynamic>.from(session['timeline_segments'] ?? []);

    if (timeline.isNotEmpty) {
      return timeline
          .map((item) => Map<String, dynamic>.from(item))
          .any((item) => !hasDetailedRange(item));
    }

    final workSegments = List<dynamic>.from(session['work_segments'] ?? []);
    final breakSegments = List<dynamic>.from(session['break_segments'] ?? []);
    final awaySegments = List<dynamic>.from(session['away_segments'] ?? []);
    final combined = [
      ...workSegments,
      ...breakSegments,
      ...awaySegments,
    ].map((item) => Map<String, dynamic>.from(item));

    if (combined.isNotEmpty) {
      return combined.any((item) => !hasDetailedRange(item));
    }

    return number(session['break_seconds']) > 0 ||
        number(session['away_seconds']) > 0 ||
        List<dynamic>.from(session['focus_drop_events'] ?? []).isNotEmpty;
  }

  String? timelineNote(Map<String, dynamic> session) {
    if (!timelineIsEstimated(session)) return null;
    return 'Bu eski kayıtta detaylı zaman çizelgesi sınırlı; gösterim tahmini.';
  }

  List<_TimelineSegment> estimatedOrderedSegments({
    required Map<String, dynamic> session,
    required List<Map<String, dynamic>> ordered,
    required bool cameraEnabled,
  }) {
    final segments = <_TimelineSegment>[];
    var cursor = 0.0;

    for (final item in ordered) {
      final type = item['type'];
      final duration = number(
        item['duration'] ?? item['actual_duration'] ?? item['planned_duration'],
      );

      if (duration <= 0) continue;

      final data = {
        ...item,
        'start_second': cursor,
        'end_second': cursor + duration,
        'duration': duration,
      };

      if (type == 'break') {
        segments.add(
          _TimelineSegment(
            label: 'Mola',
            seconds: duration,
            color: AppTheme.textMuted,
          ),
        );
      } else if (type == 'away') {
        segments.add(
          _TimelineSegment(
            label: 'Ekran başında değil',
            seconds: duration,
            color: categoryColor('away'),
            striped: true,
          ),
        );
      } else if (type == 'focus_drop') {
        final category = categoryFromData(data, fallbackCategory: 'drop');
        segments.add(
          _TimelineSegment(
            label: categoryLabel(category),
            seconds: duration,
            color: categoryColor(category),
            striped: category == 'no_face',
          ),
        );
      } else {
        segments.addAll(
          workTimelineSegments(
            session: session,
            data: data,
            cameraEnabled: cameraEnabled,
          ),
        );
      }

      cursor += duration;
    }

    return segments.where((item) => item.seconds > 0).toList();
  }

  List<_TimelineSegment> estimatedLegacySegments({
    required Map<String, dynamic> session,
    required List<dynamic> workSegments,
    required List<dynamic> breakSegments,
    required List<dynamic> awaySegments,
    required bool cameraEnabled,
  }) {
    final ordered = <Map<String, dynamic>>[];
    final maxCount = [
      workSegments.length,
      breakSegments.length,
      awaySegments.length,
    ].fold<int>(0, (max, value) => value > max ? value : max);

    for (var index = 0; index < maxCount; index++) {
      if (index < workSegments.length) {
        ordered.add({
          ...Map<String, dynamic>.from(workSegments[index]),
          'type': 'work',
        });
      }

      if (index < breakSegments.length) {
        final data = Map<String, dynamic>.from(breakSegments[index]);
        ordered.add({
          ...data,
          'type': 'break',
          'duration': data['duration'] ?? data['actual_duration'],
        });
      }

      if (index < awaySegments.length) {
        ordered.add({
          ...Map<String, dynamic>.from(awaySegments[index]),
          'type': 'away',
        });
      }
    }

    if (ordered.isEmpty) {
      final active = number(session['active_seconds']);
      final breakSeconds = number(session['break_seconds']);
      final awaySeconds = number(session['away_seconds']);

      if (active > 0) {
        ordered.add({'type': 'work', 'duration': active});
      }

      if (breakSeconds > 0) {
        ordered.add({'type': 'break', 'duration': breakSeconds});
      }

      if (awaySeconds > 0) {
        ordered.add({'type': 'away', 'duration': awaySeconds});
      }
    }

    return estimatedOrderedSegments(
      session: session,
      ordered: ordered,
      cameraEnabled: cameraEnabled,
    );
  }

  List<_TimelineSegment> timelineSegments(Map<String, dynamic> session) {
    final cameraEnabled = session['camera_enabled'] == true;
    final timeline = List<dynamic>.from(session['timeline_segments'] ?? []);

    if (timeline.isNotEmpty) {
      final timelineItems = timeline
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      if (timelineItems.any((item) => !hasDetailedRange(item))) {
        return estimatedOrderedSegments(
          session: session,
          ordered: timelineItems,
          cameraEnabled: cameraEnabled,
        );
      }

      final segments = <_TimelineSegment>[];
      final sortedTimeline = timelineItems
        ..sort(
          (a, b) =>
              number(a['start_second']).compareTo(number(b['start_second'])),
        );

      for (final data in sortedTimeline) {
        final type = data['type'];

        if (type == 'break') {
          segments.add(
            _TimelineSegment(
              label: 'Mola',
              seconds: number(data['duration']),
              color: AppTheme.textMuted,
            ),
          );
          continue;
        }

        if (type == 'away') {
          segments.add(
            _TimelineSegment(
              label: 'Ekran başında değil',
              seconds: number(data['duration']),
              color: categoryColor('away'),
              striped: true,
            ),
          );
          continue;
        }

        if (type == 'focus_drop') {
          final category = categoryFromData(data, fallbackCategory: 'drop');
          segments.add(
            _TimelineSegment(
              label: categoryLabel(category),
              seconds: number(data['duration']),
              color: categoryColor(category),
              striped: category == 'no_face',
            ),
          );
          continue;
        }

        segments.addAll(
          workTimelineSegments(
            session: session,
            data: data,
            cameraEnabled: cameraEnabled,
          ),
        );
      }

      return segments.where((item) => item.seconds > 0).toList();
    }

    final workSegments = List<dynamic>.from(session['work_segments'] ?? []);
    final breakSegments = List<dynamic>.from(session['break_segments'] ?? []);
    final awaySegments = List<dynamic>.from(session['away_segments'] ?? []);
    final segments = <_TimelineSegment>[];

    if (workSegments.isNotEmpty ||
        breakSegments.isNotEmpty ||
        awaySegments.isNotEmpty) {
      final chronological =
          <Map<String, dynamic>>[
            for (final item in workSegments)
              {...Map<String, dynamic>.from(item), 'type': 'work'},
            for (final item in breakSegments)
              {
                ...Map<String, dynamic>.from(item),
                'type': 'break',
                'duration': Map<String, dynamic>.from(item)['actual_duration'],
              },
            for (final item in awaySegments)
              {...Map<String, dynamic>.from(item), 'type': 'away'},
          ]..sort(
            (a, b) =>
                number(a['start_second']).compareTo(number(b['start_second'])),
          );

      if (chronological.any((item) => !hasDetailedRange(item))) {
        return estimatedLegacySegments(
          session: session,
          workSegments: workSegments,
          breakSegments: breakSegments,
          awaySegments: awaySegments,
          cameraEnabled: cameraEnabled,
        );
      }

      final built = <_TimelineSegment>[];

      for (final item in chronological) {
        if (item['type'] == 'break') {
          built.add(
            _TimelineSegment(
              label: 'Mola',
              seconds: number(item['duration']),
              color: AppTheme.textMuted,
            ),
          );
          continue;
        }

        if (item['type'] == 'away') {
          built.add(
            _TimelineSegment(
              label: 'Ekran başında değil',
              seconds: number(item['duration']),
              color: categoryColor('away'),
              striped: true,
            ),
          );
          continue;
        }

        built.addAll(
          workTimelineSegments(
            session: session,
            data: item,
            cameraEnabled: cameraEnabled,
          ),
        );
      }

      return built.where((item) => item.seconds > 0).toList();
    }

    final breakSeconds = number(session['break_seconds']);
    final awaySeconds = number(session['away_seconds']);

    if (!cameraEnabled) {
      final work = number(session['active_seconds']);
      return [
        if (work > 0)
          _TimelineSegment(
            label: 'Çalışma',
            seconds: work,
            color: AppTheme.calmBlue,
          ),
        if (breakSeconds > 0)
          _TimelineSegment(
            label: 'Mola',
            seconds: breakSeconds,
            color: AppTheme.textMuted,
          ),
        if (awaySeconds > 0)
          _TimelineSegment(
            label: 'Ekran başında değil',
            seconds: awaySeconds,
            color: categoryColor('away'),
            striped: true,
          ),
      ];
    }

    final snapshots = List<dynamic>.from(session['minute_snapshots'] ?? []);

    if (snapshots.isNotEmpty) {
      for (final item in snapshots) {
        final snapshot = Map<String, dynamic>.from(item);
        final score = number(snapshot['focus_score']);
        final category = categoryFromData(
          snapshot,
          fallbackScore: score,
          fallbackCategory: categoryForScore(score),
        );
        segments.add(
          _TimelineSegment(
            label: categoryLabel(category),
            seconds: 60,
            color: categoryColor(category),
          ),
        );
      }
    } else {
      final focus = number(session['focus_seconds']);
      final notFocus = number(session['not_focus_seconds']);

      if (focus > 0) {
        segments.add(
          _TimelineSegment(
            label: 'Odak dengeli',
            seconds: focus,
            color: categoryColor('balanced'),
          ),
        );
      }

      if (notFocus > 0) {
        segments.add(
          _TimelineSegment(
            label: 'Odak düşüşü',
            seconds: notFocus,
            color: categoryColor('drop'),
          ),
        );
      }
    }

    if (breakSeconds > 0) {
      segments.add(
        _TimelineSegment(
          label: 'Mola',
          seconds: breakSeconds,
          color: AppTheme.textMuted,
        ),
      );
    }

    if (awaySeconds > 0) {
      segments.add(
        _TimelineSegment(
          label: 'Ekran başında değil',
          seconds: awaySeconds,
          color: categoryColor('away'),
          striped: true,
        ),
      );
    }

    return segments;
  }

  Widget timelineBar(Map<String, dynamic> session, {double height = 12}) {
    final segments = timelineSegments(session);

    if (segments.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: AppTheme.surfaceMuted,
          borderRadius: BorderRadius.circular(20),
        ),
      );
    }

    final total = segments.fold<double>(0, (sum, item) => sum + item.seconds);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (final segment in segments)
              Expanded(
                flex: ((segment.seconds / total) * 100).round().clamp(1, 1000),
                child: Tooltip(
                  message:
                      '${segment.label} · ${minuteText(segment.seconds)} dk',
                  child: segment.striped
                      ? CustomPaint(
                          painter: _StripePainter(segment.color),
                          child: Container(
                            color: segment.color.withValues(alpha: 0.12),
                          ),
                        )
                      : Container(color: segment.color),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget legend(bool cameraEnabled) {
    final items = cameraEnabled
        ? [
            _LegendItem('Odak iyi/dengeli', AppTheme.focusGreen),
            _LegendItem('Odak dalgalanıyor', AppTheme.focusAmber),
            _LegendItem('Odak düşüşü', AppTheme.focusOrange),
            _LegendItem('Ciddi odak düşüşü', AppTheme.dangerRed),
            _LegendItem('Mola', AppTheme.textMuted),
            _LegendItem(
              'Ekran başında değil',
              AppTheme.textMuted,
              striped: true,
            ),
          ]
        : [
            _LegendItem('Çalışma', AppTheme.calmBlue),
            _LegendItem('Mola', AppTheme.textMuted),
            _LegendItem(
              'Ekran başında değil',
              AppTheme.textMuted,
              striped: true,
            ),
          ];

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        for (final item in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              legendSwatch(item),
              const SizedBox(width: 6),
              Text(
                item.label,
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

  Widget legendSwatch(_LegendItem item) {
    final swatch = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: item.color, shape: BoxShape.circle),
    );

    if (!item.striped) return swatch;

    return ClipOval(
      child: CustomPaint(
        painter: _StripePainter(item.color),
        child: Container(
          width: 10,
          height: 10,
          color: item.color.withValues(alpha: 0.12),
        ),
      ),
    );
  }

  Widget metric({required String title, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
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

  Widget sessionCard(Map<String, dynamic> session) {
    final cameraEnabled = session['camera_enabled'] == true;
    final focusScore = number(session['focus_score']);
    final color = cameraEnabled ? scoreColor(focusScore) : AppTheme.calmBlue;
    final note = timelineNote(session);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SessionDetailScreen(
              session: session,
              timelineBuilder: timelineBar,
              legendBuilder: legend,
              timelineNoteBuilder: timelineNote,
              modeName: modeName,
              minuteText: minuteText,
              number: number,
            ),
          ),
        );
      },
      child: PremiumCard(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${session['date'] ?? ''}',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
              ],
            ),
            const SizedBox(height: 18),
            timelineBar(session),
            const SizedBox(height: 12),
            legend(cameraEnabled),
            if (note != null) ...[
              const SizedBox(height: 10),
              Text(
                note,
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                metric(title: 'Mod', value: modeName(session['session_mode'])),
                metric(
                  title: 'Kamera',
                  value: cameraEnabled ? 'Açık' : 'Kapalı',
                ),
                metric(
                  title: 'Aktif süre',
                  value: '${minuteText(session['active_seconds'])} dk',
                ),
                metric(
                  title: 'Mola',
                  value: '${minuteText(session['break_seconds'])} dk',
                ),
                if (number(session['away_seconds']) > 0)
                  metric(
                    title: 'Uzakta',
                    value: '${minuteText(session['away_seconds'])} dk',
                  ),
                metric(
                  title: 'Odak',
                  value: cameraEnabled
                      ? '${focusScore.toStringAsFixed(0)}%'
                      : 'kamera kapalı',
                ),
                metric(
                  title: 'Düşüş',
                  value: cameraEnabled
                      ? '${session['distraction_count'] ?? 0}'
                      : '-',
                ),
              ],
            ),
          ],
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final visible = filteredSessions;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(32),
                child: RefreshIndicator(
                  onRefresh: loadSessions,
                  child: ListView(
                    children: [
                      Text(
                        'Geçmiş',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${visible.length} oturum gösteriliyor · toplam ${sessions.length} kayıt',
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
                      if (visible.isEmpty)
                        PremiumCard(
                          padding: EdgeInsets.all(28),
                          child: Text(
                            'Bu filtre için kayıt bulunmuyor.',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else
                        for (final session in visible)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: sessionCard(session),
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

class SessionDetailScreen extends StatelessWidget {
  final Map<String, dynamic> session;
  final Widget Function(Map<String, dynamic>, {double height}) timelineBuilder;
  final Widget Function(bool cameraEnabled) legendBuilder;
  final String? Function(Map<String, dynamic>) timelineNoteBuilder;
  final String Function(dynamic mode) modeName;
  final String Function(dynamic seconds) minuteText;
  final double Function(dynamic value) number;

  const SessionDetailScreen({
    super.key,
    required this.session,
    required this.timelineBuilder,
    required this.legendBuilder,
    required this.timelineNoteBuilder,
    required this.modeName,
    required this.minuteText,
    required this.number,
  });

  bool get cameraEnabled => session['camera_enabled'] == true;

  @override
  Widget build(BuildContext context) {
    final breakSegments = List<dynamic>.from(session['break_segments'] ?? []);
    final awaySegments = List<dynamic>.from(session['away_segments'] ?? []);
    final drops = List<dynamic>.from(session['focus_drop_events'] ?? []);
    final actions = List<dynamic>.from(session['notification_actions'] ?? []);
    final focusScore = number(session['focus_score']);
    final note = timelineNoteBuilder(session);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ListView(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Geri',
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${session['date'] ?? 'Oturum detayı'}',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              PremiumCard(
                padding: const EdgeInsets.all(26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Büyük Timeline',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 18),
                    timelineBuilder(session, height: 22),
                    const SizedBox(height: 14),
                    legendBuilder(cameraEnabled),
                    if (note != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        note,
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              PremiumCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Grafikler',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 18),
                    graphLine(
                      'Aktif süre',
                      number(session['active_seconds']),
                      number(session['total_seconds']),
                      AppTheme.calmBlue,
                    ),
                    graphLine(
                      'Mola süresi',
                      number(session['break_seconds']),
                      number(session['total_seconds']),
                      AppTheme.textMuted,
                    ),
                    if (number(session['away_seconds']) > 0)
                      graphLine(
                        'Uzakta',
                        number(session['away_seconds']),
                        number(session['total_seconds']),
                        AppTheme.textMuted,
                      ),
                    if (cameraEnabled)
                      graphLine(
                        'Odak oranı',
                        focusScore,
                        100,
                        AppTheme.focusGreen,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              detailGrid(
                breakSegments: breakSegments,
                awaySegments: awaySegments,
                drops: drops,
                actions: actions,
              ),
              const SizedBox(height: 18),
              PremiumCard(
                padding: const EdgeInsets.all(24),
                child: Text(
                  interpretation(),
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
        ),
      ),
    );
  }

  Widget graphLine(String title, double value, double total, Color color) {
    final denominator = total <= 0 ? 1 : total;
    final ratio = (value / denominator).clamp(0, 1).toDouble();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                title == 'Odak oranı'
                    ? '${value.toStringAsFixed(0)}%'
                    : '${minuteText(value)} dk',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 9,
              backgroundColor: AppTheme.surfaceMuted,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget detailGrid({
    required List<dynamic> breakSegments,
    required List<dynamic> awaySegments,
    required List<dynamic> drops,
    required List<dynamic> actions,
  }) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: listCard(
                title: 'Molalar',
                empty: 'Mola kaydı yok.',
                items: breakSegments.map((item) {
                  final data = Map<String, dynamic>.from(item);
                  return '${minuteText(data['actual_duration'])} dk · ${minuteText(data['start_second'])}. dakikada';
                }).toList(),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: listCard(
                title: 'Dikkat Düşüşleri',
                empty: cameraEnabled ? 'Düşüş kaydı yok.' : 'Kamera kapalı.',
                items: drops.map((item) {
                  final data = Map<String, dynamic>.from(item);
                  final start = number(data['start_second']) > 0
                      ? data['start_second']
                      : data['time_second'];
                  return '${minuteText(start)}. dakika · ${minuteText(data['duration'])} dk';
                }).toList(),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: listCard(
                title: 'Bildirim Aksiyonları',
                empty: 'Aksiyon kaydı yok.',
                items: actions.map((item) {
                  final data = Map<String, dynamic>.from(item);
                  return '${actionName(data['action'])} · ${minuteText(data['active_second'])}. dakika';
                }).toList(),
              ),
            ),
          ],
        ),
        if (awaySegments.isNotEmpty) ...[
          const SizedBox(height: 16),
          listCard(
            title: 'Uzakta Segmentleri',
            empty: 'Uzakta kaydı yok.',
            items: awaySegments.map((item) {
              final data = Map<String, dynamic>.from(item);
              return '${minuteText(data['duration'])} dk · ${minuteText(data['start_second'])}. dakikada';
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget listCard({
    required String title,
    required String empty,
    required List<String> items,
  }) {
    return PremiumCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            Text(
              empty,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  item,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
        ],
      ),
    );
  }

  String actionName(dynamic action) {
    if (action == 'notification_shown') return 'Bildirim gösterildi';
    if (action == 'break_accepted') return 'Mola kabul';
    if (action == 'break_declined') return 'Devam et';
    if (action == 'break_snoozed') return '5 dk ertele';
    if (action == 'break_started') return 'Mola başladı';
    if (action == 'break_extended') return 'Mola uzatıldı';
    if (action == 'break_ended') return 'Mola bitti';
    if (action == 'away_detected') return 'Uzakta algılandı';
    if (action == 'away_resumed') return 'Oturum devam etti';
    if (action == 'focus_drop_notification') return 'Odak bildirimi';
    if (action == 'planned_break_notification') return 'Planlı mola bildirimi';
    if (action == 'return_work') return 'Çalışmaya dön';
    if (action == 'accept_break') return 'Mola kabul';
    if (action == 'decline_break') return 'Devam et';
    if (action == 'snooze_break') return 'Ertele';
    if (action == 'extend_break') return 'Molayı uzat';
    return '$action';
  }

  String interpretation() {
    if (!cameraEnabled) {
      return 'Bu oturum kamerasız tamamlanmış. Odak oranı yerine çalışma ve mola süreleri değerlendirilmeli.';
    }

    final score = number(session['focus_score']);
    final drops = number(session['distraction_count']);

    if (score >= 75 && drops <= 2) {
      return 'Odak stabilitesi güçlü. Bu oturumdaki çalışma bloğu benzer planlar için iyi bir referans olabilir.';
    }

    if (score >= 45) {
      return 'Oturumda dalgalı ama kullanılabilir bir odak ritmi var. Mola zamanlaması detayları sonraki planı iyileştirebilir.';
    }

    return 'Odak düşüşleri belirgin. Daha kısa çalışma blokları ve erken mola önerileri bu ritme daha uygun görünüyor.';
  }
}

class _TimelineSegment {
  final String label;
  final double seconds;
  final Color color;
  final bool striped;

  const _TimelineSegment({
    required this.label,
    required this.seconds,
    required this.color,
    this.striped = false,
  });
}

class _FocusDropRange {
  final double start;
  final double end;
  final double score;
  final String category;

  const _FocusDropRange({
    required this.start,
    required this.end,
    required this.score,
    required this.category,
  });
}

class _LegendItem {
  final String label;
  final Color color;
  final bool striped;

  const _LegendItem(this.label, this.color, {this.striped = false});
}

class _StripePainter extends CustomPainter {
  final Color color;

  const _StripePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1.3;

    for (var x = -size.height; x < size.width + size.height; x += 6) {
      canvas.drawLine(
        Offset(x.toDouble(), size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StripePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
