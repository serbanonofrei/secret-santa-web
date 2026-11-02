import 'package:dio/dio.dart';
import 'package:secret_santa/core/network/api_client.dart';
import 'package:secret_santa/core/storage/secure_storage.dart';

/// One recorded [FakeApiClient.post] call.
class RecordedCall {
  const RecordedCall(this.functionName, this.body);

  final String functionName;
  final Map<String, Object?> body;
}

/// [ApiClient] that never touches the network.
///
/// Register a response (JSON map) or an error (any object, usually an
/// [ApiFailure]) per function name. Every call is recorded.
class FakeApiClient extends ApiClient {
  FakeApiClient() : super(Dio());

  final Map<String, Map<String, dynamic>> _responses = {};
  final Map<String, Object> _errors = {};
  final List<RecordedCall> calls = [];

  void respond(String functionName, Map<String, dynamic> json) {
    _errors.remove(functionName);
    _responses[functionName] = json;
  }

  void fail(String functionName, Object error) {
    _responses.remove(functionName);
    _errors[functionName] = error;
  }

  List<RecordedCall> callsTo(String functionName) =>
      calls.where((c) => c.functionName == functionName).toList();

  @override
  Future<Map<String, dynamic>> post(
    String functionName, {
    Map<String, Object?> body = const {},
    CancelToken? cancelToken,
  }) async {
    calls.add(RecordedCall(functionName, Map.unmodifiable(body)));
    final error = _errors[functionName];
    if (error != null) throw error;
    final response = _responses[functionName];
    if (response == null) {
      throw StateError('FakeApiClient: no response registered for $functionName');
    }
    return response;
  }
}

/// In-memory storage whose writes fail on demand (reads keep working).
class FlakyWriteStorage extends InMemorySecureStorage {
  bool failWrites = true;

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw SecureStorageException('write', key, 'disk full');
    return super.write(key, value);
  }
}
