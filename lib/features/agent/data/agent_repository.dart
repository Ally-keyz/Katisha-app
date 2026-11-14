import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';

import '../../../core/error/failures.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/booking_model.dart';
import '../../../shared/models/booking_response.dart';

/// Agent-side booking operations: the assigned-route feed plus the two
/// acknowledgements the field agent makes at the counter.
class AgentRepository {
  final ApiClient _api;

  AgentRepository(this._api);

  Future<Either<Failure, BookingResponse>> getAgentBookings({
    int page = 1,
    int limit = 50,
    bool today = false,
    String? status,
  }) async {
    try {
      final response = await _api.get(
        '/bookings/agent/today',
        queryParameters: {
          'page': page,
          'limit': limit,
          if (today) 'today': 'true',
          if (status != null && status.isNotEmpty) 'status': status,
        },
      );
      final data = response.data;
      final normalized = data is Map<String, dynamic>
          ? data
          : <String, dynamic>{'bookings': data};
      return Right(BookingResponse.fromJson(normalized));
    } on DioException catch (e) {
      return Left(ApiClient.mapDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, Booking>> markSeen(String bookingId) async {
    try {
      final response = await _api.patch('/bookings/$bookingId/seen');
      final data = response.data;
      final bookingJson = data is Map<String, dynamic>
          ? (data['booking'] as Map<String, dynamic>? ?? data)
          : <String, dynamic>{};
      return Right(Booking.fromJson(bookingJson));
    } on DioException catch (e) {
      return Left(ApiClient.mapDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  /// Uploads the mandatory photo of the physical ticket the agent issued and
  /// marks the booking ready for the passenger.
  Future<Either<Failure, Booking>> markReady(
    String bookingId,
    File ticketPhoto,
  ) async {
    try {
      final form = FormData.fromMap({
        'ticketImage': await MultipartFile.fromFile(
          ticketPhoto.path,
          filename: ticketPhoto.uri.pathSegments.isNotEmpty
              ? ticketPhoto.uri.pathSegments.last
              : 'ticket.jpg',
        ),
      });
      final response = await _api.post(
        '/bookings/$bookingId/ready',
        data: form,
      );
      final data = response.data;
      final bookingJson = data is Map<String, dynamic>
          ? (data['booking'] as Map<String, dynamic>? ?? data)
          : <String, dynamic>{};
      return Right(Booking.fromJson(bookingJson));
    } on DioException catch (e) {
      return Left(ApiClient.mapDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
