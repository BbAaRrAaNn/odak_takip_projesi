import 'package:flutter/foundation.dart';

import 'api_service.dart';

class AppSettings {
  final bool notificationsEnabled;
  final bool breakRemindersEnabled;
  final bool liveFocusNotificationsEnabled;
  final bool cameraPreviewDefaultVisible;
  final String themeMode;
  final String language;
  final String colorVisionMode;

  const AppSettings({
    required this.notificationsEnabled,
    required this.breakRemindersEnabled,
    required this.liveFocusNotificationsEnabled,
    required this.cameraPreviewDefaultVisible,
    required this.themeMode,
    required this.language,
    required this.colorVisionMode,
  });

  factory AppSettings.defaults() {
    return const AppSettings(
      notificationsEnabled: true,
      breakRemindersEnabled: true,
      liveFocusNotificationsEnabled: true,
      cameraPreviewDefaultVisible: true,
      themeMode: 'light',
      language: 'tr',
      colorVisionMode: 'standard',
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final themeMode = '${json['theme_mode'] ?? 'light'}';
    final colorVisionMode = '${json['color_vision_mode'] ?? 'standard'}';

    return AppSettings(
      notificationsEnabled: json['notifications_enabled'] != false,
      breakRemindersEnabled: json['break_reminders_enabled'] != false,
      liveFocusNotificationsEnabled:
          json['live_focus_notifications_enabled'] != false,
      cameraPreviewDefaultVisible:
          json['camera_preview_default_visible'] != false,
      themeMode: ['light', 'dark'].contains(themeMode) ? themeMode : 'light',
      language: 'tr',
      colorVisionMode:
          [
            'standard',
            'protanopia',
            'deuteranopia',
            'tritanopia',
            'achromatopsia',
          ].contains(colorVisionMode)
          ? colorVisionMode
          : 'standard',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'notifications_enabled': notificationsEnabled,
      'break_reminders_enabled': breakRemindersEnabled,
      'live_focus_notifications_enabled': liveFocusNotificationsEnabled,
      'camera_preview_default_visible': cameraPreviewDefaultVisible,
      'theme_mode': themeMode,
      'language': 'tr',
      'color_vision_mode': colorVisionMode,
    };
  }

  AppSettings copyWith({
    bool? notificationsEnabled,
    bool? breakRemindersEnabled,
    bool? liveFocusNotificationsEnabled,
    bool? cameraPreviewDefaultVisible,
    String? themeMode,
    String? language,
    String? colorVisionMode,
  }) {
    return AppSettings(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      breakRemindersEnabled:
          breakRemindersEnabled ?? this.breakRemindersEnabled,
      liveFocusNotificationsEnabled:
          liveFocusNotificationsEnabled ?? this.liveFocusNotificationsEnabled,
      cameraPreviewDefaultVisible:
          cameraPreviewDefaultVisible ?? this.cameraPreviewDefaultVisible,
      themeMode: themeMode ?? this.themeMode,
      language: language ?? this.language,
      colorVisionMode: colorVisionMode ?? this.colorVisionMode,
    );
  }
}

class AppSettingsService {
  static final ValueNotifier<AppSettings> settings = ValueNotifier<AppSettings>(
    AppSettings.defaults(),
  );

  static AppSettings get current => settings.value;

  static Future<void> loadSettings() async {
    final response = await ApiService().getSettings();
    final settingsData = Map<String, dynamic>.from(response['settings'] ?? {});

    settings.value = AppSettings.fromJson(settingsData);
  }

  static Future<void> updateSettings(AppSettings next) async {
    settings.value = next;

    final response = await ApiService().updateSettings(next.toJson());
    final settingsData = Map<String, dynamic>.from(response['settings'] ?? {});

    settings.value = AppSettings.fromJson(settingsData);
  }
}
