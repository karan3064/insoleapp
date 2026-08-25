/// Mirrors `store/modules/auth.js`'s `emptyProfile()` shape.
class UserProfile {
  final double? heightCm;
  final double? weightKg;
  final String? displayName;
  final String? sex; // 'male' | 'female' | 'other'
  final String? birthDate; // ISO date string
  final String? avatarUrl;

  const UserProfile({
    this.heightCm,
    this.weightKg,
    this.displayName,
    this.sex,
    this.birthDate,
    this.avatarUrl,
  });

  static const empty = UserProfile();

  UserProfile copyWith({
    double? heightCm,
    double? weightKg,
    String? displayName,
    String? sex,
    String? birthDate,
    String? avatarUrl,
  }) {
    return UserProfile(
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      displayName: displayName ?? this.displayName,
      sex: sex ?? this.sex,
      birthDate: birthDate ?? this.birthDate,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'heightCm': heightCm,
        'weightKg': weightKg,
        'displayName': displayName,
        'sex': sex,
        'birthDate': birthDate,
        'avatarUrl': avatarUrl,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        heightCm: (json['heightCm'] as num?)?.toDouble(),
        weightKg: (json['weightKg'] as num?)?.toDouble(),
        displayName: json['displayName'] as String?,
        sex: json['sex'] as String?,
        birthDate: json['birthDate'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
      );
}
