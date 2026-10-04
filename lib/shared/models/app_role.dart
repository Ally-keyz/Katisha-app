/// Mobile application roles.
///
/// The backend keeps a legacy single `role` field plus an authoritative `roles[]`
/// array (see `server/src/utils/authUser.ts`), so parsing has to consider both:
/// a promoter account may still carry `role: 'user'` from before the multi-role
/// backfill.
enum AppRole {
  user('user'),
  promoter('promoter');

  final String value;
  const AppRole(this.value);

  /// Parses a single role string from the backend JWT or profile response.
  factory AppRole.fromString(String value) {
    return switch (value) {
      'user' || 'regular_user' => AppRole.user,
      'promoter' => AppRole.promoter,
      _ => AppRole.user,
    };
  }

  /// Whether an authenticated user payload grants [role].
  ///
  /// Checks `roles[]` first and falls back to the legacy `role` field, so an
  /// account created before the backfill still resolves correctly.
  static bool hasRole(Map<String, dynamic> json, AppRole role) {
    final roles = json['roles'];
    if (roles is List && roles.contains(role.value)) return true;
    return json['role'] == role.value;
  }

  /// Resolves the primary role for an authenticated user payload.
  ///
  /// `promoter` deliberately wins over the legacy `role` value: the promoter
  /// programme is a distinct surface, and treating a promoter as a plain user
  /// would hide their dashboard.
  static AppRole fromUserJson(Map<String, dynamic> json) {
    if (hasRole(json, AppRole.promoter)) return AppRole.promoter;
    return AppRole.fromString(json['role'] as String? ?? 'user');
  }
}
