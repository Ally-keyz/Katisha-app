import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _screenSecurityChannel = MethodChannel(
  'rw.katisha.today/screen_security',
);

/// Enables screenshot protection (Android: FLAG_SECURE) for [duration].
///
/// On iOS screenshotting cannot be blocked by third-party apps, so this is a
/// no-op there. Call [enable] when a protected screen is shown and [disable]
/// when it is popped.
class ScreenSecurity {
  static bool _enabled = false;

  /// Enables screenshot prevention for the current window.
  static Future<void> enable() async {
    if (_enabled) return;
    _enabled = true;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _screenSecurityChannel.invokeMethod('enableSecureFlag');
      } catch (_) {}
    }
  }

  /// Disables screenshot prevention.
  static Future<void> disable() async {
    _enabled = false;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _screenSecurityChannel.invokeMethod('disableSecureFlag');
      } catch (_) {}
    }
  }
}
