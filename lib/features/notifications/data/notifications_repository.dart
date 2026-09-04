import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';

import '../../../core/error/failures.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/notification_model.dart';

class NotificationsRepository {
  final ApiClient _apiClient;

  NotificationsRepository(this._apiClient);

  Future<Either<Failure, PaginatedNotifications>> getNotifications(
    int page,
    int limit,
  ) async {
    try {
      final response = await _apiClient.get(
        '/notifications',
        queryParameters: {'page': page, 'limit': limit},
      );
      final result = PaginatedNotifications.fromJson(
          response.data as Map<String, dynamic>);
      return Right(result);
    } on DioException catch (e) {
      return Left(ApiClient.mapDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, void>> markAllAsRead() async {
    try {
      await _apiClient.patch('/notifications/read-all');
      return const Right(null);
    } on DioException catch (e) {
      return Left(ApiClient.mapDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, void>> deleteNotification(String id) async {
    try {
      await _apiClient.delete('/notifications/$id');
      return const Right(null);
    } on DioException catch (e) {
      return Left(ApiClient.mapDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
