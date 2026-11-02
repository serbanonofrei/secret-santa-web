import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal key-value interface over secure storage, so it can be replaced by
/// [InMemorySecureStorage] in tests.
abstract interface class SecureStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// Thrown when the platform secure storage fails (e.g. Keychain locked,
/// Keystore unavailable, WebCrypto blocked).
class SecureStorageException implements Exception {
  const SecureStorageException(this.operation, this.key, this.cause);

  final String operation;
  final String key;
  final Object cause;

  @override
  String toString() => 'SecureStorageException($operation "$key"): $cause';
}

/// [SecureStorage] backed by `flutter_secure_storage`.
///
/// * Android: EncryptedSharedPreferences (Keystore-backed key).
/// * iOS: Keychain, available after first unlock, never synced to other devices.
/// * Web: WebCrypto-encrypted values. The key is also stored in the browser,
///   so this only protects against casual inspection, not XSS or someone with
///   access to the browser profile.
class FlutterSecureStorageAdapter implements SecureStorage {
  FlutterSecureStorageAdapter([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
              webOptions: WebOptions(
                dbName: 'secret_santa',
                publicKey: 'secret_santa',
              ),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _guard('read', key, () => _storage.read(key: key));

  @override
  Future<void> write(String key, String value) =>
      _guard('write', key, () => _storage.write(key: key, value: value));

  @override
  Future<void> delete(String key) => _guard('delete', key, () => _storage.delete(key: key));

  Future<T> _guard<T>(String operation, String key, Future<T> Function() action) async {
    try {
      return await action();
    } on PlatformException catch (e) {
      throw SecureStorageException(operation, key, e);
    }
  }
}

/// In-memory [SecureStorage] for tests.
class InMemorySecureStorage implements SecureStorage {
  InMemorySecureStorage([Map<String, String>? initial]) : _values = {...?initial};

  final Map<String, String> _values;

  /// Read-only view, for assertions in tests.
  Map<String, String> get values => Map.unmodifiable(_values);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
