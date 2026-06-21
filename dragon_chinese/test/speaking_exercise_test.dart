import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/speaking_exercise.dart';

class _SpeakingHarness extends StatefulWidget {
  const _SpeakingHarness();

  @override
  State<_SpeakingHarness> createState() => _SpeakingHarnessState();
}

class _SpeakingHarnessState extends State<_SpeakingHarness> {
  bool permissionGranted = true;
  bool isRecording = false;
  int? durationMs;
  SpeakingRating? rating;

  void _start() {
    setState(() => isRecording = true);
  }

  void _stop() {
    setState(() {
      isRecording = false;
      durationMs = 1200;
    });
  }

  void _rate(SpeakingRating value) {
    setState(() => rating = value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            SpeakReadAloudExercise(
              hanzi: '你好',
              pinyin: 'ni hao',
              sampleAnswers: const ['你好', '你好啊'],
              permissionGranted: permissionGranted,
              isRecording: isRecording,
              durationMs: durationMs,
              rating: rating,
              onRequestPermission: () {},
              onStartRecording: _start,
              onStopRecording: _stop,
              onRate: _rate,
            ),
            if (rating != null)
              Text('Selected: ${speakingRatingLabel(rating!)}'),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('Speaking exercise shows permission request when denied', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SpeakReadAloudExercise(
            hanzi: '你好',
            pinyin: 'ni hao',
            sampleAnswers: ['你好'],
            permissionGranted: false,
            isRecording: false,
            durationMs: null,
            rating: null,
            onRequestPermission: _noop,
            onStartRecording: _noop,
            onStopRecording: _noop,
            onRate: _noopRate,
          ),
        ),
      ),
    );

    expect(find.text('Microphone access required'), findsOneWidget);
    expect(find.text('Enable microphone'), findsOneWidget);
  });

  testWidgets('Speaking exercise record flow updates review state', (
    tester,
  ) async {
    await tester.pumpWidget(const _SpeakingHarness());

    // Initial state: idle mic button visible.
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump();

    // Recording state: stop button visible.
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();

    // Back to idle. Manual rating action remains available.
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    await tester.tap(find.text('Skip for now'));
    await tester.pump();

    expect(find.text('Selected: Needs work'), findsOneWidget);
  });
}

void _noop() {}

void _noopRate(SpeakingRating _) {}
