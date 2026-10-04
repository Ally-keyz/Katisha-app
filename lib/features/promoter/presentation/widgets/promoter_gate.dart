import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../auth/presentation/screens/sign_in_screen.dart';
import '../screens/promoter_setup_screen.dart';

/// Guards the promoter area.
///
/// `/promoter/*` is `authorize('promoter')` on the server, so the UI has to
/// resolve three states before rendering anything: still checking, signed out,
/// and signed in without the promoter role.
///
/// A signed-in account without the role is not a dead end: it drops straight
/// into [PromoterSetupScreen], because that is exactly the account that should
/// be applying. Only a promoter ever sees [child].
class PromoterGate extends ConsumerStatefulWidget {
  final Widget child;

  const PromoterGate({super.key, required this.child});

  @override
  ConsumerState<PromoterGate> createState() => _PromoterGateState();
}

class _PromoterGateState extends ConsumerState<PromoterGate> {
  /// Guards the post-frame sign-out below: registering it from `build` meant
  /// every rebuild queued another callback (and another `markSignedOut()`
  /// write), which grew without bound for as long as the state stayed unknown.
  bool _requestedSignOut = false;

  @override
  void initState() {
    super.initState();
    // Resolve the stored session once, after the first frame so the router is
    // settled and a redirect here cannot race with the initial navigation.
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  Future<void> _restore() async {
    if (!mounted) return;
    await ref.read(authControllerProvider.notifier).restore();
  }

  void _openSignIn() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SignInScreen(
          title: 'promoter_gate_signin_title',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    if (auth is AuthSignedIn && auth.user.isPromoter) {
      return widget.child;
    }

    // A stored token that the server rejects (or a network blip) leaves the
    // session unknown forever, so fall through to the signed-out view instead
    // of spinning. The controller is reset to signed-out for auth failures;
    // this covers the rest.
    if (auth is AuthUnknown) {
      if (!_requestedSignOut) {
        _requestedSignOut = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(authControllerProvider.notifier).markSignedOut();
        });
      }
      return const Center(child: CircularProgressIndicator(strokeWidth: 3));
    }
    _requestedSignOut = false;

    // Signed out, or signed in without the promoter role.
    if (auth is AuthSignedIn) {
      return const PromoterSetupScreen(standalone: false);
    }

    return _SignedOutView(onSignIn: _openSignIn);
  }
}

class _SignedOutView extends StatelessWidget {
  final VoidCallback onSignIn;

  const _SignedOutView({required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              child: const Icon(
                Icons.campaign_outlined,
                size: 34,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.translate('promoter_gate_signin_title'),
              style: AppTypography.titleLarge.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.translate('promoter_only_when_signed_in'),
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSub,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: onSignIn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                ),
                child: Text(
                  l10n.translate('sign_in'),
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Signing in is not the only way in: the setup form creates a new
            // promoter account, so visitors without an account can still apply.
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () => context.go('/promoter/setup'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                ),
                child: Text(
                  l10n.translate('promoter_setup_title'),
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => context.go('/home'),
              child: Text(l10n.translate('back_to_booking')),
            ),
          ],
        ),
      ),
    );
  }
}
