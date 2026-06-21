import 'dart:math';
import 'package:flutter/material.dart';
import 'package:dragon_chinese/features/course/engine/practice_exercise_engine.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/services/pilot_exercise_pack_loader.dart';
import 'package:dragon_chinese/features/course/services/practice_scheduler.dart';
import 'package:dragon_chinese/features/course/services/practice_state_store.dart';
import 'package:dragon_chinese/features/course/services/practice_models.dart';
import 'package:dragon_chinese/features/course/services/goal_profile.dart';
import 'package:dragon_chinese/features/course/services/goal_profile_store.dart';
import 'package:dragon_chinese/features/course/services/context_template_resolver.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/exercise_shell.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/speaking_exercise.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/explain_panel.dart';
import 'package:dragon_chinese/features/course/screens/practice_summary_screen.dart';
import 'package:dragon_chinese/features/course/services/speaking_evaluator.dart';
import 'package:dragon_chinese/features/course/services/speaking_recorder.dart';
import 'package:dragon_chinese/features/course/services/speaking_notebook.dart';
import 'package:dragon_chinese/features/course/services/mastery_store.dart';
import 'package:dragon_chinese/features/course/services/mastery_updater.dart';
import 'package:dragon_chinese/features/course/services/exercise_analytics.dart';
import 'package:dragon_chinese/core/utils/app_log.dart';

class PracticeSessionScreen extends StatefulWidget {
  static const String routeName = '/practice';
  final String seed;
  final String? dateBucket;
  final PilotExercisePack? packOverride;
  final PracticeStateStore? stateOverride;
  final PracticeSessionPlan? planOverride;

  const PracticeSessionScreen({
    super.key,
    this.seed = 'practice-v1',
    this.dateBucket,
    this.packOverride,
    this.stateOverride,
    this.planOverride,
  });

  @override
  State<PracticeSessionScreen> createState() => _PracticeSessionScreenState();
}

class _PracticeSessionScreenState extends State<PracticeSessionScreen> {
  final _loader = PilotExercisePackLoader();
  final _scheduler = PracticeSessionBuilder();
  final SpeakingRecorder _speakingRecorder = SpeakingRecorderService.instance;
  GoalProfile _goalProfile = GoalProfiles.defaultProfile;
  late ContextTemplateResolver _contextResolver;
  PilotExercisePack? _pack;
  PracticeStateStore? _store;
  SpeakingNotebook? _speakingNotebook;
  MasteryStore? _masteryStore;
  PracticeSessionPlan? _plan;
  String? _error;
  int _currentIndex = 0;
  int? _selectedIndex;
  String _textAnswer = '';
  bool _isAnswered = false;
  bool _showPinyin = false;
  int _readingQuestionIndex = 0;
  List<String> _orderChunks = [];
  List<String> _orderAnswer = [];
  bool _matchReady = false;
  bool _matchCorrect = false;
  int _attemptsRemaining = 0;
  int _attemptsAllowed = 3; // Default 3
  int _attemptsUsed = 0;
  final List<AttemptEvent> _attempts = [];
  bool _speakingPermissionGranted = true;
  bool _speakingIsRecording = false;
  SpeakingRecording? _speakingRecording;
  SpeakingRating? _speakingRating;
  double? _speakingScore;
  bool _speakingSubmitInFlight = false;
  String _analyticsSessionId = ExerciseAnalytics.newSessionId(
    ExerciseRunner.practice,
  );
  String? _analyticsLastShownKey;
  final Set<String> _analyticsInteractedKeys = <String>{};
  bool _analyticsSessionActive = false;
  bool _analyticsSessionFinalized = false;
  DateTime? _analyticsStartedAt;

  @override
  void initState() {
    super.initState();
    _contextResolver = ContextTemplateResolver(_goalProfile);
    _analyticsStartedAt = DateTime.now();
    _load();
  }

  @override
  void dispose() {
    _trackSessionQuitIfNeeded();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final pack = widget.packOverride ?? await _loader.loadPack();
      final store = widget.stateOverride ?? await PracticeStateStore.load();
      final speakingNotebook = await SpeakingNotebook.load();
      final masteryStore = await MasteryStore.load();
      final goalProfile = await GoalProfileStore.loadProfile();
      final dateBucket = widget.dateBucket ?? _todayBucket();
      final plan =
          widget.planOverride ??
          _scheduler.buildPlan(
            pack: pack,
            state: store,
            seed: widget.seed,
            dateBucket: dateBucket,
            goalProfile: goalProfile,
          );
      if (mounted) {
        setState(() {
          _pack = pack;
          _store = store;
          _plan = plan;
          _speakingNotebook = speakingNotebook;
          _masteryStore = masteryStore;
          _goalProfile = goalProfile;
          _contextResolver = ContextTemplateResolver(goalProfile);
        });
        _beginAnalyticsSession(totalExercises: plan.items.length);
        _resetItemState();
        _trackExerciseShownIfNeeded(source: 'session_start');
      }
    } catch (e, st) {
      AppLog.e('Failed to load practice session', error: e, stackTrace: st);
      if (mounted) setState(() => _error = e.toString());
    }
  }

  PracticeSessionItem? get _currentPlanItem {
    final plan = _plan;
    if (plan == null) return null;
    if (_currentIndex >= plan.items.length) return null;
    return plan.items[_currentIndex];
  }

  PilotExerciseItem? get _currentItem {
    final planItem = _currentPlanItem;
    if (planItem == null) return null;
    final pack = _pack;
    if (pack == null) return null;
    return pack.items.firstWhere(
      (item) => item.id == planItem.id,
      orElse: () => pack.items.first,
    );
  }

  void _resetItemState() {
    _selectedIndex = null;
    _textAnswer = '';
    _isAnswered = false;
    _showPinyin = false;
    _readingQuestionIndex = 0;
    _orderChunks = [];
    _orderAnswer = [];
    _matchReady = false;
    _matchCorrect = false;
    _attemptsUsed = 0;

    // Always 3 attempts for standard exercises
    _attemptsAllowed = 3;
    _attemptsRemaining = 3;

    _resetSpeakingState();
    final item = _currentItem;
    if (item != null && _isSpeaking(item)) {
      _refreshSpeakingPermission();
    }
  }

  void _checkAnswer() {
    final item = _currentItem;
    if (item == null) return;
    final analyticsContext = _analyticsContextForItem(item);
    if (analyticsContext != null) {
      ExerciseAnalytics.checkTapped(analyticsContext);
    }

    final correct = _isCorrect(item);
    _attemptsUsed += 1;
    final nextRemaining = correct
        ? _attemptsRemaining
        : (_attemptsRemaining > 0 ? _attemptsRemaining - 1 : 0);
    final isFinalized = correct || nextRemaining == 0;
    final resultContext = _analyticsContextForItem(
      item,
      attemptsRemaining: nextRemaining,
    );
    if (resultContext != null) {
      ExerciseAnalytics.result(
        resultContext,
        isCorrect: correct,
        finalized: isFinalized,
        attemptsUsed: max(1, _attemptsUsed),
      );
    }

    // Logic: if correct, we are done. If incorrect, deduct attempt.
    if (correct) {
      setState(
        () => _isAnswered = true,
      ); // Shows feedback (Correct) -> Continue
    } else {
      if (_attemptsRemaining > 0) {
        setState(() {
          _attemptsRemaining -= 1;
          _isAnswered = true; // Shows feedback (Incorrect/Try Again)
        });
      }
    }
  }

  void _tryAgain() {
    final context = _analyticsContextForCurrent();
    if (context != null) {
      ExerciseAnalytics.tryAgain(context);
    }
    // Reset selection for next attempt
    setState(() {
      _selectedIndex = null;
      _textAnswer = '';
      _isAnswered = false;
      // Do NOT reset attemptsRemaining here, it persists
    });
  }

  Future<void> _continue() async {
    final item = _currentItem;
    final context = item == null ? null : _analyticsContextForItem(item);
    if (context != null) {
      ExerciseAnalytics.continued(context);
    }
    if (item != null && !_isSpeaking(item)) {
      final correct = _isCorrect(item);
      _recordAttempt(item, correct);

      // Multi-step reading support
      if (item.exerciseType == 'reading_micro' &&
          _readingQuestionIndex < item.questions.length - 1) {
        setState(() {
          _readingQuestionIndex += 1;
          _selectedIndex = null;
          _textAnswer = '';
          _isAnswered = false;
          _attemptsUsed = 0;
          _attemptsAllowed = 3;
          _attemptsRemaining = 3;
        });
        _analyticsLastShownKey = null;
        _trackExerciseShownIfNeeded(source: 'reading_step');
        return;
      }
    }
    _advance();
  }

  void _advance() {
    setState(() {
      _currentIndex += 1;
    });
    if (_currentPlanItem == null) {
      _markSessionCompleted();
      return;
    }
    _analyticsLastShownKey = null;
    _resetItemState();
    _trackExerciseShownIfNeeded(source: 'advance');
  }

  void _recordAttempt(PilotExerciseItem item, bool isCorrect) {
    final planItem = _currentPlanItem;
    final skill = planItem?.skill ?? _skillForType(item.exerciseType);
    final masterySkill = _masterySkillFor(skill);
    final event = AttemptEvent(
      wordId: item.conceptId,
      exerciseType: item.exerciseType,
      skill: skill,
      isCorrect: isCorrect,
      attemptsUsed: max(1, _attemptsUsed),
      durationMs: 0,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      selfRating: null,
    );
    _attempts.add(event);
    _store?.applyAttempt(event);
    _store?.save();
    if (_masteryStore != null) {
      final now = event.timestamp;
      // Update generic production skill
      final prodCurrent = _masteryStore!.skillStateFor(
        item.conceptId,
        'production',
      );
      final prodUpdated = MasteryUpdater.applyAttempt(
        current: prodCurrent,
        skill: 'production',
        isCorrect: isCorrect,
        attemptsUsed: event.attemptsUsed,
        durationMs: event.durationMs,
        now: now,
      );
      _masteryStore!.updateSkill(item.conceptId, 'production', prodUpdated);

      // Update specific skill
      final skillCurrent = _masteryStore!.skillStateFor(
        item.conceptId,
        masterySkill,
      );
      final skillUpdated = MasteryUpdater.applyAttempt(
        current: skillCurrent,
        skill: masterySkill,
        isCorrect: isCorrect,
        attemptsUsed: event.attemptsUsed,
        durationMs: event.durationMs,
        now: now,
      );
      _masteryStore!.updateSkill(item.conceptId, masterySkill, skillUpdated);

      _masteryStore!.save();
    }
  }

  PracticeExerciseUiState get _exerciseUiState => PracticeExerciseUiState(
    selectedIndex: _selectedIndex,
    textAnswer: _textAnswer,
    isAnswered: _isAnswered,
    showPinyin: _showPinyin,
    readingQuestionIndex: _readingQuestionIndex,
    orderChunks: _orderChunks,
    orderAnswer: _orderAnswer,
    matchReady: _matchReady,
    matchCorrect: _matchCorrect,
    speakingPermissionGranted: _speakingPermissionGranted,
    speakingIsRecording: _speakingIsRecording,
    speakingRecording: _speakingRecording,
    speakingRating: _speakingRating,
    speakingScore: _speakingScore,
  );

  PracticeExerciseCallbacks get _exerciseCallbacks => PracticeExerciseCallbacks(
    onSelectIndex: (index) {
      _trackInteractionIfNeeded('select_index');
      setState(() => _selectedIndex = index);
    },
    onTextChanged: (value) {
      _trackInteractionIfNeeded('text_changed');
      setState(() => _textAnswer = value);
    },
    onTogglePinyin: () {
      _trackInteractionIfNeeded('toggle_pinyin');
      setState(() => _showPinyin = !_showPinyin);
    },
    onOrderChanged: (updated) {
      _trackInteractionIfNeeded('order_changed');
      setState(() {
        _orderChunks = updated;
        _textAnswer = '';
      });
    },
    onMatchStatus: (ready, correct) {
      _trackInteractionIfNeeded('match_status');
      setState(() {
        _matchReady = ready;
        _matchCorrect = correct;
      });
    },
    onRequestSpeakingPermission: () {
      _trackInteractionIfNeeded('speaking_permission');
      _requestSpeakingPermission();
    },
    onStartSpeakingRecording: () {
      _trackInteractionIfNeeded('speaking_start');
      _startSpeakingRecording();
    },
    onStopSpeakingRecording: () {
      _trackInteractionIfNeeded('speaking_stop');
      _stopSpeakingRecording();
    },
    onSetSpeakingRating: (rating) {
      _trackInteractionIfNeeded('speaking_rate');
      _setSpeakingRating(rating);
    },
  );

  bool _isCorrect(PilotExerciseItem item) {
    return PracticeExerciseEngine.isCorrect(
      item: item,
      state: _exerciseUiState,
    );
  }

  void _ensureOrderState(PilotExerciseItem item) {
    if (item.exerciseType != 'order_sentence') return;
    if (_orderAnswer.isNotEmpty) return;
    final answer = (item.payload['answer'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    _orderAnswer = List<String>.from(answer);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(body: Center(child: Text('Error: $_error')));
    }
    if (_plan == null || _pack == null) {
      return const ExerciseLoadingSkeleton();
    }

    final planItem = _currentPlanItem;
    final item = _currentItem;
    if (planItem == null || item == null) {
      _markSessionCompleted();
      return PracticeSummaryScreen(
        attempts: _summaryAttempts(),
        onFixMistakes: _restartWithMistakes,
        onWeakSkillDrill: _restartWithWeakSkill,
      );
    }

    _trackExerciseShownIfNeeded(source: 'build');
    _ensureOrderState(item);
    final resolvedPromptText = _resolvedPromptText(item);

    if (!_isItemValid(item, resolvedPromptText: resolvedPromptText)) {
      return ExerciseShell(
        index: _currentIndex,
        total: _plan!.items.length,
        skillLabel: _labelForSkill(planItem.skill),
        skillIcon: _iconForSkill(planItem.skill),
        instruction: 'This exercise cannot load',
        subInstruction: 'The item is missing required fields.',
        levelLabel: 'L${item.level}',
        attemptsRemaining: _attemptsRemaining,
        attemptsTotal: _attemptsAllowed,
        isAnswered: false,
        isCorrect: false,
        isReady: true,
        primaryLabelOverride: 'Skip',
        onPrimaryOverride: () {
          final context = _analyticsContextForItem(item);
          if (context != null) {
            ExerciseAnalytics.skipped(context, reason: 'invalid_content');
          }
          _advance();
        },
        content: const ExerciseUnavailableCard(
          message: 'This item is missing required content. It will be skipped.',
        ),
        onExplain: planItem.reasonCodes.isNotEmpty
            ? () =>
                  ExplainButton.showExplain(context, _buildWhyForPlan(planItem))
            : null,
        showSecondaryToggle: false,
        showSettingsMenu: true,
        onCheck: _checkAnswer,
        onTryAgain: _tryAgain,
        onContinue: _continue,
      );
    }

    final isSpeakingItem = _isSpeaking(item);
    final supportsHeaderPinyin =
        PracticeExerciseEngine.supportsHeaderPinyinToggle(item);
    // Debug logging for Issue B - header control disappearing
    AppLog.d(
      '[PracticeSession] Building exercise ${_currentIndex + 1}/${_plan!.items.length}',
    );
    AppLog.d(
      '[PracticeSession] onExplain will be: non-null (always provided on valid items)',
    );
    AppLog.d(
      '[PracticeSession] isAnswered=$_isAnswered, attemptsRemaining=$_attemptsRemaining',
    );
    return ExerciseShell(
      index: _currentIndex,
      total: _plan!.items.length,
      skillLabel: _labelForSkill(planItem.skill),
      skillIcon: _iconForSkill(planItem.skill),
      instruction: _instructionFor(
        item,
        resolvedPromptText: resolvedPromptText,
      ),
      subInstruction:
          PracticeExerciseEngine.normalizeType(item.exerciseType) ==
              'order_sentence'
          ? null
          : planItem.why,
      levelLabel: 'L${item.level}',
      attemptsRemaining: _attemptsRemaining,
      attemptsTotal: _attemptsAllowed,
      isAnswered: isSpeakingItem ? false : _isAnswered,
      isCorrect: isSpeakingItem ? false : _isCorrect(item),
      isReady: _isReady(item),
      hideFooter: isSpeakingItem,
      // Keep options docked just above footer CTA across exercise types.
      bodyScrollable: false,
      mediaSlot: _buildMediaSlot(item, isSpeakingItem: isSpeakingItem),
      hintBuilder: () => 'Review the prompt and try again.',
      revealBuilder: () => _buildReveal(item),
      onExplain: () =>
          ExplainButton.showExplain(context, _buildWhyForPlan(planItem)),
      showSecondaryToggle: supportsHeaderPinyin,
      secondaryToggleActive: _showPinyin,
      onToggleSecondary: supportsHeaderPinyin
          ? () {
              _trackInteractionIfNeeded('toggle_pinyin');
              setState(() => _showPinyin = !_showPinyin);
            }
          : null,
      showSettingsMenu: true,
      onCheck: _checkAnswer,
      onTryAgain: _tryAgain,
      onContinue: _continue,
      content: _buildExercise(item, resolvedPromptText: resolvedPromptText),
    );
  }

  Widget _buildExercise(PilotExerciseItem item, {String? resolvedPromptText}) {
    return PracticeExerciseEngine.buildExercise(
      item: item,
      state: _exerciseUiState,
      callbacks: _exerciseCallbacks,
      resolvedPromptText: resolvedPromptText,
    );
  }

  Widget? _buildMediaSlot(
    PilotExerciseItem item, {
    required bool isSpeakingItem,
  }) {
    return PracticeExerciseEngine.buildMediaSlot(
      item: item,
      isSpeakingItem: isSpeakingItem,
    );
  }

  bool _isItemValid(PilotExerciseItem item, {String? resolvedPromptText}) {
    if (!PracticeExerciseEngine.isSessionEnabledType(item.exerciseType)) {
      return false;
    }
    return PracticeExerciseEngine.isItemValid(
      item: item,
      resolvedPromptText: resolvedPromptText,
    );
  }

  String _instructionFor(PilotExerciseItem item, {String? resolvedPromptText}) {
    return PracticeExerciseEngine.instructionFor(
      item: item,
      resolvedPromptText: resolvedPromptText,
    );
  }

  bool _isReady(PilotExerciseItem item) {
    return PracticeExerciseEngine.isReady(item: item, state: _exerciseUiState);
  }

  String _labelForSkill(String skill) {
    switch (skill) {
      case 'listening':
        return 'Listening';
      case 'reading':
        return 'Reading';
      case 'grammar':
        return 'Grammar';
      case 'production':
      case 'speaking':
        return 'Speaking';
      case 'pinyin':
        return 'Pinyin';
      case 'characters':
        return 'Characters';
      case 'meaning':
        return 'Meaning';
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
      case 'production':
      case 'speaking':
        return Icons.mic_rounded;
      case 'pinyin':
        return Icons.record_voice_over_outlined;
      case 'characters':
        return Icons.translate_rounded;
      case 'meaning':
        return Icons.lightbulb_outline;
      default:
        return Icons.translate_rounded;
    }
  }

  String _buildReveal(PilotExerciseItem item) {
    return PracticeExerciseEngine.revealFor(item);
  }

  PilotWhy _buildWhyForPlan(PracticeSessionItem planItem) {
    final reason = planItem.why;
    final codes = planItem.reasonCodes;
    final meta = planItem.meta;
    final dueIn = meta['due_in_ms'] is int ? meta['due_in_ms'] as int : null;
    final skillTarget = meta['skill_target']?.toString() ?? planItem.skill;
    final stage = meta['word_stage']?.toString();
    return PilotWhy(
      reasons: [reason],
      reasonCodes: codes,
      signals: PilotWhySignals(
        skillTarget: skillTarget,
        wordStage: stage,
        dueInMs: dueIn,
      ),
    );
  }

  String? _resolvedPromptText(PilotExerciseItem item) {
    final raw = item.promptText;
    if (raw != null && raw.trim().isNotEmpty) return raw;
    final word = item.prompt.hanzi ?? item.prompt.meaning;
    return _contextResolver.resolvePrompt(
      wordId: item.conceptId,
      unitId: item.unitId,
      exerciseType: item.exerciseType,
      index: _currentIndex,
      word: word,
      meaning: item.prompt.meaning,
    );
  }

  bool _isSpeaking(PilotExerciseItem item) {
    return PracticeExerciseEngine.isSpeaking(item);
  }

  String _skillForType(String exerciseType) {
    return PracticeExerciseEngine.skillForType(exerciseType);
  }

  String _masterySkillFor(String skill) {
    return PracticeExerciseEngine.masterySkillFor(skill);
  }

  void _beginAnalyticsSession({required int totalExercises}) {
    _analyticsSessionId = ExerciseAnalytics.newSessionId(
      ExerciseRunner.practice,
    );
    _analyticsStartedAt = DateTime.now();
    _analyticsSessionActive = totalExercises > 0;
    _analyticsSessionFinalized = false;
    _analyticsLastShownKey = null;
    _analyticsInteractedKeys.clear();
    if (!_analyticsSessionActive) return;
    ExerciseAnalytics.sessionStarted(
      sessionId: _analyticsSessionId,
      runner: ExerciseRunner.practice,
      totalExercises: totalExercises,
      seed: widget.seed,
    );
  }

  String? _analyticsCurrentExerciseKey() {
    final item = _currentItem;
    if (item == null) return null;
    final step = item.exerciseType == 'reading_micro'
        ? _readingQuestionIndex
        : 0;
    return '${item.id}:$_currentIndex:$step';
  }

  ExerciseAnalyticsContext? _analyticsContextForCurrent() {
    final item = _currentItem;
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
    final planItem = _currentPlanItem;
    final step = item.exerciseType == 'reading_micro'
        ? _readingQuestionIndex + 1
        : null;
    return ExerciseAnalyticsContext(
      sessionId: _analyticsSessionId,
      runner: ExerciseRunner.practice,
      exerciseId: item.id,
      exerciseType: item.exerciseType,
      skill: planItem?.skill ?? item.skill,
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
      runner: ExerciseRunner.practice,
      totalExercises: total,
      completedExercises: completed,
      correctExercises: correct,
      durationMs: durationMs,
    );
  }

  void _trackSessionQuitIfNeeded() {
    if (!_analyticsSessionActive || _analyticsSessionFinalized) return;
    _analyticsSessionFinalized = true;
    final total = _plan?.items.length ?? 0;
    final durationMs = _analyticsStartedAt == null
        ? null
        : DateTime.now().difference(_analyticsStartedAt!).inMilliseconds;
    ExerciseAnalytics.sessionQuit(
      sessionId: _analyticsSessionId,
      runner: ExerciseRunner.practice,
      totalExercises: total,
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
    final item = _currentItem;
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
      final planItem = _currentPlanItem;
      final skill = planItem?.skill ?? 'production';
      final recording = _speakingRecording;
      final durationMs = recording?.durationMs ?? 0;
      final isCorrect = rating != SpeakingRating.needsWork;
      final context = _analyticsContextForItem(item);
      if (context != null) {
        ExerciseAnalytics.result(
          context,
          isCorrect: isCorrect,
          finalized: true,
          latencyMs: durationMs,
          attemptsUsed: 1,
        );
      }
      final event = AttemptEvent(
        wordId: item.conceptId,
        exerciseType: item.exerciseType,
        skill: skill,
        isCorrect: isCorrect,
        attemptsUsed: 1,
        durationMs: durationMs,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        selfRating: speakingRatingLabel(rating),
      );
      _attempts.add(event);
      _store?.applyAttempt(event);
      _store?.save();

      // Speaking notebook update
      _speakingNotebook?.addEntry(
        SpeakingEntry(
          conceptId: item.conceptId,
          exerciseType: item.exerciseType,
          rating: speakingRatingLabel(rating),
          durationMs: durationMs,
          recordingPath: recording?.path,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          promptText: item.promptText,
          sampleAnswers:
              (item.payload['sample_answers'] as List<dynamic>? ?? [])
                  .map((e) => e.toString())
                  .toList(),
        ),
      );
      _speakingNotebook?.save();

      _advance();
    } finally {
      _speakingSubmitInFlight = false;
    }
  }

  void _restartWithMistakes() {
    final wrongIds = _attempts
        .where((e) => !e.isCorrect)
        .map((e) => e.wordId)
        .toSet();
    if (wrongIds.isEmpty) return;
    final pack = _pack;
    if (pack == null) return;
    final items = pack.items
        .where((item) => wrongIds.contains(item.conceptId))
        .toList();
    _plan = PracticeSessionPlan(
      seed: widget.seed,
      dateBucket: widget.dateBucket ?? _todayBucket(),
      sections: [
        PracticeSessionSection(
          label: 'Fix mistakes',
          items: items
              .map(
                (item) => PracticeSessionItem(
                  id: item.id,
                  wordId: item.conceptId,
                  exerciseType: item.exerciseType,
                  skill: _skillForType(item.exerciseType),
                  level: item.level,
                  why: 'Fixing mistakes',
                  reasonCodes: const ['MISTAKE_REVIEW'],
                  meta: {
                    'unit_id': item.unitId,
                    'skill_target': _skillForType(item.exerciseType),
                  },
                ),
              )
              .toList(),
        ),
      ],
      items: items
          .map(
            (item) => PracticeSessionItem(
              id: item.id,
              wordId: item.conceptId,
              exerciseType: item.exerciseType,
              skill: _skillForType(item.exerciseType),
              level: item.level,
              why: 'Fixing mistakes',
              reasonCodes: const ['MISTAKE_REVIEW'],
              meta: {
                'unit_id': item.unitId,
                'skill_target': _skillForType(item.exerciseType),
              },
            ),
          )
          .toList(),
    );
    setState(() {
      _currentIndex = 0;
      _attempts.clear();
    });
    _beginAnalyticsSession(totalExercises: _plan?.items.length ?? 0);
    _resetItemState();
    _trackExerciseShownIfNeeded(source: 'restart_mistakes');
  }

  void _restartWithWeakSkill() {
    if (_attempts.isEmpty) return;
    final stats = <String, List<AttemptEvent>>{};
    for (final attempt in _attempts) {
      stats.putIfAbsent(attempt.skill, () => []).add(attempt);
    }
    String weakest = stats.keys.first;
    double lowest = 2.0;
    for (final entry in stats.entries) {
      final total = entry.value.length;
      final correct = entry.value.where((e) => e.isCorrect).length;
      final accuracy = total == 0 ? 0.0 : correct / total;
      if (accuracy < lowest) {
        lowest = accuracy;
        weakest = entry.key;
      }
    }
    final pack = _pack;
    final store = _store;
    if (pack == null || store == null) return;
    final plan = _scheduler.buildPlan(
      pack: pack,
      state: store,
      seed: widget.seed,
      dateBucket: widget.dateBucket ?? _todayBucket(),
      goalProfile: _goalProfile,
      config: PracticeSchedulerConfig(
        totalCount: 10,
        skillWeights: {weakest: 100},
        overrideGoalWeights: true,
      ),
    );
    setState(() {
      _plan = plan;
      _currentIndex = 0;
      _attempts.clear();
    });
    _beginAnalyticsSession(totalExercises: plan.items.length);
    _resetItemState();
    _trackExerciseShownIfNeeded(source: 'restart_weak_skill');
  }

  String _todayBucket() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  List<PracticeAttempt> _summaryAttempts() {
    return _attempts
        .map(
          (e) => PracticeAttempt(
            skill: e.skill,
            isCorrect: e.isCorrect,
            latencyMs: e.durationMs,
          ),
        )
        .toList();
  }
}
