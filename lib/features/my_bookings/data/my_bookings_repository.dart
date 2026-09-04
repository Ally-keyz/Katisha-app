import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';

import '../../../core/error/failures.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/booking_model.dart';
import '../../../shared/models/booking_response.dart';

class MyBookingsRepository {
  final ApiClient _apiClient;

  MyBookingsRepository(this._apiClient);

  Future<Either<Failure, BookingResponse>> getMyBookings(
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
}
