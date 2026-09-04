/// Mobile application roles.
/// Only the User role is supported on mobile.
enum AppRole {
  user('user');

  final String value;
  const AppRole(this.value);

  /// Parses a role string from the backend JWT or profile response.
  factory AppRole.fromString(String value) {
    return switch (value) {
      'user' || 'regular_user' => AppRole.user,
      _ => AppRole.user,
    };
  }
}
