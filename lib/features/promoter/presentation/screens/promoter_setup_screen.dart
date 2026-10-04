import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/katisha_app_bar.dart';
import '../../../../core/widgets/katisha_modal.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/application/auth_controller.dart';
import '../../application/promoter_providers.dart';
import '../../data/models/promoter_models.dart';

/// Promoter onboarding / "apply to become a promoter" flow.
///
/// Mirrors the web `PromoterSetup` page. `POST /promoter/setup` is
/// `optionalAuth`, so the same endpoint covers both paths:
///
///  * anonymous → creates a new promoter account through a 3-step wizard
///    (details → payout → security), the same shape as the web flow;
///  * signed in → a single payout + terms screen upgrades the current account.
///
/// A brand-new account is created as `pending` until an admin approves it, so
/// the copy says the dashboard unlocks after review rather than promising
/// instant earnings.
class PromoterSetupScreen extends ConsumerStatefulWidget {
  /// False when hosted inside the promoter gate, which supplies its own chrome.
  final bool standalone;

  const PromoterSetupScreen({super.key, this.standalone = true});

  @override
  ConsumerState<PromoterSetupScreen> createState() =>
      _PromoterSetupScreenState();
}

class _PromoterSetupScreenState extends ConsumerState<PromoterSetupScreen> {
  static const int _totalSteps = 3;
  static const int _passwordMinLength = 6;

  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _payoutPhoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  int _step = 1;
  bool _isSignedIn = false;
  bool _useSeparatePayout = false;
  bool _acceptTerms = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _busy = false;
  String? _error;

  /// Direction of the last step change, so the slide transition moves the right
  /// way (forward pushes left, back pushes right).
  bool _forward = true;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _isSignedIn = user != null;
    if (user != null && user.phone.isNotEmpty) {
      _phoneController.text = user.phone;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _payoutPhoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _goToStep(int next) {
    setState(() {
      _error = null;
      _forward = next > _step;
      _step = next;
    });
  }

  void _next() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_step < _totalSteps) _goToStep(_step + 1);
  }

  void _back() {
    if (_step > 1) _goToStep(_step - 1);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_acceptTerms || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final auth = ref.read(authControllerProvider.notifier);
    final l10n = AppLocalizations.of(context);

    final result = await ref.read(promoterRepositoryProvider).setup(
          // Only send account-creation fields on the anonymous path; the server
          // rejects them for an already-authenticated caller.
          name: _isSignedIn ? null : _nameController.text.trim(),
          phone: _isSignedIn ? null : _phoneController.text.trim(),
          password: _isSignedIn ? null : _passwordController.text,
          payoutPhone: _useSeparatePayout
              ? _payoutPhoneController.text.trim()
              : null,
          acceptTerms: true,
        );

    if (!mounted) return;

    // The success path continues with awaits, so it cannot live inside `fold`.
    // A null result means the failure branch already surfaced the message.
    final setup = result.fold<SetupResult?>(
      (failure) {
        setState(() {
          _busy = false;
          _error = failure.message;
        });
        return null;
      },
      (value) => value,
    );
    if (setup == null) return;

    if (setup.needsSignIn && !_isSignedIn) {
      // The account exists but no session came back — sign in with the
      // credentials just submitted so the dashboard can load.
      final signedIn = await auth.signIn(
        identifier: _phoneController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;

      signedIn.fold(
        (failure) => setState(() {
          _busy = false;
          _error = failure.message;
        }),
        (_) {
          setState(() => _busy = false);
          _finish(l10n);
        },
      );
      return;
    }

    // Existing account: re-resolve the session so the promoter role lands.
    await auth.restore();
    if (!mounted) return;
    setState(() => _busy = false);
    _finish(l10n);
  }

  void _finish(AppLocalizations l10n) {
    ref.read(promoterDataVersionProvider.notifier).state++;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.translate('promoter_setup_submitted')),
        backgroundColor: AppColors.primary,
      ),
    );
    context.go('/promoter');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final body = SafeArea(
      child: ListView(
        // Bottom padding keeps the last field and the inline action row clear
        // of the keyboard and the system navigation bar.
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        children: [
          _intro(l10n),
          const SizedBox(height: AppSpacing.lg),
          Form(
            key: _formKey,
            child: _isSignedIn
                ? _existingAccountBody(l10n)
                : _wizardBody(l10n),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            _errorBox(_error!),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (_isSignedIn)
            KatishaModalAction(
              label: l10n.translate('promoter_finish_setup'),
              busy: _busy,
              onPressed: _acceptTerms ? _submit : null,
            )
          else
            _wizardActions(l10n),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton(
              onPressed: () => context.go('/home'),
              child: Text(l10n.translate('back_to_booking')),
            ),
          ),
        ],
      ),
    );

    if (!widget.standalone) return body;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: KatishaAppBar(
        title: l10n.translate('promoter_setup_title'),
        showBackButton: true,
        showBell: false,
      ),
      body: body,
    );
  }

  // ── New-account wizard ────────────────────────────────────────────────────

  Widget _wizardBody(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepIndicator(l10n),
        const SizedBox(height: AppSpacing.lg),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final slide = Tween<Offset>(
              begin: Offset(_forward ? 0.12 : -0.12, 0),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: slide, child: child),
            );
          },
          child: KeyedSubtree(
            key: ValueKey(_step),
            child: _stepBody(l10n),
          ),
        ),
      ],
    );
  }

  Widget _stepBody(AppLocalizations l10n) {
    switch (_step) {
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(
              controller: _nameController,
              label: l10n.translate('name'),
              icon: Icons.person_outline,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _next(),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? l10n.translate('promoter_name_required')
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            _field(
              controller: _phoneController,
              label: l10n.translate('phone'),
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              formatter: _phoneFormatter,
              onSubmitted: (_) => _next(),
              validator: (v) =>
                  (v == null || v.replaceAll(RegExp(r'\D'), '').length < 9)
                      ? l10n.translate('promoter_invalid_phone')
                      : null,
            ),
          ],
        );
      case 2:
        return _payoutSection(l10n);
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(
              controller: _passwordController,
              label: l10n.translate('password'),
              icon: Icons.lock_outline,
              obscure: _obscure,
              textInputAction: TextInputAction.next,
              onToggleObscure: () => setState(() => _obscure = !_obscure),
              validator: (v) => (v == null || v.length < _passwordMinLength)
                  ? l10n.translate('promoter_password_too_short')
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            _field(
              controller: _confirmController,
              label: l10n.translate('promoter_confirm_password'),
              icon: Icons.lock_outline,
              obscure: _obscureConfirm,
              textInputAction: TextInputAction.done,
              onToggleObscure: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              onSubmitted: (_) => _submit(),
              validator: (v) => v != _passwordController.text
                  ? l10n.translate('promoter_passwords_dont_match')
                  : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            _terms(l10n),
          ],
        );
    }
  }

  Widget _stepIndicator(AppLocalizations l10n) {
    final labels = [
      l10n.translate('promoter_step_basics'),
      l10n.translate('promoter_step_payout'),
      l10n.translate('promoter_step_security'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              labels[_step - 1],
              style: AppTypography.titleSmall.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              l10n
                  .translate('promoter_step_of')
                  .replaceAll('{current}', '$_step')
                  .replaceAll('{total}', '$_totalSteps'),
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSub),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: List.generate(_totalSteps, (i) {
            final active = i + 1 <= _step;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 4,
                margin: EdgeInsets.only(right: i == _totalSteps - 1 ? 0 : 6),
                decoration: BoxDecoration(
                  color: active ? AppColors.primary : AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _wizardActions(AppLocalizations l10n) {
    final isLast = _step == _totalSteps;
    return Row(
      children: [
        if (_step > 1) ...[
          Expanded(
            child: KatishaModalAction(
              label: l10n.translate('back'),
              isSecondary: true,
              onPressed: _back,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(
          child: KatishaModalAction(
            label: isLast
                ? l10n.translate('promoter_finish_setup')
                : l10n.translate('next'),
            busy: isLast && _busy,
            onPressed: isLast ? (_acceptTerms ? _submit : null) : _next,
          ),
        ),
      ],
    );
  }

  // ── Existing-account (signed in) body ─────────────────────────────────────

  Widget _existingAccountBody(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _payoutSection(l10n),
        const SizedBox(height: AppSpacing.lg),
        _terms(l10n),
      ],
    );
  }

  // ── Shared UI ─────────────────────────────────────────────────────────────

  Widget _intro(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          child: const Icon(Icons.campaign, size: 28, color: AppColors.primary),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.translate('promoter_apply_title'),
          style: AppTypography.headlineSmall.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.translate('promoter_apply_subtitle'),
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSub),
        ),
      ],
    );
  }

  Widget _payoutSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('promoter_payout_phone'),
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.textSub,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.translate('promoter_payout_phone_hint'),
          style: AppTypography.bodySmall.copyWith(color: AppColors.textSub),
        ),
        const SizedBox(height: AppSpacing.sm),
        _radio(
          l10n.translate('promoter_payout_same_as_account'),
          !_useSeparatePayout,
          () => setState(() => _useSeparatePayout = false),
        ),
        _radio(
          l10n.translate('promoter_payout_different'),
          _useSeparatePayout,
          () => setState(() => _useSeparatePayout = true),
        ),
        if (_useSeparatePayout) ...[
          const SizedBox(height: AppSpacing.sm),
          _field(
            controller: _payoutPhoneController,
            label: l10n.translate('promoter_payout_phone'),
            icon: Icons.account_balance_outlined,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            formatter: _phoneFormatter,
            validator: (v) =>
                (v == null || v.replaceAll(RegExp(r'\D'), '').length < 9)
                    ? l10n.translate('promoter_invalid_phone')
                    : null,
          ),
        ],
      ],
    );
  }

  Widget _radio(String label, bool value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              value ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 20,
              color: value ? AppColors.primary : AppColors.textMuted,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(label, style: AppTypography.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }

  Widget _terms(AppLocalizations l10n) {
    return InkWell(
      onTap: () => setState(() => _acceptTerms = !_acceptTerms),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                _acceptTerms
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                size: 20,
                color: _acceptTerms ? AppColors.primary : AppColors.textMuted,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                l10n.translate('promoter_terms_self_referral'),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSub,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBox(String message) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.errorBorder),
      ),
      child: Text(
        message,
        style: AppTypography.bodySmall.copyWith(color: AppColors.error),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    TextInputAction textInputAction = TextInputAction.next,
    TextInputFormatter? formatter,
    bool obscure = false,
    VoidCallback? onToggleObscure,
    ValueChanged<String>? onSubmitted,
    String? Function(String?)? validator,
  }) {
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
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          obscureText: obscure,
          inputFormatters: formatter == null ? null : [formatter],
          enabled: !_busy,
          style: AppTypography.bodyLarge,
          onFieldSubmitted: onSubmitted,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 20),
            suffixIcon: onToggleObscure == null
                ? null
                : IconButton(
                    onPressed: onToggleObscure,
                    icon: Icon(
                      obscure ? Icons.visibility_off : Icons.visibility,
                      size: 20,
                    ),
                  ),
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
          validator: validator,
        ),
      ],
    );
  }

  static final TextInputFormatter _phoneFormatter =
      FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'));

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
