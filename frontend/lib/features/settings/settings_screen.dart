import 'package:flutter/material.dart';

import '../../core/services/app_settings_service.dart';
import '../../core/services/api_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/user_profile_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/premium_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiService apiService = ApiService();

  bool loading = true;
  bool cameraPreviewVisible = true;
  bool notificationsEnabled = true;
  bool breakRemindersEnabled = true;
  bool liveFocusNotificationsEnabled = true;
  String themeMode = 'light';
  String language = 'tr';
  String colorVisionMode = 'standard';
  bool notificationPermissionGranted = false;
  String notificationPermissionStatus = 'unknown';

  int sessionCount = 0;
  int cameraSessionCount = 0;
  DateTime? latestSessionAt;
  DateTime? latestCameraSessionAt;

  @override
  void initState() {
    super.initState();
    loadDataState();
  }

  Future<void> loadDataState() async {
    try {
      await UserProfileService.loadProfile();
      await AppSettingsService.loadSettings();
    } catch (_) {}

    final settings = AppSettingsService.current;
    var permissionGranted = false;

    try {
      permissionGranted = await NotificationService.checkPermissions();
    } catch (_) {}

    final permissionStatus = await NotificationService.permissionStatus();

    try {
      final result = await apiService.getSessions();
      final sessions = List<dynamic>.from(result['sessions'] ?? []);

      DateTime? newest;
      DateTime? newestCamera;
      var cameraCount = 0;

      for (final item in sessions) {
        final session = Map<String, dynamic>.from(item);
        final date = parseDate(session['date']);
        if (date != null && (newest == null || date.isAfter(newest))) {
          newest = date;
        }

        if (session['camera_enabled'] == true) {
          cameraCount += 1;
          if (date != null &&
              (newestCamera == null || date.isAfter(newestCamera))) {
            newestCamera = date;
          }
        }
      }

      if (!mounted) return;

      setState(() {
        sessionCount = result['session_count'] ?? sessions.length;
        cameraSessionCount = cameraCount;
        latestSessionAt = newest;
        latestCameraSessionAt = newestCamera;
        notificationPermissionGranted = permissionGranted;
        notificationPermissionStatus = permissionStatus;
        applySettingsToState(settings);
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        notificationPermissionGranted = permissionGranted;
        notificationPermissionStatus = permissionStatus;
        applySettingsToState(settings);
        loading = false;
      });
    }
  }

  DateTime? parseDate(dynamic value) {
    if (value is! String || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    final iso = DateTime.tryParse(trimmed);
    if (iso != null) return iso;

    final match = RegExp(
      r'^(\d{2})\.(\d{2})\.(\d{4})(?:\s+(\d{2}):(\d{2}))?$',
    ).firstMatch(trimmed);
    if (match == null) return null;

    return DateTime(
      int.parse(match.group(3)!),
      int.parse(match.group(2)!),
      int.parse(match.group(1)!),
      int.parse(match.group(4) ?? '0'),
      int.parse(match.group(5) ?? '0'),
    );
  }

  String formatDate(DateTime? date) {
    if (date == null) return 'Henüz yok';

    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day.$month.${local.year} $hour:$minute';
  }

  void placeholder(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  void applySettingsToState(AppSettings settings) {
    notificationsEnabled = settings.notificationsEnabled;
    breakRemindersEnabled = settings.breakRemindersEnabled;
    liveFocusNotificationsEnabled = settings.liveFocusNotificationsEnabled;
    cameraPreviewVisible = settings.cameraPreviewDefaultVisible;
    themeMode = settings.themeMode;
    language = settings.language;
    colorVisionMode = settings.colorVisionMode;
  }

  Future<void> saveSettings(
    AppSettings next,
    String successMessage, {
    bool showSuccess = true,
  }) async {
    final previous = AppSettingsService.current;

    AppSettingsService.settings.value = next;
    AppTheme.configure(
      themeMode: next.themeMode,
      colorVisionMode: next.colorVisionMode,
    );

    setState(() {
      applySettingsToState(next);
    });

    if (showSuccess) {
      placeholder(successMessage);
    }

    try {
      await AppSettingsService.updateSettings(next);

      if (!mounted) return;

      setState(() {
        applySettingsToState(AppSettingsService.current);
      });
    } catch (_) {
      if (!mounted) return;

      AppSettingsService.settings.value = previous;
      AppTheme.configure(
        themeMode: previous.themeMode,
        colorVisionMode: previous.colorVisionMode,
      );

      setState(() {
        applySettingsToState(previous);
      });

      placeholder('Ayar kaydedilemedi. Backend bağlantısını kontrol et.');
    }
  }

  Future<void> toggleNotifications(bool value) async {
    if (value) {
      final allowed = await NotificationService.ensureDesktopPermission();

      if (!allowed) {
        if (!mounted) return;

        setState(() {
          notificationPermissionGranted = false;
          notificationPermissionStatus =
              NotificationService.permissionStatusText;
        });
        placeholder(
          'macOS bildirim izni kapalı. Sistem Ayarları > Bildirimler bölümünden FocusVision iznini aç.',
        );
        return;
      }

      if (mounted) {
        setState(() {
          notificationPermissionGranted = true;
          notificationPermissionStatus =
              NotificationService.permissionStatusText;
        });
      }
    }

    await saveSettings(
      AppSettingsService.current.copyWith(notificationsEnabled: value),
      value ? 'Bildirimler açıldı.' : 'Bildirimler kapatıldı.',
    );
  }

  String modelStatus() {
    if (cameraSessionCount >= 10) return 'Hazır';
    if (cameraSessionCount >= 3) return 'Öğreniyor';
    return 'Yeterli veri yok';
  }

  String modelSummary() {
    if (cameraSessionCount >= 10) {
      return 'Kamera açık oturumlardan kişisel ritmini öğrenmeye hazır.';
    }
    if (cameraSessionCount >= 3) {
      return 'Model daha güvenilir öneriler için birkaç oturum daha gözlemliyor.';
    }
    return 'Kişisel model için kamera açık daha fazla oturum gerekiyor.';
  }

  Color modelColor() {
    if (cameraSessionCount >= 10) return AppTheme.focusGreen;
    if (cameraSessionCount >= 3) return AppTheme.warningOrange;
    return AppTheme.textMuted;
  }

  String languageLabel(String value) {
    return 'Türkçe';
  }

  String themeLabel(String value) {
    switch (value) {
      case 'dark':
        return 'Koyu';
      default:
        return 'Açık';
    }
  }

  String colorVisionLabel(String value) {
    switch (value) {
      case 'protanopia':
        return 'Protanopia';
      case 'deuteranopia':
        return 'Deuteranopia';
      case 'tritanopia':
        return 'Tritanopia';
      case 'achromatopsia':
        return 'Achromatopsia';
      default:
        return 'Standart';
    }
  }

  Future<void> editProfile(UserProfile profile) async {
    final nameController = TextEditingController(text: profile.displayName);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Profili düzenle'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Kullanıcı adı',
                    hintText: 'Adını gir',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Vazgeç'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Kaydet'),
            ),
          ],
        );
      },
    );

    if (saved == true) {
      try {
        await UserProfileService.updateProfile(
          displayName: nameController.text.trim(),
        );
        if (mounted) placeholder('Profil bilgileri güncellendi.');
      } catch (_) {
        if (mounted) {
          placeholder('Profil kaydedilemedi. Backend bağlantısını kontrol et.');
        }
      }
    }

    nameController.dispose();
  }

  Future<void> confirmAndClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Oturum geçmişi temizlensin mi?'),
          content: Text(
            'Bu işlem local oturum geçmişini temizler. Profil ve ayarlar korunur.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Vazgeç'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.dangerRed,
              ),
              child: Text('Temizle'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await apiService.clearHistory();
      await loadDataState();

      if (!mounted) return;

      placeholder('Oturum geçmişi temizlendi.');
    } catch (_) {
      if (mounted) placeholder('Oturum geçmişi temizlenemedi.');
    }
  }

  Future<void> retrainModel() async {
    try {
      final result = await apiService.retrainModel();
      final training = Map<String, dynamic>.from(
        result['training_result'] ?? {},
      );

      if (!mounted) return;

      placeholder('${training['message'] ?? 'Model eğitimi tamamlandı.'}');
      await loadDataState();
    } catch (_) {
      if (mounted) placeholder('Model eğitimi başlatılamadı.');
    }
  }

  Widget sectionHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget statusPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }

  Widget infoRow({
    required IconData icon,
    required String title,
    required String value,
    Color? color,
  }) {
    final effectiveColor = color ?? AppTheme.textPrimary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: effectiveColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: effectiveColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget settingSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    final enabled = onChanged != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: enabled ? AppTheme.textPrimary : AppTheme.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: enabled
                        ? AppTheme.textSecondary
                        : AppTheme.textMuted,
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget actionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool destructive = false,
  }) {
    final enabled = onPressed != null;
    final color = !enabled
        ? AppTheme.textMuted
        : destructive
        ? AppTheme.dangerRed
        : AppTheme.textPrimary;

    return SizedBox(
      height: 42,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17, color: color),
        label: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: destructive
                ? AppTheme.dangerRed.withValues(alpha: 0.3)
                : AppTheme.border,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget profileCard(UserProfile profile) {
    return PremiumCard(
      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: AppTheme.textPrimary,
              borderRadius: BorderRadius.circular(22),
            ),
            alignment: Alignment.center,
            child: Text(
              profile.initials,
              style: TextStyle(
                color: AppTheme.onPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.visibleName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Kişisel odak alanın',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    statusPill(profile.accountType, AppTheme.calmBlue),
                    statusPill(
                      '${languageLabel(language)} arayüz',
                      AppTheme.textSecondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          ElevatedButton.icon(
            onPressed: () => editProfile(profile),
            icon: Icon(Icons.edit_rounded, size: 17),
            label: Text('Profili düzenle'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget localAccountCard(UserProfile profile) {
    return PremiumCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionHeader(
            'Hesap ve Yerel Veri',
            'Profil, ayarlar ve oturum geçmişi bu cihazda yerel olarak yönetilir.',
          ),
          Row(
            children: [
              Expanded(
                child: statusPill(profile.accountType, AppTheme.calmBlue),
              ),
            ],
          ),
          const SizedBox(height: 16),
          infoRow(
            icon: Icons.person_rounded,
            title: 'Profil',
            value: '${profile.visibleName} · ${profile.accountType}',
            color: AppTheme.calmBlue,
          ),
          infoRow(
            icon: Icons.offline_bolt_rounded,
            title: 'Yerel oturum verisi',
            value: sessionCount == 0
                ? 'Henüz kayıtlı oturum yok. İlk oturumdan sonra burada özet görünür.'
                : '$sessionCount oturum bu cihazda hızlı erişime hazır.',
            color: AppTheme.textPrimary,
          ),
          infoRow(
            icon: Icons.schedule_rounded,
            title: 'Son oturum',
            value: formatDate(latestSessionAt),
            color: AppTheme.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget privacyCameraCard() {
    return PremiumCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionHeader(
            'Gizlilik ve Kamera',
            'Kamera yalnızca izin verilen oturumlarda çalışır; preview gizlense bile takip açık kalabilir.',
          ),
          infoRow(
            icon: Icons.videocam_rounded,
            title: 'Kamera izni',
            value:
                'Oturum başlatırken kamera seçilirse sistem izniyle çalışır.',
            color: AppTheme.calmBlue,
          ),
          settingSwitch(
            title: 'Kamera preview varsayılan görünür',
            subtitle:
                'Preview gizlendiğinde görüntü UI’dan kalkar; kamera açık oturumda takip devam eder.',
            value: cameraPreviewVisible,
            onChanged: (value) => saveSettings(
              AppSettingsService.current.copyWith(
                cameraPreviewDefaultVisible: value,
              ),
              value
                  ? 'Kamera preview varsayılan olarak görünür.'
                  : 'Kamera preview varsayılan olarak gizli.',
            ),
          ),
          actionButton(
            icon: Icons.privacy_tip_rounded,
            label: 'Kamera izinlerini kontrol et',
            onPressed: () async {
              try {
                final result = await apiService.checkCameraPermission();
                if (!mounted) return;
                placeholder('${result['message'] ?? 'Kamera kontrol edildi.'}');
              } catch (_) {
                if (mounted) {
                  placeholder('Kamera izni kontrol edilemedi.');
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget dataPrivacyCard() {
    return PremiumCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionHeader(
            'Veri ve Gizlilik',
            'Dışa aktarma, geçmiş temizleme ve yerel cache işlemlerini yönet.',
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              actionButton(
                icon: Icons.ios_share_rounded,
                label: 'Verilerimi dışa aktar',
                onPressed: () async {
                  try {
                    final result = await apiService.exportData();
                    if (!mounted) return;
                    placeholder(
                      'Dışa aktarıldı: ${result['export_path'] ?? ''}',
                    );
                  } catch (_) {
                    if (mounted) placeholder('Dışa aktarma başarısız oldu.');
                  }
                },
              ),
              actionButton(
                icon: Icons.cleaning_services_rounded,
                label: "Yerel cache'i temizle",
                onPressed: () async {
                  try {
                    final result = await apiService.clearCache();
                    if (!mounted) return;
                    placeholder('${result['message'] ?? 'Cache temizlendi.'}');
                  } catch (_) {
                    if (mounted) placeholder('Cache temizlenemedi.');
                  }
                },
              ),
              actionButton(
                icon: Icons.delete_outline_rounded,
                label: 'Oturum geçmişimi temizle',
                destructive: true,
                onPressed: () => confirmAndClearHistory(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget preferencesCard() {
    return PremiumCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionHeader(
            'Uygulama Tercihleri',
            'Bildirimler, tema ve canlı odak geri bildirimlerini yönet.',
          ),
          settingSwitch(
            title: 'Bildirimleri aç',
            subtitle:
                'Oturum ve mola hatırlatmaları için sistem bildirimi kullanılır.',
            value: notificationsEnabled,
            onChanged: toggleNotifications,
          ),
          infoRow(
            icon: notificationPermissionGranted
                ? Icons.notifications_active_rounded
                : Icons.notifications_off_rounded,
            title: 'macOS bildirim izni',
            value: notificationPermissionGranted
                ? 'Sistem bildirimi izni açık · $notificationPermissionStatus'
                : 'İzin kapalı · $notificationPermissionStatus',
            color: notificationPermissionGranted
                ? AppTheme.focusGreen
                : AppTheme.warningOrange,
          ),
          const SizedBox(height: 10),
          settingSwitch(
            title: 'Mola hatırlatmaları',
            subtitle:
                'Planlanan veya uzun çalışma sonrası sakin hatırlatma gösterilir.',
            value: breakRemindersEnabled,
            onChanged: notificationsEnabled
                ? (value) => saveSettings(
                    AppSettingsService.current.copyWith(
                      breakRemindersEnabled: value,
                    ),
                    value
                        ? 'Mola hatırlatmaları açıldı.'
                        : 'Mola hatırlatmaları kapatıldı.',
                  )
                : null,
          ),
          settingSwitch(
            title: 'Canlı odak bildirimi',
            subtitle:
                'Yalnızca kamera açık oturumlarda odak düşüşü için öneri üretir.',
            value: liveFocusNotificationsEnabled,
            onChanged: notificationsEnabled
                ? (value) => saveSettings(
                    AppSettingsService.current.copyWith(
                      liveFocusNotificationsEnabled: value,
                    ),
                    value
                        ? 'Canlı odak bildirimi açıldı.'
                        : 'Canlı odak bildirimi kapatıldı.',
                  )
                : null,
          ),
          const SizedBox(height: 4),
          Text(
            'Tema',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'light', label: Text('Açık')),
              ButtonSegment(value: 'dark', label: Text('Koyu')),
            ],
            selected: {themeMode},
            onSelectionChanged: (selection) {
              saveSettings(
                AppSettingsService.current.copyWith(themeMode: selection.first),
                '${themeLabel(selection.first)} tema açıldı.',
                showSuccess: false,
              );
            },
          ),
          const SizedBox(height: 18),
          Text(
            'Renk erişilebilirliği',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: colorVisionMode,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
            items: [
              DropdownMenuItem(value: 'standard', child: Text('Standart')),
              DropdownMenuItem(value: 'protanopia', child: Text('Protanopia')),
              DropdownMenuItem(
                value: 'deuteranopia',
                child: Text('Deuteranopia'),
              ),
              DropdownMenuItem(value: 'tritanopia', child: Text('Tritanopia')),
              DropdownMenuItem(
                value: 'achromatopsia',
                child: Text('Achromatopsia'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;

              saveSettings(
                AppSettingsService.current.copyWith(colorVisionMode: value),
                '${colorVisionLabel(value)} renk modu açıldı.',
                showSuccess: false,
              );
            },
          ),
          const SizedBox(height: 18),
          infoRow(
            icon: Icons.contrast_rounded,
            title: 'Tema',
            value: '${themeLabel(themeMode)} tema aktif.',
            color: AppTheme.textPrimary,
          ),
          infoRow(
            icon: Icons.translate_rounded,
            title: 'Dil',
            value: 'Türkçe arayüz aktif.',
            color: AppTheme.textPrimary,
          ),
          infoRow(
            icon: Icons.visibility_rounded,
            title: 'Renk modu',
            value:
                '${colorVisionLabel(colorVisionMode)} paleti odak, uyarı ve timeline renklerine uygulanır.',
            color: AppTheme.calmBlue,
          ),
        ],
      ),
    );
  }

  Widget modelCard() {
    final status = modelStatus();
    final color = modelColor();

    return PremiumCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionHeader(
            'Model / AI Durumu',
            'Kişisel odak modeli kamera açık oturumlardan öğrenir.',
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Kişisel odak modeli',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              statusPill(status, color),
            ],
          ),
          const SizedBox(height: 14),
          infoRow(
            icon: Icons.auto_awesome_rounded,
            title: 'Durum',
            value: modelSummary(),
            color: color,
          ),
          infoRow(
            icon: Icons.history_toggle_off_rounded,
            title: 'Son eğitim zamanı',
            value: cameraSessionCount >= 10
                ? formatDate(latestCameraSessionAt ?? latestSessionAt)
                : 'Henüz tamamlanmadı',
            color: AppTheme.calmBlue,
          ),
          actionButton(
            icon: Icons.model_training_rounded,
            label: 'Modeli yeniden eğit',
            onPressed: retrainModel,
          ),
        ],
      ),
    );
  }

  Widget settingsColumns(UserProfile profile) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 920;
        final left = Column(
          children: [
            localAccountCard(profile),
            const SizedBox(height: 16),
            privacyCameraCard(),
          ],
        );
        final right = Column(
          children: [
            preferencesCard(),
            const SizedBox(height: 16),
            modelCard(),
            const SizedBox(height: 16),
            dataPrivacyCard(),
          ],
        );

        if (!wide) {
          return Column(children: [left, const SizedBox(height: 16), right]);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 16),
            Expanded(child: right),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserProfile>(
      valueListenable: UserProfileService.profile,
      builder: (context, profile, _) {
        return Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: RefreshIndicator(
                onRefresh: loadDataState,
                child: ListView(
                  children: [
                    Text(
                      'Profil ve Ayarlar',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Hesap, gizlilik, kamera ve kişisel odak tercihleri.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 15,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 24),
                    profileCard(profile),
                    const SizedBox(height: 18),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.all(36),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      settingsColumns(profile),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
