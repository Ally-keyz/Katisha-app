import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failures.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/app_user.dart';
import '../data/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider));
});

/// The app's session state.
///
/// Guest-first by design: [AuthState.unknown] is the resting state and no
/// network call happens until the promoter area asks for it. That keeps the
/// booking flow unaffected for the (vast majority of) signed-out users.
sealed class AuthState {
  const AuthState();
}

/// Not resolved yet — either nothing was attempted or a check is in flight.
class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthSignedOut extends AuthState {
  const AuthSignedOut();
}

class AuthSignedIn extends AuthState {
  final AppUser user;
  const AuthSignedIn(this.user);
}

class AuthController extends Notifier<AuthState> {
  late final AuthRepository _repository;

  @override
  AuthState build() {
    _repository = ref.watch(authRepositoryProvider);
    return const AuthUnknown();
  }

  /// Resolves the stored session, if any.
  ///
  /// Returns the signed-in user, or `null` when there is no usable session. A
  /// stale token is cleared so the promoter area falls back to sign-in instead
  /// of looping on 401s. Already-resolved state short-circuits, so the shell
  /// and the gate can both ask without duplicating the request.
  Future<AppUser?> restore() async {
    final current = state;
    if (current is AuthSignedIn) return current.user;
    if (current is AuthSignedOut) return null;

    final api = ref.read(apiClientProvider);
    if (!api.isAuthenticated) {
      state = const AuthSignedOut();
      return null;
    }

    final result = await _repository.profile();
    if (result.isRight()) {
      return _signedIn(result.getOrElse(() => throw StateError('unreachable')));
    }

    final failure = result.fold((f) => f, (_) => const UnknownFailure());
    if (failure is AuthFailure) {
      return _expired();
    }
    // A network/server error leaves the token intact. Settle on signed-out so
    // callers get a terminal state instead of an indefinite spinner; the token
    // is retried on the next restore.
    state = const AuthSignedOut();
    return null;
  }

  /// Forces the session to signed-out without touching stored tokens.
  ///
  /// Used by [PromoterGate] to break out of the unresolved state.
  void markSignedOut() {
    if (state is! AuthSignedOut) state = const AuthSignedOut();
  }

  Future<Either<Failure, AppUser>> signIn({
    required String identifier,
    required String password,
  }) async {
    final result = await _repository.signIn(
      identifier: identifier,
      password: password,
    );

    if (result.isLeft()) {
      return Left(result.fold((f) => f, (_) => const UnknownFailure()));
    }

    final user = result.fold((_) => null, (u) => u)!;

    // The login payload omits the promoter fields, so prefer the profile when
    // it is available and fall back to the login payload otherwise.
    final profile = await _repository.profile();
    final resolved = profile.fold((_) => user, (p) => p);
    return Right(_signedIn(resolved)!);
  }

  Future<void> signOut() async {
    await _repository.signOut();
    state = const AuthSignedOut();
  }

  AppUser? _signedIn(AppUser user) {
    state = AuthSignedIn(user);
    return user;
  }

  Future<AppUser?> _expired() async {
    await ref.read(apiClientProvider).clearTokens();
    state = const AuthSignedOut();
    return null;
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// The signed-in user, or `null` when signed out or not yet resolved.
final currentUserProvider = Provider<AppUser?>((ref) {
  final auth = ref.watch(authControllerProvider);
  return auth is AuthSignedIn ? auth.user : null;
});

/// Whether the current account may use the promoter area.
///
/// Returns `false` while the session is still unresolved so the promoter tab
/// does not flicker in for signed-out users during a restore.
final isPromoterProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider)?.isPromoter ?? false;
});
