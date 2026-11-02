import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/core/providers.dart';
import 'package:secret_santa/core/storage/identity_store.dart';
import 'package:secret_santa/core/storage/secure_storage.dart';
import 'package:secret_santa/data/models/app_session.dart';
import 'package:secret_santa/data/models/participant_identity.dart';
import 'package:secret_santa/features/startup/startup_controller.dart';

class _FailingStorage implements SecureStorage {
  @override
  Future<String?> read(String key) async => throw const SecureStorageException('read', 'k', 'locked');

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

ProviderContainer containerWith(SecureStorage storage) {
  final container = ProviderContainer(
    overrides: [secureStorageProvider.overrideWithValue(storage)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('no stored credentials -> AnonymousSession', () async {
    final container = containerWith(InMemorySecureStorage());

    final session = await container.read(startupControllerProvider.future);

    expect(session, const AnonymousSession());
  });

  test('stored credentials -> ParticipantSession', () async {
    final storage = InMemorySecureStorage();
    final credentials = ParticipantCredentials(
      participantId: 'p1',
      browserToken: 'BT_${'x' * 43}',
      savedAt: DateTime.utc(2026, 12, 1),
    );
    await CredentialStore(storage).saveParticipant(credentials);
    final container = containerWith(storage);

    final session = await container.read(startupControllerProvider.future);

    expect(session, ParticipantSession(credentials));
  });

  test('storage failure -> AsyncError, nothing deleted', () async {
    final container = containerWith(_FailingStorage());

    await expectLater(
      container.read(startupControllerProvider.future),
      throwsA(isA<SecureStorageException>()),
    );
    expect(container.read(startupControllerProvider).hasError, isTrue);
  });
}
