enum AppRole { superAdmin, businessOwner, dispatcher, rider }

AppRole appRoleFromString(String s) => switch (s) {
      'super_admin'    => AppRole.superAdmin,
      'business_owner' => AppRole.businessOwner,
      'dispatcher'     => AppRole.dispatcher,
      'rider'          => AppRole.rider,
      _                => AppRole.rider,
    };

class Profile {
  const Profile({
    required this.userId,
    required this.role,
    this.fullName,
    this.phone,
    this.avatarUrl,
  });

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        userId: j['user_id'] as String,
        role: appRoleFromString(j['role'] as String),
        fullName: j['full_name'] as String?,
        phone: j['phone'] as String?,
        avatarUrl: j['avatar_url'] as String?,
      );

  final String userId;
  final AppRole role;
  final String? fullName;
  final String? phone;
  final String? avatarUrl;

  String homeRoute() => switch (role) {
        AppRole.superAdmin    => '/d/home',
        AppRole.dispatcher    => '/d/home',
        AppRole.businessOwner => '/b/home',
        AppRole.rider         => '/r/home',
      };
}
