import 'package:dartz/dartz.dart';
import 'failures.dart';

/// Wraps a use-case or repository call in a try-catch that maps exceptions
/// to [Failure] subclasses. This keeps business logic clean of try-catch noise.
Future<Either<Failure, T>> safeCall<T>(Future<T> Function() call) async {
  try {
    final result = await call();
    return Right(result);
  } catch (e) {
    if (e is Failure) return Left(e);
    return Left(UnknownFailure(e.toString()));
  }
}
