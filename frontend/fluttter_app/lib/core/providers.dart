import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/app_config.dart';
import 'network/api_client.dart';
import 'storage/identity_store.dart';
import 'storage/secure_storage.dart';

/// Application configuration. Overridden in `main.dart` with the value read
/// from `--dart-define-from-file`, and in tests with a fixed config.
final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider must be overridden in ProviderScope'),
  name: 'appConfigProvider',
);

/// HTTP client for the Edge Functions.
final apiClientProvider = Provider<ApiClient>(
  (ref) {
    final client = ApiClient.create(ref.watch(appConfigProvider));
    ref.onDispose(client.close);
    return client;
  },
  name: 'apiClientProvider',
);

/// Platform secure storage. Override with [InMemorySecureStorage] in tests.
final secureStorageProvider = Provider<SecureStorage>(
  (ref) => FlutterSecureStorageAdapter(),
  name: 'secureStorageProvider',
);

/// Typed credential access on top of [secureStorageProvider].
final credentialStoreProvider = Provider<CredentialStore>(
  (ref) => CredentialStore(ref.watch(secureStorageProvider)),
  name: 'credentialStoreProvider',
);
