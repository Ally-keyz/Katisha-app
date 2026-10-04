import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';

import '../../../core/error/failures.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/app_user.dart';

/// Sign-in / profile calls needed to gate the promoter area.
///
/// The app is guest-first, so nothing here runs until the promoter surface asks
/// for it: there is no session bootstrap on launch.
class AuthRepository {
  final ApiClient _apiClient;

  AuthRepository(this._apiClient);

  /// `POST /auth/login` — accepts a phone number or username in [identifier].
  ///
  /// Tokens are persisted by [ApiClient.setTokens] so the rest of the app can
  /// send the bearer header without knowing about auth.
  Future<Either<Failure, AppUser>> signIn({
    required String identifier,
    required String password,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'identifier': identifier, 'password': password},
      );
      final data = ApiClient.payload(response);

      final accessToken = data['accessToken'] as String?;
      final refreshToken = data['refreshToken'] as String?;
      final user = data['user'];
      if (accessToken == null ||
          accessToken.isEmpty ||
          refreshToken == null ||
          refreshToken.isEmpty ||
          user is! Map<String, dynamic>) {
        return const Left(ServerFailure('Login response was incomplete'));
      }

      await _apiClient.setTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
      return Right(AppUser.fromJson(user));
    } on DioException catch (e) {
      return Left(ApiClient.mapDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  /// `GET /auth/profile` — resolves the current session's user.
  ///
  /// The login payload omits `promoterCode`/`promoterStatus`, so a fresh sign-in
  /// still needs this call before the promoter surface can be trusted.
  Future<Either<Failure, AppUser>> profile() async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/auth/profile',
      );
      final data = ApiClient.payload(response);
      final user = data['user'];
      if (user is! Map<String, dynamic>) {
        return const Left(ServerFailure('Profile response was incomplete'));
      }
      return Right(AppUser.fromJson(user));
    } on DioException catch (e) {
      return Left(ApiClient.mapDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  /// `PATCH /auth/change-password`.
  Future<Either<Failure, Unit>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _apiClient.patch<Map<String, dynamic>>(
        '/auth/change-password',
        data: {'currentPassword': currentPassword, 'newPassword': newPassword},
      );
      return const Right(unit);
    } on DioException catch (e) {
      return Left(ApiClient.mapDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  /// Clears the stored session.
  Future<void> signOut() => _apiClient.clearTokens();
}
