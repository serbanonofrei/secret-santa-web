import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/core/storage/identity_store.dart';
import 'package:secret_santa/core/storage/secure_storage.dart';
import 'package:secret_santa/data/models/organizer_session.dart';
import 'package:secret_santa/data/models/participant_identity.dart';

void main() {
  late InMemorySecureStorage storage;
  late CredentialStore store;

  setUp(() {
    storage = InMemorySecureStorage();
    store = CredentialStore(storage);
  });

  final participant = ParticipantCredentials(
    participantId: '11111111-1111-4111-8111-111111111111',
    browserToken: 'BT_${'a' * 43}',
    recoveryCode: 'ABCD-EFGH-JKLM',
    participantName: 'Maria',
    savedAt: DateTime.utc(2026, 12, 1),
  );

  group('participant', () {
    test('returns null when nothing is stored', () async {
      expect(await store.readParticipant(), isNull);
    });

    test('save then read round-trips', () async {
      await store.saveParticipant(participant);
      expect(await store.readParticipant(), participant);
    });

    test('clear removes the value', () async {
      await store.saveParticipant(participant);
      await store.clearParticipant();
      expect(await store.readParticipant(), isNull);
    });

    test('corrupt value is deleted and treated as absent', () async {
      await storage.write(CredentialStore.participantKey, '{not json');
      expect(await store.readParticipant(), isNull);
      expect(storage.values.containsKey(CredentialStore.participantKey), isFalse);
    });

    test('valid JSON with the wrong shape is corruption (deleted)', () async {
      for (final raw in ['[1, 2, 3]', '"just a string"', '42']) {
        await storage.write(CredentialStore.participantKey, raw);
        expect(await store.readParticipant(), isNull, reason: raw);
        expect(storage.values.containsKey(CredentialStore.participantKey), isFalse, reason: raw);
      }
    });

    test('missing or wrongly typed field is corruption (deleted)', () async {
      final json = participant.toJson();
      final missingToken = Map<String, dynamic>.from(json)..remove('browserToken');
      final wrongType = Map<String, dynamic>.from(json)..['participantId'] = 123;
      final badDate = Map<String, dynamic>.from(json)..['savedAt'] = 'not-a-date';

      for (final value in [missingToken, wrongType, badDate]) {
        await storage.write(CredentialStore.participantKey, jsonEncode(value));
        expect(await store.readParticipant(), isNull);
        expect(storage.values.containsKey(CredentialStore.participantKey), isFalse);
      }
    });

    test('storage read failure propagates and nothing is deleted', () async {
      final failing = _ReadFailingStorage(
        {CredentialStore.participantKey: jsonEncode(participant.toJson())},
      );

      await expectLater(
        CredentialStore(failing).readParticipant(),
        throwsA(isA<SecureStorageException>()),
      );
      expect(failing.deletedKeys, isEmpty);
    });

    test('toString never contains the token or recovery code', () {
      final text = participant.toString();
      expect(text, isNot(contains(participant.browserToken)));
      expect(text, isNot(contains('ABCD-EFGH-JKLM')));
    });
  });

  group('organizer sessions (unchanged policy)', () {
    OrganizerSession session(String id) => OrganizerSession(
          sessionId: id,
          organizerToken: 'ORG_$id',
          inviteCode: 'ABC234',
          sessionName: 'Office',
          createdAt: DateTime.utc(2026, 11, 1),
        );

    test('upsert adds and replaces by sessionId', () async {
      await store.upsertOrganizerSession(session('a'));
      await store.upsertOrganizerSession(session('b'));
      await store.upsertOrganizerSession(session('a').copyWith(sessionName: 'Renamed'));

      final sessions = await store.readOrganizerSessions();
      expect(sessions.map((s) => s.sessionId), ['b', 'a']);
      expect((await store.findOrganizerSession('a'))?.sessionName, 'Renamed');
    });

    test('remove deletes the key when the list becomes empty', () async {
      await store.upsertOrganizerSession(session('a'));
      await store.removeOrganizerSession('a');

      expect(await store.readOrganizerSessions(), isEmpty);
      expect(storage.values.containsKey(CredentialStore.organizerSessionsKey), isFalse);
    });

    test('corrupt list throws and is NOT deleted', () async {
      await storage.write(CredentialStore.organizerSessionsKey, '{"oops": true}');

      await expectLater(store.readOrganizerSessions(), throwsA(isA<CredentialDecodeException>()));
      expect(storage.values.containsKey(CredentialStore.organizerSessionsKey), isTrue);
    });
  });
}

/// Storage whose read always fails; records deletes so tests can assert none happen.
class _ReadFailingStorage implements SecureStorage {
  _ReadFailingStorage(this._values);

  final Map<String, String> _values;
  final List<String> deletedKeys = [];

  @override
  Future<String?> read(String key) async =>
      throw SecureStorageException('read', key, 'Keychain locked');

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async {
    deletedKeys.add(key);
    _values.remove(key);
  }
}
