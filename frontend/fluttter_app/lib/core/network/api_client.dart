import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../logging/redaction.dart';
import 'api_failure.dart';
import 'error_mapper.dart';

/// Thin HTTP client for the Supabase Edge Functions.
///
/// * Every call is `POST <SUPABASE_URL>/functions/v1/<functionName>` with a
///   JSON body, matching the backend.
/// * Sends the publishable key in the `apikey` header.
/// * No automatic retries: create-session and join-session are not
///   idempotent, so retrying is a user decision.
/// * Every failure is thrown as an [ApiFailure].
class ApiClient {
  ApiClient(this._dio);

  factory ApiClient.create(AppConfig config, {Dio? dio}) {
    final client = dio ?? Dio();
    client.options = BaseOptions(
      baseUrl: config.functionsBaseUrl,
      connectTimeout: config.connectTimeout,
      receiveTimeout: config.receiveTimeout,
      sendTimeout: config.receiveTimeout,
      responseType: ResponseType.json,
      contentType: Headers.jsonContentType,
      headers: <String, Object>{
        'apikey': config.publishableKey,
        Headers.acceptHeader: Headers.jsonContentType,
      },
    );
    if (kDebugMode) {
      client.interceptors.add(_RedactingLogInterceptor());
    }
    return ApiClient(client);
  }

  final Dio _dio;

  /// Calls the Edge Function [functionName] (e.g. `'join-session'`) and returns
  /// the decoded JSON object.
  ///
  /// Throws an [ApiFailure] on any error, including a 2xx response whose body
  /// is not a JSON object.
  Future<Map<String, dynamic>> post(
    String functionName, {
    Map<String, Object?> body = const {},
    CancelToken? cancelToken,
  }) async {
    assert(!functionName.startsWith('/'), 'functionName must not start with "/"');

    final Response<Object?> response;
    try {
      response = await _dio.post<Object?>(
        functionName,
        data: body,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }

    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);

    throw ServerFailure(
      code: ApiErrorCodes.invalidResponse,
      message: 'Expected a JSON object from $functionName',
      statusCode: response.statusCode,
    );
  }

  void close() => _dio.close(force: true);
}

/// Debug-only request/response logging. Headers are never logged, and token
/// and code values in bodies are redacted.
class _RedactingLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint('[api] -> ${options.method} ${options.path} ${redactSensitive(options.data)}');
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    debugPrint(
      '[api] <- ${response.statusCode} ${response.requestOptions.path} ${redactSensitive(response.data)}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint(
      '[api] !! ${err.type.name} ${err.requestOptions.path} '
      '${err.response?.statusCode ?? '-'} ${redactSensitive(err.response?.data)}',
    );
    handler.next(err);
  }
}
