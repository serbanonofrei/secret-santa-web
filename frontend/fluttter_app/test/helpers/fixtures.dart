/// JSON bodies exactly as the Edge Functions return them.
abstract final class Fixtures {
  static const sessionId = '0b9d6c2e-6f1a-4c55-9a51-3f8f3b0f2a10';
  static const participantId = '5c3b1e7a-2d4f-4e8b-8a6c-1f2e3d4c5b6a';
  static const organizerToken = 'ORG_7e1a2b3c-4d5e-4f60-8a1b-2c3d4e5f6a7b';
  static final browserToken = 'BT_${'A1b2C3d4E5' * 4}xyz';
  static const recoveryCode = 'ABCD-EFGH-JKLM';
  static const inviteCode = 'ABC234';

  static const red = {'name': 'RED', 'hexColor': '#FF0000'};
  static const green = {'name': 'GREEN', 'hexColor': '#00FF00'};

  static const listColors = {
    'colors': [
      {'id': 2, 'name': 'GREEN', 'hexColor': '#00FF00'},
      {'id': 1, 'name': 'RED', 'hexColor': '#FF0000'},
    ],
  };

  static const createSession = {
    'sessionId': sessionId,
    'inviteCode': inviteCode,
    'organizerToken': organizerToken,
    'published': false,
    'selectedColors': [
      {'catalogId': 1, 'name': 'RED', 'hexColor': '#FF0000'},
      {'catalogId': 2, 'name': 'GREEN', 'hexColor': '#00FF00'},
    ],
  };

  static const publishSession = {
    'sessionId': sessionId,
    'sessionName': 'Office Xmas',
    'inviteCode': inviteCode,
    'maxParticipants': 2,
    'status': 'ACTIVE',
    'published': true,
    'draft': false,
    'colorCount': 2,
  };

  static const getParticipants = {
    'sessionId': sessionId,
    'sessionName': 'Office Xmas',
    'status': 'ACTIVE',
    'published': true,
    'joinedCount': 1,
    'maxParticipants': 2,
    'participants': [
      {'participantId': participantId, 'participantName': 'Maria'},
    ],
  };

  static const closeSession = {
    'sessionId': sessionId,
    'status': 'CLOSED',
    'published': true,
    'sessionName': 'Office Xmas',
  };

  static Map<String, dynamic> joinSession() => {
        'participantId': participantId,
        'browserToken': browserToken,
        'recoveryCode': recoveryCode,
        'myColor': red,
        'giftColor': green,
      };

  static const getMyAssignment = {
    'participantId': participantId,
    'participantName': 'Maria',
    'myColor': red,
    'giftColor': green,
  };

  static Map<String, dynamic> recoverAssignment() => {
        'participantId': participantId,
        'participantName': 'Maria',
        'browserToken': browserToken,
        'myColor': red,
        'giftColor': green,
      };
}
