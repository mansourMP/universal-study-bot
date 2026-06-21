import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/services/mistake_notebook.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('MistakeNotebook persists entries', () async {
    SharedPreferences.setMockInitialValues({});
    final notebook = await MistakeNotebook.load();
    notebook.recordAttempt(conceptId: 1, exerciseType: 'meaning_select', isCorrect: false);
    notebook.recordAttempt(conceptId: 1, exerciseType: 'meaning_select', isCorrect: false);
    notebook.recordAttempt(conceptId: 2, exerciseType: 'audio_select', isCorrect: false);
    await notebook.save();

    final reloaded = await MistakeNotebook.load();
    final weakest = reloaded.weakest(10);
    expect(weakest.first.conceptId, 1);
    expect(weakest.first.wrongCount, 2);
  });
}
