import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/services/notification_service.dart';
import 'core/services/window_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService.initialize();

  await windowManager.ensureInitialized();
  WindowService.initialize();

  const WindowOptions options = WindowOptions(
    size: Size(1220, 780),
    minimumSize: Size(980, 640),
    center: true,
    backgroundColor: Colors.transparent,
    title: 'FocusVision',
  );

  await windowManager.setPreventClose(true);

  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();

    await windowManager.focus();
  });

  runApp(const FocusVisionApp());
}
