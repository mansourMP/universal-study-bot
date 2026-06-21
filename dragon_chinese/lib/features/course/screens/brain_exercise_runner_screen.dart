// Brain Exercise Runner Screen
// Learning Path 2.0 - Phase 8
//
// Exercise runner that uses BrainExerciseController for API-driven exercise flow.
// Handles loading, error states, stage completion, and skill feedback.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dragon_chinese/core/config/app_config.dart';
import 'package:dragon_chinese/features/course/models/brain_models.dart';
import 'package:dragon_chinese/features/course/controllers/brain_exercise_controller.dart';
import 'package:dragon_chinese/features/course/engine/practice_exercise_engine.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/explain_panel.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/exercise_shell.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/exercise_media.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/speaking_exercise.dart';
import 'package:dragon_chinese/features/course/services/local_mastery_tracker.dart';
import 'package:dragon_chinese/features/course/services/exercise_analytics.dart';
import 'package:dragon_chinese/features/course/services/speaking_evaluator.dart';
import 'package:dragon_chinese/features/course/services/speaking_recorder.dart';
import 'package:dragon_chinese/features/course/screens/practice_summary_screen.dart';
import 'package:dragon_chinese/features/learning_engine/models/attempt_signal.dart';

class BrainExerciseRunnerScreen extends StatefulWidget {
  /// Intent for the mission (daily, review, learn).
  final String intent;

  /// Optional number of exercises to fetch.
  /// If null, backend chooses based on its default/budgeting logic.
  final int? exerciseCount;

  /// List of word IDs to force (e.g. from a lesson).
  final List<String>? forcedIds;

  /// Optional whitelist scope. If null, controller falls back to forcedIds.
  final List<String>? allowedWordIds;

  /// Path node ID for context/analytics.
  final String? nodeId;

  /// Optional contextual unit ID
  final String? unitId;

  /// Optional skill focus for drill missions.
  final String? focusDimension;

  /// Optional duration targets (seconds)
  final int? targetMinSeconds;
  final int? targetMaxSeconds;

  /// Callback when session completes.
  final VoidCallback? onComplete;

  const BrainExerciseRunnerScreen({
    super.key,
    this.intent = 'daily',
    this.exerciseCount,
    this.forcedIds,
    this.allowedWordIds,
    this.nodeId,
    this.unitId,
    this.focusDimension,
    this.targetMinSeconds,
    this.targetMaxSeconds,
    this.onComplete,
  });

  @override
  State<BrainExerciseRunnerScreen> createState() =>
      _BrainExerciseRunnerScreenState();
}

class _BrainExerciseRunnerScreenState extends State<BrainExerciseRunnerScreen> {
  late final BrainExerciseController _controller;
  final SpeakingRecorder _speakingRecorder = SpeakingRecorderService.instance;
  int? _selectedIndex;
  String _textAnswer = '';
  bool _isAnswered = false;
  bool _lastAnswerCorrect = false;
  bool _showPinyin = false;
  bool _matchReady = false;
  bool _matchCorrect = false;
  List<String> _orderChunks = [];
  List<String> _orderAnswer = [];
  final int _attemptsAllowed = 3;
  int _attemptsRemaining = 3;
  final List<PracticeAttempt> _practiceAttempts = [];
  bool _showSummary = false;
  LocalMasteryTracker? _mastery;
  bool _speakingPermissionGranted = true;
  bool _speakingIsRecording = false;
  SpeakingRecording? _speakingRecording;
  SpeakingRating? _speakingRating;
  double? _speakingScore;
  String? _speakingExerciseMarker;
  bool _speakingSubmitInFlight = false;
  final Map<String, int> _knowledgeStateCounts = {
    AttemptKnowledgeState.knows.wireName: 0,
    AttemptKnowledgeState.learning.wireName: 0,
    AttemptKnowledgeState.struggling.wireName: 0,
  };
  String _analyticsSessionId = ExerciseAnalytics.newSessionId(
    ExerciseRunner.brain,
  );
  String? _analyticsLastShownKey;
  final Set<String> _analyticsInteractedKeys = <String>{};
  bool _analyticsSessionActive = false;
  bool _analyticsSessionFinalized = false;
  DateTime? _analyticsStartedAt;

  @override
  void initState() {
    super.initState();
    _controller = BrainExerciseController();
    _controller.addListener(_onControllerUpdate);
    _analyticsStartedAt = DateTime.now();
    _startSession();
    _loadMastery();
  }

  Future<void> _loadMastery() async {
    _mastery = await LocalMasteryTracker.load();
  }

  @override
  void dispose() {
    _trackSessionQuitIfNeeded();
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    _syncSpeakingStateForCurrentExercise();
    if (mounted) setState(() {});
  }

  Future<void> _startSession() async {
    _analyticsSessionId = ExerciseAnalytics.newSessionId(ExerciseRunner.brain);
    _analyticsStartedAt = DateTime.now();
    _analyticsSessionActive = false;
    _analyticsSessionFinalized = false;
    _analyticsLastShownKey = null;
    _analyticsInteractedKeys.clear();
    _knowledgeStateCounts.updateAll((_, __) => 0);
    await _controller.startSession(
      intent: widget.intent,
      limit: widget.exerciseCount,
      forcedIds: widget.forcedIds,
      allowedWordIds: widget.allowedWordIds,
      nodeId: widget.nodeId,
      unitId: widget.unitId,
      focusDimension: widget.focusDimension,
      targetMinSeconds: widget.targetMinSeconds,
      targetMaxSeconds: widget.targetMaxSeconds,
    );
    if (_controller.state == SessionState.ready &&
        _controller.exercisesTotal > 0) {
      _analyticsSessionActive = true;
      ExerciseAnalytics.sessionStarted(
        sessionId: _analyticsSessionId,
        runner: ExerciseRunner.brain,
        totalExercises: _controller.exercisesTotal,
        missionId: _controller.missionId,
      );
      _trackExerciseShownIfNeeded(source: 'session_start');
    }
    _syncSpeakingStateForCurrentExercise();
  }

  Future<void> _checkAnswer() async {
    final ex = _controller.currentExercise;
    if (ex == null) return;
    final item = _toPilotExerciseItem(ex);
    final analyticsContext = _analyticsContextFor(ex, item: item);
    if (analyticsContext != null) {
      ExerciseAnalytics.checkTapped(analyticsContext);
    }
    _ensureOrderState(item);
    final isSpeaking = PracticeExerciseEngine.isSpeaking(item);
    if (isSpeaking) {
      await _completeSpeaking();
      return;
    }
    final isCorrect = PracticeExerciseEngine.isCorrect(
      item: item,
      state: _exerciseUiState,
    );

    HapticFeedback.mediumImpact();
    final attemptsUsed = _attemptsUsedForCurrent();

    if (!isCorrect && _attemptsRemaining > 1) {
      if (analyticsContext != null) {
        ExerciseAnalytics.result(
          analyticsContext,
          isCorrect: false,
          finalized: false,
          latencyMs: _controller.currentLatencyMs,
          attemptsUsed: attemptsUsed,
        );
      }
      setState(() {
        _attemptsRemaining -= 1;
        _isAnswered = true;
        _lastAnswerCorrect = false;
      });
      return;
    }

    setState(() {
      _isAnswered = true;
      _lastAnswerCorrect = isCorrect;
      if (!isCorrect) {
        _attemptsRemaining = 0;
      }
    });

    final attemptSignal = PracticeExerciseEngine.classifyAttemptSignal(
      item: item,
      isCorrect: isCorrect,
      attemptsUsed: attemptsUsed,
      latencyMs: _controller.currentLatencyMs,
    );
    await _controller.submitAnswer(
      isCorrect: isCorrect,
      attemptMeta: _attemptMetaFor(
        signal: attemptSignal,
        source: 'exercise_engine',
      ),
    );
    if (analyticsContext != null) {
      ExerciseAnalytics.result(
        analyticsContext,
        isCorrect: isCorrect,
        finalized: true,
        latencyMs: _controller.currentLatencyMs,
        attemptsUsed: attemptsUsed,
        knowledgeState: attemptSignal.knowledgeState.wireName,
      );
    }
    _recordKnowledgeState(attemptSignal.knowledgeState);
    _mastery?.recordAttempt(
      conceptId: int.tryParse(ex.wordId) ?? 0,
      skillBucket: LocalMasteryTracker.skillBucketForExercise(ex.type),
      isCorrect: isCorrect,
      isExamMode: false,
      isTimed: false,
    );
    _mastery?.save();
    _practiceAttempts.add(
      PracticeAttempt(
        skill: _skillForFocus(ex.skillFocus),
        isCorrect: isCorrect,
        latencyMs: _controller.currentLatencyMs ?? 0,
        knowledgeState: attemptSignal.knowledgeState.wireName,
      ),
    );
  }

  void _nextExercise() {
    final context = _analyticsContextForCurrent();
    if (context != null) {
      ExerciseAnalytics.continued(context);
    }
    if (_controller.hasMoreExercises) {
      _controller.nextExercise();
      setState(() {
        _selectedIndex = null;
        _textAnswer = '';
        _isAnswered = false;
        _showPinyin = false;
        _orderChunks = [];
        _orderAnswer = [];
        _matchReady = false;
        _matchCorrect = false;
        _attemptsRemaining = _attemptsAllowed;
        _resetSpeakingState();
      });
      _analyticsLastShownKey = null;
      _syncSpeakingStateForCurrentExercise();
      _trackExerciseShownIfNeeded(source: 'next');
    } else {
      // Session complete
      _markSessionCompleted();
      setState(() {
        _showSummary = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showSummary) {
      return PracticeSummaryScreen(
        attempts: _practiceAttempts,
        onDrillAgain: _restartPractice,
        onFinish: () {
          _markSessionCompleted();
          widget.onComplete?.call();
          Navigator.of(context).pop();
        },
      );
    }
    return Scaffold(backgroundColor: Colors.white, body: _buildBody());
  }

  Widget _buildBody() {
    switch (_controller.state) {
      case SessionState.loading:
        return _buildLoadingState();
      case SessionState.error:
        return _buildErrorState();
      case SessionState.stageComplete:
        return _buildStageCompleteState();
      case SessionState.ready:
      case SessionState.submitting:
        return _buildExerciseState();
    }
  }

  Widget _buildLoadingState() {
    return const ExerciseLoadingSkeleton();
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Error loading exercises',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _controller.errorMessage ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _startSession,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStageCompleteState() {
    final response = _controller.lastResponse;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.celebration, size: 80, color: Colors.amber),
            const SizedBox(height: 24),
            const Text(
              'Stage Complete! 🎉',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (response?.nextReviewAt != null)
              Text(
                'Next review: ${_formatNextReview(response!.nextReviewAt!)}',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (_controller.hasMoreExercises) {
                    _nextExercise();
                    return;
                  }
                  _markSessionCompleted();
                  setState(() {
                    _showSummary = true;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'CONTINUE',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatNextReview(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final diff = date.difference(DateTime.now());
      if (diff.inHours < 24) {
        return 'in ${diff.inHours} hours';
      } else {
        return 'in ${diff.inDays} days';
      }
    } catch (_) {
      return isoDate;
    }
  }

  void _restartPractice() {
    _practiceAttempts.clear();
    _showSummary = false;
    _analyticsSessionFinalized = false;
    _analyticsSessionActive = false;
    _selectedIndex = null;
    _textAnswer = '';
    _isAnswered = false;
    _lastAnswerCorrect = false;
    _showPinyin = false;
    _orderChunks = [];
    _orderAnswer = [];
    _matchReady = false;
    _matchCorrect = false;
    _attemptsRemaining = _attemptsAllowed;
    _resetSpeakingState();
    _speakingExerciseMarker = null;
    _startSession();
    setState(() {});
  }

  Future<void> _completeSpeaking() async {
    final ex = _controller.currentExercise;
    final rating = _speakingRating;
    if (ex == null || rating == null || _speakingSubmitInFlight) return;
    _speakingSubmitInFlight = true;

    try {
      final isCorrect = rating != SpeakingRating.needsWork;
      HapticFeedback.mediumImpact();

      final item = _toPilotExerciseItem(ex);
      final analyticsContext = _analyticsContextFor(ex, item: item);
      final attemptsUsed = _attemptsUsedForCurrent();
      final attemptSignal = PracticeExerciseEngine.classifyAttemptSignal(
        item: item,
        isCorrect: isCorrect,
        attemptsUsed: attemptsUsed,
        latencyMs: _controller.currentLatencyMs,
        speakingScore: _speakingScore,
      );
      await _controller.submitAnswer(
        isCorrect: isCorrect,
        attemptMeta: _attemptMetaFor(
          signal: attemptSignal,
          source: 'exercise_engine',
        ),
      );
      if (analyticsContext != null) {
        ExerciseAnalytics.result(
          analyticsContext,
          isCorrect: isCorrect,
          finalized: true,
          latencyMs: _controller.currentLatencyMs,
          attemptsUsed: attemptsUsed,
          knowledgeState: attemptSignal.knowledgeState.wireName,
        );
      }
      _recordKnowledgeState(attemptSignal.knowledgeState);
      _mastery?.recordAttempt(
        conceptId: int.tryParse(ex.wordId) ?? 0,
        skillBucket: LocalMasteryTracker.skillBucketForExercise(ex.type),
        isCorrect: isCorrect,
        isExamMode: false,
        isTimed: false,
      );
      _mastery?.save();
      _practiceAttempts.add(
        PracticeAttempt(
          skill: _skillForFocus(ex.skillFocus),
          isCorrect: isCorrect,
          latencyMs: _controller.currentLatencyMs ?? 0,
          knowledgeState: attemptSignal.knowledgeState.wireName,
        ),
      );

      if (!mounted) return;
      if (_controller.state == SessionState.stageComplete) {
        setState(() {});
        return;
      }
      if (_controller.hasMoreExercises) {
        _nextExercise();
        return;
      }
      _markSessionCompleted();
      setState(() {
        _showSummary = true;
      });
    } finally {
      _speakingSubmitInFlight = false;
    }
  }

  int _attemptsUsedForCurrent() {
    final used = (_attemptsAllowed - _attemptsRemaining + 1);
    return used.clamp(1, _attemptsAllowed);
  }

  Map<String, dynamic> _attemptMetaFor({
    required AttemptSignal signal,
    required String source,
  }) {
    return {
      'engine_id': PracticeExerciseEngine.engineId,
      'source': source,
      'knowledge_signal': signal.toJson(),
      'knowledge_state_counts': Map<String, int>.from(_knowledgeStateCounts),
    };
  }

  void _recordKnowledgeState(AttemptKnowledgeState state) {
    final key = state.wireName;
    _knowledgeStateCounts[key] = (_knowledgeStateCounts[key] ?? 0) + 1;
  }

  Widget _buildExerciseState() {
    final ex = _controller.currentExercise;
    if (ex == null) {
      return const Center(child: Text('No exercises available'));
    }
    final item = _toPilotExerciseItem(ex);
    _trackExerciseShownIfNeeded(source: 'build');
    _ensureOrderState(item);
    final resolvedPromptText = _resolvedPromptText(item, ex);
    final effectiveSkill = _effectiveSkill(ex);
    final normalizedType = PracticeExerciseEngine.normalizeType(ex.type);
    final isSpeakingExercise = PracticeExerciseEngine.isSpeaking(item);
    final supportsHeaderPinyin =
        PracticeExerciseEngine.supportsHeaderPinyinToggle(item);
    final explainWhy = _resolveWhy(ex);
    final isSupported = _isSupportedExerciseType(item.exerciseType);
    final isValid =
        isSupported &&
        PracticeExerciseEngine.isItemValid(
          item: item,
          resolvedPromptText: resolvedPromptText,
        );

    if (!isValid) {
      return ExerciseShell(
        index: _controller.currentIndex,
        total: _controller.exercisesTotal,
        sectionLabel: _missionSectionLabel(),
        skillLabel: _labelForSkill(effectiveSkill),
        skillIcon: _iconForSkill(effectiveSkill),
        instruction: 'This exercise cannot load',
        subInstruction: 'The item is missing required fields.',
        attemptsRemaining: _attemptsRemaining,
        attemptsTotal: _attemptsAllowed,
        isAnswered: false,
        isCorrect: false,
        isReady: true,
        explainLabel: 'Explain',
        onExplain: () => ExplainButton.showExplain(context, explainWhy),
        showSecondaryToggle: false,
        showSettingsMenu: true,
        primaryLabelOverride: 'Skip',
        onPrimaryOverride: () {
          final context = _analyticsContextFor(ex, item: item);
          if (context != null) {
            ExerciseAnalytics.skipped(context, reason: 'invalid_content');
          }
          _nextExercise();
        },
        content: const ExerciseUnavailableCard(
          message: 'Unsupported or invalid exercise. It will be skipped.',
        ),
        onCheck: () {},
        onTryAgain: () {},
        onContinue: _nextExercise,
      );
    }

    return ExerciseShell(
      index: _controller.currentIndex,
      total: _controller.exercisesTotal,
      sectionLabel: _missionSectionLabel(),
      skillLabel: _labelForSkill(effectiveSkill),
      skillIcon: _iconForSkill(effectiveSkill),
      instruction: PracticeExerciseEngine.instructionFor(
        item: item,
        resolvedPromptText: resolvedPromptText,
      ),
      subInstruction: normalizedType == 'order_sentence'
          ? null
          : _combinedSubInstruction(ex),
      attemptsRemaining: _attemptsRemaining,
      attemptsTotal: _attemptsAllowed,
      isAnswered: isSpeakingExercise ? false : _isAnswered,
      isCorrect: isSpeakingExercise ? false : _lastAnswerCorrect,
      isReady: isSpeakingExercise
          ? _speakingRating != null
          : PracticeExerciseEngine.isReady(item: item, state: _exerciseUiState),
      hideFooter: isSpeakingExercise,
      // Keep options docked just above footer CTA across exercise types.
      bodyScrollable: false,
      explainLabel: 'Explain',
      onExplain: () => ExplainButton.showExplain(context, explainWhy),
      showSecondaryToggle: supportsHeaderPinyin,
      secondaryToggleActive: _showPinyin,
      onToggleSecondary: supportsHeaderPinyin
          ? () {
              _trackInteractionIfNeeded('toggle_pinyin');
              setState(() => _showPinyin = !_showPinyin);
            }
          : null,
      showSettingsMenu: true,
      mediaSlot: _buildMediaSlot(ex),
      hintBuilder: () => _buildHint(ex),
      revealBuilder: () => PracticeExerciseEngine.revealFor(item),
      onCheck: _checkAnswer,
      onTryAgain: () {
        final context = _analyticsContextForCurrent();
        if (context != null) {
          ExerciseAnalytics.tryAgain(context);
        }
        setState(() {
          _selectedIndex = null;
          _textAnswer = '';
          _isAnswered = false;
        });
      },
      onContinue: _nextExercise,
      content: PracticeExerciseEngine.buildExercise(
        item: item,
        state: _exerciseUiState,
        callbacks: _exerciseCallbacksFor(item),
        resolvedPromptText: resolvedPromptText,
      ),
    );
  }

  String _effectiveSkill(BrainExercise ex) {
    switch (ex.type) {
      case 'audio_select':
        return 'listening';
      case 'reading_micro':
      case 'reading_span_select':
        return 'reading';
      case 'character_writing':
        return 'characters';
      case 'reverse_recall':
      case 'error_correction':
      case 'conversation_simulation':
        return 'production';
      case 'speak_read_aloud':
      case 'speak_prompted_reply':
      case 'speaking':
        return 'speaking';
      case 'order_sentence':
        return 'production';
      default:
        return ex.skillFocus;
    }
  }

  Map<String, dynamic>? _adaptivePolicyMap() {
    final metadata = _controller.missionMetadata;
    if (metadata == null) return null;
    final policy = metadata['adaptive_policy'];
    if (policy is Map) {
      return policy.cast<String, dynamic>();
    }
    return null;
  }

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? fallback;
    if (value is double) return value.round();
    return fallback;
  }

  String? _missionSectionLabel() {
    final policy = _adaptivePolicyMap();
    if (policy == null) return null;
    switch ((policy['mode'] ?? '').toString()) {
      case 'review_only':
        return 'Review Focus';
      case 'reduced_new':
        return 'Stabilize';
      case 'normal':
        return 'Balanced';
      case 'learn_forced':
        return 'Guided Lesson';
      default:
        return null;
    }
  }

  String? _missionSchedulerNote() {
    final policy = _adaptivePolicyMap();
    if (policy == null) return null;
    final hard = _toInt(policy['hard_due_count']);
    final soft = _toInt(policy['soft_due_count']);
    final newCap = _toInt(policy['max_new']);
    final modeReason = (policy['mode_reason'] ?? '').toString();

    final parts = <String>[
      if (hard > 0) 'Hard due $hard',
      if (soft > 0) 'Soft due $soft',
      'New cap $newCap',
    ];

    if (modeReason == 'hard_due_backlog_over_capacity') {
      parts.add('Paying down urgent reviews');
    } else if (modeReason == 'hard_due_backlog_rising') {
      parts.add('Reducing new to protect retention');
    } else if (modeReason == 'soft_due_backlog_dampening') {
      parts.add('Light dampening for backlog');
    }

    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  String? _combinedSubInstruction(BrainExercise ex) {
    final base = _subInstructionFor(ex);
    final note = _missionSchedulerNote();
    if (base == null || base.isEmpty) return note;
    if (note == null || note.isEmpty) return base;
    return '$base · $note';
  }

  String _buildHint(BrainExercise ex) {
    final options = _extractOptions(ex.payload);
    final idx = _extractAnswerIndex(ex.payload) ?? 0;
    if (options.isEmpty || idx >= options.length) {
      return 'Focus on the prompt details.';
    }
    final correct = options[idx];
    if (correct.length <= 2) {
      return "Starts with '${correct[0]}'";
    }
    return 'Answer length: ${correct.length}';
  }

  bool _isPunctuationOnlyChunk(String token) {
    return RegExp(
      r'^[\.\,\!\?\;\:\u3002\uff01\uff1f\uff0c\u3001\u2026\u2014\u2013'
      r'\u300c\u300d\u300e\u300f\u201c\u201d\u2018\u2019'
      r'\(\)\[\]\{\}\uff08\uff09\u300a\u300b<>]+$',
    ).hasMatch(token);
  }

  List<String> _normalizeOrderSentenceChunks(List<String> rawChunks) {
    final merged = <String>[];
    for (final raw in rawChunks) {
      final token = raw.trim();
      if (token.isEmpty) continue;
      if (_isPunctuationOnlyChunk(token) && merged.isNotEmpty) {
        merged[merged.length - 1] = '${merged.last}$token';
      } else {
        merged.add(token);
      }
    }
    return merged;
  }

  String _labelForSkill(String skill) {
    final skillConfig = _controller.config?.skills[skill];
    if (skillConfig != null) return skillConfig.label;

    switch (skill) {
      case 'listening':
        return 'Listening';
      case 'production':
        return 'Production';
      case 'usage':
        return 'Usage';
      case 'speaking':
        return 'Speaking';
      default:
        return 'Recognition';
    }
  }

  IconData _iconForSkill(String skill) {
    final skillConfig = _controller.config?.skills[skill];
    if (skillConfig != null) {
      // Basic mapping for known icons
      switch (skillConfig.icon) {
        case 'hearing':
          return Icons.headphones_rounded;
        case 'edit':
          return Icons.edit_rounded;
        case 'chat_bubble':
          return Icons.chat_bubble_outline;
        case 'visibility':
          return Icons.visibility_rounded;
        default:
          return Icons.star_outline_rounded;
      }
    }

    switch (skill) {
      case 'listening':
        return Icons.headphones_rounded;
      case 'production':
        return Icons.edit_rounded;
      case 'usage':
        return Icons.chat_bubble_outline;
      case 'speaking':
        return Icons.mic_rounded;
      default:
        return Icons.visibility_rounded;
    }
  }

  PracticeExerciseUiState get _exerciseUiState => PracticeExerciseUiState(
    selectedIndex: _selectedIndex,
    textAnswer: _textAnswer,
    isAnswered: _isAnswered,
    showPinyin: _showPinyin,
    readingQuestionIndex: 0,
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

  PracticeExerciseCallbacks _exerciseCallbacksFor(PilotExerciseItem item) {
    return PracticeExerciseCallbacks(
      onSelectIndex: (index) {
        _trackInteractionIfNeeded('select_index');
        setState(() {
          _selectedIndex = index;
        });
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
          _selectedIndex = updated.isNotEmpty ? 0 : null;
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
  }

  ExerciseAnalyticsContext? _analyticsContextForCurrent() {
    final ex = _controller.currentExercise;
    if (ex == null) return null;
    final item = _toPilotExerciseItem(ex);
    return _analyticsContextFor(ex, item: item);
  }

  ExerciseAnalyticsContext? _analyticsContextFor(
    BrainExercise ex, {
    required PilotExerciseItem item,
  }) {
    final total = _controller.exercisesTotal;
    if (total <= 0) return null;
    return ExerciseAnalyticsContext(
      sessionId: _analyticsSessionId,
      runner: ExerciseRunner.brain,
      exerciseId: ex.exerciseId,
      exerciseType: item.exerciseType,
      skill: _effectiveSkill(ex),
      index: _controller.currentIndex + 1,
      total: total,
      attemptsRemaining: _attemptsRemaining,
      attemptsAllowed: _attemptsAllowed,
    );
  }

  String? _analyticsCurrentExerciseKey() {
    final ex = _controller.currentExercise;
    if (ex == null) return null;
    return '${ex.exerciseId}:${_controller.currentIndex}';
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
    final durationMs = _analyticsStartedAt == null
        ? null
        : DateTime.now().difference(_analyticsStartedAt!).inMilliseconds;
    final correct = _practiceAttempts.where((a) => a.isCorrect).length;
    ExerciseAnalytics.sessionCompleted(
      sessionId: _analyticsSessionId,
      runner: ExerciseRunner.brain,
      totalExercises: _controller.exercisesTotal,
      completedExercises: _practiceAttempts.length,
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
      runner: ExerciseRunner.brain,
      totalExercises: _controller.exercisesTotal,
      completedExercises: _practiceAttempts.length,
      durationMs: durationMs,
    );
  }

  bool _isSupportedExerciseType(String exerciseType) {
    return PracticeExerciseEngine.isSessionEnabledType(exerciseType);
  }

  void _ensureOrderState(PilotExerciseItem item) {
    if (item.exerciseType != 'order_sentence') return;
    final payload = item.payload;
    final chunksRaw =
        (payload['chunks'] ?? payload['segments']) as List<dynamic>? ??
        const [];
    final answerRaw = payload['answer'];
    final normalizedChunks = _normalizeOrderSentenceChunks(
      chunksRaw.map((e) => e.toString()).toList(),
    );
    List<String> answer;
    if (answerRaw is List) {
      answer = answerRaw.map((e) => e.toString()).toList();
    } else if (answerRaw is String && answerRaw.trim().isNotEmpty) {
      answer = normalizedChunks;
    } else {
      answer = normalizedChunks;
    }
    if (_orderAnswer.isEmpty || _orderChunks.isEmpty) {
      _orderChunks = <String>[];
      _orderAnswer = answer;
    }
  }

  PilotExerciseItem _toPilotExerciseItem(BrainExercise ex) {
    final normalizedType = PracticeExerciseEngine.normalizeType(ex.type);
    final payload = _pilotPayloadFromBrain(ex, normalizedType);
    final choices = _extractOptions(payload);
    final answerIndex = _extractAnswerIndex(payload) ?? 0;
    final promptMap =
        (payload['prompt'] as Map?)?.cast<String, dynamic>() ?? {};
    final prompt = PilotPrompt(
      hanzi:
          promptMap['hanzi']?.toString() ??
          promptMap['word_zh']?.toString() ??
          promptMap['speaker_a_zh']?.toString(),
      pinyin: promptMap['pinyin']?.toString(),
      meaning:
          promptMap['meaning']?.toString() ??
          payload['instruction_en']?.toString(),
    );
    final readingRaw = payload['reading'] as Map<String, dynamic>?;
    final reading = readingRaw == null
        ? null
        : PilotReading.fromJson(readingRaw);
    final questionsRaw = (payload['questions'] as List<dynamic>? ?? const []);
    final questions = questionsRaw
        .whereType<Map>()
        .map((q) => PilotQuestion.fromJson(q.cast<String, dynamic>()))
        .toList();
    final level = int.tryParse(ex.difficulty) ?? 1;

    return PilotExerciseItem(
      id: ex.exerciseId,
      templateId: '',
      variantId: normalizedType,
      exerciseType: normalizedType,
      conceptId: _conceptIdFromWord(ex.wordId),
      unitId: widget.unitId,
      level: level,
      skill: _effectiveSkill(ex),
      constraints: PilotConstraints(),
      attemptsAllowed: _attemptsAllowed,
      timeLimitMs: null,
      difficultyLevel: level,
      requiredAssets: PilotRequiredAssets(
        audio:
            (payload['audio_url']?.toString().isNotEmpty ?? false) ||
            (payload['audio']?.toString().isNotEmpty ?? false),
        image: payload['image_url']?.toString().isNotEmpty ?? false,
      ),
      promptText: _derivePromptText(ex, normalizedType, payload, promptMap),
      prompt: prompt,
      choices: choices,
      answerIndex: choices.isEmpty
          ? 0
          : answerIndex.clamp(0, choices.length - 1).toInt(),
      options: const [],
      correctOptionId: null,
      meta: PilotMeta(hskLevel: 1, unitId: widget.unitId, tags: const []),
      why: _resolveWhy(ex),
      audioUrl:
          payload['audio_url']?.toString() ?? payload['audio']?.toString(),
      choiceType: payload['choice_type']?.toString(),
      payload: payload,
      reading: reading,
      questions: questions,
    );
  }

  Map<String, dynamic> _pilotPayloadFromBrain(
    BrainExercise ex,
    String normalizedType,
  ) {
    final payload = Map<String, dynamic>.from(ex.payload);
    final prompt = (payload['prompt'] as Map?)?.cast<String, dynamic>() ?? {};

    if ((payload['audio_url']?.toString().isEmpty ?? true) &&
        (payload['audio']?.toString().isNotEmpty ?? false)) {
      payload['audio_url'] = payload['audio'];
    }

    if (normalizedType == 'order_sentence') {
      final segments =
          (payload['segments'] ?? payload['chunks']) as List<dynamic>? ??
          const [];
      final chunks = _normalizeOrderSentenceChunks(
        segments.map((e) => e.toString()).toList(),
      );
      payload['segments'] = chunks;
      payload['chunks'] = chunks;
      final answer = payload['answer'];
      if (answer is String && answer.trim().isNotEmpty) {
        payload['answer'] = chunks;
      } else if (answer is! List) {
        payload['answer'] = chunks;
      }
    }

    if (normalizedType == 'reading_micro') {
      final reading = payload['reading'];
      if (reading is! Map) {
        final textZh = prompt['text_zh']?.toString() ?? '';
        final textEn = prompt['text_en']?.toString() ?? '';
        if (textZh.isNotEmpty || textEn.isNotEmpty) {
          payload['reading'] = {
            'title_zh': '短文',
            'title_en': 'Passage',
            'story_zh': textZh,
            'story_pinyin': '',
            'story_en': textEn,
          };
        }
      }
      final questions = payload['questions'];
      if (questions is! List || questions.isEmpty) {
        final options = _extractOptions(payload);
        if (options.isNotEmpty) {
          payload['questions'] = [
            {
              'type': 'meaning_select',
              'prompt': {
                'question':
                    prompt['question_en']?.toString() ??
                    prompt['question']?.toString() ??
                    'Choose the best answer',
              },
              'choices': options,
              'answer_index': _extractAnswerIndex(payload) ?? 0,
            },
          ];
        }
      }
    }

    if (normalizedType == 'reading_span_select') {
      final reading = payload['reading'];
      final readingMap = reading is Map
          ? reading.cast<String, dynamic>()
          : const <String, dynamic>{};

      final currentPassage = payload['passage']?.toString().trim() ?? '';
      if (currentPassage.isEmpty) {
        final passage =
            readingMap['story_zh']?.toString() ??
            readingMap['story_en']?.toString() ??
            payload['text']?.toString() ??
            prompt['text_zh']?.toString() ??
            prompt['text_en']?.toString() ??
            '';
        if (passage.trim().isNotEmpty) {
          payload['passage'] = passage.trim();
        }
      }

      if (payload['question']?.toString().trim().isEmpty ?? true) {
        final q =
            payload['prompt_text']?.toString() ??
            prompt['question_en']?.toString() ??
            prompt['question']?.toString() ??
            'Select the best answer from the passage';
        payload['question'] = q;
      }

      final existingChoices = _extractOptions(payload);
      if (existingChoices.isEmpty) {
        final questions = payload['questions'];
        if (questions is List && questions.isNotEmpty) {
          final first = questions.first;
          if (first is Map) {
            final firstMap = first.cast<String, dynamic>();
            final firstChoices = _extractOptions(firstMap);
            if (firstChoices.isNotEmpty) {
              payload['choices'] = firstChoices;
            }
            payload['answer_index'] ??= _extractAnswerIndex(firstMap) ?? 0;
          }
        }
      } else {
        payload['choices'] = existingChoices;
      }
    }

    if (normalizedType == 'reverse_recall') {
      if (payload['question']?.toString().trim().isEmpty ?? true) {
        final q =
            payload['prompt_text']?.toString() ??
            payload['instruction_en']?.toString() ??
            prompt['question_en']?.toString() ??
            prompt['question']?.toString() ??
            prompt['meaning']?.toString() ??
            'Type the correct answer';
        payload['question'] = q;
      }

      final answerRaw = payload['answer']?.toString().trim() ?? '';
      final samples = payload['sample_answers'];
      final acceptedRaw = payload['accepted_answers'];
      final accepted = <String>{};

      if (answerRaw.isNotEmpty) accepted.add(answerRaw);
      if (samples is List) {
        for (final s in samples) {
          final text = s.toString().trim();
          if (text.isNotEmpty) accepted.add(text);
        }
      }
      if (acceptedRaw is List) {
        for (final s in acceptedRaw) {
          final text = s.toString().trim();
          if (text.isNotEmpty) accepted.add(text);
        }
      }
      if (accepted.isNotEmpty) {
        payload['accepted_answers'] = accepted.toList(growable: false);
      }
    }

    if (normalizedType == 'error_correction') {
      if (payload['question']?.toString().trim().isEmpty ?? true) {
        final q =
            payload['prompt_text']?.toString() ??
            payload['instruction_en']?.toString() ??
            prompt['question_en']?.toString() ??
            prompt['question']?.toString() ??
            'Correct this sentence';
        payload['question'] = q;
      }

      if (payload['incorrect_sentence']?.toString().trim().isEmpty ?? true) {
        final sentence =
            payload['sentence']?.toString() ??
            prompt['sentence_zh']?.toString() ??
            prompt['text_zh']?.toString() ??
            '';
        if (sentence.trim().isNotEmpty) {
          payload['incorrect_sentence'] = sentence.trim();
        }
      }

      final accepted = <String>{};
      for (final key in const ['answer', 'correction', 'corrected_sentence']) {
        final raw = payload[key]?.toString().trim() ?? '';
        if (raw.isNotEmpty) accepted.add(raw);
      }
      final acceptedRaw = payload['accepted_answers'];
      if (acceptedRaw is List) {
        for (final s in acceptedRaw) {
          final text = s.toString().trim();
          if (text.isNotEmpty) accepted.add(text);
        }
      }
      if (accepted.isNotEmpty) {
        payload['accepted_answers'] = accepted.toList(growable: false);
      }
    }

    if (normalizedType == 'conversation_simulation') {
      final existingChoices = _extractOptions(payload);
      if (existingChoices.isNotEmpty) {
        payload['choices'] = existingChoices;
      }

      if (payload['question']?.toString().trim().isEmpty ?? true) {
        final q =
            payload['prompt_text']?.toString() ??
            payload['instruction_en']?.toString() ??
            payload['scenario']?.toString() ??
            payload['context']?.toString() ??
            prompt['context_en']?.toString() ??
            prompt['question_en']?.toString() ??
            prompt['question']?.toString() ??
            prompt['speaker_a_zh']?.toString() ??
            'Choose the best next reply';
        payload['question'] = q;
      }

      payload['answer_index'] ??= _extractAnswerIndex(payload) ?? 0;
    }

    if (normalizedType == 'character_writing') {
      if (payload['target_character']?.toString().trim().isEmpty ?? true) {
        final target =
            payload['hanzi']?.toString() ??
            prompt['hanzi']?.toString() ??
            prompt['word_zh']?.toString() ??
            '';
        if (target.trim().isNotEmpty) {
          payload['target_character'] = target.trim();
        }
      }
      payload['pinyin'] ??=
          prompt['pinyin']?.toString() ?? payload['prompt_pinyin']?.toString();
      payload['meaning'] ??=
          prompt['meaning']?.toString() ??
          payload['instruction_en']?.toString();
    }

    if (normalizedType == 'true_false') {
      final existingChoices = _extractOptions(payload);
      if (existingChoices.length < 2) {
        payload['choices'] = const ['True', 'False'];
      } else {
        payload['choices'] = existingChoices.take(2).toList(growable: false);
      }

      if (payload['answer_index'] == null) {
        final answerRaw = payload['answer'];
        int idx = 0;
        if (answerRaw is bool) {
          idx = answerRaw ? 0 : 1;
        } else if (answerRaw != null) {
          final s = answerRaw.toString().trim().toLowerCase();
          if (s == 'true' || s == 't' || s == 'yes' || s == '1') {
            idx = 0;
          } else if (s == 'false' || s == 'f' || s == 'no' || s == '0') {
            idx = 1;
          } else {
            final options = _extractOptions(payload);
            final optionIdx = options.indexWhere(
              (o) => o.trim().toLowerCase() == s,
            );
            if (optionIdx >= 0) idx = optionIdx;
          }
        }
        payload['answer_index'] = idx;
      }
    }

    if (normalizedType == 'speak_read_aloud' ||
        normalizedType == 'speak_prompted_reply') {
      final samples = payload['sample_answers'];
      if (samples is! List || samples.isEmpty) {
        final fallback = <String>[
          prompt['hanzi']?.toString() ?? '',
          payload['answer']?.toString() ?? '',
        ].where((v) => v.trim().isNotEmpty).toList();
        if (fallback.isNotEmpty) payload['sample_answers'] = fallback;
      }
    }

    return payload;
  }

  String? _resolvedPromptText(PilotExerciseItem item, BrainExercise ex) {
    final promptText = item.promptText?.trim();
    if (promptText != null && promptText.isNotEmpty) return promptText;
    final promptMap = (ex.payload['prompt'] as Map?)?.cast<String, dynamic>();
    final candidates = <String?>[
      ex.payload['prompt_text']?.toString(),
      ex.payload['scenario']?.toString(),
      ex.payload['context']?.toString(),
      ex.payload['question']?.toString(),
      ex.payload['instruction_en']?.toString(),
      ex.payload['instruction_zh']?.toString(),
      promptMap?['scenario_en']?.toString(),
      promptMap?['scenario']?.toString(),
      promptMap?['question']?.toString(),
      promptMap?['question_en']?.toString(),
      promptMap?['context_en']?.toString(),
      promptMap?['context']?.toString(),
      promptMap?['task_en']?.toString(),
      promptMap?['speaker_a_zh']?.toString(),
    ];
    for (final candidate in candidates) {
      if (candidate != null && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return null;
  }

  String? _derivePromptText(
    BrainExercise ex,
    String normalizedType,
    Map<String, dynamic> payload,
    Map<String, dynamic> prompt,
  ) {
    if (normalizedType == 'speak_prompted_reply') {
      return _extractSpeakingPromptText(ex);
    }
    final candidates = <String?>[
      payload['statement']?.toString(),
      payload['scenario']?.toString(),
      payload['context']?.toString(),
      payload['question']?.toString(),
      payload['prompt_text']?.toString(),
      payload['instruction_en']?.toString(),
      prompt['statement']?.toString(),
      prompt['scenario_en']?.toString(),
      prompt['scenario']?.toString(),
      prompt['question']?.toString(),
      prompt['question_en']?.toString(),
      prompt['context_en']?.toString(),
      prompt['context']?.toString(),
      prompt['task_en']?.toString(),
      prompt['speaker_a_zh']?.toString(),
    ];
    for (final candidate in candidates) {
      if (candidate != null && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return null;
  }

  int _conceptIdFromWord(String wordId) {
    final numeric = RegExp(r'\d+').firstMatch(wordId)?.group(0);
    if (numeric != null) {
      final parsed = int.tryParse(numeric);
      if (parsed != null) return parsed;
    }
    return wordId.hashCode & 0x7fffffff;
  }

  String? _subInstructionFor(BrainExercise ex) {
    if (ex.type == 'reading_micro' || ex.type == 'reading_span_select') {
      return 'Answer the short questions below.';
    }
    if (ex.type == 'reverse_recall') {
      return 'Type the target answer.';
    }
    if (ex.type == 'error_correction') {
      return 'Fix the sentence by typing the corrected version.';
    }
    if (ex.type == 'character_writing') {
      return 'Practice writing the target character.';
    }
    if (ex.type == 'conversation_simulation') {
      return 'Choose the best line to continue the conversation.';
    }
    if (_isSpeakingExercise(ex)) {
      return 'Record your voice. We check it automatically.';
    }
    return null;
  }

  String _skillForFocus(String focus) {
    switch (focus.toLowerCase()) {
      case 'listening':
        return 'listening';
      case 'speaking':
        return 'speaking';
      case 'reading':
        return 'reading';
      case 'grammar':
        return 'grammar';
      default:
        return 'vocab';
    }
  }

  List<String> _extractOptions(Map<String, dynamic> payload) {
    final choices = payload['choices'];
    if (choices is List) {
      return choices
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();
    }
    final options = payload['options'];
    if (options is List) {
      final out = <String>[];
      for (final option in options) {
        if (option == null) continue;
        if (option is String) {
          final text = option.trim();
          if (text.isNotEmpty) out.add(text);
          continue;
        }
        if (option is Map) {
          final m = option.cast<String, dynamic>();
          final text =
              m['text']?.toString() ??
              m['label']?.toString() ??
              m['value']?.toString() ??
              '';
          if (text.trim().isNotEmpty) out.add(text.trim());
        }
      }
      return out;
    }
    return [];
  }

  int? _extractAnswerIndex(Map<String, dynamic> payload) {
    final answerIndex = payload['answer_index'];
    if (answerIndex is int) return answerIndex;
    if (answerIndex is String) {
      return int.tryParse(answerIndex);
    }
    final answerText = payload['answer']?.toString();
    if (answerText != null && answerText.trim().isNotEmpty) {
      final options = _extractOptions(payload);
      final idx = options.indexWhere((o) => o.trim() == answerText.trim());
      if (idx >= 0) return idx;
    }
    return null;
  }

  List<String> _extractSampleAnswers(
    Map<String, dynamic> payload, {
    List<String> fallback = const [],
  }) {
    final samples = payload['sample_answers'];
    if (samples is List) {
      final values = samples
          .map((e) => e.toString())
          .where((s) => s.isNotEmpty)
          .toList();
      if (values.isNotEmpty) return values;
    }
    return fallback.isNotEmpty ? fallback : const [];
  }

  String _extractSpeakingPromptText(BrainExercise ex) {
    final promptMap = (ex.payload['prompt'] as Map?)?.cast<String, dynamic>();
    final candidates = <String?>[
      ex.payload['prompt_text']?.toString(),
      ex.payload['instruction_en']?.toString(),
      ex.payload['instruction_zh']?.toString(),
      promptMap?['instruction']?.toString(),
      promptMap?['meaning']?.toString(),
    ];
    for (final candidate in candidates) {
      if (candidate != null && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return 'Respond aloud';
  }

  PilotWhy? _extractWhy(Map<String, dynamic> payload) {
    final raw = payload['why'];
    if (raw is Map) {
      return PilotWhy.fromJson(raw.cast<String, dynamic>());
    }
    return null;
  }

  PilotWhy _resolveWhy(BrainExercise ex) {
    final existing = _extractWhy(ex.payload);
    if (existing != null) return existing;

    final policy = _adaptivePolicyMap();
    final hsk1Pack = (_controller.missionMetadata?['hsk1_pack'] as Map?)
        ?.cast<String, dynamic>();
    final mode =
        policy?['learning_mode']?.toString() ??
        policy?['mode']?.toString() ??
        'normal';
    final modeReason =
        policy?['learning_mode_reason']?.toString() ??
        policy?['mode_reason']?.toString() ??
        'selected by deterministic planner';
    final circleId = hsk1Pack?['circle_id']?.toString();

    final reasons = <String>[
      'Picked to strengthen ${_labelForSkill(_effectiveSkill(ex)).toLowerCase()}.',
      'Planner mode: $mode ($modeReason).',
      if (circleId != null && circleId.isNotEmpty)
        'Circle $circleId scope is active for this mission.',
      'No random generation at runtime; this follows the contract.',
    ];

    return PilotWhy(
      reasons: reasons,
      reasonCodes: const ['fallback_explain'],
      signals: PilotWhySignals(skillTarget: _effectiveSkill(ex)),
    );
  }

  Widget? _buildMediaSlot(BrainExercise ex) {
    if (_isSpeakingExercise(ex)) return null;
    final normalizedType = PracticeExerciseEngine.normalizeType(ex.type);
    final inlineAudioTypes = <String>{
      'audio_select',
      'dictation_select',
      'listen_write',
    };
    final imageUrl = _resolveImageUrl(ex.payload['image_url']?.toString());
    final audioUrl = _resolveAudioUrl(ex.payload['audio_url']?.toString());
    final showImage = imageUrl != null && imageUrl.isNotEmpty;
    final showAudio =
        audioUrl != null &&
        audioUrl.isNotEmpty &&
        !inlineAudioTypes.contains(normalizedType);
    if (!showImage && !showAudio) return null;
    return ExerciseMediaSlot(
      imageUrl: imageUrl,
      audioUrl: audioUrl,
      showImagePlaceholder: false,
      showAudio: showAudio,
      enableAudio: true,
    );
  }

  bool _isSpeakingExercise(BrainExercise ex) {
    return ex.type == 'speak_read_aloud' ||
        ex.type == 'speak_prompted_reply' ||
        ex.type == 'speaking';
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

  void _resetSpeakingState() {
    _speakingIsRecording = false;
    _speakingRecording = null;
    _speakingRating = null;
    _speakingScore = null;
    _speakingSubmitInFlight = false;
  }

  void _syncSpeakingStateForCurrentExercise() {
    final ex = _controller.currentExercise;
    final marker = ex?.exerciseId;
    if (marker == _speakingExerciseMarker) return;
    _speakingExerciseMarker = marker;
    _resetSpeakingState();
    if (ex != null && _isSpeakingExercise(ex)) {
      _refreshSpeakingPermission();
    }
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
    // Optimistic UI update so the button reacts instantly.
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
    final ex = _controller.currentExercise;
    final expected = _expectedSpeakingAnswers(ex);
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
    unawaited(_completeSpeaking());
  }

  void _setSpeakingRating(SpeakingRating rating) {
    setState(() => _speakingRating = rating);
    if (!_speakingIsRecording) {
      unawaited(_completeSpeaking());
    }
  }

  List<String> _expectedSpeakingAnswers(BrainExercise? ex) {
    if (ex == null) return const [];
    final out = <String>{};
    for (final a in _extractSampleAnswers(ex.payload)) {
      final v = a.trim();
      if (v.isNotEmpty) out.add(v);
    }
    final prompt =
        (ex.payload['prompt'] as Map?)?.cast<String, dynamic>() ?? {};
    final hanzi = prompt['hanzi']?.toString().trim() ?? '';
    final pinyin = prompt['pinyin']?.toString().trim() ?? '';
    if (hanzi.isNotEmpty) out.add(hanzi);
    if (pinyin.isNotEmpty) out.add(pinyin);

    final answerRaw = ex.payload['answer'];
    if (answerRaw is String && answerRaw.trim().isNotEmpty) {
      out.add(answerRaw.trim());
    }
    return out.toList();
  }
}
