import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/analytics/analytics_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/session/live_session_screen.dart';
import '../../features/session/new_session_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../core/services/api_service.dart';
import '../../core/services/app_settings_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/user_profile_service.dart';
import '../theme/app_theme.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  final ApiService apiService = ApiService();
  StreamSubscription<String>? notificationActionSub;

  int selectedIndex = 0;

  final List<Widget> screens = const [
    DashboardScreen(),
    NewSessionScreen(),
    HistoryScreen(),
    AnalyticsScreen(),
    SettingsScreen(),
  ];

  final List<_NavigationItem> items = const [
    _NavigationItem(title: 'Ana Sayfa', icon: Icons.home_rounded),
    _NavigationItem(title: 'Oturum', icon: Icons.timer_rounded),
    _NavigationItem(title: 'Geçmiş', icon: Icons.history_rounded),
    _NavigationItem(title: 'Analitik', icon: Icons.insights_rounded),
    _NavigationItem(title: 'Ayarlar', icon: Icons.tune_rounded),
  ];

  @override
  void initState() {
    super.initState();

    notificationActionSub = NotificationService.actionStream.listen(
      openLiveSessionFromNotification,
    );
  }

  Future<void> openLiveSessionFromNotification(String action) async {
    if (!mounted) return;

    final route = ModalRoute.of(context);

    if (route?.isCurrent != true) return;

    try {
      final response = await apiService.getLiveStatus();
      final live = Map<String, dynamic>.from(response['live_status'] ?? {});

      if (live['session_active'] != true) return;
    } catch (_) {
      return;
    }

    if (!mounted) return;

    setState(() {
      selectedIndex = 1;
    });

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveSessionScreen(initialNotificationAction: action),
      ),
    );
  }

  @override
  void dispose() {
    notificationActionSub?.cancel();
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

        final selectedNavFill = Color.lerp(
          AppTheme.surface,
          AppTheme.calmBlue,
          AppTheme.isDark ? 0.20 : 0.11,
        )!;
        final screenKey = ValueKey(
          'screen-$selectedIndex-${settings.themeMode}-${settings.colorVisionMode}',
        );

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: Row(
            children: [
              Container(
                width: 236,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  border: Border(right: BorderSide(color: AppTheme.border)),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 240),
                              curve: Curves.easeOutCubic,
                              width: 44,
                              height: 44,
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: AppTheme.isDark
                                    ? AppTheme.surfaceMuted
                                    : AppTheme.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: AppTheme.border.withValues(
                                    alpha: AppTheme.isDark ? 0.72 : 0.92,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: AppTheme.isDark ? 0.24 : 0.06,
                                    ),
                                    blurRadius: 14,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/brand/app_mark.png',
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'FocusVision',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Container(height: 1, color: AppTheme.border),
                        const SizedBox(height: 18),
                        ...List.generate(items.length, (index) {
                          final item = items[index];
                          final selected = selectedIndex == index;

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                selectedIndex = index;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 13,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? selectedNavFill
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(14),
                                border: selected
                                    ? Border.all(
                                        color: AppTheme.calmBlue.withValues(
                                          alpha: 0.42,
                                        ),
                                      )
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    curve: Curves.easeOutCubic,
                                    width: 3,
                                    height: selected ? 22 : 10,
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? AppTheme.calmBlue
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Icon(
                                    item.icon,
                                    color: selected
                                        ? AppTheme.calmBlue
                                        : AppTheme.textSecondary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: selected
                                            ? AppTheme.textPrimary
                                            : AppTheme.textSecondary,
                                        fontSize: 14,
                                        fontWeight: selected
                                            ? FontWeight.w900
                                            : FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceMuted,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: AppTheme.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppTheme.border),
                                ),
                                child: Icon(
                                  Icons.person_rounded,
                                  color: AppTheme.textPrimary,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ValueListenableBuilder<UserProfile>(
                                  valueListenable: UserProfileService.profile,
                                  builder: (context, profile, _) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          profile.visibleName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: AppTheme.textPrimary,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          profile.accountType,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: KeyedSubtree(
                  key: screenKey,
                  child: screens[selectedIndex],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NavigationItem {
  final String title;
  final IconData icon;

  const _NavigationItem({required this.title, required this.icon});
}
