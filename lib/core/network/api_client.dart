import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../error/failures.dart';

/// Keys used to persist auth tokens locally (stored in secure storage).
const String kAccessTokenKey = 'katisha_access_token';
const String kRefreshTokenKey = 'katisha_refresh_token';

/// Provider for the API client singleton.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

/// Centralized HTTP client wrapping [Dio].
///
/// Handles base URL configuration, auth header injection, automatic token
/// refresh on 401, and common error mapping.
class ApiClient {
  late final Dio _dio;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  String? _accessToken;
  String? _refreshToken;
  bool _isRefreshing = false;

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'https://api.katisha.today/api',
      ),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onResponse: _onResponse,
      onError: _onError,
    ));
    if (kDebugMode) debugPrint('[API] baseUrl=${_dio.options.baseUrl}');
  }

  /// Load persisted tokens into memory on app startup.
  Future<void> init() async {
    _accessToken = await _secureStorage.read(key: kAccessTokenKey);
    _refreshToken = await _secureStorage.read(key: kRefreshTokenKey);
  }

  /// Persist tokens both in memory and on disk (secure storage).
  Future<void> setTokens({required String accessToken, required String refreshToken}) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    await _secureStorage.write(key: kAccessTokenKey, value: accessToken);
    await _secureStorage.write(key: kRefreshTokenKey, value: refreshToken);
  }

  /// Clear all stored tokens (logout).
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    await _secureStorage.delete(key: kAccessTokenKey);
    await _secureStorage.delete(key: kRefreshTokenKey);
  }

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get isAuthenticated => _accessToken != null && _accessToken!.isNotEmpty;

  /// Performs a GET request.
  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters, Options? options}) {
    return _dio.get<T>(path, queryParameters: queryParameters, options: options);
  }

  /// Performs a POST request.
  Future<Response<T>> post<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters, Options? options}) {
    return _dio.post<T>(path, data: data, queryParameters: queryParameters, options: options);
  }

  /// Performs a PATCH request.
  Future<Response<T>> patch<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters, Options? options}) {
    return _dio.patch<T>(path, data: data, queryParameters: queryParameters, options: options);
  }

  /// Performs a PUT request.
  Future<Response<T>> put<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters, Options? options}) {
    return _dio.put<T>(path, data: data, queryParameters: queryParameters, options: options);
  }

  /// Performs a DELETE request.
  Future<Response<T>> delete<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters, Options? options}) {
    return _dio.delete<T>(path, data: data, queryParameters: queryParameters, options: options);
  }

  /// Extracts the inner payload from the server envelope `{ ok, message, data }`.
  static Map<String, dynamic> payload(Response response) {
    final body = response.data;
    if (body is Map<String, dynamic>) {
      if (body.containsKey('data') && body['data'] is Map<String, dynamic>) {
        return body['data'] as Map<String, dynamic>;
      }
      return body;
    }
    return {};
  }

  /// Download a file as bytes (for Excel reports, PDFs, etc.).
  Future<Response<List<int>>> downloadBytes(String path, {Map<String, dynamic>? queryParameters}) {
    return _dio.get<List<int>>(
      path,
      queryParameters: queryParameters,
      options: Options(responseType: ResponseType.bytes),
    );
  }

  // ── Interceptors ──────────────────────────────────────────────────────

  void _onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) debugPrint('[API] → ${options.method} ${options.uri}');
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $_accessToken';
    }
    handler.next(options);
  }

  void _onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) debugPrint('[API] ← ${response.statusCode} ${response.requestOptions.method} ${response.requestOptions.uri}');
    // Unwrap the { ok, message, data } envelope so all callers can read
    // response.data['user'] directly without knowing about the wrapper.
    final body = response.data;
    if (body is Map<String, dynamic> && body.containsKey('data') && body['data'] is Map) {
      handler.next(Response<dynamic>(
        data: body['data'],
        requestOptions: response.requestOptions,
        statusCode: response.statusCode,
        statusMessage: response.statusMessage,
        redirects: response.redirects,
        extra: response.extra,
      ));
      return;
    }
    handler.next(response);
  }

  Future<void> _onError(DioException err, ErrorInterceptorHandler handler) async {
    if (kDebugMode) debugPrint('[API] ✖ ${err.type} ${err.requestOptions.method} ${err.requestOptions.uri} → ${err.message}');
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      final refreshed = await _attemptTokenRefresh();
      if (refreshed) {
        // Retry the original request with the new token.
        final retryResponse = await _dio.fetch(err.requestOptions);
        return handler.resolve(retryResponse);
      }
      // Refresh failed — clear tokens so the auth layer redirects to login.
      await clearTokens();
    }
    handler.next(err);
  }

  /// Attempts to refresh the access token using the stored refresh token.
  /// Returns true if the refresh succeeded.
  Future<bool> _attemptTokenRefresh() async {
    if (_refreshToken == null || _refreshToken!.isEmpty) return false;
    _isRefreshing = true;
    try {
      final response = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
      )).post(
        '${_dio.options.baseUrl}/auth/refresh-token',
        data: {'refreshToken': _refreshToken},
      );
      if (response.statusCode == 200 && response.data != null) {
        // The server wraps in { ok, data: { accessToken, refreshToken } }
        final raw = response.data as Map<String, dynamic>;
        final payload = (raw['data'] as Map<String, dynamic>?) ?? raw;
        await setTokens(
          accessToken: payload['accessToken'] as String,
          refreshToken: payload['refreshToken'] as String,
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      _isRefreshing = false;
    }
  }

  /// Maps a [DioException] to a domain-level [Failure].
  static Failure mapDioError(DioException e) {
    if (kDebugMode) debugPrint('[API] mapDioError: type=${e.type} uri=${e.requestOptions.uri} message=${e.message}');
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return TimeoutFailure('The request timed out. Please check your connection and try again.');
    }
    if (e.type == DioExceptionType.connectionError) {
      return NetworkFailure('Unable to reach Katisha servers. Please check your internet connection and try again.');
    }
    final statusCode = e.response?.statusCode;
    final message = _extractErrorMessage(e.response?.data);
    if (statusCode == 401) return const AuthFailure();
    if (statusCode != null && statusCode >= 400) {
      return ServerFailure(message, statusCode: statusCode);
    }
    return UnknownFailure(message);
  }

  static String _extractErrorMessage(dynamic data) {
    if (data == null) return 'An unexpected error occurred.';
    if (data is Map<String, dynamic>) {
      return data['message'] as String? ??
          data['error'] as String? ??
          'An unexpected error occurred.';
    }
    return data.toString();
  }
}
