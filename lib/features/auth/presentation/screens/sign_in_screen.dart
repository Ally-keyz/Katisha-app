import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/katisha_app_bar.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/auth_controller.dart';

/// Minimal sign-in screen.
///
/// The app has no general auth flow — this exists so the promoter area can be
/// reached at all, since every `/promoter/*` endpoint requires a session with
/// the promoter role.
///
/// [title] and [subtitle] are translation *keys*, not literal copy.
class SignInScreen extends ConsumerStatefulWidget {
  final String title;
  final String? subtitle;

  const SignInScreen({super.key, this.title = 'sign_in', this.subtitle});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = '';
    });

    final result = await ref
        .read(authControllerProvider.notifier)
        .signIn(
          identifier: _identifierController.text.trim(),
          password: _passwordController.text,
        );

    if (!mounted) return;

    result.fold(
      (failure) => setState(() {
        _busy = false;
        _error = failure.message;
      }),
      (_) {
        setState(() => _busy = false);
        // Let the caller (usually the promoter gate) re-check the role and
        // route onwards, rather than pushing a screen from here.
        Navigator.of(context).maybePop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: KatishaAppBar(
        title: l10n.translate(widget.title),
        showBackButton: true,
        showBell: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: const Icon(
                    Icons.campaign_outlined,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  widget.subtitle ??
                      'Sign in with the account you use to share your promoter code.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSub,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                _buildLabel(l10n.translate('phone')),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _identifierController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  style: AppTypography.bodyLarge,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                  ],
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
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? l10n.translate('please_enter_name')
                      : null,
                ),
                const SizedBox(height: AppSpacing.lg),

                _buildLabel(l10n.translate('password')),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  style: AppTypography.bodyLarge,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
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
                  validator: (value) => (value == null || value.isEmpty)
                      ? l10n.translate('promoter_password_required')
                      : null,
                ),

                if (_error.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.errorBg,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: AppColors.errorBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 18,
                          color: AppColors.error,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            _error,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      disabledBackgroundColor: AppColors.primaryLight,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.white,
                            ),
                          )
                        : Text(
                            l10n.translate('sign_in'),
                            style: AppTypography.titleMedium.copyWith(
                              color: AppColors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: AppTypography.labelLarge.copyWith(
        color: AppColors.textSub,
        fontWeight: FontWeight.w700,
      ),
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
