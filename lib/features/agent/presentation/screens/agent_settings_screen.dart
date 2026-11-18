import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/socket_service.dart';
import '../../../../core/platform/platform_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Neutral tones used by this screen. Kept local so the redesign does not
/// touch the shared palette.
const Color _kGray = Color(0xFFF3F4F6); // card / input fill
const Color _kGrayStrong = Color(0xFFE5E7EB); // subtle dividers, pressed states
const Color _kSuccess = Color(0xFF15803D);
const Color _kSuccessBg = Color(0xFFECFDF3);

const double _kRadius = 16;
const double _kFieldRadius = 12;

/// Settings tab of the agent portal.
///
/// Holds the two things a field agent may need to change from the counter:
/// their password and the device's notification permission.
class AgentSettingsView extends ConsumerStatefulWidget {
  const AgentSettingsView({super.key, required this.onLogout});

  final Future<void> Function() onLogout;

  @override
  ConsumerState<AgentSettingsView> createState() => _AgentSettingsViewState();
}

class _AgentSettingsViewState extends ConsumerState<AgentSettingsView> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _saving = false;
  String? _error;
  bool _success = false;

  bool? _alertsEnabled;
  bool _checkingAlerts = true;
  bool _requestingAlerts = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshAlertState());
  }

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _refreshAlertState() async {
    if (!mounted) return;
    setState(() => _checkingAlerts = true);
    final enabled = await ref
        .read(notificationServiceProvider)
        .notificationsEnabled();
    if (!mounted) return;
    setState(() {
      _alertsEnabled = enabled;
      _checkingAlerts = false;
    });
  }

  Future<void> _enableAlerts() async {
    if (_requestingAlerts) return;
    setState(() => _requestingAlerts = true);
    final granted = await ref
        .read(notificationServiceProvider)
        .requestPermission();
    if (!mounted) return;
    setState(() => _requestingAlerts = false);
    await _refreshAlertState();
    if (!mounted) return;
    _showSnack(
      granted
          ? 'Device alerts are on.'
          : 'Alerts are blocked. Allow notifications for Katisha in your phone settings.',
      isError: !granted,
    );
  }

  Future<void> _sendTestAlert() async {
    await ref
        .read(notificationServiceProvider)
        .showImmediateAlert(
          title: 'Katisha alerts are working',
          body: 'You will be notified about paid bookings and bookings that need attention.',
          type: 'agent_settings_test',
          // Exercise the same loud, actionable channel as a real alarm.
          alarm: true,
        );
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
      _success = false;
    });

    try {
      await ref
          .read(sessionProvider.notifier)
          .changePassword(
            currentPassword: _currentController.text,
            newPassword: _newController.text,
            confirmPassword: _confirmController.text,
          );
      if (!mounted) return;
      _currentController.clear();
      _newController.clear();
      _confirmController.clear();
      setState(() {
        _saving = false;
        _success = true;
      });

      // The socket authenticated with the previous access token, which the
      // rotation just invalidated. Reconnect with the fresh one so real-time
      // booking alerts keep arriving on this device.
      try {
        final socket = ref.read(socketServiceProvider);
        final token = ref.read(apiClientProvider).accessToken;
        socket.disconnect();
        if (token != null && token.isNotEmpty) {
          unawaited(socket.connect(token));
        }
      } catch (_) {
        // Realtime is best-effort; a later sign-in reconnects it.
      }

      _showSnack('Password changed successfully.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _messageFor(error);
      });
    }
  }

  String _messageFor(Object error) {
    if (error is DioException) return ApiClient.mapDioError(error).message;
    if (error is Failure) return error.message;
    return 'Could not change your password. Please try again.';
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? AppColors.error : AppColors.text,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        _buildProfileCard(user),
        const SizedBox(height: 32),
        _sectionHeader(
          'Password',
          'Choose a strong password you don’t use elsewhere.',
        ),
        const SizedBox(height: 16),
        _buildPasswordSection(),
        const SizedBox(height: 32),
        _sectionHeader(
          'Notifications',
          'Get alerted the moment a booking comes in.',
        ),
        const SizedBox(height: 16),
        _buildNotificationsCard(),
        const SizedBox(height: 32),
        _buildLogoutTile(),
      ],
    );
  }

  // ── Profile ───────────────────────────────────────────────────────────────

  Widget _buildProfileCard(SessionUser? user) {
    final name = (user?.name.trim().isNotEmpty ?? false)
        ? user!.name.trim()
        : (user?.username.trim().isNotEmpty == true ? user!.username : 'Agent');
    final initials = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first.toUpperCase())
        .join();

    final secondary = user?.username.isNotEmpty == true
        ? '@${user!.username}'
        : (user?.phone.isNotEmpty == true ? user!.phone : 'Field agent');
    final agency = user?.agencyName;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kGray,
        borderRadius: BorderRadius.circular(_kRadius + 4),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initials.isEmpty ? 'A' : initials,
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.text,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.text,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  secondary,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSub,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (agency != null && agency.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    agency,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            ),
            child: Text(
              'Agent',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Password ──────────────────────────────────────────────────────────────

  /// Flat section: no card, no border. The filled fields carry the structure.
  Widget _buildPasswordSection() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_success) ...[
            _banner(
              icon: Icons.check_circle_rounded,
              color: _kSuccess,
              background: _kSuccessBg,
              message: 'Your password has been updated.',
            ),
            const SizedBox(height: 16),
          ],
          if (_error != null) ...[
            _banner(
              icon: Icons.error_rounded,
              color: AppColors.error,
              background: AppColors.errorBg,
              message: _error!,
            ),
            const SizedBox(height: 16),
          ],

          TextFormField(
            controller: _currentController,
            obscureText: _obscureCurrent,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.password],
            decoration: _fieldDecoration(
              label: 'Current password',
              obscured: _obscureCurrent,
              onToggle: () =>
                  setState(() => _obscureCurrent = !_obscureCurrent),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Enter your current password';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _newController,
            obscureText: _obscureNew,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            decoration: _fieldDecoration(
              label: 'New password',
              helper: 'At least 8 characters',
              obscured: _obscureNew,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Enter a new password';
              }
              if (value.length < 8) {
                return 'Use at least 8 characters';
              }
              if (value.length > 128) {
                return 'Use at most 128 characters';
              }
              if (value == _currentController.text) {
                return 'The new password must be different';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _confirmController,
            obscureText: _obscureConfirm,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            onFieldSubmitted: (_) => _submit(),
            decoration: _fieldDecoration(
              label: 'Confirm new password',
              obscured: _obscureConfirm,
              onToggle: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Re-enter the new password';
              }
              if (value != _newController.text) {
                return 'The two new passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          FilledButton(
            onPressed: _saving ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
              disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.6),
              disabledForegroundColor: AppColors.white,
              elevation: 0,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_kFieldRadius),
              ),
              textStyle: AppTypography.buttonMedium,
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.white,
                    ),
                  )
                : const Text('Update password'),
          ),
          const SizedBox(height: 12),
          Text(
            'Changing your password signs you out on any other device.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required bool obscured,
    required VoidCallback onToggle,
    String? helper,
  }) {
    OutlineInputBorder border(Color color, [double width = 0]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(_kFieldRadius),
          borderSide: width == 0
              ? BorderSide.none
              : BorderSide(color: color, width: width),
        );

    return InputDecoration(
      labelText: label,
      helperText: helper,
      helperStyle: AppTypography.bodySmall.copyWith(
        color: AppColors.textMuted,
      ),
      labelStyle: AppTypography.bodyMedium.copyWith(
        color: AppColors.textSub,
      ),
      floatingLabelStyle: AppTypography.bodySmall.copyWith(
        color: AppColors.textSub,
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: _kGray,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(Colors.transparent),
      enabledBorder: border(Colors.transparent),
      disabledBorder: border(Colors.transparent),
      focusedBorder: border(AppColors.primary, 1.5),
      errorBorder: border(AppColors.error, 1.2),
      focusedErrorBorder: border(AppColors.error, 1.5),
      suffixIcon: _visibilityToggle(obscured: obscured, onPressed: onToggle),
    );
  }

  Widget _visibilityToggle({
    required bool obscured,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      tooltip: obscured ? 'Show password' : 'Hide password',
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 20,
        color: AppColors.textSub,
      ),
    );
  }

  // ── Notifications ─────────────────────────────────────────────────────────

  Widget _buildNotificationsCard() {
    final enabled = _alertsEnabled;
    final (
      Color color,
      IconData icon,
      String title,
      String subtitle,
    ) = switch (enabled) {
      true => (
        _kSuccess,
        Icons.notifications_active_rounded,
        'Alerts are on',
        'You’ll be notified about new, paid and cancelled bookings.',
      ),
      false => (
        AppColors.error,
        Icons.notifications_off_rounded,
        'Alerts are blocked',
        'Allow notifications for Katisha in your phone settings.',
      ),
      null => (
        AppColors.textMuted,
        Icons.notifications_none_rounded,
        'Device alerts',
        'Checking whether this phone can receive alerts.',
      ),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kGray,
        borderRadius: BorderRadius.circular(_kRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: AppColors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.titleSmall.copyWith(
                        color: AppColors.text,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSub,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              if (_checkingAlerts) ...[
                const SizedBox(width: 10),
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (enabled != true) ...[
                Expanded(
                  child: FilledButton(
                    onPressed: _requestingAlerts ? null : _enableAlerts,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      disabledBackgroundColor: AppColors.primary.withValues(
                        alpha: 0.6,
                      ),
                      disabledForegroundColor: AppColors.white,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_kFieldRadius),
                      ),
                      textStyle: AppTypography.buttonSmall,
                    ),
                    child: _requestingAlerts
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.white,
                            ),
                          )
                        : const Text('Enable alerts'),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: _sendTestAlert,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.white,
                    foregroundColor: AppColors.text,
                    elevation: 0,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_kFieldRadius),
                    ),
                    textStyle: AppTypography.buttonSmall.copyWith(
                      color: AppColors.text,
                    ),
                  ),
                  child: const Text('Send test'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Widget _buildLogoutTile() {
    return Material(
      color: AppColors.errorBg,
      borderRadius: BorderRadius.circular(_kRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onLogout,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              const Icon(
                Icons.logout_rounded,
                size: 20,
                color: AppColors.error,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Log out',
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.error.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Shared bits ───────────────────────────────────────────────────────────

  Widget _sectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.titleMedium.copyWith(
            color: AppColors.text,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textMuted,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _banner({
    required IconData icon,
    required Color color,
    required Color background,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(_kFieldRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}