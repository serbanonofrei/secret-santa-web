import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/core/providers.dart';
import 'package:secret_santa/core/storage/identity_store.dart';
import 'package:secret_santa/core/storage/secure_storage.dart';
import 'package:secret_santa/data/models/app_session.dart';
import 'package:secret_santa/data/models/participant_identity.dart';
import 'package:secret_santa/features/startup/startup_controller.dart';

/// Storage whose reads are held until the test releases them, in order.
/// Each read captures the value at the moment it is RELEASED.
class _GatedStorage extends InMemorySecureStorage {
  final Queue<Completer<void>> _gates = Queue();
  bool gate = false;

  int get pendingReads => _gates.length;

  void releaseNext() => _gates.removeFirst().complete();

  /// Releases a specific pending read (0 = oldest), to simulate out-of-order completion.
  void releaseAt(int index) {
    final gate = _gates.elementAt(index);
    _gates.remove(gate);
    gate.complete();
  }

  @override
  Future<String?> read(String key) async {
    if (gate) {
      final completer = Completer<void>();
      _gates.add(completer);
      await completer.future;
    }
    return super.read(key);
  }
}

ParticipantCredentials credentials(String id) =>
    ParticipantCredentials(participantId: id, browserToken: 'BT_$id', savedAt: DateTime.utc(2026, 12, 1));

void main() {
  late _GatedStorage storage;
  late ProviderContainer container;

  setUp(() async {
    storage = _GatedStorage();
    container = ProviderContainer(overrides: [secureStorageProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    await container.read(startupControllerProvider.future); // initial build: anonymous
    storage.gate = true;
  });

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  test('two quick syncFromStorage calls: the later call wins even if it finishes first', () async {
    final notifier = container.read(startupControllerProvider.notifier);

    final first = notifier.syncFromStorage();
    await pump();
    // State changes between the two calls: identity saved.
    storage.gate = false;
    await CredentialStore(storage).saveParticipant(credentials('new'));
    storage.gate = true;
    final second = notifier.syncFromStorage();
    await pump();
    expect(storage.pendingReads, 2);

    // Second (newer) read completes first, then the stale first read.
    storage.releaseAt(1);
    await second;
    expect((container.read(startupControllerProvider).value as ParticipantSession).credentials.participantId, 'new');

    storage.releaseNext();
    await first;
    // The stale read must not overwrite the newer result.
    expect(container.read(startupControllerProvider).value, isA<ParticipantSession>());
  });

  test('markAnonymous during a sync discards the late read', () async {
    storage.gate = false;
    await CredentialStore(storage).saveParticipant(credentials('p'));
    storage.gate = true;
    final notifier = container.read(startupControllerProvider.notifier);

    final sync = notifier.syncFromStorage();
    await pump();

    // User leaves the device while the read is still running.
    storage.gate = false;
    await CredentialStore(storage).clearParticipant();
    storage.gate = true;
    notifier.markAnonymous();

    // Worst case for the old code: release the read while the identity is
    // temporarily back in storage, so the late read sees a participant.
    storage.gate = false;
    await CredentialStore(storage).saveParticipant(credentials('p'));
    storage.gate = true;
    storage.releaseNext();
    await sync;

    expect(container.read(startupControllerProvider).value, isA<AnonymousSession>());
  });

  test('syncFromStorage returns the current state after completion', () async {
    storage.gate = false;
    await CredentialStore(storage).saveParticipant(credentials('p'));
    final result = await container.read(startupControllerProvider.notifier).syncFromStorage();

    expect(result.value, isA<ParticipantSession>());
    expect(container.read(startupControllerProvider), same(result));
  });

  test('syncFromStorage called before the initial build finishes is not overwritten by it', () async {
    final fresh = _GatedStorage()..gate = true;
    final c = ProviderContainer(overrides: [secureStorageProvider.overrideWithValue(fresh)]);
    addTearDown(c.dispose);

    c.read(startupControllerProvider); // starts the initial build (read #1, sees nothing)
    await pump();
    final sync = c.read(startupControllerProvider.notifier).syncFromStorage();
    await pump();

    // Identity is saved after the initial read started.
    fresh.gate = false;
    await CredentialStore(fresh).saveParticipant(credentials('p'));
    fresh.gate = true;

    fresh.releaseNext(); // initial build completes: anonymous
    await pump();
    await pump();
    fresh.releaseNext(); // sync read completes: participant
    await sync;

    expect(c.read(startupControllerProvider).value, isA<ParticipantSession>());
  });
}
