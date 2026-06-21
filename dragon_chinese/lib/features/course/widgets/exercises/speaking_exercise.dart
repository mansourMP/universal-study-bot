import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/exercise_theme.dart';
import 'package:dragon_chinese/design_system/pressable_keycap.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/exercise_answer_tray.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/exercise_feedback_banner.dart';

enum SpeakingRating { clean, ok, needsWork }

enum SpeakingPromptMode { readAloud, translateAndSpeak }

String speakingRatingLabel(SpeakingRating rating) {
  switch (rating) {
    case SpeakingRating.clean:
      return 'Clean';
    case SpeakingRating.ok:
      return 'OK';
    case SpeakingRating.needsWork:
      return 'Needs work';
  }
}

class SpeakReadAloudExercise extends StatelessWidget {
  final String hanzi;
  final String? pinyin;
  final String? meaning;
  final List<String> sampleAnswers;
  final bool permissionGranted;
  final bool isRecording;
  final int? durationMs;
  final SpeakingRating? rating;
  final String? transcript;
  final double? score;
  final VoidCallback onRequestPermission;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final ValueChanged<SpeakingRating> onRate;

  const SpeakReadAloudExercise({
    super.key,
    required this.hanzi,
    this.pinyin,
    this.meaning,
    required this.sampleAnswers,
    required this.permissionGranted,
    required this.isRecording,
    required this.durationMs,
    required this.rating,
    this.transcript,
    this.score,
    required this.onRequestPermission,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    return SpeakingExerciseView(
      title: 'Read aloud',
      promptMode: SpeakingPromptMode.readAloud,
      primaryPrompt: hanzi,
      secondaryPrompt: pinyin,
      meaningHint: meaning,
      sampleAnswers: sampleAnswers,
      permissionGranted: permissionGranted,
      isRecording: isRecording,
      durationMs: durationMs,
      rating: rating,
      transcript: transcript,
      score: score,
      onRequestPermission: onRequestPermission,
      onStartRecording: onStartRecording,
      onStopRecording: onStopRecording,
      onRate: onRate,
    );
  }
}

class SpeakPromptedReplyExercise extends StatelessWidget {
  final String promptText;
  final String? meaning;
  final List<String> sampleAnswers;
  final bool permissionGranted;
  final bool isRecording;
  final int? durationMs;
  final SpeakingRating? rating;
  final String? transcript;
  final double? score;
  final VoidCallback onRequestPermission;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final ValueChanged<SpeakingRating> onRate;

  const SpeakPromptedReplyExercise({
    super.key,
    required this.promptText,
    this.meaning,
    required this.sampleAnswers,
    required this.permissionGranted,
    required this.isRecording,
    required this.durationMs,
    required this.rating,
    this.transcript,
    this.score,
    required this.onRequestPermission,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    final visiblePrompt = _bestVisiblePrompt(promptText);
    return SpeakingExerciseView(
      title: 'Respond aloud',
      promptMode: SpeakingPromptMode.translateAndSpeak,
      primaryPrompt: visiblePrompt,
      secondaryPrompt: null,
      meaningHint: meaning,
      sampleAnswers: sampleAnswers,
      permissionGranted: permissionGranted,
      isRecording: isRecording,
      durationMs: durationMs,
      rating: rating,
      transcript: transcript,
      score: score,
      onRequestPermission: onRequestPermission,
      onStartRecording: onStartRecording,
      onStopRecording: onStopRecording,
      onRate: onRate,
    );
  }

  String _bestVisiblePrompt(String prompt) {
    final trimmed = prompt.trim();
    if (trimmed.isNotEmpty) {
      final cleaned = trimmed.replaceFirst(
        RegExp(
          r'^(respond(?:\s+using)?|respond\s+aloud|translate\s+and\s+speak|say|speak)\s*[:：\-]\s*',
          caseSensitive: false,
        ),
        '',
      );
      final normalized = cleaned.trim();
      if (normalized.isNotEmpty) return normalized;
      return trimmed;
    }
    return 'Translate and speak';
  }
}

class SpeakingExerciseView extends StatelessWidget {
  final String title;
  final SpeakingPromptMode promptMode;
  final String primaryPrompt;
  final String? secondaryPrompt;
  final String? meaningHint;
  final List<String> sampleAnswers;
  final bool permissionGranted;
  final bool isRecording;
  final int? durationMs;
  final SpeakingRating? rating;
  final String? transcript;
  final double? score;
  final VoidCallback onRequestPermission;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final ValueChanged<SpeakingRating> onRate;

  const SpeakingExerciseView({
    super.key,
    required this.title,
    required this.promptMode,
    required this.primaryPrompt,
    this.secondaryPrompt,
    this.meaningHint,
    required this.sampleAnswers,
    required this.permissionGranted,
    required this.isRecording,
    required this.durationMs,
    required this.rating,
    this.transcript,
    this.score,
    required this.onRequestPermission,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight = constraints.maxHeight.isFinite;
        final stageHeight = hasBoundedHeight
            ? constraints.maxHeight
            : (screenHeight * 0.62).clamp(460.0, 700.0).toDouble();
        return SizedBox(
          height: stageHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _targetPromptCard(),
              if (secondaryPrompt != null && secondaryPrompt!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  secondaryPrompt!,
                  textAlign: TextAlign.center,
                  style: ExerciseThemeTokens.caption,
                ),
              ],
              const SizedBox(height: 14),
              Expanded(
                child: ExerciseAnswerTray(
                  children: [
                    _recordCard(),
                    if (permissionGranted) ...[
                      const SizedBox(height: 10),
                      _secondaryAction(),
                    ],
                    if (rating != null) ...[
                      const SizedBox(height: 10),
                      _autoCheckStatus(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _targetPromptCard() {
    final isChinese = _looksLikeChinese(primaryPrompt);
    final isTranslatePrompt =
        promptMode == SpeakingPromptMode.translateAndSpeak;
    return Align(
      alignment: Alignment.center,
      child: Container(
        width: _promptCardWidth(primaryPrompt),
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5EAF2)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          primaryPrompt,
          textAlign: TextAlign.center,
          maxLines: isTranslatePrompt ? 4 : (isChinese ? 2 : 3),
          overflow: TextOverflow.ellipsis,
          style: isTranslatePrompt
              ? ExerciseThemeTokens.promptBody.copyWith(
                  fontSize: 20,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: ExerciseThemeTokens.textPrimary,
                )
              : ExerciseThemeTokens.promptDisplay.copyWith(
                  fontSize: isChinese ? 30 : 24,
                ),
        ),
      ),
    );
  }

  double _promptCardWidth(String prompt) {
    final compact = prompt.trim().replaceAll(
      RegExp(r'[\s\p{P}\p{S}]', unicode: true),
      '',
    );
    final count = compact.length;
    final isTranslatePrompt =
        promptMode == SpeakingPromptMode.translateAndSpeak;
    final multiplier = _looksLikeChinese(prompt)
        ? (isTranslatePrompt ? 16 : 24)
        : (isTranslatePrompt ? 10 : 12);
    final width = 92 + (count * multiplier);
    return width.clamp(140, isTranslatePrompt ? 360 : 340).toDouble();
  }

  Widget _recordCard() {
    if (!permissionGranted) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ExerciseThemeTokens.surface,
          borderRadius: BorderRadius.circular(ExerciseThemeTokens.cardRadius),
          border: Border.all(color: ExerciseThemeTokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Microphone access required',
              style: ExerciseThemeTokens.promptTitle,
            ),
            const SizedBox(height: 6),
            Text(
              'Enable microphone access to record your response.',
              style: ExerciseThemeTokens.promptBody,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRequestPermission,
              child: const Text('Enable microphone'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: isRecording ? _recordingWaveButton() : _idleMicButton(),
    );
  }

  Widget _idleMicButton() {
    return PressableMicButton(
      isRecording: false,
      onTap: onStartRecording,
      enabled: true,
      height: 56,
      fullWidth: true,
      iconSize: 34,
      borderRadius: ExerciseThemeTokens.buttonRadius,
    );
  }

  Widget _recordingWaveButton() {
    return PressableMicButton(
      isRecording: true,
      onTap: onStopRecording,
      enabled: true,
      height: 56,
      fullWidth: true,
      iconSize: 34,
      borderRadius: ExerciseThemeTokens.buttonRadius,
    );
  }

  Widget _secondaryAction() {
    return Align(
      alignment: Alignment.center,
      child: TextButton(
        onPressed: () => onRate(SpeakingRating.needsWork),
        child: Text(
          'Skip for now',
          style: ExerciseThemeTokens.caption.copyWith(
            letterSpacing: 0.1,
            fontWeight: FontWeight.w500,
            color: ExerciseThemeTokens.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _autoCheckStatus() {
    final isGood =
        rating == SpeakingRating.clean || rating == SpeakingRating.ok;
    final heard = (transcript ?? '').trim();
    final title = isGood
        ? 'Good pronunciation'
        : (heard.isEmpty ? 'No speech detected. Try again.' : 'Try again');
    final pct = score == null ? null : (score! * 100).round();
    final details = <String>[
      if (isGood && (meaningHint ?? '').trim().isNotEmpty)
        'Meaning: ${(meaningHint ?? '').trim()}',
      if (pct != null) 'Match score: $pct%',
      if (heard.isNotEmpty) 'Heard: ${_truncate(heard, 48)}',
    ];
    return ExerciseFeedbackBanner(
      tone: isGood ? ExerciseFeedbackTone.success : ExerciseFeedbackTone.error,
      title: title,
      details: details,
    );
  }

  String _truncate(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars)}...';
  }

  bool _looksLikeChinese(String value) {
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(value);
  }
}
