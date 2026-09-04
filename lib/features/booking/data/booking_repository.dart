import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/error/failures.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/booking_model.dart';
import '../../../shared/models/booking_response.dart';
import '../../../shared/models/route_model.dart';

class BookingRepository {
  final ApiClient _apiClient;

  BookingRepository(this._apiClient);

  Future<Either<Failure, List<RouteModel>>> searchRoutes(
    String origin,
    String destination,
  ) async {
    try {
      debugPrint('[BookingRepo] searchRoutes origin="$origin" destination="$destination"');
      final response = await _apiClient.get(
        '/routes/search',
        queryParameters: {'origin': origin, 'destination': destination},
      );
      debugPrint('[BookingRepo] raw response.data runtime=${response.data.runtimeType} value=${response.data}');
      final data = response.data;
      final list = data is Map<String, dynamic>
          ? (data['routes'] as List<dynamic>? ??
              data['data'] as List<dynamic>? ??
              [])
          : data as List<dynamic>? ?? [];
      debugPrint('[BookingRepo] parsed ${list.length} routes');
      final routes = list
          .map((r) => RouteModel.fromJson(r as Map<String, dynamic>))
          .toList();
      return Right(routes);
    } on DioException catch (e) {
      return Left(ApiClient.mapDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, Map<String, dynamic>>> createBooking(
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _apiClient.post('/bookings', data: data);
      final result = response.data as Map<String, dynamic>;
      return Right(result);
    } on DioException catch (e) {
      return Left(ApiClient.mapDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, Map<String, dynamic>>> createGuestBooking(
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _apiClient.post('/bookings/guest', data: data);
      final result = response.data as Map<String, dynamic>;
      return Right(result);
    } on DioException catch (e) {
      return Left(ApiClient.mapDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, BookingResponse>> getUserBookings(
    int page,
    int limit, {
    String? status,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'limit': limit,
      };
      if (status != null) queryParams['status'] = status;

      final response = await _apiClient.get(
        '/bookings',
        queryParameters: queryParams,
      );
      final result = BookingResponse.fromJson(
          response.data as Map<String, dynamic>);
      return Right(result);
    } on DioException catch (e) {
      return Left(ApiClient.mapDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, Booking>> getBooking(String id) async {
    try {
      final response = await _apiClient.get('/bookings/$id');
      final booking =
          Booking.fromJson(response.data as Map<String, dynamic>);
      return Right(booking);
    } on DioException catch (e) {
      return Left(ApiClient.mapDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  /// Tracks a booking by its public reference code. Unlike [getBooking], this
  /// endpoint is unauthenticated and actively verifies the pawaPay collection
  /// server-side, flipping the booking to paid/failed so polling resolves.
  Future<Either<Failure, Booking>> trackBooking(String referenceCode) async {
    try {
      final response = await _apiClient.get(
        '/bookings/track/$referenceCode',
      );
      final data = response.data as Map<String, dynamic>;
      final bookingMap = data['booking'] is Map<String, dynamic>
          ? data['booking'] as Map<String, dynamic>
          : data;
      final booking = Booking.fromJson(bookingMap);
      return Right(booking);
    } on DioException catch (e) {
      return Left(ApiClient.mapDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  /// Lightweight payment-status-only poll. Returns just paymentStatus and
  /// status — much smaller payload than [trackBooking] for rapid polling.
  Future<Either<Failure, ({String paymentStatus, String status})>> trackBookingStatus(String referenceCode) async {
    try {
      final response = await _apiClient.get(
        '/bookings/track/$referenceCode/status',
      );
      final data = response.data as Map<String, dynamic>;
      return Right((
        paymentStatus: data['paymentStatus'] as String? ?? 'processing',
        status: data['status'] as String? ?? 'pending',
      ));
    } on DioException catch (e) {
      return Left(ApiClient.mapDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, Booking>> cancelBooking(String id) async {
    try {
      final response = await _apiClient.patch('/bookings/$id/cancel');
      final booking =
          Booking.fromJson(response.data as Map<String, dynamic>);
      return Right(booking);
    } on DioException catch (e) {
      return Left(ApiClient.mapDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  /// Abandon (but do not cancel) an unpaid booking so its seats are released.
  Future<Either<Failure, Booking>> abandonBooking(String id) async {
    try {
      final response = await _apiClient.post('/bookings/$id/abandon');
      final booking =
          Booking.fromJson(response.data as Map<String, dynamic>);
      return Right(booking);
    } on DioException catch (e) {
      return Left(ApiClient.mapDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, Map<String, dynamic>>> viewTicket(
    String bookingId,
  ) async {
    try {
      final response = await _apiClient.get('/bookings/$bookingId/ticket');
      final result = response.data as Map<String, dynamic>;
      return Right(result);
    } on DioException catch (e) {
      return Left(ApiClient.mapDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, List<String>>> getTakenSeats(
    String agencyId,
    String travelDate,
    String travelTime,
  ) async {
    try {
      final response = await _apiClient.get(
        '/bookings/taken-seats',
        queryParameters: {
          'agencyId': agencyId,
          'travelDate': travelDate,
          'travelTime': travelTime,
        },
      );
      final data = response.data;
      final seats = data is Map<String, dynamic>
          ? (data['takenSeats'] as List<dynamic>? ?? data['seats'] as List<dynamic>? ?? [])
          : data as List<dynamic>? ?? [];
      return Right(seats.map((s) => s as String).toList());
    } on DioException catch (e) {
      return Left(ApiClient.mapDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
