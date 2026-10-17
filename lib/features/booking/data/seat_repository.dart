import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/failures.dart';
import '../../../core/network/api_client.dart';
import '../domain/seat_models.dart';

/// Persisted client id used to own seat holds so the booking checkout can claim
/// them. Mirrors the web `useTripSeats` `vdk_seat_client_id` localStorage key.
const String kSeatClientIdKey = 'vdk_seat_client_id';

String? _cachedClientId;

/// Stable id for this install. Held in memory after the first read so the map
/// only touches disk once per session.
Future<String> seatClientId() async {
  final cached = _cachedClientId;
  if (cached != null) return cached;
  String makeId() =>
      'c_${const Uuid().v4().replaceAll('-', '').substring(0, 18)}';
  try {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(kSeatClientIdKey);
    if (existing != null && existing.isNotEmpty) {
      _cachedClientId = existing;
      return existing;
    }
    final id = makeId();
    await prefs.setString(kSeatClientIdKey, id);
    _cachedClientId = id;
    return id;
  } catch (_) {
    final id = makeId();
    _cachedClientId = id;
    return id;
  }
}

/// Result of resolving a departure tuple to a trip.
class ResolvedTrip {
  final String tripId;
  final bool created;
  final int totalSeats;
  final int seatVersion;

  const ResolvedTrip({
    required this.tripId,
    required this.created,
    required this.totalSeats,
    required this.seatVersion,
  });

  factory ResolvedTrip.fromJson(Map<String, dynamic> json) {
    return ResolvedTrip(
      tripId: json['tripId']?.toString() ?? '',
      created: json['created'] as bool? ?? false,
      totalSeats: (json['totalSeats'] as num?)?.toInt() ?? 0,
      seatVersion: (json['seatVersion'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Raised when a reservation is rejected because another client grabbed one or
/// more of the requested seats first. Carries the taken labels so the UI can
/// drop them and tell the rider.
class SeatConflictFailure extends Failure {
  final List<String> alreadyTaken;

  const SeatConflictFailure(
    super.message, {
    required this.alreadyTaken,
  });

  @override
  List<Object> get props => [message, alreadyTaken];
}

/// Seat API. Paths are relative to the API base URL (`.../api`), so the server
/// sees `/api/v1/trips/...`.
class SeatRepository {
  final ApiClient _apiClient;

  SeatRepository(this._apiClient);

  /// `POST /v1/trips/resolve` — finds or creates the trip for a departure tuple
  /// so the passenger flow can obtain a `tripId`.
  Future<Either<Failure, ResolvedTrip>> resolveTrip({
    required String agencyId,
    required String routeId,
    required String travelDate,
    required String travelTime,
    required num price,
  }) async {
    return _guard(() async {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/v1/trips/resolve',
        data: {
          'agencyId': agencyId,
          'routeId': routeId,
          'travelDate': travelDate,
          'travelTime': travelTime,
          'price': price,
        },
      );
      return ResolvedTrip.fromJson(response.data ?? const {});
    });
  }

  /// `GET /v1/trips/:tripId/seats` — the stored layout plus the live status of
  /// every seat.
  Future<Either<Failure, TripSeatMap>> getTripSeats(
    String tripId, {
    String? clientId,
  }) async {
    return _guard(() async {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/v1/trips/$tripId/seats',
        queryParameters: {
          if (clientId != null && clientId.isNotEmpty) 'clientId': clientId,
        },
      );
      return TripSeatMap.fromJson(response.data ?? const {});
    });
  }

  /// `POST /v1/trips/:tripId/seats/reserve` — places a short-lived hold on the
  /// requested seats. A conflict surfaces as [SeatConflictFailure].
  Future<Either<Failure, List<String>>> reserveTripSeats({
    required String tripId,
    required List<String> seatNumbers,
    required String clientId,
    int? ttlMinutes,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/v1/trips/$tripId/seats/reserve',
        data: {
          'seatNumbers': seatNumbers,
          'clientId': clientId,
          'ttlMinutes': ?ttlMinutes,
        },
      );
      final data = response.data ?? const {};
      return Right(
        (data['seats'] as List<dynamic>?)?.map((s) => s.toString()).toList() ??
            seatNumbers,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        final gone = _extractAlreadyTaken(e.response?.data);
        final list = gone.isEmpty ? seatNumbers : gone;
        return Left(SeatConflictFailure(
          list.length == 1
              ? 'Seat ${list.first} was just taken, please choose another.'
              : 'Seats ${list.join(', ')} were just taken, please choose another.',
          alreadyTaken: list,
        ));
      }
      return Left(ApiClient.mapDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  static List<String> _extractAlreadyTaken(dynamic body) {
    dynamic source = body;
    if (source is Map<String, dynamic> && source['data'] is Map) {
      source = source['data'];
    }
    if (source is Map<String, dynamic>) {
      final raw = source['alreadyTaken'];
      if (raw is List) return raw.map((s) => s.toString()).toList();
    }
    return const [];
  }

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

final seatRepositoryProvider = Provider<SeatRepository>((ref) {
  return SeatRepository(ref.read(apiClientProvider));
});
