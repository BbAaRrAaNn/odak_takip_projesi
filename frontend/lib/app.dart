import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'core/services/app_settings_service.dart';
import 'core/services/api_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/user_profile_service.dart';
import 'core/services/window_service.dart';
import 'shared/theme/app_theme.dart';
import 'shared/widgets/main_navigation.dart';

class FocusVisionApp extends StatefulWidget {
  const FocusVisionApp({super.key});

  @override
  State<FocusVisionApp> createState() => _FocusVisionAppState();
}

class _FocusVisionAppState extends State<FocusVisionApp> with WindowListener {
  final ApiService apiService = ApiService();

  Timer? heartbeatTimer;

  bool closing = false;

  @override
  void initState() {
    super.initState();

    windowManager.addListener(this);

    unawaited(UserProfileService.loadProfile());
    unawaited(AppSettingsService.loadSettings());

    heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      apiService.sendHeartbeat();
    });

    apiService.sendHeartbeat();
  }

  Future<void> closeAppSafely() async {
    if (closing) {
      return;
    }

    closing = true;

    heartbeatTimer?.cancel();

    try {
      await NotificationService.cancelSessionNotifications();
    } catch (_) {}

    try {
      await apiService.endSession();
    } catch (_) {}

    try {
      await apiService.stopCamera();
    } catch (_) {}

    try {
      if (WindowService.miniMode) {
        await WindowService.exitMiniCameraMode();
      }
    } catch (_) {}

    await windowManager.destroy();
  }

  @override
  Future<void> onWindowClose() async {
    await closeAppSafely();
  }

  @override
  void dispose() {
    heartbeatTimer?.cancel();

    windowManager.removeListener(this);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppSettings>(
      valueListenable: AppSettingsService.settings,
      builder: (context, settings, _) {
        AppTheme.configure(
          themeMode: settings.themeMode,
          colorVisionMode: settings.colorVisionMode,
        );

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'FocusVision',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: AppTheme.materialThemeMode,
          home: const MainNavigation(),
        );
      },
    );
  }
}
