import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dragon_chinese/features/course/engine/practice_exercise_engine.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/services/pilot_exercise_pack_loader.dart';
import 'package:dragon_chinese/features/course/services/exam_scheduler.dart';
import 'package:dragon_chinese/features/course/services/mistake_notebook.dart';
import 'package:dragon_chinese/features/course/services/performance_tracker.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/multiple_choice_exercise.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/explain_panel.dart';
import 'package:dragon_chinese/features/course/screens/exam_report_screen.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/exercise_shell.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/exercise_media.dart';
import 'package:dragon_chinese/core/config/app_config.dart';
import 'package:dragon_chinese/features/course/services/local_mastery_tracker.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/speaking_exercise.dart';
import 'package:dragon_chinese/features/course/services/speaking_notebook.dart';
import 'package:dragon_chinese/features/course/services/speaking_evaluator.dart';
import 'package:dragon_chinese/features/course/services/speaking_recorder.dart';
import 'package:dragon_chinese/features/course/services/exercise_analytics.dart';

class ExamSessionScreen extends StatefulWidget {
  final String seed;
  final PilotExercisePack? packOverride;
  final ExamSchedulerConfig? configOverride;

  const ExamSessionScreen({
    super.key,
    this.seed = 'hsk1-exam',
    this.packOverride,
    this.configOverride,
  });

  @override
  State<ExamSessionScreen> createState() => _ExamSessionScreenState();
}

class _ExamSessionScreenState extends State<ExamSessionScreen> {
  final _loader = PilotExercisePackLoader();
  final _scheduler = ExamScheduler();
  PilotExercisePack? _pack;
  ExamSessionPlan? _plan;
  MistakeNotebook? _notebook;
  PerformanceTracker? _performance;
  LocalMasteryTracker? _mastery;
  SpeakingNotebook? _speakingNotebook;
  final SpeakingRecorder _speakingRecorder = SpeakingRecorderService.instance;
  bool _speakingPermissionGranted = true;
  bool _speakingIsRecording = false;
  SpeakingRecording? _speakingRecording;
  SpeakingRating? _speakingRating;
  double? _speakingScore;
  bool _speakingSubmitInFlight = false;
  String? _error;
  int _currentIndex = 0;
  int? _selectedIndex;
  bool _isAnswered = false;
  int _score = 0;
  int _readingQuestionIndex = 0;
  Timer? _timer;
  Duration _remaining = const Duration(minutes: 18);
  Timer? _itemTimer;
  int? _itemRemainingSec;
  DateTime? _itemStartTime;
  final List<ExamAttempt> _attempts = [];
  int _attemptsRemaining = 0;
  int _attemptsAllowed = 0;
  int _skippedCount = 0;
  List<String> _orderChunks = [];
  List<String> _orderAnswer = [];
  bool _matchReady = false;
  bool _matchCorrect = false;
  String _analyticsSessionId = ExerciseAnalytics.newSessionId(
    ExerciseRunner.exam,
  );
  String? _analyticsLastShownKey;
  final Set<String> _analyticsInteractedKeys = <String>{};
  bool _analyticsSessionActive = false;
  bool _analyticsSessionFinalized = false;
  DateTime? _analyticsStartedAt;

  @override
  void initState() {
    super.initState();
    _analyticsStartedAt = DateTime.now();
    _load();
  }

  @override
  void dispose() {
    _trackSessionQuitIfNeeded();
    _timer?.cancel();
    _itemTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final pack = widget.packOverride ?? await _loader.loadPack();
      final notebook = await MistakeNotebook.load();
      final performance = await PerformanceTracker.load();
      final mastery = await LocalMasteryTracker.load();
      final speakingNotebook = await SpeakingNotebook.load();
      final plan = _scheduler.buildPlan(
        pack: pack,
        seed: widget.seed,
        performance: performance.snapshot(),
        mistakes: notebook.stats(),
        config:
            widget.configOverride ??
            const ExamSchedulerConfig(duration: Duration(minutes: 18)),
      );
      setState(() {
        _pack = pack;
        _plan = plan;
        _notebook = notebook;
        _performance = performance;
        _mastery = mastery;
        _speakingNotebook = speakingNotebook;
        _remaining = plan.duration;
      });
      _beginAnalyticsSession(totalExercises: plan.items.length);
      _startTimer();
      _ensureAvailableItem();
      _resetItemState();
      _trackExerciseShownIfNeeded(source: 'session_start');
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _plan == null) return;
      if (_remaining.inSeconds <= 0) {
        timer.cancel();
        setState(() {});
        return;
      }
      setState(() {
        _remaining = _remaining - const Duration(seconds: 1);
      });
    });
  }

  ExamSessionItem? get _currentItem {
    final plan = _plan;
    if (plan == null) return null;
    if (_currentIndex >= plan.items.length) return null;
    return plan.items[_currentIndex];
  }

  void _ensureAvailableItem() {
    final plan = _plan;
    if (plan == null) return;
    while (_currentIndex < plan.items.length) {
      final item = plan.items[_currentIndex].item;
      if (item.requiredAssets.audio) {
        final url = item.audioUrl;
        if (url != null && url.contains('_placeholder')) {
          final context = _analyticsContextForItem(item);
          if (context != null) {
            ExerciseAnalytics.skipped(context, reason: 'placeholder_audio');
          }
          _skippedCount += 1;
          _attempts.add(
            ExamAttempt(
              item: item,
              isCorrect: false,
              latencyMs: 0,
              timedOverrun: false,
              skipped: true,
              skippedReason: 'placeholder_audio',
            ),
          );
          _currentIndex += 1;
          continue;
        }
      }
      final missingAudio =
          item.requiredAssets.audio &&
          (item.audioUrl == null || item.audioUrl!.isEmpty);
      final imageUrl = item.payload['image_url']?.toString() ?? '';
      final missingImage = item.requiredAssets.image && imageUrl.isEmpty;
      if (missingAudio || missingImage) {
        final context = _analyticsContextForItem(item);
        if (context != null) {
          ExerciseAnalytics.skipped(
            context,
            reason: missingAudio ? 'missing_audio' : 'missing_image',
          );
        }
        _skippedCount += 1;
        _attempts.add(
          ExamAttempt(
            item: item,
            isCorrect: false,
            latencyMs: 0,
            timedOverrun: false,
            skipped: true,
            skippedReason: missingAudio ? 'missing_audio' : 'missing_image',
          ),
        );
        _currentIndex += 1;
        continue;
      }
      break;
    }
  }

  void _checkAnswer() {
    final item = _currentItem;
    if (item == null) return;
    final context = _analyticsContextForItem(item.item);
    if (context != null) {
      ExerciseAnalytics.checkTapped(context);
    }
    final correct = _isCorrect(item);
    final latencyMs = _itemStartTime == null
        ? 0
        : DateTime.now().difference(_itemStartTime!).inMilliseconds;
    final timedSec = item.item.constraints.timedSec ?? 0;
    final timedOverrun = timedSec > 0 && latencyMs > timedSec * 1000;
    if (correct) _score += 1;
    _notebook?.recordAttempt(
      conceptId: item.item.conceptId,
      exerciseType: item.item.exerciseType,
      isCorrect: correct,
    );
    _notebook?.save();
    _performance?.recordAttempt(
      skill: item.item.skill,
      level: item.item.level,
      isCorrect: correct,
      latencyMs: latencyMs,
    );
    _performance?.save();
    _attempts.add(
      ExamAttempt(
        item: item.item,
        isCorrect: correct,
        latencyMs: latencyMs,
        timedOverrun: timedOverrun,
      ),
    );
    _mastery?.recordAttempt(
      conceptId: item.item.conceptId,
      skillBucket: LocalMasteryTracker.skillBucketForExercise(
        item.item.exerciseType,
      ),
      isCorrect: correct,
      isExamMode: true,
      isTimed: timedSec > 0,
    );
    _mastery?.save();
    if (!correct && _attemptsRemaining > 0) {
      _attemptsRemaining -= 1;
    }
    final resultContext = _analyticsContextForItem(
      item.item,
      attemptsRemaining: _attemptsRemaining,
    );
    if (resultContext != null) {
      ExerciseAnalytics.result(
        resultContext,
        isCorrect: correct,
        finalized: correct || _attemptsRemaining == 0,
        latencyMs: latencyMs,
        attemptsUsed: (_attemptsAllowed - _attemptsRemaining).clamp(1, 99),
      );
    }
    setState(() => _isAnswered = true);
  }

  bool _isCorrect(ExamSessionItem item) {
    final exercise = item.item;
    if (exercise.exerciseType == 'reading_micro') {
      final question = exercise.questions[_readingQuestionIndex];
      return _selectedIndex == question.answerIndex;
    }
    if (exercise.exerciseType == 'order_sentence') {
      return _orderChunks.join('|') == _orderAnswer.join('|');
    }
    if (exercise.exerciseType == 'meaning_match') {
      return _matchReady && _matchCorrect;
    }
    if (exercise.exerciseType == 'audio_match') {
      return _matchReady && _matchCorrect;
    }
    return _selectedIndex == exercise.answerIndex;
  }

  void _next() {
    final item = _currentItem;
    if (item == null) return;
    final context = _analyticsContextForItem(item.item);
    if (context != null) {
      ExerciseAnalytics.continued(context);
    }

    if (item.item.exerciseType == 'reading_micro') {
      final questions = item.item.questions;
      if (_readingQuestionIndex < questions.length - 1) {
        setState(() {
          _readingQuestionIndex += 1;
          _selectedIndex = null;
          _isAnswered = false;
          _attemptsRemaining = _attemptsAllowed;
        });
        _analyticsLastShownKey = null;
        _trackExerciseShownIfNeeded(source: 'reading_step');
        return;
      }
    }

    setState(() {
      _currentIndex += 1;
      _ensureAvailableItem();
      _resetItemState();
    });
    _analyticsLastShownKey = null;
    if (_currentItem == null) {
      _markSessionCompleted();
      return;
    }
    _trackExerciseShownIfNeeded(source: 'next');
  }

  void _tryAgain() {
    final item = _currentItem;
    final context = item == null ? null : _analyticsContextForItem(item.item);
    if (context != null) {
      ExerciseAnalytics.tryAgain(context);
    }
    setState(() {
      _selectedIndex = null;
      _isAnswered = false;
    });
  }

  void _resetItemState() {
    _selectedIndex = null;
    _isAnswered = false;
    _readingQuestionIndex = 0;
    _orderChunks = [];
    _orderAnswer = [];
    _matchReady = false;
    _matchCorrect = false;
    _resetSpeakingState();
    _itemStartTime = DateTime.now();
    final item = _currentItem;
    final allowed = item?.item.attemptsAllowed ?? 3;
    final capped = allowed > 2 ? 2 : allowed;
    _attemptsAllowed = capped < 1 ? 1 : capped;
    _attemptsRemaining = _attemptsAllowed;
    _setupItemTimer();
    if (item != null && _isSpeaking(item.item)) {
      _refreshSpeakingPermission();
    }
  }

  void _setupItemTimer() {
    _itemTimer?.cancel();
    final item = _currentItem;
    final timeLimitMs = item?.item.timeLimitMs;
    final timedSec = timeLimitMs != null
        ? (timeLimitMs / 1000).ceil()
        : item?.item.constraints.timedSec;
    if (timedSec == null || timedSec <= 0) {
      _itemRemainingSec = null;
      return;
    }
    _itemRemainingSec = timedSec;
    _itemTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _itemRemainingSec == null) return;
      if (_itemRemainingSec! <= 1) {
        timer.cancel();
        setState(() => _itemRemainingSec = 0);
        return;
      }
      setState(() => _itemRemainingSec = _itemRemainingSec! - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(body: Center(child: Text('Error: $_error')));
    }
    if (_plan == null) {
      return const ExerciseLoadingSkeleton();
    }

    final item = _currentItem;
    if (item == null) {
      _markSessionCompleted();
      return _buildSummary();
    }

    _trackExerciseShownIfNeeded(source: 'build');
    if (!_isItemValid(item.item)) {
      return ExerciseShell(
        index: _currentIndex,
        total: _plan?.items.length ?? 0,
        sectionLabel: item.section,
        skillLabel: _labelForSkill(item.item.skill),
        skillIcon: _iconForSkill(item.item.skill),
        instruction: 'This exercise cannot load',
        subInstruction: 'The item is missing required fields.',
        levelLabel: 'L${item.item.level}',
        attemptsRemaining: _attemptsRemaining,
        attemptsTotal: _attemptsAllowed,
        isAnswered: false,
        isCorrect: false,
        isReady: true,
        explainLabel: 'Explain',
        onExplain: item.item.why == null
            ? null
            : () => ExplainButton.showExplain(context, item.item.why!),
        showSecondaryToggle: false,
        showSettingsMenu: true,
        primaryLabelOverride: 'Skip',
        onPrimaryOverride: () => _skipCurrentItem('content_unavailable'),
        content: const ExerciseUnavailableCard(
          message: 'This item is missing required content. It will be skipped.',
        ),
        onCheck: _checkAnswer,
        onContinue: _next,
        onTryAgain: _tryAgain,
      );
    }

    final timerTotal = item.item.timeLimitMs != null
        ? (item.item.timeLimitMs! / 1000).ceil()
        : item.item.constraints.timedSec;
    final isSpeakingItem = _isSpeaking(item.item);
    return ExerciseShell(
      index: _currentIndex,
      total: _plan?.items.length ?? 0,
      sectionLabel: item.section,
      skillLabel: _labelForSkill(item.item.skill),
      skillIcon: _iconForSkill(item.item.skill),
      instruction: _instructionFor(item.item),
      subInstruction: _subInstructionFor(item.item),
      levelLabel: 'L${item.item.level}',
      attemptsRemaining: _attemptsRemaining,
      attemptsTotal: _attemptsAllowed,
      isAnswered: isSpeakingItem ? false : _isAnswered,
      isCorrect: isSpeakingItem ? false : _isCorrect(item),
      isReady: isSpeakingItem
          ? (_speakingRating != null)
          : ((item.item.exerciseType == 'meaning_match' ||
                    item.item.exerciseType == 'audio_match')
                ? _matchReady
                : _selectedIndex != null ||
                      item.item.exerciseType == 'order_sentence'),
      hideFooter: isSpeakingItem,
      // Keep options docked just above footer CTA across exercise types.
      bodyScrollable: false,
      timerRemainingSec: _itemRemainingSec,
      timerTotalSec: timerTotal,
      explainLabel: 'Explain',
      onExplain: item.item.why == null
          ? null
          : () => ExplainButton.showExplain(context, item.item.why!),
      showSecondaryToggle: false,
      showSettingsMenu: true,
      mediaSlot: _buildMediaSlot(item.item),
      hintBuilder: () => 'Review the prompt and try again.',
      revealBuilder: () => _buildReveal(item.item),
      onCheck: _checkAnswer,
      onContinue: _next,
      onTryAgain: _tryAgain,
      content: _buildExercise(item),
    );
  }

  Widget _buildExercise(ExamSessionItem item) {
    final ex = item.item;
    switch (ex.exerciseType) {
      case 'meaning_select':
        return MeaningSelectExercise(
          hanzi: ex.prompt.hanzi ?? '',
          pinyin: ex.prompt.pinyin,
          choices: ex.choices,
          answerIndex: ex.answerIndex,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          showPinyin: false,
          onTogglePinyin: () {},
          onSelect: _onSelectIndex,
        );
      case 'character_select':
        return CharacterSelectExercise(
          meaning: ex.prompt.meaning ?? '',
          pinyin: ex.prompt.pinyin,
          choices: ex.choices,
          answerIndex: ex.answerIndex,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          showPinyin: false,
          onTogglePinyin: () {},
          onSelect: _onSelectIndex,
        );
      case 'audio_select':
        return AudioSelectExercise(
          audioUrl: _resolveAudioUrl(ex.audioUrl),
          choiceType: ex.choiceType ?? 'hanzi',
          choices: ex.choices,
          answerIndex: ex.answerIndex,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          onSelect: _onSelectIndex,
          showPrompt: false,
        );
      case 'dictation_select':
        return DictationSelectExercise(
          audioUrl: _resolveAudioUrl(ex.audioUrl),
          promptText: ex.promptText ?? 'Listen and choose the correct sentence',
          options: ex.options.isNotEmpty
              ? ex.options.map((o) => o.text).toList()
              : ex.choices,
          answerIndex: ex.answerIndex,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          onSelect: _onSelectIndex,
          showPrompt: false,
        );
      case 'cloze_select':
        final sentence =
            ex.payload['sentence']?.toString() ??
            ex.payload['text']?.toString() ??
            ex.payload['stem']?.toString() ??
            ex.payload['prompt']?.toString() ??
            '';
        final contextPassage =
            ex.payload['context_passage']?.toString() ??
            ex.payload['passage_context']?.toString() ??
            ex.payload['context']?.toString() ??
            ex.payload['paragraph']?.toString();
        final maxContextWordsRaw = ex.payload['max_context_words'];
        final maxContextWords = maxContextWordsRaw is int
            ? (maxContextWordsRaw > 0 ? maxContextWordsRaw : null)
            : (maxContextWordsRaw is String
                  ? int.tryParse(maxContextWordsRaw.trim())
                  : null);
        final phraseModeValue =
            ex.payload['blank_mode']?.toString().toLowerCase() ??
            ex.payload['choice_mode']?.toString().toLowerCase() ??
            ex.payload['variant']?.toString().toLowerCase() ??
            ex.payload['response_mode']?.toString().toLowerCase();
        final phraseMode =
            phraseModeValue == 'phrase' ||
            phraseModeValue == 'phrase_select' ||
            phraseModeValue == 'clause' ||
            phraseModeValue == 'fragment';
        return ClozeSelectExercise(
          sentence: sentence,
          contextPassage: contextPassage,
          contextMaxWords: maxContextWords != null && maxContextWords > 0
              ? maxContextWords
              : null,
          phraseMode: phraseMode,
          choices: ex.choices,
          answerIndex: ex.answerIndex,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          onSelect: _onSelectIndex,
        );
      case 'order_sentence':
        final chunks = (ex.payload['chunks'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        final answer = (ex.payload['answer'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        if (_orderAnswer.isEmpty) {
          _orderAnswer = List<String>.from(answer);
        }
        return OrderSentenceExercise(
          chunks: chunks,
          onChanged: _onOrderChanged,
        );
      case 'meaning_match':
        final left = (ex.payload['left'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        final right = (ex.payload['right'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        final mapping = (ex.payload['mapping'] as List<dynamic>? ?? [])
            .map((e) => e as int)
            .toList();
        return MeaningMatchExercise(
          leftItems: left,
          rightItems: right,
          mapping: mapping,
          onStatus: _onMatchStatus,
        );
      case 'audio_match':
        final right = (ex.payload['right'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        final left = (ex.payload['left'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        final leftAudio =
            (ex.payload['left_audio_urls'] as List<dynamic>? ??
                    ex.payload['audio_urls'] as List<dynamic>? ??
                    const [])
                .map((e) => e.toString())
                .toList();
        final mapping = (ex.payload['mapping'] as List<dynamic>? ?? [])
            .map((e) => e as int)
            .toList();
        final fallbackLeft = List<String>.generate(
          right.length,
          (i) => 'Audio ${i + 1}',
          growable: false,
        );
        return AudioMeaningMatchExercise(
          leftItems: left.isNotEmpty ? left : fallbackLeft,
          leftAudioUrls: leftAudio,
          rightItems: right,
          mapping: mapping,
          onStatus: _onMatchStatus,
        );
      case 'reading_micro':
        final reading = ex.reading;
        if (reading == null) {
          return const Center(child: Text('Reading content missing'));
        }
        return ReadingMicroExercise(
          titleZh: reading.titleZh,
          titleEn: reading.titleEn,
          storyZh: reading.storyZh,
          storyEn: reading.storyEn,
          questionIndex: _readingQuestionIndex,
          questions: ex.questions
              .map(
                (q) => {
                  'type': q.type,
                  'prompt': q.prompt,
                  'choices': q.choices,
                  'answer_index': q.answerIndex,
                },
              )
              .toList(),
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          onSelect: _onSelectIndex,
        );
      case 'speak_read_aloud':
        final samples = (ex.payload['sample_answers'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        return SpeakReadAloudExercise(
          hanzi: ex.prompt.hanzi ?? '',
          pinyin: ex.prompt.pinyin,
          meaning: ex.prompt.meaning,
          sampleAnswers: samples,
          permissionGranted: _speakingPermissionGranted,
          isRecording: _speakingIsRecording,
          durationMs: _speakingRecording?.durationMs,
          rating: _speakingRating,
          transcript: _speakingRecording?.transcript,
          score: _speakingScore,
          onRequestPermission: () {
            _trackInteractionIfNeeded('speaking_permission');
            _requestSpeakingPermission();
          },
          onStartRecording: () {
            _trackInteractionIfNeeded('speaking_start');
            _startSpeakingRecording();
          },
          onStopRecording: () {
            _trackInteractionIfNeeded('speaking_stop');
            _stopSpeakingRecording();
          },
          onRate: (rating) {
            _trackInteractionIfNeeded('speaking_rate');
            _setSpeakingRating(rating);
          },
        );
      case 'speak_prompted_reply':
        final samples = (ex.payload['sample_answers'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        return SpeakPromptedReplyExercise(
          promptText: ex.promptText ?? 'Respond aloud',
          meaning: ex.prompt.meaning,
          sampleAnswers: samples,
          permissionGranted: _speakingPermissionGranted,
          isRecording: _speakingIsRecording,
          durationMs: _speakingRecording?.durationMs,
          rating: _speakingRating,
          transcript: _speakingRecording?.transcript,
          score: _speakingScore,
          onRequestPermission: () {
            _trackInteractionIfNeeded('speaking_permission');
            _requestSpeakingPermission();
          },
          onStartRecording: () {
            _trackInteractionIfNeeded('speaking_start');
            _startSpeakingRecording();
          },
          onStopRecording: () {
            _trackInteractionIfNeeded('speaking_stop');
            _stopSpeakingRecording();
          },
          onRate: (rating) {
            _trackInteractionIfNeeded('speaking_rate');
            _setSpeakingRating(rating);
          },
        );
      case 'pinyin_select':
        return PinyinSelectExercise(
          hanzi: ex.prompt.hanzi ?? '',
          choices: ex.choices,
          answerIndex: ex.answerIndex,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          onSelect: _onSelectIndex,
        );
      case 'reply_select':
        return ReplySelectExercise(
          prompt: ex.promptText ?? (ex.prompt.hanzi ?? ''),
          choices: ex.choices,
          answerIndex: ex.answerIndex,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          onSelect: _onSelectIndex,
        );
      default:
        return Center(child: Text('Unsupported ${ex.exerciseType}'));
    }
  }

  void _onSelectIndex(int index) {
    _trackInteractionIfNeeded('select_index');
    setState(() => _selectedIndex = index);
  }

  void _onOrderChanged(List<String> updated) {
    _trackInteractionIfNeeded('order_changed');
    setState(() => _orderChunks = updated);
  }

  void _onMatchStatus(bool ready, bool correct) {
    _trackInteractionIfNeeded('match_status');
    setState(() {
      _matchReady = ready;
      _matchCorrect = correct;
    });
  }

  String _buildHint(PilotExerciseItem item) {
    final correct = _correctAnswerText(item);
    if (correct.isEmpty) return 'Focus on key characters.';
    if (correct.length <= 2) {
      return "Starts with '${correct[0]}'";
    }
    return 'Answer length: ${correct.length}';
  }

  String _buildReveal(PilotExerciseItem item) {
    final correct = _correctAnswerText(item);
    if (correct.isEmpty) return 'Correct answer shown above.';
    return 'Correct: $correct';
  }

  String _correctAnswerText(PilotExerciseItem item) {
    if (item.exerciseType == 'order_sentence') {
      final answer = (item.payload['answer'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      return answer.join('');
    }
    if (item.exerciseType == 'meaning_match') {
      final left = (item.payload['left'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      final right = (item.payload['right'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      if (left.isEmpty || right.isEmpty) return '';
      return '${left.first} → ${right.first}';
    }
    if (item.exerciseType == 'audio_match') {
      final right = (item.payload['right'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      if (right.isEmpty) return '';
      return 'Audio 1 → ${right.first}';
    }
    if (item.answerIndex >= 0 && item.answerIndex < item.choices.length) {
      return item.choices[item.answerIndex];
    }
    return '';
  }

  Widget? _buildMediaSlot(PilotExerciseItem item) {
    final imageUrl = _resolveImageUrl(item.payload['image_url']?.toString());
    final normalizedType = PracticeExerciseEngine.normalizeType(
      item.exerciseType,
    );
    final audioUrl =
        item.exerciseType == 'audio_select' ||
            item.exerciseType == 'dictation_select'
        ? _resolveAudioUrl(item.audioUrl)
        : null;
    final showImage = imageUrl != null && imageUrl.isNotEmpty;
    final showAudio =
        audioUrl != null &&
        audioUrl.isNotEmpty &&
        normalizedType != 'audio_select' &&
        normalizedType != 'dictation_select' &&
        normalizedType != 'listen_write';
    final isSpeaking =
        item.exerciseType == 'speak_read_aloud' ||
        item.exerciseType == 'speak_prompted_reply';
    if (isSpeaking) return null;
    if (!showImage && !showAudio) return null;
    return ExerciseMediaSlot(
      imageUrl: imageUrl,
      audioUrl: audioUrl,
      showImagePlaceholder: false,
      showAudio: showAudio,
      enableAudio: false,
    );
  }

  Widget _buildSummary() {
    _markSessionCompleted();
    final pack = _pack;
    return ExamReportScreen(
      attempts: _attempts,
      sessionDuration: _plan?.duration ?? const Duration(minutes: 18),
      seed: widget.seed,
      packOverride: pack,
      masterySnapshot: _mastery?.snapshot(),
    );
  }

  void _skipCurrentItem(String reason) {
    final item = _currentItem;
    if (item == null) return;
    final context = _analyticsContextForItem(item.item);
    if (context != null) {
      ExerciseAnalytics.skipped(context, reason: reason);
    }
    _skippedCount += 1;
    _attempts.add(
      ExamAttempt(
        item: item.item,
        isCorrect: false,
        latencyMs: 0,
        timedOverrun: false,
        skipped: true,
        skippedReason: reason,
      ),
    );
    setState(() {
      _currentIndex += 1;
      _ensureAvailableItem();
      _resetItemState();
    });
    _analyticsLastShownKey = null;
    if (_currentItem == null) {
      _markSessionCompleted();
      return;
    }
    _trackExerciseShownIfNeeded(source: 'skip');
  }

  bool _isItemValid(PilotExerciseItem item) {
    if (!PracticeExerciseEngine.isSessionEnabledType(item.exerciseType)) {
      return false;
    }
    if (item.exerciseType == 'reading_micro') {
      return item.reading != null && item.questions.isNotEmpty;
    }
    if (item.exerciseType == 'order_sentence') {
      final chunks = item.payload['chunks'] as List<dynamic>?;
      return chunks != null && chunks.isNotEmpty;
    }
    if (item.exerciseType == 'meaning_match') {
      final left = item.payload['left'] as List<dynamic>?;
      final right = item.payload['right'] as List<dynamic>?;
      return left != null &&
          right != null &&
          left.isNotEmpty &&
          right.isNotEmpty;
    }
    if (item.exerciseType == 'audio_match') {
      final right = item.payload['right'] as List<dynamic>?;
      if (right == null || right.isEmpty) return false;
      final left = item.payload['left'] as List<dynamic>?;
      if (left != null && left.isNotEmpty) return true;
      final audioUrls =
          item.payload['left_audio_urls'] as List<dynamic>? ??
          item.payload['audio_urls'] as List<dynamic>?;
      return audioUrls != null && audioUrls.isNotEmpty;
    }
    if (_isSpeaking(item)) {
      final samples = item.payload['sample_answers'] as List<dynamic>?;
      if (samples == null || samples.isEmpty) return false;
      if (item.exerciseType == 'speak_prompted_reply') {
        return (item.promptText ?? '').isNotEmpty;
      }
      return true;
    }
    return item.choices.isNotEmpty;
  }

  String _labelForSkill(String skill) {
    switch (skill) {
      case 'listening':
        return 'Listening';
      case 'reading':
        return 'Reading';
      case 'grammar':
        return 'Grammar';
      case 'speaking':
        return 'Speaking';
      default:
        return 'Vocab';
    }
  }

  IconData _iconForSkill(String skill) {
    switch (skill) {
      case 'listening':
        return Icons.headphones_rounded;
      case 'reading':
        return Icons.menu_book_rounded;
      case 'grammar':
        return Icons.auto_awesome_mosaic_outlined;
      case 'speaking':
        return Icons.mic_rounded;
      default:
        return Icons.translate_rounded;
    }
  }

  String _instructionFor(PilotExerciseItem item) {
    switch (item.exerciseType) {
      case 'meaning_select':
        return 'Choose the meaning';
      case 'character_select':
        return 'Choose the characters';
      case 'pinyin_select':
        return 'Choose the correct pinyin';
      case 'reply_select':
        return 'Choose the best reply';
      case 'audio_select':
        return item.choiceType == 'meaning'
            ? 'Choose the meaning'
            : 'Choose the characters';
      case 'dictation_select':
        return item.promptText ?? 'Listen and choose the correct sentence';
      case 'cloze_select':
        return 'Complete the sentence';
      case 'order_sentence':
        return 'Order the sentence';
      case 'meaning_match':
        return 'Match the pairs';
      case 'audio_match':
        return 'Match audio to words';
      case 'reading_micro':
        return 'Read the passage and answer';
      case 'speak_read_aloud':
        return 'Read aloud';
      case 'speak_prompted_reply':
        return 'Respond aloud';
      default:
        return 'Answer the question';
    }
  }

  String? _subInstructionFor(PilotExerciseItem item) {
    if (item.exerciseType == 'reading_micro') {
      return 'Two short questions follow.';
    }
    return null;
  }

  String? _resolveImageUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.trim().isEmpty) return null;
    final normalized = imageUrl.trim();
    if (normalized.startsWith('http') || normalized.startsWith('assets/')) {
      return normalized;
    }
    if (normalized.startsWith('/')) {
      return '${AppConfig.apiBaseUrl}$normalized';
    }
    return normalized;
  }

  String? _resolveAudioUrl(String? audioUrl) {
    if (audioUrl == null || audioUrl.trim().isEmpty) return null;
    final normalized = audioUrl.trim();
    if (normalized.startsWith('http')) return normalized;
    if (normalized.startsWith('/')) {
      return '${AppConfig.apiBaseUrl}$normalized';
    }
    return normalized;
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  bool _isSpeaking(PilotExerciseItem item) {
    return item.exerciseType == 'speak_read_aloud' ||
        item.exerciseType == 'speak_prompted_reply' ||
        item.exerciseType == 'speaking';
  }

  void _beginAnalyticsSession({required int totalExercises}) {
    _analyticsSessionId = ExerciseAnalytics.newSessionId(ExerciseRunner.exam);
    _analyticsStartedAt = DateTime.now();
    _analyticsSessionActive = totalExercises > 0;
    _analyticsSessionFinalized = false;
    _analyticsLastShownKey = null;
    _analyticsInteractedKeys.clear();
    if (!_analyticsSessionActive) return;
    ExerciseAnalytics.sessionStarted(
      sessionId: _analyticsSessionId,
      runner: ExerciseRunner.exam,
      totalExercises: totalExercises,
      seed: widget.seed,
    );
  }

  String? _analyticsCurrentExerciseKey() {
    final item = _currentItem?.item;
    if (item == null) return null;
    final step = item.exerciseType == 'reading_micro'
        ? _readingQuestionIndex
        : 0;
    return '${item.id}:$_currentIndex:$step';
  }

  ExerciseAnalyticsContext? _analyticsContextForCurrent() {
    final item = _currentItem?.item;
    if (item == null) return null;
    return _analyticsContextForItem(item);
  }

  ExerciseAnalyticsContext? _analyticsContextForItem(
    PilotExerciseItem item, {
    int? attemptsRemaining,
    int? attemptsAllowed,
  }) {
    final plan = _plan;
    if (plan == null || plan.items.isEmpty) return null;
    final step = item.exerciseType == 'reading_micro'
        ? _readingQuestionIndex + 1
        : null;
    return ExerciseAnalyticsContext(
      sessionId: _analyticsSessionId,
      runner: ExerciseRunner.exam,
      exerciseId: item.id,
      exerciseType: item.exerciseType,
      skill: item.skill,
      index: _currentIndex + 1,
      total: plan.items.length,
      attemptsRemaining: attemptsRemaining ?? _attemptsRemaining,
      attemptsAllowed: attemptsAllowed ?? _attemptsAllowed,
      subStepIndex: step,
    );
  }

  void _trackExerciseShownIfNeeded({required String source}) {
    if (!_analyticsSessionActive) return;
    final key = _analyticsCurrentExerciseKey();
    if (key == null || key == _analyticsLastShownKey) return;
    final context = _analyticsContextForCurrent();
    if (context == null) return;
    _analyticsLastShownKey = key;
    ExerciseAnalytics.exerciseShown(context, source: source);
  }

  void _trackInteractionIfNeeded(String interaction) {
    if (!_analyticsSessionActive) return;
    final key = _analyticsCurrentExerciseKey();
    if (key == null || _analyticsInteractedKeys.contains(key)) return;
    final context = _analyticsContextForCurrent();
    if (context == null) return;
    _analyticsInteractedKeys.add(key);
    ExerciseAnalytics.interacted(context, interaction: interaction);
  }

  void _markSessionCompleted() {
    if (!_analyticsSessionActive || _analyticsSessionFinalized) return;
    _analyticsSessionFinalized = true;
    final total = _plan?.items.length ?? 0;
    final completed = _attempts.length;
    final correct = _attempts.where((a) => a.isCorrect).length;
    final durationMs = _analyticsStartedAt == null
        ? null
        : DateTime.now().difference(_analyticsStartedAt!).inMilliseconds;
    ExerciseAnalytics.sessionCompleted(
      sessionId: _analyticsSessionId,
      runner: ExerciseRunner.exam,
      totalExercises: total,
      completedExercises: completed,
      correctExercises: correct,
      durationMs: durationMs,
    );
  }

  void _trackSessionQuitIfNeeded() {
    if (!_analyticsSessionActive || _analyticsSessionFinalized) return;
    _analyticsSessionFinalized = true;
    final durationMs = _analyticsStartedAt == null
        ? null
        : DateTime.now().difference(_analyticsStartedAt!).inMilliseconds;
    ExerciseAnalytics.sessionQuit(
      sessionId: _analyticsSessionId,
      runner: ExerciseRunner.exam,
      totalExercises: _plan?.items.length ?? 0,
      completedExercises: _attempts.length,
      durationMs: durationMs,
    );
  }

  void _resetSpeakingState() {
    _speakingIsRecording = false;
    _speakingRecording = null;
    _speakingRating = null;
    _speakingScore = null;
    _speakingSubmitInFlight = false;
  }

  Future<void> _refreshSpeakingPermission() async {
    final permission = await _speakingRecorder.checkPermission();
    if (!mounted) return;
    setState(() {
      _speakingPermissionGranted = permission == SpeakingPermission.granted;
    });
  }

  Future<void> _requestSpeakingPermission() async {
    final permission = await _speakingRecorder.requestPermission();
    if (!mounted) return;
    setState(() {
      _speakingPermissionGranted = permission == SpeakingPermission.granted;
    });
  }

  Future<void> _startSpeakingRecording() async {
    if (_speakingIsRecording) return;
    if (!mounted) return;
    setState(() {
      _speakingIsRecording = true;
      _speakingRecording = null;
      _speakingRating = null;
      _speakingScore = null;
    });
    try {
      await _speakingRecorder.start();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _speakingIsRecording = false;
        _speakingPermissionGranted = false;
      });
    }
  }

  Future<void> _stopSpeakingRecording() async {
    final recording = await _speakingRecorder.stop();
    if (!mounted) return;
    final item = _currentItem?.item;
    final expected = _expectedSpeakingAnswers(item);
    final evaluation = SpeakingEvaluator.evaluate(
      transcript: recording.transcript,
      expectedAnswers: expected,
      durationMs: recording.durationMs,
    );
    setState(() {
      _speakingIsRecording = false;
      _speakingRecording = recording;
      _speakingRating = evaluation.rating;
      _speakingScore = evaluation.score;
    });
    _completeSpeaking();
  }

  void _setSpeakingRating(SpeakingRating rating) {
    setState(() => _speakingRating = rating);
    if (_speakingIsRecording) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _completeSpeaking();
    });
  }

  List<String> _expectedSpeakingAnswers(PilotExerciseItem? item) {
    if (item == null) return const [];
    final out = <String>{};
    for (final a in (item.payload['sample_answers'] as List<dynamic>? ?? [])) {
      final value = a.toString().trim();
      if (value.isNotEmpty) out.add(value);
    }
    final hanzi = item.prompt.hanzi?.trim() ?? '';
    final pinyin = item.prompt.pinyin?.trim() ?? '';
    if (hanzi.isNotEmpty) out.add(hanzi);
    if (pinyin.isNotEmpty) out.add(pinyin);
    final answerRaw = item.payload['answer'];
    if (answerRaw is String && answerRaw.trim().isNotEmpty) {
      out.add(answerRaw.trim());
    }
    return out.toList();
  }

  void _completeSpeaking() {
    final item = _currentItem;
    final rating = _speakingRating;
    if (item == null || rating == null || _speakingSubmitInFlight) return;
    _speakingSubmitInFlight = true;
    try {
      final recording = _speakingRecording;
      final durationMs = recording?.durationMs ?? 0;
      final isCorrect = rating != SpeakingRating.needsWork;
      final context = _analyticsContextForItem(item.item);
      if (context != null) {
        ExerciseAnalytics.result(
          context,
          isCorrect: isCorrect,
          finalized: true,
          latencyMs: durationMs,
          attemptsUsed: 1,
        );
      }
      _speakingNotebook?.addEntry(
        SpeakingEntry(
          conceptId: item.item.conceptId,
          exerciseType: item.item.exerciseType,
          rating: speakingRatingLabel(rating),
          durationMs: durationMs,
          recordingPath: recording?.path,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          promptText: item.item.promptText,
          sampleAnswers:
              (item.item.payload['sample_answers'] as List<dynamic>? ?? [])
                  .map((e) => e.toString())
                  .toList(),
        ),
      );
      _speakingNotebook?.save();
      _performance?.recordAttempt(
        skill: item.item.skill,
        level: item.item.level,
        isCorrect: isCorrect,
        latencyMs: durationMs,
      );
      _performance?.save();
      _mastery?.recordAttempt(
        conceptId: item.item.conceptId,
        skillBucket: LocalMasteryTracker.skillBucketForExercise(
          item.item.exerciseType,
        ),
        isCorrect: isCorrect,
        isExamMode: true,
        isTimed: false,
      );
      _mastery?.save();
      _attempts.add(
        ExamAttempt(
          item: item.item,
          isCorrect: isCorrect,
          latencyMs: durationMs,
          timedOverrun: false,
        ),
      );
      _next();
    } finally {
      _speakingSubmitInFlight = false;
    }
  }
}
