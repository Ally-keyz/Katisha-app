import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';

import '../../../core/error/failures.dart';
import '../../../core/network/api_client.dart';
import 'models/promoter_models.dart';

/// Promoter self-service API.
///
/// All paths are relative to the API base URL (`.../api`), so the server sees
/// `/api/promoter/...`. Every endpoint is `authorize('promoter')`, which means a
/// signed-out or non-promoter session comes back as 401/403 — callers surface
/// that as [AuthFailure]/[ServerFailure] and the UI falls back to sign-in.
class PromoterRepository {
  final ApiClient _apiClient;

  PromoterRepository(this._apiClient);

  /// `POST /promoter/setup` — apply to become a promoter.
  ///
  /// The only promoter endpoint that does not require the promoter role: it is
  /// `optionalAuth`, so the same call creates a brand-new promoter account when
  /// called anonymously and upgrades the current one when a token is attached.
  /// On success the server may return tokens for the account it just created,
  /// which is signalled by [SetupResult.needsSignIn] being false.
  Future<Either<Failure, SetupResult>> setup({
    String? name,
    String? phone,
    String? password,
    String? payoutPhone,
    required bool acceptTerms,
  }) async {
    return _guard(() async {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/promoter/setup',
        data: {
          'name': ?name,
          'phone': ?phone,
          'password': ?password,
          'payoutPhone': ?payoutPhone,
          'acceptTerms': acceptTerms,
        },
      );
      final data = ApiClient.payload(response);
      return SetupResult(
        needsSignIn: data['accessToken'] == null,
        message: data['message'] as String?,
      );
    });
  }

  /// `GET /promoter/profile`
  Future<Either<Failure, PromoterProfile>> getProfile() async {
    return _guard(() async {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/promoter/profile',
      );
      return PromoterProfile.fromJson(ApiClient.payload(response));
    });
  }

  /// `PATCH /promoter/profile` — change the mobile-money number payouts go to.
  Future<Either<Failure, PromoterProfile>> updatePayoutPhone(
    String payoutPhone,
  ) async {
    return _guard(() async {
      final response = await _apiClient.patch<Map<String, dynamic>>(
        '/promoter/profile',
        data: {'payoutPhone': payoutPhone},
      );
      return PromoterProfile.fromJson(ApiClient.payload(response));
    });
  }

  /// `GET /promoter/stats` — dashboard counters in a single round-trip.
  Future<Either<Failure, PromoterStats>> getStats() async {
    return _guard(() async {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/promoter/stats',
      );
      return PromoterStats.fromJson(ApiClient.payload(response));
    });
  }

  /// `GET /promoter/referrals`
  Future<Either<Failure, PromoterReferralsPage>> getReferrals({
    int page = 1,
    int limit = 20,
    String? status,
  }) async {
    return _guard(() async {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/promoter/referrals',
        queryParameters: {'page': page, 'limit': limit, 'status': ?status},
      );
      return PromoterReferralsPage.fromJson(ApiClient.payload(response));
    });
  }

  /// `GET /promoter/earnings`
  Future<Either<Failure, PromoterEarningsPage>> getEarnings({
    int page = 1,
    int limit = 20,
    String? status,
  }) async {
    return _guard(() async {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/promoter/earnings',
        queryParameters: {'page': page, 'limit': limit, 'status': ?status},
      );
      return PromoterEarningsPage.fromJson(ApiClient.payload(response));
    });
  }

  /// `GET /promoter/payouts`
  Future<Either<Failure, PromoterPayoutsPage>> getPayouts({
    int page = 1,
    int limit = 20,
  }) async {
    return _guard(() async {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/promoter/payouts',
        queryParameters: {'page': page, 'limit': limit},
      );
      return PromoterPayoutsPage.fromJson(ApiClient.payload(response));
    });
  }

  /// `POST /promoter/payouts/request`
  ///
  /// The server queues the payout and then processes it inline, so the returned
  /// status is already final (`paid`/`failed`) rather than `pending`. Anything
  /// above the 1 RWF floor is payable — there is no threshold to wait for.
  Future<Either<Failure, PromoterPayout>> requestPayout() async {
    return _guard(() async {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/promoter/payouts/request',
      );
      final data = ApiClient.payload(response);
      final payout = data['payout'];
      if (payout is! Map<String, dynamic>) {
        throw const ServerFailure('Payout response was incomplete');
      }
      return PromoterPayout.fromJson(payout);
    });
  }

  /// Runs [action], mapping transport and parse errors onto the app's [Failure]
  /// hierarchy so every caller handles failures the same way.
  Future<Either<Failure, T>> _guard<T>(Future<T> Function() action) async {
    try {
      return Right(await action());
    } on DioException catch (e) {
      return Left(ApiClient.mapDioError(e));
    } on Failure catch (e) {
      return Left(e);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
