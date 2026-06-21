import 'package:flutter/material.dart';
import 'package:dragon_chinese/features/course/engine/practice_exercise_engine.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/services/pilot_exercise_pack_loader.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/multiple_choice_exercise.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/explain_panel.dart';
import 'package:dragon_chinese/core/config/app_config.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/exercise_shell.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/exercise_media.dart';
import 'package:dragon_chinese/features/course/services/local_mastery_tracker.dart';
import 'package:dragon_chinese/features/course/services/speaking_evaluator.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/speaking_exercise.dart';
import 'package:dragon_chinese/features/course/services/speaking_notebook.dart';
import 'package:dragon_chinese/features/course/services/speaking_recorder.dart';
import 'package:dragon_chinese/features/course/screens/practice_summary_screen.dart';

class PilotExerciseRunnerScreen extends StatefulWidget {
  const PilotExerciseRunnerScreen({super.key});

  @override
  State<PilotExerciseRunnerScreen> createState() =>
      _PilotExerciseRunnerScreenState();
}

class _PilotExerciseRunnerScreenState extends State<PilotExerciseRunnerScreen> {
  final _loader = PilotExercisePackLoader();
  LocalMasteryTracker? _mastery;
  SpeakingNotebook? _speakingNotebook;
  final SpeakingRecorder _speakingRecorder = SpeakingRecorderService.instance;
  bool _speakingPermissionGranted = true;
  bool _speakingIsRecording = false;
  SpeakingRecording? _speakingRecording;
  SpeakingRating? _speakingRating;
  double? _speakingScore;
  bool _speakingSubmitInFlight = false;
  PilotExercisePack? _pack;
  String? _error;
  int _currentIndex = 0;
  int? _selectedIndex;
  bool _isAnswered = false;
  bool _showPinyin = false;
  int _readingQuestionIndex = 0;
  List<String> _orderChunks = [];
  List<String> _orderAnswer = [];
  bool _matchReady = false;
  bool _matchCorrect = false;
  int _attemptsRemaining = 0;
  int _attemptsAllowed = 0;
  final List<PracticeAttempt> _attempts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pack = await _loader.loadPack();
      final mastery = await LocalMasteryTracker.load();
      final speakingNotebook = await SpeakingNotebook.load();
      setState(() {
        _pack = pack;
        _mastery = mastery;
        _speakingNotebook = speakingNotebook;
        _error = null;
      });
      _resetItemState();
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  PilotExerciseItem? get _currentItem {
    if (_pack == null) return null;
    if (_currentIndex >= _pack!.items.length) return null;
    return _pack!.items[_currentIndex];
  }

  void _next() {
    final item = _currentItem;
    if (item == null) return;

    if (_isAnswered && !_isSpeaking(item)) {
      final correct = _isCorrect(item);
      _mastery?.recordAttempt(
        conceptId: item.conceptId,
        skillBucket: LocalMasteryTracker.skillBucketForExercise(
          item.exerciseType,
        ),
        isCorrect: correct,
        isExamMode: false,
        isTimed:
            item.timeLimitMs != null || (item.constraints.timedSec ?? 0) > 0,
      );
      _mastery?.save();
      _attempts.add(PracticeAttempt(skill: item.skill, isCorrect: correct));
    }

    if (item.exerciseType == 'reading_micro') {
      final questions = item.questions;
      if (_readingQuestionIndex < questions.length - 1) {
        setState(() {
          _readingQuestionIndex += 1;
          _selectedIndex = null;
          _isAnswered = false;
          _attemptsRemaining = _attemptsAllowed;
        });
        return;
      }
    }

    setState(() {
      _currentIndex += 1;
    });
    _resetItemState();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(body: Center(child: Text('Error loading pack: $_error')));
    }
    if (_pack == null) {
      return const ExerciseLoadingSkeleton();
    }

    final item = _currentItem;
    if (item == null) {
      return PracticeSummaryScreen(
        attempts: _attempts,
        onDrillAgain: _restartPractice,
      );
    }

    if (!_isItemValid(item)) {
      return ExerciseShell(
        index: _currentIndex,
        total: _pack!.items.length,
        sectionLabel: _labelForSkill(item.skill),
        skillLabel: _labelForSkill(item.skill),
        skillIcon: _iconForSkill(item.skill),
        instruction: 'This exercise cannot load',
        subInstruction: 'The item is missing required fields.',
        levelLabel: 'L${item.level}',
        attemptsRemaining: _attemptsRemaining,
        attemptsTotal: _attemptsAllowed,
        isAnswered: false,
        isCorrect: false,
        isReady: true,
        explainLabel: 'Explain',
        onExplain: item.why == null
            ? null
            : () => ExplainButton.showExplain(context, item.why!),
        showSecondaryToggle: false,
        showSettingsMenu: true,
        primaryLabelOverride: 'Skip',
        onPrimaryOverride: _skipCurrentItem,
        content: const ExerciseUnavailableCard(
          message: 'This item is missing required content. It will be skipped.',
        ),
        onCheck: () {},
        onTryAgain: () {},
        onContinue: _next,
      );
    }

    if (_attemptsAllowed == 0) {
      final allowed = item.attemptsAllowed;
      _attemptsAllowed = allowed < 1 ? 1 : allowed;
      _attemptsRemaining = _attemptsAllowed;
    }
    final isSpeakingItem = _isSpeaking(item);
    final supportsHeaderPinyin =
        PracticeExerciseEngine.supportsHeaderPinyinToggle(item);

    return ExerciseShell(
      index: _currentIndex,
      total: _pack!.items.length,
      sectionLabel: _labelForSkill(item.skill),
      skillLabel: _labelForSkill(item.skill),
      skillIcon: _iconForSkill(item.skill),
      instruction: _instructionFor(item),
      subInstruction: _subInstructionFor(item),
      levelLabel: 'L${item.level}',
      attemptsRemaining: _attemptsRemaining,
      attemptsTotal: _attemptsAllowed,
      isAnswered: isSpeakingItem ? false : _isAnswered,
      isCorrect: isSpeakingItem ? false : _isCorrect(item),
      isReady: isSpeakingItem
          ? (_speakingRating != null)
          : ((item.exerciseType == 'meaning_match' ||
                    item.exerciseType == 'audio_match')
                ? _matchReady
                : _selectedIndex != null ||
                      item.exerciseType == 'order_sentence'),
      hideFooter: isSpeakingItem,
      // Keep options docked just above footer CTA across exercise types.
      bodyScrollable: false,
      explainLabel: 'Explain',
      onExplain: item.why == null
          ? null
          : () => ExplainButton.showExplain(context, item.why!),
      showSecondaryToggle: supportsHeaderPinyin,
      secondaryToggleActive: _showPinyin,
      onToggleSecondary: supportsHeaderPinyin
          ? () => setState(() => _showPinyin = !_showPinyin)
          : null,
      showSettingsMenu: true,
      mediaSlot: _buildMediaSlot(item),
      hintBuilder: () => _buildHint(item),
      revealBuilder: () => _buildReveal(item),
      onCheck: () {
        final correct = _isCorrect(item);
        if (!correct && _attemptsRemaining > 0) {
          _attemptsRemaining -= 1;
        }
        setState(() => _isAnswered = true);
      },
      onTryAgain: () {
        setState(() {
          _selectedIndex = null;
          _isAnswered = false;
        });
      },
      onContinue: _next,
      content: _buildExercise(item),
    );
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
    final isSpeaking = _isSpeaking(item);
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

  Widget _buildExercise(PilotExerciseItem item) {
    switch (item.exerciseType) {
      case 'meaning_select':
        return MeaningSelectExercise(
          hanzi: item.prompt.hanzi ?? '',
          pinyin: item.prompt.pinyin,
          choices: item.choices,
          answerIndex: item.answerIndex,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          showPinyin: _showPinyin,
          onTogglePinyin: () => setState(() => _showPinyin = !_showPinyin),
          onSelect: (index) => setState(() {
            _selectedIndex = index;
          }),
        );
      case 'character_select':
        return CharacterSelectExercise(
          meaning: item.prompt.meaning ?? '',
          pinyin: item.prompt.pinyin,
          choices: item.choices,
          answerIndex: item.answerIndex,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          showPinyin: _showPinyin,
          onTogglePinyin: () => setState(() => _showPinyin = !_showPinyin),
          onSelect: (index) => setState(() {
            _selectedIndex = index;
          }),
        );
      case 'audio_select':
        return AudioSelectExercise(
          audioUrl: _resolveAudioUrl(item.audioUrl),
          choiceType: item.choiceType ?? 'hanzi',
          choices: item.choices,
          answerIndex: item.answerIndex,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          onSelect: (index) => setState(() {
            _selectedIndex = index;
          }),
          showPrompt: false,
        );
      case 'dictation_select':
        return DictationSelectExercise(
          audioUrl: _resolveAudioUrl(item.audioUrl),
          promptText:
              item.promptText ?? 'Listen and choose the correct sentence',
          options: item.options.isNotEmpty
              ? item.options.map((o) => o.text).toList()
              : item.choices,
          answerIndex: item.answerIndex,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          onSelect: (index) => setState(() {
            _selectedIndex = index;
          }),
          showPrompt: false,
        );
      case 'cloze_select':
        final sentence =
            item.payload['sentence']?.toString() ??
            item.payload['text']?.toString() ??
            item.payload['stem']?.toString() ??
            item.payload['prompt']?.toString() ??
            '';
        final contextPassage =
            item.payload['context_passage']?.toString() ??
            item.payload['passage_context']?.toString() ??
            item.payload['context']?.toString() ??
            item.payload['paragraph']?.toString();
        final maxContextWordsRaw = item.payload['max_context_words'];
        final maxContextWords = maxContextWordsRaw is int
            ? (maxContextWordsRaw > 0 ? maxContextWordsRaw : null)
            : (maxContextWordsRaw is String
                  ? int.tryParse(maxContextWordsRaw.trim())
                  : null);
        final phraseModeValue =
            item.payload['blank_mode']?.toString().toLowerCase() ??
            item.payload['choice_mode']?.toString().toLowerCase() ??
            item.payload['variant']?.toString().toLowerCase() ??
            item.payload['response_mode']?.toString().toLowerCase();
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
          choices: item.choices,
          answerIndex: item.answerIndex,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          onSelect: (index) => setState(() => _selectedIndex = index),
        );
      case 'order_sentence':
        final chunks = (item.payload['chunks'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        final answer = (item.payload['answer'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        if (_orderAnswer.isEmpty) {
          _orderAnswer = List<String>.from(answer);
        }
        return OrderSentenceExercise(
          chunks: chunks,
          onChanged: (updated) => setState(() => _orderChunks = updated),
        );
      case 'meaning_match':
        final left = (item.payload['left'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        final right = (item.payload['right'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        final mapping = (item.payload['mapping'] as List<dynamic>? ?? [])
            .map((e) => e as int)
            .toList();
        return MeaningMatchExercise(
          leftItems: left,
          rightItems: right,
          mapping: mapping,
          onStatus: (ready, correct) {
            setState(() {
              _matchReady = ready;
              _matchCorrect = correct;
            });
          },
        );
      case 'audio_match':
        final right = (item.payload['right'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        final left = (item.payload['left'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        final leftAudio =
            (item.payload['left_audio_urls'] as List<dynamic>? ??
                    item.payload['audio_urls'] as List<dynamic>? ??
                    const [])
                .map((e) => e.toString())
                .toList();
        final mapping = (item.payload['mapping'] as List<dynamic>? ?? [])
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
          onStatus: (ready, correct) {
            setState(() {
              _matchReady = ready;
              _matchCorrect = correct;
            });
          },
        );
      case 'reading_micro':
        return _buildReadingMicro(item);
      case 'speak_read_aloud':
        final samples = (item.payload['sample_answers'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        return SpeakReadAloudExercise(
          hanzi: item.prompt.hanzi ?? '',
          pinyin: item.prompt.pinyin,
          meaning: item.prompt.meaning,
          sampleAnswers: samples,
          permissionGranted: _speakingPermissionGranted,
          isRecording: _speakingIsRecording,
          durationMs: _speakingRecording?.durationMs,
          rating: _speakingRating,
          transcript: _speakingRecording?.transcript,
          score: _speakingScore,
          onRequestPermission: _requestSpeakingPermission,
          onStartRecording: _startSpeakingRecording,
          onStopRecording: _stopSpeakingRecording,
          onRate: _setSpeakingRating,
        );
      case 'speak_prompted_reply':
        final samples = (item.payload['sample_answers'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        return SpeakPromptedReplyExercise(
          promptText: item.promptText ?? 'Respond aloud',
          meaning: item.prompt.meaning,
          sampleAnswers: samples,
          permissionGranted: _speakingPermissionGranted,
          isRecording: _speakingIsRecording,
          durationMs: _speakingRecording?.durationMs,
          rating: _speakingRating,
          transcript: _speakingRecording?.transcript,
          score: _speakingScore,
          onRequestPermission: _requestSpeakingPermission,
          onStartRecording: _startSpeakingRecording,
          onStopRecording: _stopSpeakingRecording,
          onRate: _setSpeakingRating,
        );
      case 'pinyin_select':
        return PinyinSelectExercise(
          hanzi: item.prompt.hanzi ?? '',
          choices: item.choices,
          answerIndex: item.answerIndex,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          onSelect: (index) => setState(() => _selectedIndex = index),
        );
      case 'reply_select':
        return ReplySelectExercise(
          prompt: item.promptText ?? (item.prompt.hanzi ?? ''),
          choices: item.choices,
          answerIndex: item.answerIndex,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          onSelect: (index) => setState(() => _selectedIndex = index),
        );
      default:
        return Center(child: Text('Unsupported exercise ${item.exerciseType}'));
    }
  }

  Widget _buildReadingMicro(PilotExerciseItem item) {
    final reading = item.reading;
    final questions = item.questions;
    if (reading == null || questions.isEmpty) {
      return const Center(child: Text('Reading content missing'));
    }
    return ReadingMicroExercise(
      titleZh: reading.titleZh,
      titleEn: reading.titleEn,
      storyZh: reading.storyZh,
      storyEn: reading.storyEn,
      questionIndex: _readingQuestionIndex,
      questions: questions
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
      onSelect: (index) => setState(() => _selectedIndex = index),
    );
  }

  bool _isCorrect(PilotExerciseItem item) {
    if (item.exerciseType == 'reading_micro') {
      final question = item.questions[_readingQuestionIndex];
      return _selectedIndex == question.answerIndex;
    }
    if (item.exerciseType == 'order_sentence') {
      return _orderChunks.join('|') == _orderAnswer.join('|');
    }
    if (item.exerciseType == 'meaning_match') {
      return _matchReady && _matchCorrect;
    }
    if (item.exerciseType == 'audio_match') {
      return _matchReady && _matchCorrect;
    }
    return _selectedIndex == item.answerIndex;
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

  String? _resolveAudioUrl(String? audioUrl) {
    if (audioUrl == null || audioUrl.isEmpty) return null;
    if (audioUrl.startsWith('http')) return audioUrl;
    if (audioUrl.startsWith('/')) {
      return '${AppConfig.apiBaseUrl}$audioUrl';
    }
    return audioUrl;
  }

  void _skipCurrentItem() {
    setState(() {
      _currentIndex += 1;
      _selectedIndex = null;
      _isAnswered = false;
      _showPinyin = false;
      _readingQuestionIndex = 0;
      _orderChunks = [];
      _orderAnswer = [];
      _matchReady = false;
      _matchCorrect = false;
      _attemptsRemaining = 0;
      _attemptsAllowed = 0;
    });
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
    if (imageUrl == null || imageUrl.isEmpty) return null;
    if (imageUrl.startsWith('http') || imageUrl.startsWith('assets/')) {
      return imageUrl;
    }
    if (imageUrl.startsWith('/')) {
      return '${AppConfig.apiBaseUrl}$imageUrl';
    }
    return imageUrl;
  }

  void _restartPractice() {
    setState(() {
      _currentIndex = 0;
      _attempts.clear();
    });
    _resetItemState();
  }

  bool _isSpeaking(PilotExerciseItem item) {
    return item.exerciseType == 'speak_read_aloud' ||
        item.exerciseType == 'speak_prompted_reply' ||
        item.exerciseType == 'speaking';
  }

  void _resetItemState() {
    _selectedIndex = null;
    _isAnswered = false;
    _showPinyin = false;
    _readingQuestionIndex = 0;
    _orderChunks = [];
    _orderAnswer = [];
    _matchReady = false;
    _matchCorrect = false;
    _attemptsRemaining = 0;
    _attemptsAllowed = 0;
    _resetSpeakingState();
    final item = _currentItem;
    if (item != null && _isSpeaking(item)) {
      _refreshSpeakingPermission();
    }
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
      final recording = _speakingRecording;
      final durationMs = recording?.durationMs ?? 0;
      final isCorrect = rating != SpeakingRating.needsWork;
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
      _mastery?.recordAttempt(
        conceptId: item.conceptId,
        skillBucket: LocalMasteryTracker.skillBucketForExercise(
          item.exerciseType,
        ),
        isCorrect: isCorrect,
        isExamMode: false,
        isTimed: false,
      );
      _mastery?.save();
      _attempts.add(PracticeAttempt(skill: item.skill, isCorrect: isCorrect));
      _next();
    } finally {
      _speakingSubmitInFlight = false;
    }
  }
}
