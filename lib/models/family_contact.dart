/// A family member who should be alerted if the patient leaves their
/// [SafeZone]. There's no separate login for family members -- they join
/// via an invite code (see `JoinFamilyContactScreen`), which registers
/// their device's push token onto this same document. Until they do,
/// [fcmToken] is null and they're only reachable by email.
class FamilyContact {
  final String id;
  final String name;
  final String email;
  final String? fcmToken;

  const FamilyContact({
    required this.id,
    required this.name,
    required this.email,
    this.fcmToken,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'fcmToken': fcmToken,
      };

  factory FamilyContact.fromJson(String id, Map<String, dynamic> json) => FamilyContact(
        id: id,
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        fcmToken: json['fcmToken'] as String?,
      );
}
