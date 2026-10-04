import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/katisha_modal.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/application/auth_controller.dart';
import '../../application/promoter_providers.dart';
import '../../data/models/promoter_models.dart';
import '../widgets/promoter_ui.dart';

/// Built once: a new `RegExp` was being allocated on every build (and again on
/// every keystroke, in the validator), and `TextFormField` re-registers its
/// `inputFormatters` whenever the list identity changes.
final _phoneFormatter =
    FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'));
final _nonDigitPattern = RegExp(r'[^0-9]');

/// Promoter settings, presented inside the shared 89%-height Katisha modal.
///
/// Two tabs mirror the web promoter settings: the payout number that receives
/// mobile money, and a password change. Both are sensitive, which is why this
/// is a modal with an explicit Close rather than a pushed screen.
class PromoterSettingsModal extends ConsumerStatefulWidget {
  const PromoterSettingsModal({super.key});

  @override
  ConsumerState<PromoterSettingsModal> createState() =>
      _PromoterSettingsModalState();
}

class _PromoterSettingsModalState extends ConsumerState<PromoterSettingsModal>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );

  PromoterProfile? _profile;
  bool _loadingProfile = true;
  String? _profileError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final result = await ref.read(promoterRepositoryProvider).getProfile();
    if (!mounted) return;

    result.fold(
      (failure) => setState(() {
        _profileError = failure.message;
        _loadingProfile = false;
      }),
      (profile) => setState(() {
        _profile = profile;
        _loadingProfile = false;
        _profileError = null;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return KatishaModal(
      title: l10n.translate('promoter_settings_title'),
      bodyScrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSub,
            indicatorColor: AppColors.primary,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: AppColors.border,
            labelStyle: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
            ),
            tabs: [
              Tab(text: l10n.translate('promoter_tab_payout')),
              Tab(text: l10n.translate('promoter_tab_security')),
            ],
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _PayoutTab(
                  profile: _profile,
                  loading: _loadingProfile,
                  error: _profileError,
                  onRetry: _loadProfile,
                  onSaved: (profile) => setState(() => _profile = profile),
                ),
                const _SecurityTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Payout tab ────────────────────────────────────────

class _PayoutTab extends ConsumerStatefulWidget {
  final PromoterProfile? profile;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<PromoterProfile> onSaved;

  const _PayoutTab({
    required this.profile,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onSaved,
  });

  @override
  ConsumerState<_PayoutTab> createState() => _PayoutTabState();
}

class _PayoutTabState extends ConsumerState<_PayoutTab> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;
  bool _prefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prefill();
  }

  @override
  void didUpdateWidget(_PayoutTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile?.payoutPhone != widget.profile?.payoutPhone) {
      _prefill();
    }
  }

  /// Seeds the field from the server value, but only once per profile value so
  /// typing is never overwritten by a rebuild.
  void _prefill() {
    if (_prefilled) return;
    final phone = widget.profile?.payoutPhone;
    if (phone == null || phone.isEmpty) return;
    _phoneController.text = phone;
    _prefilled = true;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_busy) return;

    setState(() {
      _busy = true;
      _message = null;
    });

    final result = await ref
        .read(promoterRepositoryProvider)
        .updatePayoutPhone(_phoneController.text.trim());

    if (!mounted) return;

    result.fold(
      (failure) => setState(() {
        _busy = false;
        _message = failure.message;
        _messageIsError = true;
      }),
      (profile) {
        setState(() {
          _busy = false;
          _messageIsError = false;
          _message = AppLocalizations.of(
            context,
          ).translate('promoter_payout_phone_saved');
        });
        widget.onSaved(profile);
        ref.read(promoterDataVersionProvider.notifier).state++;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = widget.profile;

    if (widget.loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 3));
    }
    if (widget.error != null && profile == null) {
      return PromoterErrorView(message: widget.error!, onRetry: widget.onRetry);
    }

    final suspended =
        profile != null &&
        PromoterStatus.parse(profile.status) == PromoterStatus.suspended;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (profile != null) ...[
              _infoRow(
                l10n.translate('promoter_commission_rate'),
                '${profile.commissionRate.round()}%',
              ),
              const SizedBox(height: AppSpacing.sm),
              _infoRow(
                l10n.translate('promoter_your_code'),
                profile.promoterCode ?? '-',
              ),
              const SizedBox(height: AppSpacing.sm),
              _infoRow(
                l10n.translate('promoter_payout_phone'),
                profile.hasCustomPayoutPhone
                    ? profile.payoutPhone
                    : '${profile.payoutPhone} (${l10n.translate("promoter_using_account_phone")})',
              ),
              const SizedBox(height: AppSpacing.lg),
              Divider(color: AppColors.border),
              const SizedBox(height: AppSpacing.lg),
            ],

            Text(
              l10n.translate('promoter_payout_phone'),
              style: AppTypography.titleSmall.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.translate('promoter_payout_phone_hint'),
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSub),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              enabled: !suspended && !_busy,
              style: AppTypography.bodyLarge,
              inputFormatters: [_phoneFormatter],
              decoration: InputDecoration(
                hintText: '0788 000 007',
                prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                filled: true,
                fillColor: AppColors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                border: _border(),
                enabledBorder: _border(),
                focusedBorder: _border(focused: true),
                disabledBorder: _border(),
              ),
              validator: (value) {
                if (suspended) return null;
                final digits = (value ?? '').replaceAll(_nonDigitPattern, '');
                if (digits.length < 9) {
                  return l10n.translate('promoter_invalid_phone');
                }
                return null;
              },
            ),

            if (suspended) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.errorBg,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(color: AppColors.errorBorder),
                ),
                child: Text(
                  l10n.translate('promoter_suspended_cannot_change_phone'),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
            ],

            if (_message != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: _messageIsError
                      ? AppColors.errorBg
                      : AppColors.successBg,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(
                    color: _messageIsError
                        ? AppColors.errorBorder
                        : AppColors.primaryLight,
                  ),
                ),
                child: Text(
                  _message!,
                  style: AppTypography.bodySmall.copyWith(
                    color: _messageIsError
                        ? AppColors.error
                        : AppColors.primary,
                  ),
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.lg),
            KatishaModalAction(
              label: l10n.translate('save'),
              busy: _busy,
              onPressed: suspended ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: AppTypography.bodySmall.copyWith(color: AppColors.textSub),
          ),
        ),
        Expanded(
          flex: 5,
          child: Text(
            value,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _border({bool focused = false}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      borderSide: BorderSide(
        color: focused ? AppColors.primary : AppColors.border,
        width: focused ? 2 : 1,
      ),
    );
  }
}

// ── Security tab ──────────────────────────────────────

class _SecurityTab extends ConsumerStatefulWidget {
  const _SecurityTab();

  @override
  ConsumerState<_SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends ConsumerState<_SecurityTab> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_busy) return;

    setState(() {
      _busy = true;
      _message = null;
    });

    final result = await ref
        .read(authRepositoryProvider)
        .changePassword(
          currentPassword: _currentController.text,
          newPassword: _newController.text,
        );

    if (!mounted) return;

    result.fold(
      (failure) => setState(() {
        _busy = false;
        _message = failure.message;
        _messageIsError = true;
      }),
      (_) {
        setState(() {
          _busy = false;
          _messageIsError = false;
          _message = AppLocalizations.of(
            context,
          ).translate('promoter_password_changed');
        });
        _currentController.clear();
        _newController.clear();
        _confirmController.clear();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.translate('promoter_change_password'),
              style: AppTypography.titleSmall.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.translate('promoter_change_password_hint'),
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSub),
            ),
            const SizedBox(height: AppSpacing.md),

            _passwordField(
              controller: _currentController,
              label: l10n.translate('promoter_current_password'),
              current: true,
            ),
            const SizedBox(height: AppSpacing.md),
            _passwordField(
              controller: _newController,
              label: l10n.translate('promoter_new_password'),
            ),
            const SizedBox(height: AppSpacing.md),
            _passwordField(
              controller: _confirmController,
              label: l10n.translate('promoter_confirm_password'),
              validator: (value) {
                if (value != _newController.text) {
                  return l10n.translate('promoter_passwords_dont_match');
                }
                return null;
              },
            ),

            if (_message != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: _messageIsError
                      ? AppColors.errorBg
                      : AppColors.successBg,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(
                    color: _messageIsError
                        ? AppColors.errorBorder
                        : AppColors.primaryLight,
                  ),
                ),
                child: Text(
                  _message!,
                  style: AppTypography.bodySmall.copyWith(
                    color: _messageIsError
                        ? AppColors.error
                        : AppColors.primary,
                  ),
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.lg),
            KatishaModalAction(
              label: l10n.translate('promoter_update_password'),
              busy: _busy,
              onPressed: _changePassword,
            ),

            const SizedBox(height: AppSpacing.lg),
            Divider(color: AppColors.border),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: () async {
                await ref.read(authControllerProvider.notifier).signOut();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.translate('logout')),
                    backgroundColor: AppColors.text,
                  ),
                );
              },
              icon: const Icon(Icons.logout, size: 18),
              label: Text(l10n.translate('logout')),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.errorBorder),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    bool current = false,
    String? Function(String?)? validator,
  }) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.textSub,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          controller: controller,
          obscureText: true,
          enabled: !_busy,
          style: AppTypography.bodyLarge,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.lock_outline, size: 20),
            filled: true,
            fillColor: AppColors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            border: _border(),
            enabledBorder: _border(),
            focusedBorder: _border(focused: true),
          ),
          validator:
              validator ??
              (value) => (value == null || value.isEmpty)
                  ? l10n.translate('promoter_password_required')
                  : null,
        ),
      ],
    );
  }

  OutlineInputBorder _border({bool focused = false}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      borderSide: BorderSide(
        color: focused ? AppColors.primary : AppColors.border,
        width: focused ? 2 : 1,
      ),
    );
  }
}
