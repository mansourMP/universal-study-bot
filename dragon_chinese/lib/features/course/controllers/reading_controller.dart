import 'package:dragon_chinese/core/network/api_client.dart';

class ReadingUnit {
  final String id;
  final String title;
  final String subtitle;
  final String guideId;

  const ReadingUnit({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.guideId,
  });

  factory ReadingUnit.fromJson(Map<String, dynamic> json) {
    return ReadingUnit(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Unit',
      subtitle: json['subtitle'] ?? 'Story',
      guideId: json['guide_id'] ?? 'CHAR_HUAHUA',
    );
  }
}

class ReadingController {
  final ApiClient _api;
  ReadingController({ApiClient? api}) : _api = api ?? ApiClient();

  Future<List<ReadingUnit>> loadUnits() async {
    final data = await _api.getJson(
      '/api/v2/path/journey',
      query: {'level': '1'},
    );
    final List<dynamic> nodes = data['nodes'] ?? [];
    return nodes.map((n) => ReadingUnit.fromJson(n)).toList();
  }
}

class StoryController {
  final ApiClient _api;
  StoryController({ApiClient? api}) : _api = api ?? ApiClient();

  Future<Map<String, dynamic>> loadStory(String unitId) async {
    return _api.getJson('/api/v2/path/unit/$unitId/passage');
  }
}
