import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/core/network/api_failure.dart';
import 'package:secret_santa/data/models/color_info.dart';
import 'package:secret_santa/data/services/edge_functions.dart';
import 'package:secret_santa/data/services/participant_service.dart';

import '../../helpers/fakes.dart';
import '../../helpers/fixtures.dart';

void main() {
  late FakeApiClient client;
  late ParticipantService service;

  setUp(() {
    client = FakeApiClient();
    service = ParticipantService(client);
  });

  group('success parsing', () {
    test('joinSession sends the contract body and parses nested colors', () async {
      client.respond(EdgeFunctions.joinSession, Fixtures.joinSession());

      final result = await service.joinSession(inviteCode: Fixtures.inviteCode, participantName: 'Maria');

      expect(client.calls.single.body, {'inviteCode': Fixtures.inviteCode, 'participantName': 'Maria'});
      expect(result.participantId, Fixtures.participantId);
      expect(result.browserToken, Fixtures.browserToken);
      expect(result.recoveryCode, Fixtures.recoveryCode);
      expect(result.myColor, const ColorInfo(name: 'RED', hexColor: '#FF0000'));
      expect(result.giftColor, const ColorInfo(name: 'GREEN', hexColor: '#00FF00'));
    });

    test('getMyAssignment sends only the browser token', () async {
      client.respond(EdgeFunctions.getMyAssignment, Fixtures.getMyAssignment);

      final assignment = await service.getMyAssignment(browserToken: Fixtures.browserToken);

      expect(client.calls.single.body, {'browserToken': Fixtures.browserToken});
      expect(assignment.participantName, 'Maria');
      expect(assignment.giftColor.name, 'GREEN');
    });

    test('recoverAssignment sends only the recovery code', () async {
      client.respond(EdgeFunctions.recoverAssignment, Fixtures.recoverAssignment());

      final recovered = await service.recoverAssignment(recoveryCode: Fixtures.recoveryCode);

      expect(client.calls.single.body, {'recoveryCode': Fixtures.recoveryCode});
      expect(recovered.browserToken, Fixtures.browserToken);
    });
  });

  group('ApiFailure propagation', () {
    test('409 duplicate name is rethrown as the same instance', () async {
      const failure = ConflictFailure(
        code: ApiErrorCodes.duplicateParticipantName,
        message: 'taken',
        statusCode: 409,
      );
      client.fail(EdgeFunctions.joinSession, failure);

      await expectLater(
        service.joinSession(inviteCode: Fixtures.inviteCode, participantName: 'Maria'),
        throwsA(same(failure)),
      );
    });

    test('404 participant not found is rethrown as the same instance', () async {
      const failure = NotFoundFailure(
        code: ApiErrorCodes.participantNotFound,
        message: 'not found',
        statusCode: 404,
      );
      client.fail(EdgeFunctions.getMyAssignment, failure);

      await expectLater(service.getMyAssignment(browserToken: Fixtures.browserToken), throwsA(same(failure)));
    });
  });

  group('malformed responses', () {
    test('missing nested color field', () async {
      client.respond(EdgeFunctions.getMyAssignment, {
        ...Fixtures.getMyAssignment,
        'giftColor': {'name': 'GREEN'},
      });

      await expectLater(
        service.getMyAssignment(browserToken: Fixtures.browserToken),
        throwsA(isA<ServerFailure>().having((f) => f.code, 'code', ApiErrorCodes.invalidResponse)),
      );
    });

    test('missing browser token in recovery', () async {
      client.respond(EdgeFunctions.recoverAssignment, Fixtures.recoverAssignment()..remove('browserToken'));

      await expectLater(
        service.recoverAssignment(recoveryCode: Fixtures.recoveryCode),
        throwsA(isA<ServerFailure>().having((f) => f.code, 'code', ApiErrorCodes.invalidResponse)),
      );
    });
  });

  group('toString redaction', () {
    test('JoinResult hides token and recovery code', () async {
      client.respond(EdgeFunctions.joinSession, Fixtures.joinSession());
      final text = (await service.joinSession(inviteCode: Fixtures.inviteCode, participantName: 'Maria')).toString();

      expect(text, isNot(contains(Fixtures.browserToken)));
      expect(text, isNot(contains(Fixtures.recoveryCode)));
    });

    test('RecoveredAssignment hides the token', () async {
      client.respond(EdgeFunctions.recoverAssignment, Fixtures.recoverAssignment());
      final text = (await service.recoverAssignment(recoveryCode: Fixtures.recoveryCode)).toString();

      expect(text, isNot(contains(Fixtures.browserToken)));
    });
  });
}
