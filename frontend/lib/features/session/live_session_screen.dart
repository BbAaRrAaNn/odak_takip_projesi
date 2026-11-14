import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/services/app_settings_service.dart';
import '../../core/services/api_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/window_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/premium_card.dart';

class LiveSessionScreen extends StatefulWidget {
  final String? initialNotificationAction;

  const LiveSessionScreen({super.key, this.initialNotificationAction});

  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen>
    with WindowListener {
  final ApiService apiService = ApiService();

  Timer? statusTimer;
  Timer? frameTimer;
  Timer? snoozeTimer;
  Timer? bannerCollapseTimer;
  Timer? toastTimer;
  StreamSubscription<String>? notificationActionSub;
  StreamSubscription<void>? miniCameraClosedSub;

  Map<String, dynamic>? liveStatus;
  Map<String, dynamic>? cameraStatus;
  Uint8List? frameBytes;

  bool loading = true;
  bool frameRequestInFlight = false;
  bool suggestionCollapsed = false;
  bool decisionPanelVisible = false;
  bool breakDurationEditorVisible = false;
  bool previewVisible = true;
  bool breakReadyNotified = false;
  bool lastAwayActive = false;
  bool autoMiniMode = false;
  bool autoMiniSuppressed = false;

  _BreakSuggestion? activeSuggestion;
  _BreakSuggestion? snoozedSuggestion;
  int selectedBreakMinutes = 5;
  int suggestedBreakMinutes = 5;
  DateTime? cooldownUntil;
  final List<_FocusWindowSample> focusWindowSamples = [];
  final Map<String, DateTime> notificationCooldownUntil = {};
  final Set<int> promptedPomodoroBlocks = {};
  bool workGoalNotified = false;
  String? toastTitle;
  String? toastMessage;
  String toastTone = 'info';

  @override
  void initState() {
    super.initState();
    initialize();

    statusTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => refreshStatus(),
    );

    frameTimer = Timer.periodic(
      const Duration(milliseconds: 90),
      (_) => refreshFrame(),
    );

    notificationActionSub = NotificationService.actionStream.listen(
      handleDesktopNotificationAction,
    );
    if (widget.initialNotificationAction != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await refreshStatus();
        await handleDesktopNotificationAction(
          widget.initialNotificationAction!,
        );
      });
    }
    miniCameraClosedSub = WindowService.miniCameraClosedStream.listen((_) {
      if (!mounted) return;

      setState(() {
        previewVisible = false;
        autoMiniMode = false;
        autoMiniSuppressed = true;
      });
    });
    windowManager.addListener(this);
  }

  Future<void> initialize() async {
    try {
      await AppSettingsService.loadSettings();
    } catch (_) {}

    if (!mounted) return;

    previewVisible = AppSettingsService.current.cameraPreviewDefaultVisible;

    await refreshStatus();
    await refreshFrame();

    if (!mounted) return;

    setState(() {
      loading = false;
    });
  }

  Future<void> refreshStatus() async {
    try {
      final response = await apiService.getLiveStatus();

      if (!mounted) return;

      final live = Map<String, dynamic>.from(response['live_status'] ?? {});
      final camera = Map<String, dynamic>.from(response['camera_status'] ?? {});

      setState(() {
        liveStatus = live;
        cameraStatus = camera;
      });

      recordFocusWindowSample(live, camera);

      if ((live['camera_enabled'] != true ||
              camera['camera_running'] != true) &&
          WindowService.miniMode) {
        await WindowService.exitMiniCameraMode();
        autoMiniMode = false;
      }

      await evaluateAwayState(live);
      await evaluateBreakReady(live);
      await evaluateWorkGoalCompleted(live);
      await evaluateBreakSuggestion(live);

      unawaited(syncAutomaticMiniCamera());
      unawaited(updateNativeMiniCamera());
    } catch (_) {}
  }

  Future<void> evaluateAwayState(Map<String, dynamic> live) async {
    final awayActive = live['away_active'] == true;
    final cameraActive =
        live['camera_enabled'] == true &&
        cameraStatus?['camera_running'] == true;

    if (awayActive && cameraActive && !lastAwayActive) {
      lastAwayActive = true;
      logNotificationEvent('away_detected', reason: 'away_detected');

      final focused = await WindowService.isAppForeground();
      var shown = false;

      if (focused) {
        logNotificationEvent(
          'notification_decision_foreground',
          reason: 'away_detected',
        );
        showInlineToast(
          title: 'Kişi aktif değil',
          message:
              'Çalışma süresi beklemeye alındı. Döndüğünde oturum devam edecek.',
          tone: 'critical',
        );
        shown = true;
      } else if (AppSettingsService.current.notificationsEnabled) {
        logNotificationEvent(
          'notification_decision_desktop',
          reason: 'away_detected',
        );
        shown = await NotificationService.showAwayNotification();
        if (shown) {
          unawaited(
            Future<void>.delayed(
              const Duration(milliseconds: 650),
            ).then((_) => WindowService.bringToFront()),
          );
        }
      }

      if (shown) {
        setReasonCooldown('away_detected', const Duration(minutes: 5));
        try {
          await apiService.recordNotificationAction(
            actionType: 'notification_shown',
            reason: 'away_detected',
          );
          await apiService.recordNotificationAction(
            actionType: 'away_detected',
            reason: 'away_detected',
          );
        } catch (_) {}
      }

      return;
    }

    if (!awayActive && lastAwayActive) {
      lastAwayActive = false;
      showInlineToast(
        title: 'Tekrar hoş geldin',
        message: 'Oturum kaldığı yerden devam ediyor.',
        tone: 'success',
      );
    }
  }

  Future<void> evaluateBreakReady(Map<String, dynamic> live) async {
    final settings = AppSettingsService.current;
    final paused = live['session_paused'] == true;
    final target = number(live['current_break_target_seconds']);
    final remaining = number(live['current_break_remaining_seconds']);

    if (!paused || target <= 0 || remaining > 0) {
      breakReadyNotified = false;
      return;
    }

    if (breakReadyNotified ||
        !settings.notificationsEnabled ||
        !settings.breakRemindersEnabled) {
      return;
    }

    breakReadyNotified = true;
    logNotificationEvent('break_finished', reason: 'break_finished');

    final focused = await WindowService.isAppForeground();
    var shown = false;

    if (focused) {
      logNotificationEvent(
        'notification_decision_foreground',
        reason: 'break_finished',
      );
      showInlineToast(
        title: 'Çalışmaya dönme zamanı',
        message: 'Mola süren tamamlandı. Çalışmaya dönmek ister misin?',
        tone: 'warning',
      );
      shown = true;
    } else {
      logNotificationEvent(
        'notification_decision_desktop',
        reason: 'break_finished',
      );
      shown = await NotificationService.showBreakReadyNotification();
    }

    if (shown) {
      try {
        await apiService.recordNotificationAction(
          actionType: 'notification_shown',
          reason: 'break_finished',
        );
        await apiService.recordNotificationAction(
          actionType: 'break_finished_notification',
          reason: 'break_finished',
        );
      } catch (_) {}
    }
  }

  Future<void> evaluateWorkGoalCompleted(Map<String, dynamic> live) async {
    if (workGoalNotified) return;
    if (activeSuggestion != null || decisionPanelVisible) return;
    if (live['session_active'] != true || live['session_paused'] == true) {
      return;
    }

    final mode = '${live['session_mode'] ?? 'classic'}';

    if (mode == 'classic') return;

    final plannedSeconds = number(live['planned_total_minutes']) * 60;
    final activeSeconds = number(live['active_seconds']);

    if (plannedSeconds <= 0 || activeSeconds < plannedSeconds) return;
    if (!AppSettingsService.current.notificationsEnabled) return;
    if (isReasonCoolingDown('work_goal_completed')) return;

    workGoalNotified = true;
    logNotificationEvent('work_goal_completed', reason: 'work_goal_completed');
    final focused = await WindowService.isAppForeground();
    var shown = false;

    if (focused) {
      logNotificationEvent(
        'notification_decision_foreground',
        reason: 'work_goal_completed',
      );
      showInlineToast(
        title: 'Çalışma hedefi tamamlandı',
        message:
            'Çalışma hedefin tamamlandı. Oturumu bitirebilir veya devam edebilirsin.',
        tone: 'info',
      );
      shown = true;
    } else {
      logNotificationEvent(
        'notification_decision_desktop',
        reason: 'work_goal_completed',
      );
      shown = await NotificationService.showWorkGoalCompletedNotification();
    }

    if (shown) {
      setReasonCooldown('work_goal_completed', const Duration(minutes: 5));
      try {
        await apiService.recordNotificationAction(
          actionType: 'notification_shown',
          reason: 'work_goal_completed',
        );
      } catch (_) {}
    } else {
      workGoalNotified = false;
    }
  }

  Future<void> refreshFrame() async {
    if (frameRequestInFlight) return;

    final live = liveStatus ?? {};

    if (live['camera_enabled'] != true ||
        cameraStatus?['camera_running'] != true) {
      if (frameBytes != null && mounted) {
        setState(() {
          frameBytes = null;
        });
      }
      return;
    }

    if (!previewVisible && !WindowService.miniMode) {
      return;
    }

    frameRequestInFlight = true;

    try {
      final bytes = await apiService.getCameraFrame();

      if (!mounted) return;

      if (bytes != null) {
        setState(() {
          frameBytes = bytes;
        });

        unawaited(updateNativeMiniCamera(frame: bytes));
      }
    } catch (_) {
    } finally {
      frameRequestInFlight = false;
    }
  }

  Future<void> updateNativeMiniCamera({Uint8List? frame}) async {
    if (!WindowService.miniMode) return;

    final live = liveStatus ?? {};
    final camera = cameraStatus ?? {};

    await WindowService.updateMiniCamera(
      frameBytes: frame ?? frameBytes,
      focusScore: number(live['focus_score']),
      isFocused: camera['latest_is_focused'] == true,
      cameraRunning: camera['camera_running'] == true,
      statusLabel: focusStatusLabel(live, compact: true),
    );
  }

  bool get canShowAutomaticMiniCamera {
    final live = liveStatus ?? {};
    final camera = cameraStatus ?? {};

    return live['camera_enabled'] == true &&
        camera['camera_running'] == true &&
        previewVisible &&
        !autoMiniSuppressed;
  }

  Future<void> syncAutomaticMiniCamera() async {
    if (!canShowAutomaticMiniCamera) {
      if (WindowService.miniMode && autoMiniMode) {
        await WindowService.exitMiniCameraMode();
      }
      autoMiniMode = false;
      return;
    }

    final foreground = await WindowService.isAppForeground();

    if (foreground) {
      if (WindowService.miniMode && autoMiniMode) {
        await WindowService.exitMiniCameraMode();
      }
      autoMiniMode = false;
      return;
    }

    if (!WindowService.miniMode) {
      autoMiniMode = true;
      await WindowService.enterMiniCameraMode();
      await refreshFrame();
    } else {
      autoMiniMode = true;
    }
  }

  @override
  void onWindowBlur() {
    syncAutomaticMiniCamera();
  }

  @override
  void onWindowMinimize() {
    syncAutomaticMiniCamera();
  }

  @override
  void onWindowFocus() {
    syncAutomaticMiniCamera();
  }

  @override
  void onWindowRestore() {
    syncAutomaticMiniCamera();
  }

  String focusStatusLabel(Map<String, dynamic> live, {bool compact = false}) {
    final presentation = focusPresentation(live);

    if (!previewVisible &&
        !compact &&
        live['camera_enabled'] == true &&
        cameraStatus?['camera_running'] == true) {
      return 'Kamera gizli, analiz devam ediyor';
    }

    return compact && presentation.key == 'away'
        ? 'Beklemede'
        : presentation.title;
  }

  String sessionBadgeText(Map<String, dynamic> live) {
    if (live['session_paused'] == true) return 'Mola modu';
    if (live['away_active'] == true) return 'Beklemede';
    return 'Oturum aktif';
  }

  _FocusPresentation focusPresentation(Map<String, dynamic> live) {
    final cameraEnabled = live['camera_enabled'] == true;
    final cameraRunning = cameraStatus?['camera_running'] == true;
    final away = live['away_active'] == true;
    final breakActive = live['session_paused'] == true;
    final noFace =
        live['focus_state'] == 'no_face' ||
        live['focus_category'] == 'no_face' ||
        cameraStatus?['latest_face_found'] == false;

    if (breakActive) {
      return _FocusPresentation(
        key: 'break',
        title: 'Mola aktif',
        subtitle: 'Odak analizi duraklatıldı',
        color: AppTheme.textMuted,
      );
    }

    if (away) {
      return _FocusPresentation(
        key: 'away',
        title: 'Ekran başında değilsin',
        subtitle: 'Oturum beklemeye alındı',
        color: AppTheme.textMuted,
      );
    }

    if (!cameraEnabled || !cameraRunning) {
      return _FocusPresentation(
        key: 'camera_off',
        title: 'Kamera kapalı — süre takibi aktif',
        subtitle: 'Süre ve mola akışı aktif',
        color: AppTheme.calmBlue,
      );
    }

    if (noFace) {
      return _FocusPresentation(
        key: 'no_face',
        title: 'Kişi algılanmadı',
        subtitle: 'Ekran başında olup olmadığın doğrulanıyor',
        color: AppTheme.textMuted,
      );
    }

    final backendCategory = '${live['focus_category'] ?? ''}';
    final score = number(live['focus_score']);
    final category = backendCategory.isNotEmpty
        ? backendCategory
        : score >= 85
        ? 'excellent'
        : score >= 70
        ? 'balanced'
        : score >= 50
        ? 'fluctuating'
        : score >= 30
        ? 'drop'
        : 'severe_drop';

    if (category == 'excellent') {
      return _FocusPresentation(
        key: 'excellent',
        title: 'Odak çok iyi',
        subtitle: 'Ritmin güçlü görünüyor',
        color: AppTheme.focusStrongGreen,
      );
    }

    if (category == 'balanced') {
      return _FocusPresentation(
        key: 'balanced',
        title: 'Odak dengeli',
        subtitle: 'Çalışma ritmin stabil',
        color: AppTheme.focusGreen,
      );
    }

    if (category == 'fluctuating') {
      return _FocusPresentation(
        key: 'fluctuating',
        title: 'Odak dalgalanıyor',
        subtitle: 'Kısa dalgalanmalar var',
        color: AppTheme.focusAmber,
      );
    }

    if (category == 'drop') {
      return _FocusPresentation(
        key: 'drop',
        title: 'Odak düşüşü var',
        subtitle: 'Kısa bir mola iyi gelebilir',
        color: AppTheme.focusOrange,
      );
    }

    return _FocusPresentation(
      key: 'severe_drop',
      title: 'Odak ciddi şekilde düştü',
      subtitle: 'Mola vermek iyi olabilir',
      color: AppTheme.dangerRed,
    );
  }

  void recordFocusWindowSample(
    Map<String, dynamic> live,
    Map<String, dynamic> camera,
  ) {
    final cameraActive =
        live['camera_enabled'] == true && camera['camera_running'] == true;
    final paused = live['session_paused'] == true;
    final away = live['away_active'] == true;
    final now = DateTime.now();

    focusWindowSamples.removeWhere(
      (sample) =>
          now.difference(sample.timestamp) > const Duration(seconds: 90),
    );

    if (!cameraActive || paused || away) return;

    final category = '${live['focus_category'] ?? ''}';

    if (category == 'camera_off' ||
        category == 'break' ||
        category == 'away' ||
        category == 'no_face') {
      return;
    }

    focusWindowSamples.add(
      _FocusWindowSample(
        timestamp: now,
        score: number(live['focus_score']),
        category: category,
      ),
    );
  }

  _FocusWindowStats focusWindowStats() {
    final now = DateTime.now();

    focusWindowSamples.removeWhere(
      (sample) =>
          now.difference(sample.timestamp) > const Duration(seconds: 90),
    );

    if (focusWindowSamples.isEmpty) {
      return const _FocusWindowStats.empty();
    }

    final count = focusWindowSamples.length;
    final windowSeconds = count <= 1
        ? 0.0
        : focusWindowSamples.last.timestamp
                  .difference(focusWindowSamples.first.timestamp)
                  .inMilliseconds /
              1000;
    final average =
        focusWindowSamples.fold<double>(0, (sum, item) => sum + item.score) /
        count;
    final severeCount = focusWindowSamples
        .where((item) => item.category == 'severe_drop' || item.score < 30)
        .length;
    final dropCount = focusWindowSamples
        .where(
          (item) =>
              item.category == 'drop' ||
              item.category == 'severe_drop' ||
              item.score < 50,
        )
        .length;
    final fluctuatingCount = focusWindowSamples
        .where(
          (item) =>
              item.category == 'fluctuating' ||
              item.category == 'drop' ||
              item.category == 'severe_drop' ||
              item.score < 70,
        )
        .length;
    final variance =
        focusWindowSamples.fold<double>(
          0,
          (sum, item) => sum + math.pow(item.score - average, 2).toDouble(),
        ) /
        count;

    return _FocusWindowStats(
      count: count,
      averageScore: average,
      severeSeconds: severeCount,
      dropSeconds: dropCount,
      fluctuatingSeconds: fluctuatingCount,
      standardDeviation: math.sqrt(variance),
      windowSeconds: windowSeconds,
    );
  }

  bool isFocusSuggestionReason(String reason) {
    return reason == 'focus_drop' ||
        reason == 'focus_fluctuation' ||
        reason == 'severe_focus_drop';
  }

  bool isReasonCoolingDown(String reason) {
    final until = notificationCooldownUntil[reason];

    if (until == null) return false;

    if (DateTime.now().isBefore(until)) {
      return true;
    }

    notificationCooldownUntil.remove(reason);
    return false;
  }

  void setReasonCooldown(String reason, Duration duration) {
    notificationCooldownUntil[reason] = DateTime.now().add(duration);
  }

  void logNotificationEvent(String event, {required String reason}) {
    // Product build keeps notification decisions quiet; actions are persisted
    // through the backend notification action log where needed.
  }

  Future<void> recordNotificationSuppressed(
    String reason,
    String detail,
  ) async {
    final suppressionKey = 'suppressed_$reason';

    if (isReasonCoolingDown(suppressionKey)) return;

    setReasonCooldown(suppressionKey, const Duration(minutes: 1));
    logNotificationEvent(
      detail == 'cooldown'
          ? 'notification_suppressed_by_cooldown'
          : 'notification_suppressed',
      reason: reason,
    );

    try {
      await apiService.recordNotificationAction(
        actionType: 'notification_suppressed',
        reason: reason,
      );
    } catch (_) {}
  }

  bool focusIssueRecovered(Map<String, dynamic> live) {
    final focus = focusPresentation(live);

    if (focus.key != 'balanced' && focus.key != 'excellent') return false;

    if (recentFocusSamplesRecovered()) return true;

    final stats = focusWindowStats();

    if (stats.count == 0) return true;

    final dropRatio = stats.dropSeconds / stats.count;
    final affectedRatio = stats.fluctuatingSeconds / stats.count;

    return stats.averageScore >= 68 &&
        dropRatio <= 0.20 &&
        affectedRatio <= 0.35;
  }

  bool recentFocusSamplesRecovered() {
    final now = DateTime.now();
    final recent = focusWindowSamples
        .where(
          (sample) =>
              now.difference(sample.timestamp) <= const Duration(seconds: 8),
        )
        .toList();

    if (recent.length < 4) return false;

    final average =
        recent.fold<double>(0, (sum, item) => sum + item.score) / recent.length;
    final lowCount = recent
        .where(
          (item) =>
              item.category == 'drop' ||
              item.category == 'severe_drop' ||
              item.score < 60,
        )
        .length;

    return average >= 72 && lowCount <= 1;
  }

  bool suggestionStillRelevant(
    _BreakSuggestion suggestion,
    Map<String, dynamic> live,
  ) {
    if (!isFocusSuggestionReason(suggestion.reason)) return true;

    final cameraActive =
        live['camera_enabled'] == true &&
        cameraStatus?['camera_running'] == true;

    if (!cameraActive || live['session_paused'] == true) return false;

    return !focusIssueRecovered(live);
  }

  Future<bool> clearRecoveredFocusSuggestion(Map<String, dynamic> live) async {
    final suggestion = activeSuggestion;

    if (suggestion == null || !isFocusSuggestionReason(suggestion.reason)) {
      return false;
    }

    if (!focusIssueRecovered(live)) return false;

    bannerCollapseTimer?.cancel();
    await NotificationService.cancelSuggestionNotification();

    if (mounted) {
      setState(() {
        activeSuggestion = null;
        suggestionCollapsed = false;
      });
    }

    setReasonCooldown(suggestion.reason, const Duration(seconds: 45));
    await recordNotificationSuppressed(suggestion.reason, 'recovered');
    return true;
  }

  Duration cooldownForSuggestion(_BreakSuggestion suggestion) {
    if (isFocusSuggestionReason(suggestion.reason)) {
      return const Duration(minutes: 2);
    }

    if (suggestion.reason == 'strong_focus_continue') {
      return const Duration(minutes: 10);
    }

    return const Duration(minutes: 4);
  }

  Future<void> evaluateBreakSuggestion(Map<String, dynamic> live) async {
    if (live['session_active'] != true ||
        live['session_paused'] == true ||
        live['away_active'] == true) {
      await clearSuggestionState(cancelDesktop: true);
      return;
    }

    if (decisionPanelVisible) return;
    if (await clearRecoveredFocusSuggestion(live)) return;
    if (activeSuggestion != null) return;
    if (snoozedSuggestion != null) return;

    if (cooldownUntil != null && DateTime.now().isBefore(cooldownUntil!)) {
      return;
    }

    final suggestion = buildSuggestion(live);

    if (suggestion == null) return;
    if (!suggestionAllowed(suggestion)) {
      await recordNotificationSuppressed(suggestion.reason, 'settings');
      return;
    }

    if (isReasonCoolingDown(suggestion.reason)) {
      await recordNotificationSuppressed(suggestion.reason, 'cooldown');
      return;
    }

    activeSuggestion = suggestion;
    suggestedBreakMinutes = suggestion.suggestedBreakMinutes;
    selectedBreakMinutes = suggestion.suggestedBreakMinutes;
    suggestionCollapsed = false;

    final shown = await deliverSuggestion(suggestion);

    if (shown) {
      setReasonCooldown(suggestion.reason, cooldownForSuggestion(suggestion));
      await recordSuggestionShown(suggestion);
    } else if (mounted) {
      setState(() {
        activeSuggestion = null;
        suggestionCollapsed = false;
      });
    }
  }

  Future<void> recordSuggestionShown(_BreakSuggestion suggestion) async {
    await apiService.recordNotificationAction(
      actionType: 'notification_shown',
      reason: suggestion.reason,
      suggestedBreakMinutes: suggestion.suggestedBreakMinutes,
    );

    if (suggestion.reason == 'planned_break') {
      if (suggestion.plannedBlock != null) {
        promptedPomodoroBlocks.add(suggestion.plannedBlock!);
      }

      logNotificationEvent('planned_break_due', reason: suggestion.reason);
      await apiService.recordNotificationAction(
        actionType: 'planned_break_notification',
        reason: suggestion.reason,
        suggestedBreakMinutes: suggestion.suggestedBreakMinutes,
      );
    } else if (suggestion.reason == 'focus_fluctuation') {
      logNotificationEvent(
        'focus_fluctuation_detected',
        reason: suggestion.reason,
      );
      await apiService.recordNotificationAction(
        actionType: 'focus_fluctuation_notification',
        reason: suggestion.reason,
        suggestedBreakMinutes: suggestion.suggestedBreakMinutes,
      );
    } else if (suggestion.reason == 'focus_drop' ||
        suggestion.reason == 'severe_focus_drop') {
      logNotificationEvent(
        suggestion.reason == 'severe_focus_drop'
            ? 'severe_focus_drop_detected'
            : 'focus_drop_detected',
        reason: suggestion.reason,
      );
      await apiService.recordNotificationAction(
        actionType: 'focus_drop_notification',
        reason: suggestion.reason,
        suggestedBreakMinutes: suggestion.suggestedBreakMinutes,
      );
    } else if (suggestion.reason == 'long_work') {
      logNotificationEvent(
        'long_work_without_break',
        reason: suggestion.reason,
      );
    }
  }

  bool suggestionAllowed(_BreakSuggestion suggestion) {
    final settings = AppSettingsService.current;

    if (!settings.notificationsEnabled) {
      return false;
    }

    if (isFocusSuggestionReason(suggestion.reason)) {
      return settings.liveFocusNotificationsEnabled;
    }

    return settings.breakRemindersEnabled;
  }

  Future<bool> deliverSuggestion(_BreakSuggestion suggestion) async {
    final focused = await WindowService.isAppForeground();

    if (!mounted) return false;

    if (focused) {
      logNotificationEvent(
        'notification_decision_foreground',
        reason: suggestion.reason,
      );
      await NotificationService.cancelSuggestionNotification();
      startBannerCollapseTimer();
      setState(() {});
      return true;
    }

    logNotificationEvent(
      'notification_decision_desktop',
      reason: suggestion.reason,
    );

    return NotificationService.showSessionSuggestionNotification(
      title: suggestion.title,
      body: suggestion.message,
      payload: suggestion.reason,
      focusDrop: isFocusSuggestionReason(suggestion.reason),
      preferContinue: suggestion.preferContinue,
    );
  }

  _BreakSuggestion? buildSuggestion(Map<String, dynamic> live) {
    final cameraEnabled =
        live['camera_enabled'] == true &&
        cameraStatus?['camera_running'] == true;
    final mode = '${live['session_mode'] ?? 'classic'}';
    final activeSeconds = number(live['active_seconds']);
    final planned = mode == 'flow' ? null : plannedBreakSuggestion(live);
    final focus = focusPresentation(live);
    final stats = focusWindowStats();

    if (planned != null) {
      if (!cameraEnabled) {
        return planned;
      }

      if (focus.key == 'no_face' ||
          focus.key == 'away' ||
          focus.key == 'break') {
        return null;
      }

      if (focus.key == 'drop' || focus.key == 'severe_drop') {
        return _BreakSuggestion(
          reason: 'planned_break',
          title: 'Odak ritmi düşüyor',
          message:
              'Odak seviyende belirgin düşüş var.\nKısa bir mola şimdi daha iyi olabilir.',
          suggestedBreakMinutes: planned.suggestedBreakMinutes,
          breakType: planned.breakType,
          plannedBlock: planned.plannedBlock,
        );
      }

      if (focus.key == 'fluctuating') {
        return _BreakSuggestion(
          reason: 'planned_break',
          title: 'Odak ritminde dalgalanma var',
          message:
              'Çalışma ritmin dalgalanıyor.\nKısa bir ara toparlanmana yardımcı olabilir.',
          suggestedBreakMinutes: planned.suggestedBreakMinutes,
          breakType: planned.breakType,
          plannedBlock: planned.plannedBlock,
        );
      }

      return _BreakSuggestion(
        reason: 'planned_break',
        title: 'Ritmini koruyabilirsin',
        message:
            'Odak seviyen iyi görünüyor.\nİstersen biraz daha devam edebilirsin.',
        suggestedBreakMinutes: planned.suggestedBreakMinutes,
        breakType: planned.breakType,
        preferContinue: true,
        plannedBlock: planned.plannedBlock,
      );
    }

    if (cameraEnabled) {
      final rollingSuggestion = rollingFocusSuggestion(
        stats: stats,
        mode: mode,
        currentFocusKey: focus.key,
      );

      if (rollingSuggestion != null) {
        return rollingSuggestion;
      }
    }

    if (activeSeconds >= 50 * 60) {
      return const _BreakSuggestion(
        reason: 'long_work',
        title: 'Ara verme zamanı',
        message:
            'Uzun süredir ara vermeden çalışıyorsun.\nKısa bir mola ritmini koruyabilir.',
        suggestedBreakMinutes: 5,
        breakType: 'önerilen',
      );
    }

    if (cameraEnabled &&
        mode == 'flow' &&
        activeSeconds >= 45 * 60 &&
        stats.count >= 45 &&
        stats.averageScore >= 82) {
      return const _BreakSuggestion(
        reason: 'strong_focus_continue',
        title: 'Ritmin güçlü görünüyor',
        message:
            'Çalışma ritmin dengeli ilerliyor.\nİstersen biraz daha devam edebilirsin.',
        suggestedBreakMinutes: 5,
        breakType: 'isteğe bağlı',
        preferContinue: true,
      );
    }

    return null;
  }

  _BreakSuggestion? rollingFocusSuggestion({
    required _FocusWindowStats stats,
    required String mode,
    required String currentFocusKey,
  }) {
    if (currentFocusKey == 'no_face' ||
        currentFocusKey == 'away' ||
        currentFocusKey == 'break' ||
        currentFocusKey == 'camera_off') {
      return null;
    }

    if (stats.windowSeconds < 55 || stats.count < 40) return null;

    final currentRecovered =
        currentFocusKey == 'balanced' || currentFocusKey == 'excellent';
    final currentShowsIssue =
        currentFocusKey == 'fluctuating' ||
        currentFocusKey == 'drop' ||
        currentFocusKey == 'severe_drop';
    final severeRatio = stats.severeSeconds / stats.count;
    final dropRatio = stats.dropSeconds / stats.count;
    final affectedRatio = stats.fluctuatingSeconds / stats.count;

    if (currentRecovered) return null;
    if (!currentShowsIssue && stats.averageScore >= 55) return null;

    if (severeRatio >= 0.35 || (stats.averageScore < 35 && dropRatio >= 0.45)) {
      return const _BreakSuggestion(
        reason: 'severe_focus_drop',
        title: 'Odak ciddi şekilde düştü',
        message:
            'Odak seviyen bir süredir çok düşük.\nOturumu toparlamak için kısa bir mola iyi olabilir.',
        suggestedBreakMinutes: 5,
        breakType: 'önerilen',
      );
    }

    if (stats.averageScore < 55 && dropRatio >= 0.45) {
      return const _BreakSuggestion(
        reason: 'focus_drop',
        title: 'Odak ritminde düşüş var',
        message:
            'Odak seviyen bir süredir düşük seyrediyor.\nKısa bir ara şimdi daha faydalı olabilir.',
        suggestedBreakMinutes: 5,
        breakType: 'önerilen',
      );
    }

    if (stats.averageScore >= 55 &&
        stats.averageScore < 72 &&
        affectedRatio >= 0.50 &&
        stats.standardDeviation >= 8) {
      return const _BreakSuggestion(
        reason: 'focus_fluctuation',
        title: 'Odak ritminde dalgalanma var',
        message:
            'Son anda ritmin belirgin dalgalandı.\nKısa bir ara toparlanmana yardımcı olabilir.',
        suggestedBreakMinutes: 5,
        breakType: 'önerilen',
      );
    }

    if (mode == 'flow' &&
        affectedRatio >= 0.50 &&
        stats.standardDeviation >= 8 &&
        stats.averageScore < 72) {
      return const _BreakSuggestion(
        reason: 'focus_fluctuation',
        title: 'Akış ritmi dalgalanıyor',
        message:
            'Odak ritminde belirgin dalgalanma var.\nKısa bir ara akışı toparlayabilir.',
        suggestedBreakMinutes: 5,
        breakType: 'önerilen',
      );
    }

    return null;
  }

  _BreakSuggestion? plannedBreakSuggestion(Map<String, dynamic> live) {
    final settings = live['pomodoro_settings'];

    if (settings is! Map) return null;

    final workMinutes = number(settings['work_minutes']).round();

    if (workMinutes <= 0) return null;

    final activeSeconds = number(live['active_seconds']);
    final block = activeSeconds ~/ (workMinutes * 60);

    if (block <= 0 || promptedPomodoroBlocks.contains(block)) return null;

    final boundary = block * workMinutes * 60;
    final nearBoundary = activeSeconds - boundary;

    if (nearBoundary < 0 || nearBoundary > 75) return null;

    final longEvery = number(settings['long_break_every']).round();
    final longMinutes = number(settings['long_break_minutes']).round();
    final shortMinutes = number(settings['short_break_minutes']).round();
    final useLongBreak = longEvery > 0 && block % longEvery == 0;
    final breakMinutes = useLongBreak
        ? (longMinutes <= 0 ? 15 : longMinutes)
        : (shortMinutes <= 0 ? 5 : shortMinutes);

    return _BreakSuggestion(
      reason: 'planned_break',
      title: 'Mola zamanı geldi',
      message: 'Mola zamanına geldin.\nİstersen kısa bir ara verebilirsin.',
      suggestedBreakMinutes: breakMinutes,
      breakType: useLongBreak ? 'uzun planlı' : 'planlı',
      plannedBlock: block,
    );
  }

  _BreakSuggestion? suggestionFromNotificationPayload(
    String payload,
    Map<String, dynamic> live,
  ) {
    if (payload == 'planned_break' || payload == 'break_time') {
      return plannedBreakSuggestion(live);
    }

    if (payload == 'focus_fluctuation') {
      return const _BreakSuggestion(
        reason: 'focus_fluctuation',
        title: 'Kısa bir mola iyi gelebilir',
        message:
            'Odak ritminde dalgalanmalar var.\nKısa bir ara iyi gelebilir.',
        suggestedBreakMinutes: 5,
        breakType: 'önerilen',
      );
    }

    if (payload == 'focus_drop') {
      return const _BreakSuggestion(
        reason: 'focus_drop',
        title: 'Kısa bir mola iyi gelebilir',
        message:
            'Odak seviyende düşüş görünüyor.\nPlanlı molaya daha zaman olsa da kısa bir ara faydalı olabilir.',
        suggestedBreakMinutes: 5,
        breakType: 'önerilen',
      );
    }

    if (payload == 'severe_focus_drop') {
      return const _BreakSuggestion(
        reason: 'severe_focus_drop',
        title: 'Kısa bir mola iyi gelebilir',
        message:
            'Odak seviyen belirgin şekilde düştü.\nKısa bir mola vermek iyi olabilir.',
        suggestedBreakMinutes: 5,
        breakType: 'önerilen',
      );
    }

    if (payload == 'long_work') {
      return const _BreakSuggestion(
        reason: 'long_work',
        title: 'Uzun çalışma bloğu',
        message:
            'Uzun süredir ara vermeden çalışıyorsun.\nKısa bir mola iyi gelebilir.',
        suggestedBreakMinutes: 5,
        breakType: 'önerilen',
      );
    }

    if (payload == 'strong_focus_continue') {
      return const _BreakSuggestion(
        reason: 'strong_focus_continue',
        title: 'Ritmin güçlü görünüyor',
        message:
            'Çalışma ritmin dengeli ilerliyor.\nİstersen biraz daha devam edebilirsin.',
        suggestedBreakMinutes: 5,
        breakType: 'isteğe bağlı',
        preferContinue: true,
      );
    }

    return null;
  }

  void startBannerCollapseTimer() {
    bannerCollapseTimer?.cancel();
    bannerCollapseTimer = Timer(const Duration(seconds: 12), () {
      if (!mounted || activeSuggestion == null || decisionPanelVisible) return;

      setState(() {
        suggestionCollapsed = true;
      });
    });
  }

  void showInlineToast({
    required String title,
    required String message,
    String tone = 'info',
  }) {
    toastTimer?.cancel();

    if (!mounted) return;

    setState(() {
      toastTitle = title;
      toastMessage = message;
      toastTone = tone;
    });

    toastTimer = Timer(Duration(seconds: tone == 'critical' ? 8 : 5), () {
      if (!mounted) return;

      setState(() {
        toastTitle = null;
        toastMessage = null;
      });
    });
  }

  Future<void> handleDesktopNotificationAction(String action) async {
    if (!mounted) return;

    await WindowService.bringToFront();
    await refreshStatus();

    if (!mounted) return;

    final live = liveStatus ?? {};

    if (live['session_active'] != true) {
      await clearSuggestionState(cancelDesktop: true);
      return;
    }

    final payload = NotificationService.lastActionPayload;
    final restoredSuggestion =
        activeSuggestion ??
        suggestionFromNotificationPayload(payload, liveStatus ?? {});

    if (restoredSuggestion != null &&
        !suggestionStillRelevant(restoredSuggestion, live)) {
      await clearSuggestionState(cancelDesktop: true);
      await recordNotificationSuppressed(
        restoredSuggestion.reason,
        'recovered',
      );
      return;
    }

    if (restoredSuggestion != null && activeSuggestion == null) {
      setState(() {
        activeSuggestion = restoredSuggestion;
        selectedBreakMinutes = restoredSuggestion.suggestedBreakMinutes;
        suggestedBreakMinutes = restoredSuggestion.suggestedBreakMinutes;
        suggestionCollapsed = false;
      });
    }

    if (action == 'accept_break') {
      openDecisionPanel();
      return;
    }

    if (action == 'snooze_break') {
      await snoozeCurrentSuggestion();
      return;
    }

    if (action == 'decline_break') {
      await declineCurrentSuggestion();
      return;
    }

    if (action == 'return_work') {
      if (live['session_paused'] == true) {
        await endBreak();
      }
      return;
    }

    if (action == 'extend_break') {
      if (live['session_paused'] == true) {
        await extendBreak();
      }
      return;
    }

    if (action == 'open_session') {
      if (restoredSuggestion != null) {
        openDecisionPanel();
        return;
      }

      await refreshStatus();
    }
  }

  Future<void> clearSuggestionState({required bool cancelDesktop}) async {
    final hadSuggestion =
        activeSuggestion != null ||
        snoozedSuggestion != null ||
        decisionPanelVisible ||
        suggestionCollapsed;

    snoozeTimer?.cancel();
    bannerCollapseTimer?.cancel();

    if (cancelDesktop) {
      await NotificationService.cancelSuggestionNotification();
    }

    if (!mounted || !hadSuggestion) return;

    setState(() {
      activeSuggestion = null;
      snoozedSuggestion = null;
      decisionPanelVisible = false;
      suggestionCollapsed = false;
      cooldownUntil = null;
    });
  }

  double number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  String clockText(dynamic seconds) {
    final total = math.max(0, number(seconds).round());
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final secs = total % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String modeName(dynamic mode) {
    if (mode == 'classic') return 'Klasik Pomodoro';
    if (mode == 'adaptive') return 'Adaptif AI';
    if (mode == 'flow') return 'Akış';
    return 'Oturum';
  }

  Color focusColor(Map<String, dynamic> live) {
    return focusPresentation(live).color;
  }

  int wholeMinutes(dynamic seconds) {
    return math.max(0, (number(seconds) / 60).floor());
  }

  int remainingMinutes(double seconds) {
    if (seconds <= 0) return 0;
    return (seconds / 60).ceil();
  }

  _PlanOverviewData planOverviewData(Map<String, dynamic> live) {
    final mode = '${live['session_mode'] ?? 'classic'}';
    final activeSeconds = number(live['active_seconds']);
    final plannedSeconds = number(live['planned_total_minutes']) * 60;
    final cameraEnabled = live['camera_enabled'] == true;
    final cameraRunning = cameraStatus?['camera_running'] == true;
    final settings = live['pomodoro_settings'];
    final statusMessage = cameraEnabled && cameraRunning
        ? 'Canlı analiz açık'
        : 'Zaman bazlı odak oturumu aktif';
    final todaySeconds = number(live['today_active_seconds']) > 0
        ? number(live['today_active_seconds'])
        : activeSeconds;

    if (settings is Map) {
      final workMinutes = math.max(1, number(settings['work_minutes']).round());
      final shortBreakMinutes = math.max(
        1,
        number(settings['short_break_minutes']).round(),
      );
      final longBreakMinutes = math.max(
        shortBreakMinutes,
        number(settings['long_break_minutes']).round(),
      );
      final longBreakEvery = math.max(
        1,
        number(settings['long_break_every']).round(),
      );
      final cycles = math.max(1, number(settings['cycles']).round());
      final workSeconds = workMinutes * 60.0;
      final completedCycles = math.min(cycles, activeSeconds ~/ workSeconds);
      final paused = live['session_paused'] == true;
      final elapsedInBlock = activeSeconds % workSeconds;
      final remainingToBreak = completedCycles >= cycles
          ? 0.0
          : workSeconds - elapsedInBlock;
      final currentCycle = math.min(cycles, completedCycles + (paused ? 0 : 1));
      final blockMinute = math.min(
        workMinutes,
        math.max(1, (elapsedInBlock / 60).floor() + 1),
      );
      final nextBreakCycle = math.min(cycles, completedCycles + 1);
      final nextBreakIsLong =
          longBreakEvery > 0 && nextBreakCycle % longBreakEvery == 0;
      final longBreakInfo = paused
          ? ('${live['current_break_type'] ?? ''}'.contains('uzun')
                ? 'Şu an uzun mola'
                : 'Şu an kısa mola')
          : nextBreakIsLong
          ? 'Sıradaki mola uzun mola'
          : 'Uzun mola ${longBreakEvery - (completedCycles % longBreakEvery)} tur sonra';

      return _PlanOverviewData(
        title: 'Pomodoro planı',
        status: statusMessage,
        mainTimeLabel: 'Ana süre',
        mainTimeValue: clockText(activeSeconds),
        nextBreak: completedCycles >= cycles
            ? 'Planlanan çalışma blokları tamamlandı'
            : paused
            ? 'Mola modu aktif'
            : 'Sonraki mola: ${remainingMinutes(remainingToBreak)} dk sonra',
        blockInfo: paused
            ? 'Mola bloğu devam ediyor'
            : '$workMinutes dakikalık çalışma bloğunun $blockMinute. dakikası',
        roundInfo: '$completedCycles/$cycles tur tamamlandı',
        longBreakInfo: longBreakInfo,
        dailyFocus: 'Bugünkü odak: ${clockText(todaySeconds)}',
        progress: completedCycles >= cycles
            ? 1.0
            : (elapsedInBlock / workSeconds).clamp(0, 1).toDouble(),
        segments: pomodoroTrackSegments(
          cycles: cycles,
          completedCycles: completedCycles,
          currentCycle: currentCycle,
          paused: paused,
          workMinutes: workMinutes,
          shortBreakMinutes: shortBreakMinutes,
          longBreakMinutes: longBreakMinutes,
          longBreakEvery: longBreakEvery,
        ),
      );
    }

    final checkpointSeconds = plannedSeconds > 0
        ? math.min(plannedSeconds, 25 * 60).toDouble()
        : 25 * 60.0;
    final elapsedInCheckpoint = checkpointSeconds <= 0
        ? 0.0
        : activeSeconds % checkpointSeconds;
    final remainingToCheckpoint = checkpointSeconds - elapsedInCheckpoint;
    final plannedMinutes = number(live['planned_total_minutes']).round();
    final checkpointMinutes = math.max(1, (checkpointSeconds / 60).round());

    return _PlanOverviewData(
      title: mode == 'flow' ? 'Akış planı' : 'Odak planı',
      status: statusMessage,
      mainTimeLabel: 'Ana süre',
      mainTimeValue: clockText(activeSeconds),
      nextBreak: mode == 'flow'
          ? 'Mola, odak ritmine göre önerilecek'
          : 'Sonraki mola kontrolü: ${remainingMinutes(remainingToCheckpoint)} dk sonra',
      blockInfo:
          '$checkpointMinutes dakikalık odak bloğunun ${math.max(1, (elapsedInCheckpoint / 60).floor() + 1)}. dakikası',
      roundInfo: plannedMinutes > 0
          ? '${wholeMinutes(activeSeconds)} / $plannedMinutes dk planlandı'
          : 'Süre takibi aktif',
      longBreakInfo: mode == 'flow'
          ? 'Sabit pomodoro planı yok'
          : 'Zaman bazlı mola kontrolü aktif',
      dailyFocus: 'Bugünkü odak: ${clockText(todaySeconds)}',
      progress: checkpointSeconds <= 0
          ? 0.0
          : (elapsedInCheckpoint / checkpointSeconds).clamp(0, 1).toDouble(),
      segments: [
        _PlanTrackSegment(
          label: 'Geçen',
          flex: math.max(1, activeSeconds.round()),
          color: AppTheme.calmBlue,
          active: true,
        ),
        _PlanTrackSegment(
          label: 'Kalan',
          flex: math.max(
            1,
            math.max(0, plannedSeconds - activeSeconds).round(),
          ),
          color: AppTheme.textMuted,
          active: false,
        ),
      ],
    );
  }

  List<_PlanTrackSegment> pomodoroTrackSegments({
    required int cycles,
    required int completedCycles,
    required int currentCycle,
    required bool paused,
    required int workMinutes,
    required int shortBreakMinutes,
    required int longBreakMinutes,
    required int longBreakEvery,
  }) {
    final segments = <_PlanTrackSegment>[];

    for (var cycle = 1; cycle <= cycles; cycle++) {
      final isCurrentWork = !paused && currentCycle == cycle;
      final workDone = completedCycles >= cycle;

      segments.add(
        _PlanTrackSegment(
          label: 'Çalışma $cycle',
          flex: workMinutes,
          color: workDone || isCurrentWork
              ? AppTheme.focusGreen
              : AppTheme.textMuted,
          active: isCurrentWork,
        ),
      );

      if (cycle == cycles) continue;

      final isLong = longBreakEvery > 0 && cycle % longBreakEvery == 0;
      final isCurrentBreak = paused && completedCycles == cycle;

      segments.add(
        _PlanTrackSegment(
          label: isLong ? 'Uzun mola' : 'Kısa mola',
          flex: isLong ? longBreakMinutes : shortBreakMinutes,
          color: isCurrentBreak ? AppTheme.warningOrange : AppTheme.textMuted,
          active: isCurrentBreak,
        ),
      );
    }

    return segments;
  }

  void openDecisionPanel() {
    final suggestion = activeSuggestion;

    if (suggestion == null) return;

    bannerCollapseTimer?.cancel();

    setState(() {
      decisionPanelVisible = true;
      suggestionCollapsed = false;
      selectedBreakMinutes = suggestion.suggestedBreakMinutes;
    });
  }

  Future<void> startSelectedBreak() async {
    final suggestion =
        activeSuggestion ??
        const _BreakSuggestion(
          reason: 'manual',
          title: 'Manuel mola',
          message: 'Manuel mola başlatılıyor.',
          suggestedBreakMinutes: 5,
          breakType: 'manuel',
        );

    snoozeTimer?.cancel();
    await NotificationService.cancelSuggestionNotification();

    await apiService.acceptBreak(
      reason: suggestion.reason,
      suggestedBreakMinutes: suggestion.suggestedBreakMinutes,
      selectedBreakMinutes: selectedBreakMinutes,
    );

    await apiService.startBreak(
      reason: suggestion.reason,
      selectedBreakMinutes: selectedBreakMinutes,
      suggestedBreakMinutes: suggestion.suggestedBreakMinutes,
      breakType: suggestion.breakType,
    );

    if (!mounted) return;

    setState(() {
      snoozedSuggestion = null;
      activeSuggestion = null;
      decisionPanelVisible = false;
      suggestionCollapsed = false;
      cooldownUntil = null;
      breakReadyNotified = false;
    });

    await refreshStatus();
  }

  Future<void> startManualBreak() async {
    setState(() {
      activeSuggestion = const _BreakSuggestion(
        reason: 'manual',
        title: 'Manuel mola',
        message: 'Mola süresini seçip başlatabilirsin.',
        suggestedBreakMinutes: 5,
        breakType: 'manuel',
      );
      selectedBreakMinutes = 5;
      suggestedBreakMinutes = 5;
      decisionPanelVisible = true;
      suggestionCollapsed = false;
      breakReadyNotified = false;
    });
  }

  Future<void> snoozeCurrentSuggestion() async {
    final suggestion = activeSuggestion;

    if (suggestion == null) return;

    snoozeTimer?.cancel();
    bannerCollapseTimer?.cancel();

    await apiService.snoozeBreak(
      snoozeMinutes: 5,
      reason: suggestion.reason,
      suggestedBreakMinutes: suggestion.suggestedBreakMinutes,
    );

    await NotificationService.cancelSuggestionNotification();

    if (!mounted) return;

    setState(() {
      snoozedSuggestion = suggestion;
      activeSuggestion = null;
      decisionPanelVisible = false;
      suggestionCollapsed = false;
      cooldownUntil = DateTime.now().add(const Duration(minutes: 5));
    });
    setReasonCooldown(suggestion.reason, const Duration(minutes: 5));

    snoozeTimer = Timer(const Duration(minutes: 5), () async {
      if (!mounted) return;

      logNotificationEvent('snooze_timer_fired', reason: suggestion.reason);

      await refreshStatus();

      final live = liveStatus ?? {};

      if (live['session_active'] != true || live['session_paused'] == true) {
        return;
      }

      final reminder = snoozedSuggestion;

      if (reminder == null) {
        cooldownUntil = null;
        await refreshStatus();
        return;
      }

      if (!suggestionStillRelevant(reminder, live)) {
        setState(() {
          cooldownUntil = null;
          snoozedSuggestion = null;
        });
        await recordNotificationSuppressed(reminder.reason, 'recovered');
        return;
      }

      if (!mounted) return;

      setState(() {
        cooldownUntil = null;
        activeSuggestion = reminder;
        selectedBreakMinutes = reminder.suggestedBreakMinutes;
        suggestedBreakMinutes = reminder.suggestedBreakMinutes;
        suggestionCollapsed = false;
        snoozedSuggestion = null;
      });

      final shown = await deliverSuggestion(reminder);

      if (shown) {
        await recordSuggestionShown(reminder);
      }
    });
  }

  Future<void> declineCurrentSuggestion() async {
    final suggestion = activeSuggestion;

    if (suggestion == null) return;

    snoozeTimer?.cancel();
    bannerCollapseTimer?.cancel();

    await apiService.declineBreak(
      reason: suggestion.reason,
      suggestedBreakMinutes: suggestion.suggestedBreakMinutes,
    );

    await NotificationService.cancelSuggestionNotification();

    if (!mounted) return;

    setState(() {
      snoozedSuggestion = null;
      activeSuggestion = null;
      decisionPanelVisible = false;
      suggestionCollapsed = false;
      cooldownUntil = DateTime.now().add(const Duration(minutes: 5));
    });
    setReasonCooldown(suggestion.reason, const Duration(minutes: 5));
  }

  Future<void> endBreak() async {
    await apiService.endBreak();
    await refreshStatus();
  }

  Future<void> extendBreak() async {
    await apiService.extendBreak(extraMinutes: 5, reason: 'manual');
    await refreshStatus();
  }

  Future<void> updateBreakDuration(int minutes) async {
    await apiService.updateBreakDuration(
      selectedBreakMinutes: minutes,
      reason: 'manual',
    );

    if (!mounted) return;

    setState(() {
      breakDurationEditorVisible = false;
    });

    await refreshStatus();
  }

  Future<void> toggleMiniMode() async {
    final live = liveStatus ?? {};

    if (live['camera_enabled'] != true) return;

    if (WindowService.miniMode) {
      await WindowService.exitMiniCameraMode();
    } else {
      await WindowService.enterMiniCameraMode();
      await refreshFrame();
      await updateNativeMiniCamera();
    }

    if (!mounted) return;

    setState(() {});
  }

  Future<void> finishSession() async {
    try {
      snoozeTimer?.cancel();
      bannerCollapseTimer?.cancel();
      snoozedSuggestion = null;
      await NotificationService.cancelSessionNotifications();

      if (WindowService.miniMode) {
        await WindowService.exitMiniCameraMode();

        if (mounted) {
          setState(() {});
        }
      }

      await apiService.endSession();

      if (!mounted) return;

      if (AppSettingsService.current.notificationsEnabled) {
        await NotificationService.showSessionFinished();
      }

      if (!mounted) return;

      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Oturum bitirilemedi.')));
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    statusTimer?.cancel();
    frameTimer?.cancel();
    snoozeTimer?.cancel();
    bannerCollapseTimer?.cancel();
    toastTimer?.cancel();
    notificationActionSub?.cancel();
    miniCameraClosedSub?.cancel();
    NotificationService.cancelSessionNotifications();
    WindowService.exitMiniCameraMode();
    super.dispose();
  }

  Widget topStatus(Map<String, dynamic> live) {
    final paused = live['session_paused'] == true;
    final cameraEnabled = live['camera_enabled'] == true;
    final cameraRunning = cameraStatus?['camera_running'] == true;
    final focus = focusPresentation(live);
    final color = paused ? AppTheme.warningOrange : focus.color;
    final subtitle = paused
        ? 'Mola modu açık.'
        : focus.key == 'away'
        ? 'Ekran başında değilsin gibi görünüyor. Oturum beklemeye alındı.'
        : focus.key == 'no_face'
        ? 'Kişi algılanmadı. Oturum beklemeye alınmadan önce kısa bir doğrulama yapılıyor.'
        : cameraEnabled && cameraRunning
        ? (previewVisible
              ? '${focus.title}. ${focus.subtitle}.'
              : 'Kamera gizli, analiz devam ediyor.')
        : 'Kamera kapalı — süre takibi aktif.';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                modeName(live['session_mode']),
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 15,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        statusBadge(sessionBadgeText(live), color),
        if (cameraEnabled && cameraRunning) ...[
          const SizedBox(width: 12),
          IconButton(
            tooltip: previewVisible
                ? 'Kamera preview gizle'
                : 'Kamera preview göster',
            onPressed: () async {
              setState(() {
                previewVisible = !previewVisible;
                autoMiniSuppressed = !previewVisible;
              });

              if (previewVisible) {
                await refreshFrame();
              }

              await syncAutomaticMiniCamera();
            },
            icon: Icon(
              previewVisible
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              color: AppTheme.textPrimary,
            ),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: AppTheme.border),
              ),
              fixedSize: const Size(46, 46),
            ),
          ),
        ],
      ],
    );
  }

  Widget statusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget timePanel(Map<String, dynamic> live) {
    final plannedSeconds = number(live['planned_total_minutes']) * 60;
    final remaining = math.max(
      0,
      plannedSeconds - number(live['active_seconds']),
    );
    final awaySeconds = number(live['away_seconds']);
    final showAway = awaySeconds > 0 || live['away_active'] == true;

    return PremiumCard(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          timeColumn(
            title: 'Çalışma',
            value: clockText(live['active_seconds']),
            color: AppTheme.focusGreen,
          ),
          const SizedBox(width: 18),
          timeColumn(
            title: 'Mola',
            value: clockText(live['break_seconds']),
            color: AppTheme.warningOrange,
          ),
          const SizedBox(width: 18),
          if (showAway) ...[
            timeColumn(
              title: 'Uzakta',
              value: clockText(awaySeconds),
              color: AppTheme.textMuted,
            ),
            const SizedBox(width: 18),
          ],
          timeColumn(
            title: 'Kalan Plan',
            value: plannedSeconds <= 0 ? '--' : clockText(remaining),
            color: AppTheme.calmBlue,
          ),
        ],
      ),
    );
  }

  Widget timeColumn({
    required String title,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.surfaceMuted,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(height: 18),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget planOverviewPanel(Map<String, dynamic> live) {
    final data = planOverviewData(live);

    return PremiumCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.textPrimary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.timeline_rounded,
                  color: AppTheme.textPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.status,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    data.dailyFocus,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Blok ${(data.progress * 100).round()}%',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          planTrack(data.segments),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              planPill(data.mainTimeLabel, data.mainTimeValue),
              planPill('Sonraki mola', data.nextBreak),
              planPill('Blok', data.blockInfo),
              planPill('Tur', data.roundInfo),
              planPill('Uzun mola', data.longBreakInfo),
            ],
          ),
        ],
      ),
    );
  }

  Widget planTrack(List<_PlanTrackSegment> segments) {
    final total = segments.fold<int>(
      0,
      (sum, item) => sum + math.max(1, item.flex),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            for (final segment in segments)
              Expanded(
                flex: ((math.max(1, segment.flex) / total) * 1000)
                    .round()
                    .clamp(1, 1000),
                child: Tooltip(
                  message: segment.label,
                  child: Container(
                    margin: const EdgeInsets.only(right: 2),
                    color: segment.active
                        ? segment.color
                        : segment.color.withValues(alpha: 0.28),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget planPill(String title, String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              height: 1.25,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget cameraCard(Map<String, dynamic> live) {
    final cameraEnabled = live['camera_enabled'] == true;
    final hasFrame = cameraStatus?['has_frame'] == true || frameBytes != null;
    final latestError = cameraStatus?['latest_error'];
    final focus = focusPresentation(live);
    final color = focusColor(live);
    final badgeText = !cameraEnabled
        ? 'Kamera kapalı — süre takibi aktif'
        : !hasFrame
        ? 'Canlı analiz açılıyor'
        : focusStatusLabel(live);

    return PremiumCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Kamera',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),
              const Spacer(),
              if (cameraEnabled)
                IconButton(
                  tooltip: previewVisible ? 'Preview gizle' : 'Preview göster',
                  onPressed: () async {
                    setState(() {
                      previewVisible = !previewVisible;
                      autoMiniSuppressed = !previewVisible;
                    });

                    if (previewVisible) {
                      await refreshFrame();
                    }

                    await syncAutomaticMiniCamera();
                  },
                  icon: Icon(
                    previewVisible
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: AppTheme.textSecondary,
                  ),
                ),
              statusBadge(badgeText, color),
            ],
          ),
          const SizedBox(height: 18),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: color.withValues(alpha: cameraEnabled ? 0.34 : 0.18),
                  width: 1.4,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
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
                  child: !cameraEnabled
                      ? KeyedSubtree(
                          key: const ValueKey('camera-off'),
                          child: cameraPlaceholder(
                            icon: Icons.videocam_off_rounded,
                            title: 'Kamera kapalı',
                            subtitle: 'Kamera kapalı — süre takibi aktif.',
                          ),
                        )
                      : !previewVisible
                      ? KeyedSubtree(
                          key: const ValueKey('camera-hidden'),
                          child: cameraPlaceholder(
                            icon: Icons.visibility_off_rounded,
                            title: 'Kamera gizli, analiz devam ediyor',
                            subtitle:
                                'Önizleme gizli tutuluyor; canlı analiz arka planda devam ediyor.',
                          ),
                        )
                      : latestError != null
                      ? KeyedSubtree(
                          key: const ValueKey('camera-error'),
                          child: cameraPlaceholder(
                            icon: Icons.videocam_off_rounded,
                            title: 'Kamera görüntüsü bekleniyor',
                            subtitle:
                                'Canlı analiz hazırlanıyor. Görüntü gelmezse kamera iznini kontrol et.',
                          ),
                        )
                      : KeyedSubtree(
                          key: ValueKey(
                            frameBytes == null
                                ? 'camera-frame-waiting'
                                : 'camera-frame',
                          ),
                          child: cameraFrame(),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          cameraFocusSummary(focus, live),
        ],
      ),
    );
  }

  Widget cameraFocusSummary(
    _FocusPresentation focus,
    Map<String, dynamic> live,
  ) {
    final cameraEnabled = live['camera_enabled'] == true;
    final score = number(live['focus_score']);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: focus.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: focus.color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: focus.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  focus.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  focus.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (cameraEnabled &&
              focus.key != 'away' &&
              focus.key != 'no_face' &&
              focus.key != 'break')
            Text(
              '${score.toStringAsFixed(0)}%',
              style: TextStyle(
                color: focus.color,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }

  Widget cameraFrame() {
    if (frameBytes == null) {
      return cameraPlaceholder(
        icon: Icons.videocam_rounded,
        title: 'Canlı analiz açılıyor',
        subtitle: 'Kamera akışı hazırlandığında burada görünecek.',
      );
    }

    return Image.memory(frameBytes!, fit: BoxFit.cover, gaplessPlayback: true);
  }

  Widget cameraPlaceholder({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      color: AppTheme.surfaceMuted,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 46, color: AppTheme.textMuted),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 320,
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget suggestionBanner() {
    final suggestion = activeSuggestion;

    if (suggestion == null || decisionPanelVisible) {
      return const SizedBox.shrink();
    }

    if (suggestionCollapsed) {
      return Positioned(
        top: 28,
        right: 28,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.notifications_active_rounded,
                  color: AppTheme.warningOrange,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Mola önerisi',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextButton(onPressed: openDecisionPanel, child: Text('Göster')),
              ],
            ),
          ),
        ),
      );
    }

    return Positioned(
      top: 28,
      right: 28,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.notifications_active_rounded,
                      color: AppTheme.warningOrange,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        suggestion.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Küçült',
                      onPressed: () {
                        setState(() {
                          suggestionCollapsed = true;
                        });
                      },
                      icon: Icon(Icons.expand_less_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  suggestion.message,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: suggestion.preferContinue
                      ? [
                          ElevatedButton(
                            onPressed: declineCurrentSuggestion,
                            child: Text('Devam et'),
                          ),
                          OutlinedButton(
                            onPressed: snoozeCurrentSuggestion,
                            child: Text('5 dk sonra hatırlat'),
                          ),
                          TextButton(
                            onPressed: openDecisionPanel,
                            child: Text('Yine de mola ver'),
                          ),
                        ]
                      : [
                          ElevatedButton(
                            onPressed: openDecisionPanel,
                            child: Text('Mola ver'),
                          ),
                          OutlinedButton(
                            onPressed: snoozeCurrentSuggestion,
                            child: Text('5 dk sonra hatırlat'),
                          ),
                          TextButton(
                            onPressed: declineCurrentSuggestion,
                            child: Text(
                              suggestion.reason == 'planned_break'
                                  ? 'Mola verme'
                                  : 'Devam et',
                            ),
                          ),
                        ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget decisionPanel() {
    final suggestion = activeSuggestion;

    if (!decisionPanelVisible || suggestion == null) {
      return const SizedBox.shrink();
    }

    return PremiumCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            suggestion.title,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Önerilen mola: ${suggestion.suggestedBreakMinutes} dk',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            children: [
              for (final value in const [3, 5, 10])
                ChoiceChip(
                  label: Text('$value dk'),
                  selected: selectedBreakMinutes == value,
                  onSelected: (_) {
                    setState(() {
                      selectedBreakMinutes = value;
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: startSelectedBreak,
                  icon: Icon(Icons.coffee_rounded),
                  label: Text('Molayı başlat'),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: declineCurrentSuggestion,
                child: Text('Vazgeç'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget breakModePanel(Map<String, dynamic> live) {
    final target = number(live['current_break_target_seconds']);
    final elapsed = number(live['current_break_seconds']);
    final remaining = number(live['current_break_remaining_seconds']);
    final type = live['current_break_type'] ?? 'manuel';
    final startedAt = live['current_break_started_at'] ?? '-';

    return PremiumCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mola modu',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          statLine('Mola süresi', clockText(elapsed)),
          statLine('Kalan mola', target <= 0 ? '--' : clockText(remaining)),
          statLine('Başlangıç', '$startedAt'),
          statLine('Mola türü', '$type'),
          const SizedBox(height: 12),
          if (breakDurationEditorVisible)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Wrap(
                spacing: 10,
                children: [
                  for (final value in const [3, 5, 10, 15])
                    ChoiceChip(
                      label: Text('$value dk'),
                      selected: (target / 60).round() == value,
                      onSelected: (_) => updateBreakDuration(value),
                    ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: endBreak,
                  icon: Icon(Icons.play_arrow_rounded),
                  label: Text('Molayı bitir'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: extendBreak,
                  icon: Icon(Icons.add_rounded),
                  label: Text('5 dk uzat'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Süreyi değiştir',
                onPressed: () {
                  setState(() {
                    breakDurationEditorVisible = !breakDurationEditorVisible;
                  });
                },
                icon: Icon(Icons.tune_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget controlPanel(Map<String, dynamic> live) {
    final paused = live['session_paused'] == true;
    final cameraEnabled = live['camera_enabled'] == true;
    final hasSuggestion = activeSuggestion != null && !decisionPanelVisible;
    final away = live['away_active'] == true;
    final focus = focusPresentation(live);

    if (paused) {
      return breakModePanel(live);
    }

    if (decisionPanelVisible) {
      return decisionPanel();
    }

    if (away) {
      return PremiumCard(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Oturum beklemede',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Ekran başında değilsin gibi görünüyor. Döndüğünde oturum devam edecek.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            statLine('Bekleme süresi', clockText(live['current_away_seconds'])),
            statLine('Aktif süre', clockText(live['active_seconds'])),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: finishSession,
                icon: Icon(Icons.stop_rounded),
                label: Text('Oturumu Bitir'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.dangerRed,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return PremiumCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Oturum Kontrolü',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          statLine('Mod', modeName(live['session_mode'])),
          if (cameraEnabled) statLine('Odak durumu', focus.title),
          if (cameraEnabled && focus.key != 'away' && focus.key != 'no_face')
            statLine(
              'Skor',
              '${number(live['focus_score']).toStringAsFixed(0)}%',
            ),
          if (cameraEnabled)
            statLine('Dikkat düşüşü', '${live['distraction_count'] ?? 0}'),
          if (!cameraEnabled) statLine('Akış', 'süre ve mola'),
          const SizedBox(height: 18),
          Row(
            children: [
              if (!hasSuggestion)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: startManualBreak,
                    icon: Icon(Icons.coffee_rounded),
                    label: Text('Mola Başlat'),
                  ),
                ),
              if (!hasSuggestion) const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: finishSession,
                  icon: Icon(Icons.stop_rounded),
                  label: Text('Oturumu Bitir'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.dangerRed,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget statLine(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget inlineToast() {
    if (toastTitle == null || toastMessage == null) {
      return const SizedBox.shrink();
    }

    final accent = toastTone == 'critical'
        ? AppTheme.dangerRed
        : toastTone == 'warning'
        ? AppTheme.warningOrange
        : toastTone == 'success'
        ? AppTheme.focusGreen
        : AppTheme.calmBlue;
    final icon = toastTone == 'critical'
        ? Icons.pause_circle_filled_rounded
        : toastTone == 'warning'
        ? Icons.timer_rounded
        : toastTone == 'success'
        ? Icons.check_circle_rounded
        : Icons.notifications_active_rounded;

    return Positioned(
      top: activeSuggestion != null && !decisionPanelVisible ? 132 : 28,
      right: 28,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.94, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, scale, child) {
          return Transform.scale(
            scale: scale,
            alignment: Alignment.topRight,
            child: child,
          );
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: Color.lerp(AppTheme.surface, accent, 0.05)!,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent.withValues(alpha: 0.30)),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.15),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 5,
                    height: 74,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(18),
                        bottomLeft: Radius.circular(18),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      child: Row(
                        children: [
                          Icon(icon, color: accent, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  toastTitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  toastMessage!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                    height: 1.35,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Kapat',
                            onPressed: () {
                              toastTimer?.cancel();
                              setState(() {
                                toastTitle = null;
                                toastMessage = null;
                              });
                            },
                            icon: Icon(Icons.close_rounded, size: 18),
                          ),
                        ],
                      ),
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

  Widget awayHoldOverlay(Map<String, dynamic> live) {
    if (live['away_active'] != true) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: 1,
          duration: const Duration(milliseconds: 220),
          child: Container(
            color: AppTheme.background.withValues(alpha: 0.78),
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.96, end: 1),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (context, scale, child) {
                  return Transform.scale(scale: scale, child: child);
                },
                child: Container(
                  width: 420,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppTheme.textMuted.withValues(alpha: 0.28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 34,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppTheme.textMuted.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.pause_circle_filled_rounded,
                          color: AppTheme.textSecondary,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Kişi aktif değil',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Çalışma süresi duraklatıldı. Kameraya döndüğünde oturum kaldığı yerden devam edecek.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                          height: 1.45,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceMuted,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Odak skoru: 0%',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget content(Map<String, dynamic> live) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ListView(
          children: [
            topStatus(live),
            const SizedBox(height: 18),
            timePanel(live),
            const SizedBox(height: 16),
            planOverviewPanel(live),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: cameraCard(live)),
                const SizedBox(width: 18),
                Expanded(flex: 5, child: controlPanel(live)),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final live = liveStatus ?? {};

    if (loading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          content(live),
          awayHoldOverlay(live),
          suggestionBanner(),
          inlineToast(),
        ],
      ),
    );
  }
}

class _BreakSuggestion {
  final String reason;
  final String title;
  final String message;
  final int suggestedBreakMinutes;
  final String breakType;
  final bool preferContinue;
  final int? plannedBlock;

  const _BreakSuggestion({
    required this.reason,
    required this.title,
    required this.message,
    required this.suggestedBreakMinutes,
    required this.breakType,
    this.preferContinue = false,
    this.plannedBlock,
  });
}

class _FocusWindowSample {
  final DateTime timestamp;
  final double score;
  final String category;

  const _FocusWindowSample({
    required this.timestamp,
    required this.score,
    required this.category,
  });
}

class _FocusWindowStats {
  final int count;
  final double averageScore;
  final int severeSeconds;
  final int dropSeconds;
  final int fluctuatingSeconds;
  final double standardDeviation;
  final double windowSeconds;

  const _FocusWindowStats({
    required this.count,
    required this.averageScore,
    required this.severeSeconds,
    required this.dropSeconds,
    required this.fluctuatingSeconds,
    required this.standardDeviation,
    required this.windowSeconds,
  });

  const _FocusWindowStats.empty()
    : count = 0,
      averageScore = 0,
      severeSeconds = 0,
      dropSeconds = 0,
      fluctuatingSeconds = 0,
      standardDeviation = 0,
      windowSeconds = 0;
}

class _PlanOverviewData {
  final String title;
  final String status;
  final String mainTimeLabel;
  final String mainTimeValue;
  final String nextBreak;
  final String blockInfo;
  final String roundInfo;
  final String longBreakInfo;
  final String dailyFocus;
  final double progress;
  final List<_PlanTrackSegment> segments;

  const _PlanOverviewData({
    required this.title,
    required this.status,
    required this.mainTimeLabel,
    required this.mainTimeValue,
    required this.nextBreak,
    required this.blockInfo,
    required this.roundInfo,
    required this.longBreakInfo,
    required this.dailyFocus,
    required this.progress,
    required this.segments,
  });
}

class _PlanTrackSegment {
  final String label;
  final int flex;
  final Color color;
  final bool active;

  const _PlanTrackSegment({
    required this.label,
    required this.flex,
    required this.color,
    required this.active,
  });
}

class _FocusPresentation {
  final String key;
  final String title;
  final String subtitle;
  final Color color;

  _FocusPresentation({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.color,
  });
}
