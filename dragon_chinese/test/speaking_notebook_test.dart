import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dragon_chinese/features/course/services/speaking_notebook.dart';

void main() {
  test('SpeakingNotebook persists entries', () async {
    SharedPreferences.setMockInitialValues({});

    final notebook = await SpeakingNotebook.load();
    expect(notebook.entries().length, 0);

    notebook.addEntry(
      SpeakingEntry(
        conceptId: 12,
        exerciseType: 'speak_read_aloud',
        rating: 'Clean',
        durationMs: 1200,
        recordingPath: '/tmp/test.wav',
        createdAt: 123456,
        promptText: 'Read aloud',
        sampleAnswers: const ['你好'],
      ),
    );
    await notebook.save();

    final reloaded = await SpeakingNotebook.load();
    expect(reloaded.entries().length, 1);
    expect(reloaded.entries().first.conceptId, 12);
    expect(reloaded.entries().first.rating, 'Clean');
  });
}
