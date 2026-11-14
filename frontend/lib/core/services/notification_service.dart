import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';
import 'window_service.dart';

class NotificationService {
  static const MethodChannel nativeNotifications = MethodChannel(
    'focusvision/desktop_notifications',
  );
  static final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  static final ApiService apiService = ApiService();
  static final StreamController<String> _actionController =
      StreamController<String>.broadcast();
  static bool? notificationsAllowed;
  static String permissionStatusText = 'unknown';
  static String lastActionId = 'open_session';
  static String lastActionPayload = 'notification';

  static Stream<String> get actionStream => _actionController.stream;

  static Future<void> initialize() async {
    nativeNotifications.setMethodCallHandler(handleNativeCall);

    final DarwinNotificationCategory breakCategory = DarwinNotificationCategory(
      'break_category',
      actions: [
        DarwinNotificationAction.plain('accept_break', 'Mola ver'),
        DarwinNotificationAction.plain('snooze_break', '5 dk sonra'),
        DarwinNotificationAction.plain('decline_break', 'Devam et'),
      ],
    );

    final DarwinNotificationCategory focusDropCategory =
        DarwinNotificationCategory(
          'focus_drop_category',
          actions: [
            DarwinNotificationAction.plain('accept_break', 'Mola ver'),
            DarwinNotificationAction.plain('snooze_break', '5 dk sonra'),
            DarwinNotificationAction.plain('decline_break', 'Devam et'),
          ],
        );

    final DarwinNotificationCategory continueCategory =
        DarwinNotificationCategory(
          'continue_category',
          actions: [
            DarwinNotificationAction.plain('decline_break', 'Devam et'),
            DarwinNotificationAction.plain('snooze_break', '5 dk sonra'),
            DarwinNotificationAction.plain('accept_break', 'Yine de mola ver'),
          ],
        );

    final DarwinNotificationCategory breakReadyCategory =
        DarwinNotificationCategory(
          'break_ready_category',
          actions: [
            DarwinNotificationAction.plain('return_work', 'Çalışmaya dön'),
            DarwinNotificationAction.plain('extend_break', '5 dk uzat'),
          ],
        );

    final DarwinNotificationCategory awayCategory = DarwinNotificationCategory(
      'away_category',
      actions: [DarwinNotificationAction.plain('ok_away', 'Tamam')],
    );

    final DarwinInitializationSettings macos = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      notificationCategories: [
        breakCategory,
        focusDropCategory,
        continueCategory,
        breakReadyCategory,
        awayCategory,
      ],
    );

    final InitializationSettings settings = InitializationSettings(
      macOS: macos,
    );

    await notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: handleAction,
    );

    try {
      await nativeNotifications.invokeMethod('configure');
    } catch (_) {}

    await checkPermissions();
  }

  static Future<bool> checkPermissions() async {
    try {
      final status = await nativeNotifications.invokeMapMethod<String, dynamic>(
        'permissionStatus',
      );

      if (status != null) {
        final allowed = status['authorized'] == true;
        notificationsAllowed = allowed;
        permissionStatusText = '${status['status'] ?? 'unknown'}';
        return allowed;
      }
    } catch (_) {}

    final macos = notifications
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();

    if (macos == null) return true;

    final status = await macos.checkPermissions();
    final allowed = status?.isEnabled == true && status?.isAlertEnabled == true;
    notificationsAllowed = allowed;
    permissionStatusText = allowed ? 'authorized' : 'denied';
    return allowed;
  }

  static Future<bool> ensureDesktopPermission() async {
    if (await checkPermissions()) return true;

    try {
      final status = await nativeNotifications.invokeMapMethod<String, dynamic>(
        'requestPermission',
      );

      if (status != null) {
        final allowed = status['authorized'] == true;
        notificationsAllowed = allowed;
        permissionStatusText = '${status['status'] ?? 'unknown'}';
        return allowed;
      }
    } catch (_) {}

    final granted = await notifications
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    notificationsAllowed = granted == true;
    permissionStatusText = notificationsAllowed == true
        ? 'authorized'
        : 'denied';
    return notificationsAllowed == true;
  }

  static Future<String> permissionStatus() async {
    await checkPermissions();
    return permissionStatusText;
  }

  static Future<void> handleNativeCall(MethodCall call) async {
    if (call.method != 'notificationAction') return;

    final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
    final actionId = '${args['actionId'] ?? 'open_session'}';
    final payload = '${args['payload'] ?? 'notification'}';

    await handleActionPayload(
      actionId: actionId,
      payload: payload,
      recordAction: actionId != 'open_session',
    );
  }

  static Future<void> handleAction(NotificationResponse response) async {
    final actionId = response.actionId;
    final payload = response.payload;

    await handleActionPayload(
      actionId: actionId == null || actionId.isEmpty
          ? 'open_session'
          : actionId,
      payload: payload == null || payload.isEmpty ? 'notification' : payload,
      recordAction: actionId != null && actionId.isNotEmpty,
    );
  }

  static Future<void> handleActionPayload({
    required String actionId,
    required String payload,
    required bool recordAction,
  }) async {
    lastActionId = actionId;
    lastActionPayload = payload;

    if (recordAction && actionId.isNotEmpty) {
      try {
        await apiService.recordNotificationAction(
          actionType: actionId,
          reason: payload.isEmpty ? 'notification' : payload,
        );
      } catch (_) {}
    }

    try {
      await nativeNotifications.invokeMethod('focusApp');
    } catch (_) {
      await WindowService.bringToFront();
    }

    if (actionId == 'accept_break') {
      _actionController.add('accept_break');
      return;
    }

    if (actionId == 'snooze_break') {
      _actionController.add('snooze_break');
      return;
    }

    if (actionId == 'decline_break') {
      _actionController.add('decline_break');
      return;
    }

    if (actionId == 'return_work') {
      _actionController.add('return_work');
      return;
    }

    if (actionId == 'extend_break') {
      _actionController.add('extend_break');
      return;
    }

    if (actionId == 'ok_away') {
      _actionController.add('open_session');
      return;
    }

    _actionController.add('open_session');
  }

  static Future<bool> showNativeNotification({
    required int id,
    required String title,
    required String body,
    required String payload,
    required String category,
  }) async {
    if (!await ensureDesktopPermission()) return false;

    try {
      final shown = await nativeNotifications.invokeMethod<bool>('show', {
        'identifier':
            'focusvision-$id-${DateTime.now().millisecondsSinceEpoch}',
        'title': title,
        'body': body,
        'payload': payload,
        'category': category,
      });

      return shown == true;
    } catch (_) {
      return false;
    }
  }

  static NotificationDetails breakDetails() {
    return const NotificationDetails(
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
        categoryIdentifier: 'break_category',
        interruptionLevel: InterruptionLevel.active,
      ),
    );
  }

  static NotificationDetails focusDropDetails() {
    return const NotificationDetails(
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
        categoryIdentifier: 'focus_drop_category',
        interruptionLevel: InterruptionLevel.active,
      ),
    );
  }

  static NotificationDetails continueDetails() {
    return const NotificationDetails(
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
        categoryIdentifier: 'continue_category',
        interruptionLevel: InterruptionLevel.active,
      ),
    );
  }

  static NotificationDetails basicDetails() {
    return const NotificationDetails(
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
        interruptionLevel: InterruptionLevel.active,
      ),
    );
  }

  static NotificationDetails breakReadyDetails() {
    return const NotificationDetails(
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
        categoryIdentifier: 'break_ready_category',
        interruptionLevel: InterruptionLevel.active,
      ),
    );
  }

  static Future<bool> showBreakTimeNotification() async {
    return showNativeNotification(
      id: 1001,
      title: 'Mola zamanı',
      body:
          'Planlanan çalışma bloğu tamamlandı.\nKısa bir ara vermen iyi olabilir.',
      payload: 'break_time',
      category: 'break_category',
    );
  }

  static Future<bool> showFocusDropNotification({
    bool isPersonalized = false,
  }) async {
    return showNativeNotification(
      id: 1002,
      title: isPersonalized
          ? 'Odak ritminde düşüş var'
          : 'Odak ritminde belirgin değişim',
      body: isPersonalized
          ? 'Odak seviyen bir süredir düşük seyrediyor.\nKısa bir ara şimdi daha faydalı olabilir.'
          : 'Odak ritminde belirgin bir değişim var.\nKısa bir mola ritmi toparlayabilir.',
      payload: 'focus_drop',
      category: 'focus_drop_category',
    );
  }

  static Future<bool> showSessionSuggestionNotification({
    required String title,
    required String body,
    required String payload,
    bool focusDrop = false,
    bool preferContinue = false,
  }) async {
    await notifications.cancel(1005);

    return showNativeNotification(
      id: 1005,
      title: title,
      body: body,
      payload: payload,
      category: preferContinue
          ? 'continue_category'
          : focusDrop
          ? 'focus_drop_category'
          : 'break_category',
    );
  }

  static Future<bool> showBreakReadyNotification() async {
    return showNativeNotification(
      id: 1003,
      title: 'Çalışmaya dönme zamanı',
      body: 'Mola süren tamamlandı.\nHazırsan çalışma bloğuna dönebilirsin.',
      payload: 'break_ready',
      category: 'break_ready_category',
    );
  }

  static Future<bool> showAwayNotification() async {
    return showNativeNotification(
      id: 1006,
      title: 'Kişi aktif değil',
      body: 'Ekran başında görünmüyorsun.\nÇalışma süresi beklemeye alındı.',
      payload: 'away_detected',
      category: 'away_category',
    );
  }

  static Future<bool> showWorkGoalCompletedNotification() async {
    return showNativeNotification(
      id: 1007,
      title: 'Çalışma hedefi tamamlandı',
      body:
          'Çalışma hedefin tamamlandı.\nOturumu bitirebilir veya devam edebilirsin.',
      payload: 'work_goal_completed',
      category: 'basic',
    );
  }

  static Future<bool> showSessionFinished() async {
    return showNativeNotification(
      id: 1004,
      title: 'Oturum tamamlandı',
      body: 'Çalışma oturumu başarıyla kaydedildi.',
      payload: 'session_finished',
      category: 'basic',
    );
  }

  static Future<void> cancelSessionNotifications() async {
    await notifications.cancel(1001);
    await notifications.cancel(1002);
    await notifications.cancel(1003);
    await notifications.cancel(1005);
    await notifications.cancel(1006);
    await notifications.cancel(1007);
  }

  static Future<void> cancelSuggestionNotification() async {
    await notifications.cancel(1005);
  }
}
