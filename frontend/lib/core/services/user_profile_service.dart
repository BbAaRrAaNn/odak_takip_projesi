import 'package:flutter/foundation.dart';

import 'api_service.dart';

class UserProfile {
  final String displayName;
  final bool premium;

  const UserProfile({required this.displayName, required this.premium});

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      displayName: '${json['display_name'] ?? json['displayName'] ?? ''}',
      premium: json['premium'] == true,
    );
  }

  String get visibleName {
    final trimmed = displayName.trim();
    return trimmed.isEmpty ? 'FocusVision kullanıcısı' : trimmed;
  }

  String get accountType {
    if (premium) return 'Premium';
    return 'Yerel hesap';
  }

  String get initials {
    final words = visibleName
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .toList();

    if (words.isEmpty) return 'FV';

    return words
        .take(2)
        .map((word) => word.substring(0, 1).toUpperCase())
        .join();
  }

  UserProfile copyWith({String? displayName, bool? premium}) {
    return UserProfile(
      displayName: displayName ?? this.displayName,
      premium: premium ?? this.premium,
    );
  }
}

class UserProfileService {
  static final ValueNotifier<UserProfile> profile = ValueNotifier<UserProfile>(
    const UserProfile(displayName: '', premium: false),
  );

  static UserProfile get current => profile.value;

  static Future<void> loadProfile() async {
    final response = await ApiService().getProfile();
    final profileData = Map<String, dynamic>.from(response['profile'] ?? {});

    profile.value = UserProfile.fromJson(profileData);
  }

  static Future<void> updateProfile({required String displayName}) async {
    final next = profile.value.copyWith(displayName: displayName);

    profile.value = next;

    final response = await ApiService().updateProfile(displayName: displayName);
    final profileData = Map<String, dynamic>.from(response['profile'] ?? {});

    profile.value = UserProfile.fromJson(profileData);
  }
}
