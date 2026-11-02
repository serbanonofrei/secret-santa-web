import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/core/providers.dart';
import 'package:secret_santa/core/storage/identity_store.dart';
import 'package:secret_santa/core/storage/secure_storage.dart';
import 'package:secret_santa/data/data_providers.dart';
import 'package:secret_santa/data/models/participant_identity.dart';
import 'package:secret_santa/data/services/participant_service.dart';
import 'package:secret_santa/data/services/session_service.dart';

import 'fakes.dart';
import 'fixtures.dart';

/// Real repositories wired to a [FakeApiClient] and an in-memory storage.
/// No network, no platform channels.
class TestEnv {
  TestEnv({SecureStorage? storage}) : storage = storage ?? InMemorySecureStorage();

  final FakeApiClient client = FakeApiClient();
  final SecureStorage storage;

  CredentialStore get store => CredentialStore(storage);

  List<Override> get overrides => [
        secureStorageProvider.overrideWithValue(storage),
        participantServiceProvider.overrideWithValue(ParticipantService(client)),
        sessionServiceProvider.overrideWithValue(SessionService(client)),
      ];

  ProviderContainer container() {
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    return container;
  }

  /// Stores a participant identity, as after a successful join.
  Future<void> storeParticipant({String? recoveryCode = Fixtures.recoveryCode}) => store.saveParticipant(
        ParticipantCredentials(
          participantId: Fixtures.participantId,
          browserToken: Fixtures.browserToken,
          recoveryCode: recoveryCode,
          participantName: 'Maria',
          savedAt: DateTime.utc(2026, 12, 1),
        ),
      );
}

/// Pumps [child] inside a ProviderScope + MaterialApp.
Future<void> pumpScreen(WidgetTester tester, TestEnv env, Widget child) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: env.overrides,
      child: MaterialApp(home: child),
    ),
  );
}
