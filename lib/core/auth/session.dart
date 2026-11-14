import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';
import '../platform/platform_providers.dart';

/// The signed-in account, reduced to the fields the app needs for routing and
/// personalisation. Tokens live in secure storage via [ApiClient].
class SessionUser {
  final String id;
  final String name;
  final String username;
  final String phone;
  final String role;
  final List<String> roles;
  final String? agencyName;

  const SessionUser({
    required this.id,
    required this.name,
    required this.username,
    required this.phone,
    required this.role,
    required this.roles,
    this.agencyName,
  });

  bool get isAgent => roles.contains('agent');

  factory SessionUser.fromJson(Map<String, dynamic> json) {
    final rawRoles = json['roles'];
    final roles = rawRoles is List
        ? rawRoles.map((r) => r.toString()).toList()
        : <String>[if (json['role'] != null) json['role'].toString()];
    if (roles.isEmpty && json['role'] != null) {
      roles.add(json['role'].toString());
    }
    final agency = json['agency'];
    return SessionUser(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: json['name'] as String? ?? '',
      username: json['username'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      role: json['role'] as String? ?? (roles.isNotEmpty ? roles.first : 'user'),
      roles: roles,
      agencyName: agency is Map ? agency['name'] as String? : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'username': username,
        'phone': phone,
        'role': role,
        'roles': roles,
        'agency': agencyName == null ? null : {'name': agencyName},
      };
}

/// Holds the current session in memory and persists the public user payload so
/// the app can route on cold start even before `/auth/profile` responds.
class SessionController extends StateNotifier<SessionUser?> {
  static const _storageKey = 'katisha_session_user_v1';

  final ApiClient _api;
  final SharedPreferences _prefs;

  SessionController(this._api, this._prefs) : super(null);

  bool get isAuthenticated => _api.isAuthenticated;

  String? get accessToken => _api.accessToken;

  /// Restores the session from secure tokens plus the cached public profile.
  /// Refreshes from the server when possible; never throws.
  Future<void> restore() async {
    if (!_api.isAuthenticated) {
      state = null;
      return;
    }

    final cached = _readCached();
    if (cached != null) state = cached;

    try {
      final response = await _api.get('/auth/profile');
      final data = response.data;
      Map<String, dynamic>? userJson;
      if (data is Map<String, dynamic>) {
        final nested = data['user'];
        if (nested is Map) {
          userJson = Map<String, dynamic>.from(nested);
        } else if (data['id'] != null || data['_id'] != null) {
          userJson = data;
        }
      }
      if (userJson != null &&
          (userJson['id'] != null || userJson['_id'] != null)) {
        final user = SessionUser.fromJson(userJson);
        state = user;
        await _save(user);
        return;
      }
    } catch (e) {
      debugPrint('[Session] Profile refresh failed: $e');
    }

    // If no cached user and the profile is unavailable, keep cached/unknown
    // state; the login screen is still reachable.
  }

  /// Signs in with phone/username + password, persists the tokens, and returns
  /// the authenticated account so the caller can route by role.
  Future<SessionUser> login({
    required String identifier,
    required String password,
  }) async {
    final response = await _api.post(
      '/auth/login',
      data: {'identifier': identifier.trim(), 'password': password},
    );
    final data = response.data as Map<String, dynamic>;
    final accessToken = data['accessToken'] as String?;
    final refreshToken = data['refreshToken'] as String?;
    if (accessToken == null || refreshToken == null) {
      throw StateError('Login response did not include tokens');
    }
    await _api.setTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );

    final userJson = data['user'] as Map<String, dynamic>? ??
        (data['user'] is Map
            ? Map<String, dynamic>.from(data['user'] as Map)
            : <String, dynamic>{});
    final user = SessionUser.fromJson(userJson);
    state = user;
    await _save(user);
    return user;
  }

  Future<void> logout() async {
    await _api.clearTokens();
    await _prefs.remove(_storageKey);
    state = null;
  }

  SessionUser? _readCached() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return SessionUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(SessionUser user) async {
    try {
      await _prefs.setString(_storageKey, jsonEncode(user.toJson()));
    } catch (_) {}
  }
}

final sessionProvider =
    StateNotifierProvider<SessionController, SessionUser?>((ref) {
  return SessionController(
    ref.read(apiClientProvider),
    ref.read(sharedPreferencesProvider),
  );
});
