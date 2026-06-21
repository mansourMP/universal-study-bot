import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/multiple_choice_exercise.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/explain_panel.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/design_system/exercise_theme.dart';

class _ExerciseHarness extends StatefulWidget {
  final Widget Function(
    BuildContext context,
    int? selectedIndex,
    bool isAnswered,
    bool showPinyin,
    ValueChanged<int> onSelect,
    VoidCallback onCheck,
  )
  builder;

  const _ExerciseHarness({required this.builder});

  @override
  State<_ExerciseHarness> createState() => _ExerciseHarnessState();
}

class _ExerciseHarnessState extends State<_ExerciseHarness> {
  int? selectedIndex;
  bool isAnswered = false;
  bool showPinyin = false;

  void _onSelect(int index) {
    setState(() {
      selectedIndex = index;
    });
  }

  void _onCheck() {
    setState(() {
      isAnswered = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        widget.builder(
          context,
          selectedIndex,
          isAnswered,
          showPinyin,
          _onSelect,
          _onCheck,
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: selectedIndex != null ? _onCheck : null,
          child: const Text('Check'),
        ),
      ],
    );
  }
}

void main() {
  testWidgets('MeaningSelectExercise shows correct feedback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _ExerciseHarness(
            builder:
                (
                  context,
                  selectedIndex,
                  isAnswered,
                  showPinyin,
                  onSelect,
                  onCheck,
                ) {
                  return MeaningSelectExercise(
                    hanzi: '你好',
                    pinyin: 'ni hao',
                    choices: const ['hello', 'thanks', 'sorry', 'bye'],
                    answerIndex: 0,
                    selectedIndex: selectedIndex,
                    isAnswered: isAnswered,
                    showPinyin: showPinyin,
                    onTogglePinyin: () {},
                    onSelect: onSelect,
                  );
                },
          ),
        ),
      ),
    );

    final cards = tester
        .widgetList<MultipleChoiceOptionCard>(
          find.byType(MultipleChoiceOptionCard),
        )
        .toList();
    expect(cards.length, 4);
    expect(cards[0].label, 'hello');
    expect(cards[1].label, 'thanks');

    await tester.tap(find.text('hello'));
    await tester.pump();
    await tester.tap(find.text('Check'));
    await tester.pump();

    // Check for success color instead of icon
    final textWidget = tester.widget<Text>(find.text('hello'));
    expect(textWidget.style?.color, ExerciseThemeTokens.success);
  });

  testWidgets('CharacterSelectExercise shows wrong feedback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _ExerciseHarness(
            builder:
                (
                  context,
                  selectedIndex,
                  isAnswered,
                  showPinyin,
                  onSelect,
                  onCheck,
                ) {
                  return CharacterSelectExercise(
                    meaning: 'to read',
                    pinyin: 'du',
                    choices: const ['读', '看', '写', '听'],
                    answerIndex: 0,
                    selectedIndex: selectedIndex,
                    isAnswered: isAnswered,
                    showPinyin: showPinyin,
                    onTogglePinyin: () {},
                    onSelect: onSelect,
                  );
                },
          ),
        ),
      ),
    );

    await tester.tap(find.text('看'));
    await tester.pump();
    await tester.tap(find.text('Check'));
    await tester.pump();

    // Check for error color instead of icon
    final textWidget = tester.widget<Text>(find.text('看'));
    expect(textWidget.style?.color, ExerciseThemeTokens.error);
  });

  testWidgets('AudioSelectExercise shows correct feedback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _ExerciseHarness(
            builder:
                (
                  context,
                  selectedIndex,
                  isAnswered,
                  showPinyin,
                  onSelect,
                  onCheck,
                ) {
                  return AudioSelectExercise(
                    audioUrl: null,
                    choiceType: 'hanzi',
                    choices: const ['你', '我', '他', '她'],
                    answerIndex: 1,
                    selectedIndex: selectedIndex,
                    isAnswered: isAnswered,
                    onSelect: onSelect,
                    showPrompt: true,
                  );
                },
          ),
        ),
      ),
    );

    await tester.tap(find.text('我'));
    await tester.pump();
    await tester.tap(find.text('Check'));
    await tester.pump();

    final textWidget = tester.widget<Text>(find.text('我'));
    expect(textWidget.style?.color, ExerciseThemeTokens.success);
  });

  testWidgets('DictationSelectExercise shows prompt', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _ExerciseHarness(
            builder:
                (
                  context,
                  selectedIndex,
                  isAnswered,
                  showPinyin,
                  onSelect,
                  onCheck,
                ) {
                  return DictationSelectExercise(
                    audioUrl: null,
                    promptText: 'Listen and choose the correct sentence',
                    options: const ['我喜欢茶。', '我喜欢水。', '我喜欢米饭。', '我喜欢咖啡。'],
                    answerIndex: 0,
                    selectedIndex: selectedIndex,
                    isAnswered: isAnswered,
                    onSelect: onSelect,
                    showPrompt: true,
                  );
                },
          ),
        ),
      ),
    );
    expect(find.text('Listen and choose the correct sentence'), findsOneWidget);
    await tester.tap(find.text('我喜欢茶。'));
    await tester.pump();
    await tester.tap(find.text('Check'));
    await tester.pump();

    final textWidget = tester.widget<Text>(find.text('我喜欢茶。'));
    expect(textWidget.style?.color, ExerciseThemeTokens.success);
  });

  testWidgets('ClozeSelectExercise shows correct feedback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _ExerciseHarness(
            builder:
                (
                  context,
                  selectedIndex,
                  isAnswered,
                  showPinyin,
                  onSelect,
                  onCheck,
                ) {
                  return ClozeSelectExercise(
                    sentence: '我 ____ 中文。',
                    choices: const ['学', '喝', '看', '吃'],
                    answerIndex: 0,
                    selectedIndex: selectedIndex,
                    isAnswered: isAnswered,
                    onSelect: onSelect,
                  );
                },
          ),
        ),
      ),
    );

    await tester.tap(find.text('学'));
    await tester.pump();
    await tester.tap(find.text('Check'));
    await tester.pump();

    final candidates = tester.widgetList<Text>(find.text('学'));
    final hasSuccessStyle = candidates.any(
      (widget) => widget.style?.color == ExerciseThemeTokens.success,
    );
    expect(hasSuccessStyle, isTrue);
  });

  testWidgets(
    'ClozeSelectExercise renders compact context passage with word limit',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 353,
              height: 502,
              child: ClozeSelectExercise(
                sentence: 'I ____ to school every day.',
                contextPassage:
                    'This sentence is from a short passage where the speaker describes a daily routine before class starts.',
                contextMaxWords: 10,
                choices: const ['go', 'eat', 'drink', 'sleep'],
                answerIndex: 0,
                selectedIndex: null,
                isAnswered: false,
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(
        find.textContaining(
          'This sentence is from a short passage where the speaker',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('daily routine before class starts.'),
        findsNothing,
      );
      expect(find.text('sleep'), findsOneWidget);
    },
  );

  testWidgets('ClozeSelectExercise phrase mode renders long options cleanly', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 353,
            height: 502,
            child: ClozeSelectExercise(
              sentence: 'I usually ____ before class.',
              phraseMode: true,
              choices: const [
                'review my notes quickly',
                'go to the gym for two hours',
                'sleep the whole morning',
                'watch random videos online',
              ],
              answerIndex: 0,
              selectedIndex: null,
              isAnswered: false,
              onSelect: _noopSelect,
            ),
          ),
        ),
      ),
    );

    expect(find.text('review my notes quickly'), findsOneWidget);
    expect(find.text('watch random videos online'), findsOneWidget);
  });

  testWidgets('OrderSentenceExercise builds sentence via tap', (tester) async {
    List<String> updated = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderSentenceExercise(
            chunks: const ['我', '喜欢', '中文'],
            onChanged: (list) => updated = list,
          ),
        ),
      ),
    );

    // Tap words in the bank
    await tester.tap(find.text('我').first);
    await tester.pumpAndSettle();
    expect(updated, equals(['我']));

    await tester.tap(find.text('喜欢').first);
    await tester.pumpAndSettle();
    expect(updated, equals(['我', '喜欢']));

    // Tap word in sentence to remove (first is the answer tile, second is ghost)
    await tester.tap(find.text('我').first);
    await tester.pumpAndSettle();
    expect(updated, equals(['喜欢']));
  });

  testWidgets('MeaningMatchExercise completes matches', (tester) async {
    bool ready = false;
    bool correct = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MeaningMatchExercise(
            leftItems: const ['你', '我'],
            rightItems: const ['you', 'me'],
            mapping: const [0, 1],
            onStatus: (r, c) {
              ready = r;
              correct = c;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('你'));
    await tester.pump();
    await tester.tap(find.text('you'));
    await tester.pump();
    await tester.tap(find.text('我'));
    await tester.pump();
    await tester.tap(find.text('me'));
    await tester.pump();

    expect(ready, isTrue);
    expect(correct, isTrue);
  });

  testWidgets('ReadingMicroExercise renders detail question', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadingMicroExercise(
            titleZh: '测试',
            titleEn: 'Test',
            storyZh: '这是一个故事。',
            storyEn: 'This is a story.',
            questionIndex: 0,
            questions: const [
              {
                'type': 'detail_select',
                'prompt': {'question': 'Which detail appears in the passage?'},
                'choices': ['This is a story.', 'Another line.'],
                'answer_index': 0,
              },
            ],
            selectedIndex: null,
            isAnswered: false,
            onSelect: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Which detail appears in the passage?'), findsOneWidget);
  });

  testWidgets('ReadingMicroExercise shows wrong feedback', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReadingMicroExercise(
            titleZh: '测试',
            titleEn: 'Test',
            storyZh: '这是一个故事。',
            storyEn: 'This is a story.',
            questionIndex: 0,
            questions: [
              {
                'type': 'detail_select',
                'prompt': {'question': 'Which detail appears in the passage?'},
                'choices': ['This is a story.', 'Another line.'],
                'answer_index': 0,
              },
            ],
            selectedIndex: 1,
            isAnswered: true,
            onSelect: _noopSelect,
          ),
        ),
      ),
    );

    // After answering incorrectly, we expect error color on the selected option
    final textWidget = tester.widget<Text>(find.text('Another line.'));
    expect(textWidget.style?.color, ExerciseThemeTokens.error);
  });

  testWidgets(
    'ReadingSpanSelectExercise keeps four options visible without tray scroll',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 353,
              height: 502,
              child: ReadingSpanSelectExercise(
                passage: '我今天在公园跑步，然后去学校学习中文。',
                question: 'Where did I run?',
                choices: const [
                  'At the park',
                  'At the hospital',
                  'At the airport',
                  'At home',
                ],
                answerIndex: 0,
                selectedIndex: null,
                isAnswered: false,
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      );

      // Passage keeps one scroll container; answer tray should not add another.
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.text('At home'), findsOneWidget);
    },
  );

  testWidgets('Explain panel renders why payload', (tester) async {
    final why = PilotWhy(
      reasons: const ['HSK1 core vocabulary', 'Exam practice'],
      signals: PilotWhySignals(accuracy: 0.9, latencyMs: 1200, mistakeCount: 1),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ExplainButton(why: why)),
      ),
    );

    // Tap the ? icon (was ! in old version)
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.text('Why this exercise?'), findsOneWidget);
    expect(find.text('HSK1 core vocabulary'), findsOneWidget);
  });
}

void _noopSelect(int _) {}
