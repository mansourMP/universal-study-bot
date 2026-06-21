import 'dart:convert';

import 'package:dragon_chinese/core/network/api_client.dart';
import 'package:dragon_chinese/core/net/endpoints.dart';
import 'package:dragon_chinese/features/course/services/skill_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('SkillService.fetchMissionWords', () {
    test('uses POST /api/v2/brain/mission with mission request body', () async {
      late String method;
      late Uri uri;
      late Map<String, dynamic> body;

      final mockClient = MockClient((request) async {
        method = request.method;
        uri = request.url;
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'mission_id': 'm1', 'exercises': []}),
          200,
        );
      });

      final service = SkillService(api: ApiClient(client: mockClient));
      await service.fetchMissionWords(
        userId: 'u1',
        limitNew: 5,
        limitReview: 3,
      );

      expect(method, equals('POST'));
      expect(uri.path, equals(Endpoints.brainMission));
      expect(body['language_code'], equals('zh'));
      expect(body['intent'], equals('daily'));
      expect(body['limit'], equals(8));
      expect(body.containsKey('user_id'), isFalse);
    });
  });
}
