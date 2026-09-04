import 'package:equatable/equatable.dart';

/// Base class for all application failures.
/// Each feature's repository maps exceptions to a specific [Failure] subclass.
abstract class Failure extends Equatable {
  final String message;
  const Failure(this.message);

  @override
  List<Object> get props => [message];
}

/// Server returned a 4xx or 5xx error.
class ServerFailure extends Failure {
  final int? statusCode;
  const ServerFailure(super.message, {this.statusCode});

  @override
  List<Object> get props => [message, if (statusCode != null) statusCode!];
}

/// No internet connection available.
class NetworkFailure extends Failure {
  const NetworkFailure([String msg = 'No internet connection. Please check your network.'])
      : super(msg);
}

/// Token expired and refresh also failed.
class AuthFailure extends Failure {
  const AuthFailure([String msg = 'Session expired. Please log in again.'])
      : super(msg);
}

/// Local storage operation failed.
class CacheFailure extends Failure {
  const CacheFailure([String msg = 'Failed to access local storage.'])
      : super(msg);
}

/// Request was cancelled or timed out.
class TimeoutFailure extends Failure {
  const TimeoutFailure([String msg = 'Request timed out. Please try again.'])
      : super(msg);
}

/// Unknown / unexpected error.
class UnknownFailure extends Failure {
  const UnknownFailure([String msg = 'An unexpected error occurred.'])
      : super(msg);
}
