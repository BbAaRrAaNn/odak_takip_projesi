import 'dart:async';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

class WindowService {
  static const MethodChannel _miniCameraChannel = MethodChannel(
    'focusvision/mini_camera',
  );

  static bool miniMode = false;
  static final StreamController<void> _miniCameraClosedController =
      StreamController<void>.broadcast();

  static Stream<void> get miniCameraClosedStream =>
      _miniCameraClosedController.stream;

  static void initialize() {
    _miniCameraChannel.setMethodCallHandler((call) async {
      if (call.method == 'closed') {
        miniMode = false;
        _miniCameraClosedController.add(null);
      }
    });
  }

  static Future<void> enterMiniCameraMode() async {
    if (miniMode) return;

    miniMode = true;

    try {
      await _miniCameraChannel.invokeMethod('show');
    } catch (_) {}
  }

  static Future<void> updateMiniCamera({
    Uint8List? frameBytes,
    required double focusScore,
    required bool isFocused,
    required bool cameraRunning,
    required String statusLabel,
  }) async {
    if (!miniMode) return;

    try {
      await _miniCameraChannel.invokeMethod('update', {
        'frame': frameBytes,
        'focusScore': focusScore,
        'isFocused': isFocused,
        'cameraRunning': cameraRunning,
        'statusLabel': statusLabel,
      });
    } catch (_) {}
  }

  static Future<void> exitMiniCameraMode() async {
    if (!miniMode) return;

    miniMode = false;

    try {
      await _miniCameraChannel.invokeMethod('hide');
    } catch (_) {}

    try {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setResizable(true);
    } catch (_) {}
  }

  static Future<bool> isFocused() async {
    return isAppForeground();
  }

  static Future<bool> isAppForeground() async {
    try {
      final state = await _miniCameraChannel.invokeMapMethod<String, dynamic>(
        'appFocusState',
      );

      if (state != null) {
        return state['shouldUseInApp'] == true;
      }
    } catch (_) {}

    try {
      return windowManager.isFocused();
    } catch (_) {
      return false;
    }
  }

  static Future<void> bringToFront() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }
}
