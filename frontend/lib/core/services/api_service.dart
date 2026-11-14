import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';

class ApiService {
  final String baseUrl = ApiConstants.baseUrl;

  Future<Map<String, dynamic>> decodeResponse(http.Response response) async {
    if (response.body.isEmpty) {
      return {
        'success': response.statusCode >= 200 && response.statusCode < 300,
      };
    }

    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  Future<void> sendHeartbeat() async {
    try {
      await http
          .post(Uri.parse('$baseUrl/app/heartbeat'))
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<Map<String, dynamic>> getProfile() async {
    final response = await http
        .get(Uri.parse('$baseUrl/profile'))
        .timeout(const Duration(seconds: 4));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> updateProfile({
    required String displayName,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/profile'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'display_name': displayName}),
        )
        .timeout(const Duration(seconds: 4));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> getSettings() async {
    final response = await http
        .get(Uri.parse('$baseUrl/settings'))
        .timeout(const Duration(seconds: 4));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> updateSettings(
    Map<String, dynamic> settings,
  ) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/settings'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(settings),
        )
        .timeout(const Duration(seconds: 4));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> startSession({
    required String sessionMode,
    required bool cameraEnabled,
    int plannedTotalMinutes = 60,
    Map<String, dynamic>? pomodoroSettings,
  }) async {
    final payload = {
      'session_mode': sessionMode,
      'camera_enabled': cameraEnabled,
      'planned_total_minutes': plannedTotalMinutes,
    };

    if (pomodoroSettings != null) {
      payload['pomodoro_settings'] = pomodoroSettings;
    }

    final response = await http
        .post(
          Uri.parse('$baseUrl/session/start'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 10));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> endSession() async {
    final response = await http
        .post(Uri.parse('$baseUrl/session/end'))
        .timeout(const Duration(seconds: 12));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> getLiveStatus() async {
    final response = await http
        .get(Uri.parse('$baseUrl/session/live'))
        .timeout(const Duration(seconds: 3));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> getSessionPlan() async {
    final response = await http
        .get(Uri.parse('$baseUrl/session/plan'))
        .timeout(const Duration(seconds: 4));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> startBreak({
    String reason = 'manual',
    int selectedBreakMinutes = 5,
    int? suggestedBreakMinutes,
    String breakType = 'manual',
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/session/break/start'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'reason': reason,
            'selected_break_minutes': selectedBreakMinutes,
            'suggested_break_minutes': suggestedBreakMinutes,
            'break_type': breakType,
          }),
        )
        .timeout(const Duration(seconds: 4));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> endBreak() async {
    final response = await http
        .post(Uri.parse('$baseUrl/session/break/end'))
        .timeout(const Duration(seconds: 4));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> acceptBreak({
    String reason = 'manual',
    int? suggestedBreakMinutes,
    int? selectedBreakMinutes,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/session/break/accept'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'reason': reason,
            'suggested_break_minutes': suggestedBreakMinutes,
            'selected_break_minutes': selectedBreakMinutes,
          }),
        )
        .timeout(const Duration(seconds: 4));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> declineBreak({
    String reason = 'manual',
    int? suggestedBreakMinutes,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/session/break/decline'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'reason': reason,
            'suggested_break_minutes': suggestedBreakMinutes,
          }),
        )
        .timeout(const Duration(seconds: 4));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> snoozeBreak({
    int snoozeMinutes = 5,
    String reason = 'manual',
    int? suggestedBreakMinutes,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/session/break/snooze'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'snooze_minutes': snoozeMinutes,
            'reason': reason,
            'suggested_break_minutes': suggestedBreakMinutes,
          }),
        )
        .timeout(const Duration(seconds: 4));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> extendBreak({
    int extraMinutes = 5,
    String reason = 'manual',
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/session/break/extend'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'extra_minutes': extraMinutes, 'reason': reason}),
        )
        .timeout(const Duration(seconds: 4));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> updateBreakDuration({
    required int selectedBreakMinutes,
    String reason = 'manual',
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/session/break/update'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'selected_break_minutes': selectedBreakMinutes,
            'reason': reason,
          }),
        )
        .timeout(const Duration(seconds: 4));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> getSessions() async {
    final response = await http
        .get(Uri.parse('$baseUrl/sessions'))
        .timeout(const Duration(seconds: 5));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> recordNotificationAction({
    required String actionType,
    String reason = 'manual',
    int? suggestedBreakMinutes,
    int? selectedBreakMinutes,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/session/notification/action'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action_type': actionType,
            'reason': reason,
            'suggested_break_minutes': suggestedBreakMinutes,
            'selected_break_minutes': selectedBreakMinutes,
          }),
        )
        .timeout(const Duration(seconds: 4));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> getAnalytics() async {
    final response = await http
        .get(Uri.parse('$baseUrl/analytics/trend'))
        .timeout(const Duration(seconds: 5));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> getPatterns() async {
    final response = await http
        .get(Uri.parse('$baseUrl/analytics/patterns'))
        .timeout(const Duration(seconds: 5));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> getTrendAnalysis() async {
    return getAnalytics();
  }

  Future<Map<String, dynamic>> getFocusPlan({
    required int plannedTotalMinutes,
  }) async {
    final response = await http
        .get(
          Uri.parse(
            '$baseUrl/analytics/focus-plan?planned_total_minutes=$plannedTotalMinutes',
          ),
        )
        .timeout(const Duration(seconds: 6));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> startCamera() async {
    final response = await http
        .post(Uri.parse('$baseUrl/camera/start'))
        .timeout(const Duration(seconds: 8));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> stopCamera() async {
    final response = await http
        .post(Uri.parse('$baseUrl/camera/stop'))
        .timeout(const Duration(seconds: 8));

    return decodeResponse(response);
  }

  Future<Uint8List?> getCameraFrame() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/camera/frame'))
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> checkCameraPermission() async {
    final response = await http
        .get(Uri.parse('$baseUrl/camera/permission/check'))
        .timeout(const Duration(seconds: 8));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> exportData() async {
    final response = await http
        .post(Uri.parse('$baseUrl/data/export'))
        .timeout(const Duration(seconds: 8));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> clearHistory() async {
    final response = await http
        .post(Uri.parse('$baseUrl/data/clear-history'))
        .timeout(const Duration(seconds: 8));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> clearCache() async {
    final response = await http
        .post(Uri.parse('$baseUrl/data/clear-cache'))
        .timeout(const Duration(seconds: 8));

    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> retrainModel() async {
    final response = await http
        .post(Uri.parse('$baseUrl/model/retrain'))
        .timeout(const Duration(seconds: 20));

    return decodeResponse(response);
  }
}
