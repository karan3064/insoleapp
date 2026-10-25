/// Mirrors `store/modules/auth.js`'s `emptyProfile()` shape.
class UserProfile {
  final double? heightCm;
  final double? weightKg;
  final String? displayName;
  final String? sex; // 'male' | 'female' | 'other'
  final String? birthDate; // ISO date string
  final String? avatarUrl;

  /// An optional recovery reference point the patient/clinician can set
  /// (e.g. "Right knee surgery", dated) -- lets `RecoveryAnalysis` compare
  /// weight-bearing right after it to the most recent sessions, so
  /// "how much have they improved" has a concrete before/after instead of
  /// just a generic recent trend.
  final String? recoveryMilestoneDate; // ISO date string
  final String? recoveryMilestoneLabel;

  /// Which condition the milestone is for, stored as a `RecoveryCondition`
  /// enum name (see `recovery_analysis.dart`) -- lets `RecoveryAnalysis`
  /// attach literature-sourced context specific to that condition (e.g.
  /// typical ACL-reconstruction recovery timelines) instead of only a
  /// generic trend. Null/unrecognized values just mean no condition-
  /// specific context is shown.
  final String? recoveryConditionType;

  const UserProfile({
    this.heightCm,
    this.weightKg,
    this.displayName,
    this.sex,
    this.birthDate,
    this.avatarUrl,
    this.recoveryMilestoneDate,
    this.recoveryMilestoneLabel,
    this.recoveryConditionType,
  });

  static const empty = UserProfile();

  UserProfile copyWith({
    double? heightCm,
    double? weightKg,
    String? displayName,
    String? sex,
    String? birthDate,
    String? avatarUrl,
    String? recoveryMilestoneDate,
    String? recoveryMilestoneLabel,
    String? recoveryConditionType,
  }) {
    return UserProfile(
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      displayName: displayName ?? this.displayName,
      sex: sex ?? this.sex,
      birthDate: birthDate ?? this.birthDate,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      recoveryMilestoneDate: recoveryMilestoneDate ?? this.recoveryMilestoneDate,
      recoveryMilestoneLabel: recoveryMilestoneLabel ?? this.recoveryMilestoneLabel,
      recoveryConditionType: recoveryConditionType ?? this.recoveryConditionType,
    );
  }

  Map<String, dynamic> toJson() => {
        'heightCm': heightCm,
        'weightKg': weightKg,
        'displayName': displayName,
        'sex': sex,
        'birthDate': birthDate,
        'avatarUrl': avatarUrl,
        'recoveryMilestoneDate': recoveryMilestoneDate,
        'recoveryMilestoneLabel': recoveryMilestoneLabel,
        'recoveryConditionType': recoveryConditionType,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        heightCm: (json['heightCm'] as num?)?.toDouble(),
        weightKg: (json['weightKg'] as num?)?.toDouble(),
        displayName: json['displayName'] as String?,
        sex: json['sex'] as String?,
        birthDate: json['birthDate'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        recoveryMilestoneDate: json['recoveryMilestoneDate'] as String?,
        recoveryMilestoneLabel: json['recoveryMilestoneLabel'] as String?,
        recoveryConditionType: json['recoveryConditionType'] as String?,
      );
}
