import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dragon_chinese/features/course/engine/practice_exercise_engine.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/exercise_shell.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/multiple_choice_exercise.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/speaking_exercise.dart';
import 'package:dragon_chinese/design_system/exercise_theme.dart';

class ExerciseDebugGalleryScreen extends StatefulWidget {
  static const String routeName = '/debug/exercises';

  const ExerciseDebugGalleryScreen({super.key});

  @override
  State<ExerciseDebugGalleryScreen> createState() =>
      _ExerciseDebugGalleryScreenState();
}

enum _DebugGalleryFilter {
  all,
  passage,
  selection,
  sequence,
  matching,
  speaking,
}

class _ExerciseDebugGalleryScreenState
    extends State<ExerciseDebugGalleryScreen> {
  _DebugGalleryFilter _filter = _DebugGalleryFilter.all;

  List<_DebugExerciseKind> _visibleItems() {
    final enabled = _DebugExerciseKind.values
        .where(
          (kind) =>
              PracticeExerciseEngine.isSessionEnabledType(kind.exerciseType),
        )
        .toList(growable: false);
    if (_filter == _DebugGalleryFilter.all) return enabled;
    return enabled
        .where((kind) => kind.matchesFilter(_filter))
        .toList(growable: false);
  }

  String _filterLabel(_DebugGalleryFilter filter) {
    switch (filter) {
      case _DebugGalleryFilter.all:
        return 'All';
      case _DebugGalleryFilter.passage:
        return 'Passage';
      case _DebugGalleryFilter.selection:
        return 'Selection';
      case _DebugGalleryFilter.sequence:
        return 'Sequence';
      case _DebugGalleryFilter.matching:
        return 'Matching';
      case _DebugGalleryFilter.speaking:
        return 'Speaking';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(
        body: Center(
          child: Text('Debug route is available only in debug mode.'),
        ),
      );
    }

    final items = _visibleItems();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercise Debug Gallery'),
        backgroundColor: ExerciseThemeTokens.background,
        actions: [
          IconButton(
            tooltip: 'Intake validator',
            icon: const Icon(Icons.rule_folder_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const _ExerciseIntakeValidatorScreen(),
                ),
              );
            },
          ),
        ],
      ),
      backgroundColor: ExerciseThemeTokens.background,
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              children: _DebugGalleryFilter.values
                  .map((filter) {
                    final selected = _filter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_filterLabel(filter)),
                        selected: selected,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final kind = items[index];
                return Card(
                  elevation: 0,
                  color: ExerciseThemeTokens.surface,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: ExerciseThemeTokens.border),
                  ),
                  child: ListTile(
                    title: Text(
                      kind.label,
                      style: ExerciseThemeTokens.promptBody,
                    ),
                    subtitle: Text(
                      '${kind.description}\n${kind.exerciseType}',
                      style: ExerciseThemeTokens.caption,
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: ExerciseThemeTokens.textMuted,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              _ExerciseDebugPreviewScreen(kind: kind),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

enum _DebugExerciseKind {
  flashcard,
  characterWriting,
  trueFalse,
  reverseRecall,
  errorCorrection,
  meaningSelect,
  characterSelect,
  pinyinSelect,
  replySelect,
  conversationSimulation,
  audioSelect,
  dictationSelect,
  listenWrite,
  clozeSelect,
  orderSentence,
  meaningMatch,
  audioMatch,
  readingMicro,
  readingSpanSelect,
  speakReadAloud,
  speakPromptedReply,
}

extension on _DebugExerciseKind {
  String get exerciseType {
    switch (this) {
      case _DebugExerciseKind.flashcard:
        return 'flashcard';
      case _DebugExerciseKind.characterWriting:
        return 'character_writing';
      case _DebugExerciseKind.trueFalse:
        return 'true_false';
      case _DebugExerciseKind.reverseRecall:
        return 'reverse_recall';
      case _DebugExerciseKind.errorCorrection:
        return 'error_correction';
      case _DebugExerciseKind.meaningSelect:
        return 'meaning_select';
      case _DebugExerciseKind.characterSelect:
        return 'character_select';
      case _DebugExerciseKind.pinyinSelect:
        return 'pinyin_select';
      case _DebugExerciseKind.replySelect:
        return 'reply_select';
      case _DebugExerciseKind.conversationSimulation:
        return 'conversation_simulation';
      case _DebugExerciseKind.audioSelect:
        return 'audio_select';
      case _DebugExerciseKind.dictationSelect:
        return 'dictation_select';
      case _DebugExerciseKind.listenWrite:
        return 'listen_write';
      case _DebugExerciseKind.clozeSelect:
        return 'cloze_select';
      case _DebugExerciseKind.orderSentence:
        return 'order_sentence';
      case _DebugExerciseKind.meaningMatch:
        return 'meaning_match';
      case _DebugExerciseKind.audioMatch:
        return 'audio_match';
      case _DebugExerciseKind.readingMicro:
        return 'reading_micro';
      case _DebugExerciseKind.readingSpanSelect:
        return 'reading_span_select';
      case _DebugExerciseKind.speakReadAloud:
        return 'speak_read_aloud';
      case _DebugExerciseKind.speakPromptedReply:
        return 'speak_prompted_reply';
    }
  }

  bool matchesFilter(_DebugGalleryFilter filter) {
    if (filter == _DebugGalleryFilter.all) return true;
    final contract = PracticeExerciseEngine.contractFor(exerciseType);
    if (contract == null) return false;
    switch (filter) {
      case _DebugGalleryFilter.all:
        return true;
      case _DebugGalleryFilter.passage:
        return contract.family == ExerciseTemplateFamily.passage;
      case _DebugGalleryFilter.selection:
        return contract.family == ExerciseTemplateFamily.selection;
      case _DebugGalleryFilter.sequence:
        return contract.family == ExerciseTemplateFamily.sequence;
      case _DebugGalleryFilter.matching:
        return contract.family == ExerciseTemplateFamily.matching;
      case _DebugGalleryFilter.speaking:
        return contract.family == ExerciseTemplateFamily.speaking;
    }
  }

  String get label {
    switch (this) {
      case _DebugExerciseKind.flashcard:
        return 'Flashcard';
      case _DebugExerciseKind.characterWriting:
        return 'Character Writing';
      case _DebugExerciseKind.trueFalse:
        return 'True / False';
      case _DebugExerciseKind.reverseRecall:
        return 'Reverse Recall';
      case _DebugExerciseKind.errorCorrection:
        return 'Error Correction';
      case _DebugExerciseKind.meaningSelect:
        return 'Meaning Select';
      case _DebugExerciseKind.characterSelect:
        return 'Character Select';
      case _DebugExerciseKind.pinyinSelect:
        return 'Pinyin Select';
      case _DebugExerciseKind.replySelect:
        return 'Reply Select';
      case _DebugExerciseKind.conversationSimulation:
        return 'Conversation Simulation';
      case _DebugExerciseKind.audioSelect:
        return 'Audio Select';
      case _DebugExerciseKind.dictationSelect:
        return 'Dictation Select';
      case _DebugExerciseKind.listenWrite:
        return 'Listen & Write';
      case _DebugExerciseKind.clozeSelect:
        return 'Cloze Select';
      case _DebugExerciseKind.orderSentence:
        return 'Order Sentence';
      case _DebugExerciseKind.meaningMatch:
        return 'Meaning Match';
      case _DebugExerciseKind.audioMatch:
        return 'Audio Match';
      case _DebugExerciseKind.readingMicro:
        return 'Reading Micro';
      case _DebugExerciseKind.readingSpanSelect:
        return 'Reading Span Select';
      case _DebugExerciseKind.speakReadAloud:
        return 'Speak Read Aloud';
      case _DebugExerciseKind.speakPromptedReply:
        return 'Speak Prompted Reply';
    }
  }

  String get description {
    switch (this) {
      case _DebugExerciseKind.flashcard:
        return 'Card view for quick recognition';
      case _DebugExerciseKind.characterWriting:
        return 'Grid-based writing skeleton';
      case _DebugExerciseKind.trueFalse:
        return 'Binary statement check';
      case _DebugExerciseKind.reverseRecall:
        return 'Type answer from prompt';
      case _DebugExerciseKind.errorCorrection:
        return 'Reorder to correct sentence';
      case _DebugExerciseKind.meaningSelect:
        return 'Choose meaning for Hanzi';
      case _DebugExerciseKind.characterSelect:
        return 'Choose characters for meaning';
      case _DebugExerciseKind.pinyinSelect:
        return 'Choose the correct pinyin';
      case _DebugExerciseKind.replySelect:
        return 'Pick a reply in context';
      case _DebugExerciseKind.conversationSimulation:
        return 'Choose next turn in dialogue';
      case _DebugExerciseKind.audioSelect:
        return 'Listening MCQ with audio';
      case _DebugExerciseKind.dictationSelect:
        return 'Sentence dictation MCQ';
      case _DebugExerciseKind.listenWrite:
        return 'Transcribe audio into text';
      case _DebugExerciseKind.clozeSelect:
        return 'Fill the blank';
      case _DebugExerciseKind.orderSentence:
        return 'Reorder chunks';
      case _DebugExerciseKind.meaningMatch:
        return 'Match pairs';
      case _DebugExerciseKind.audioMatch:
        return 'Match audio to words';
      case _DebugExerciseKind.readingMicro:
        return 'Short reading + question';
      case _DebugExerciseKind.readingSpanSelect:
        return 'Read passage and pick answer';
      case _DebugExerciseKind.speakReadAloud:
        return 'Read aloud';
      case _DebugExerciseKind.speakPromptedReply:
        return 'Prompted reply';
    }
  }
}

class _ExerciseDebugPreviewScreen extends StatefulWidget {
  final _DebugExerciseKind kind;

  const _ExerciseDebugPreviewScreen({required this.kind});

  @override
  State<_ExerciseDebugPreviewScreen> createState() =>
      _ExerciseDebugPreviewScreenState();
}

class _ExerciseDebugPreviewScreenState
    extends State<_ExerciseDebugPreviewScreen> {
  int? _selectedIndex;
  bool _isAnswered = false;
  bool _isCorrect = false;
  int _attemptsRemaining = 3;
  final List<String> _orderChunks = const ['我', '喜欢', '学习'];
  final List<String> _orderAnswer = const ['我', '喜欢', '学习'];
  List<String> _orderBuildResult = []; // Separate build result
  final List<String> _errorCorrectionChunks = const [
    'He',
    'to',
    'school.',
    'goes',
  ];
  final List<String> _errorCorrectionAnswer = const [
    'He',
    'goes',
    'to',
    'school.',
  ];
  List<String> _errorCorrectionBuildResult = [];
  bool _matchReady = false;
  bool _matchCorrect = false;
  bool _showPinyin = false;
  bool _recording = false;
  SpeakingRating? _rating;
  String _typedAnswer = '';

  void _check() {
    setState(() {
      _isAnswered = true;
      _isCorrect = _calcIsCorrect();
    });

    if (!_isCorrect && _attemptsRemaining > 0) {
      setState(() => _attemptsRemaining -= 1);
    }
  }

  void _tryAgain() {
    setState(() {
      _isAnswered = false;
      _selectedIndex = null;
      _typedAnswer = '';
      _orderBuildResult = const [];
      _errorCorrectionBuildResult = const [];
    });
  }

  void _continue() {
    Navigator.of(context).pop();
  }

  bool _calcIsCorrect() {
    switch (widget.kind) {
      case _DebugExerciseKind.flashcard:
      case _DebugExerciseKind.characterWriting:
        return true;
      case _DebugExerciseKind.reverseRecall:
        return _normalize(_typedAnswer) == _normalize('你好');
      case _DebugExerciseKind.listenWrite:
        return _normalize(_typedAnswer) == _normalize('我们今天学习中文。');
      case _DebugExerciseKind.errorCorrection:
        return _normalize(_errorCorrectionBuildResult.join(' ')) ==
            _normalize(_errorCorrectionAnswer.join(' '));
      case _DebugExerciseKind.orderSentence:
        return _orderBuildResult.join('|') == _orderAnswer.join('|');
      case _DebugExerciseKind.meaningMatch:
      case _DebugExerciseKind.audioMatch:
        return _matchReady && _matchCorrect;
      default:
        return _selectedIndex == 0;
    }
  }

  String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(
      RegExp(r'[\s\.,!?;:"\-\(\)\[\]\{\}/\\_`~@#\$%\^&\*\+=<>|]+'),
      '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSpeakingKind =
        widget.kind == _DebugExerciseKind.speakReadAloud ||
        widget.kind == _DebugExerciseKind.speakPromptedReply;
    final showPinyinHeader =
        widget.kind == _DebugExerciseKind.meaningSelect ||
        widget.kind == _DebugExerciseKind.characterSelect;
    return ExerciseShell(
      index: 0,
      total: 10,
      instruction: _instructionFor(widget.kind),
      skillLabel: _skillFor(widget.kind),
      skillIcon: _iconFor(widget.kind),
      levelLabel: 'L1',
      attemptsRemaining: _attemptsRemaining,
      attemptsTotal: 3,
      isAnswered: _isAnswered,
      isCorrect: _isCorrect,
      isReady: _isReady(),
      hideFooter: isSpeakingKind,
      bodyScrollable: false,
      mediaSlot: _mediaFor(widget.kind),
      hintBuilder: () => 'This is a hint for attempt #2.',
      revealBuilder: () => 'Correct: ${_correctTextFor(widget.kind)}',
      onExplain: () {},
      showSecondaryToggle: showPinyinHeader,
      secondaryToggleActive: _showPinyin,
      onToggleSecondary: showPinyinHeader
          ? () => setState(() => _showPinyin = !_showPinyin)
          : null,
      showSettingsMenu: true,
      onCheck: _check,
      onTryAgain: _tryAgain,
      onContinue: _continue,
      content: _buildContent(widget.kind),
    );
  }

  bool _isReady() {
    if (widget.kind == _DebugExerciseKind.orderSentence ||
        widget.kind == _DebugExerciseKind.meaningMatch ||
        widget.kind == _DebugExerciseKind.audioMatch) {
      return true;
    }
    if (widget.kind == _DebugExerciseKind.flashcard) {
      return true;
    }
    if (widget.kind == _DebugExerciseKind.characterWriting) {
      return true;
    }
    if (widget.kind == _DebugExerciseKind.speakReadAloud ||
        widget.kind == _DebugExerciseKind.speakPromptedReply) {
      return _rating != null;
    }
    if (widget.kind == _DebugExerciseKind.reverseRecall ||
        widget.kind == _DebugExerciseKind.listenWrite ||
        widget.kind == _DebugExerciseKind.errorCorrection) {
      if (widget.kind == _DebugExerciseKind.errorCorrection) {
        return _errorCorrectionBuildResult.length >=
            _errorCorrectionChunks.length;
      }
      return _typedAnswer.trim().isNotEmpty;
    }
    return _selectedIndex != null;
  }

  Widget? _mediaFor(_DebugExerciseKind kind) {
    if (kind == _DebugExerciseKind.audioSelect ||
        kind == _DebugExerciseKind.dictationSelect ||
        kind == _DebugExerciseKind.listenWrite) {
      return null;
    }
    if (kind == _DebugExerciseKind.speakReadAloud ||
        kind == _DebugExerciseKind.speakPromptedReply) {
      return null;
    }
    return null;
  }

  Widget _buildContent(_DebugExerciseKind kind) {
    switch (kind) {
      case _DebugExerciseKind.flashcard:
        return _DebugFlashcardView(
          front: '你好',
          pinyin: 'ni hao',
          back: 'hello',
        );
      case _DebugExerciseKind.characterWriting:
        return const CharacterWritingExercise(
          targetCharacter: '学',
          pinyin: 'xue',
          meaning: 'study',
        );
      case _DebugExerciseKind.trueFalse:
        return TrueFalseExercise(
          statement: 'The sentence means "hello".',
          // Keep payload-style mapping: choices are [True, False], so:
          // right button (check) selects index 0, left button (X) selects index 1.
          falseIndex: 1,
          trueIndex: 0,
          answerIndex: 0,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          onSelect: (index) => setState(() => _selectedIndex = index),
        );
      case _DebugExerciseKind.reverseRecall:
        return ClozeInputExercise(
          sentence: 'Type Chinese for "hello".',
          value: _typedAnswer,
          expectedAnswers: const ['你好'],
          isAnswered: _isAnswered,
          onChanged: (v) => setState(() => _typedAnswer = v),
        );
      case _DebugExerciseKind.errorCorrection:
        return OrderSentenceExercise(
          exerciseId: 'debug_error_correction_1',
          chunks: _errorCorrectionChunks,
          initialSelectedIndices: List<int>.generate(
            _errorCorrectionChunks.length,
            (index) => index,
            growable: false,
          ),
          showWordBankShadowForSelected: false,
          onChanged: (updated) =>
              setState(() => _errorCorrectionBuildResult = updated),
        );
      case _DebugExerciseKind.meaningSelect:
        return MeaningSelectExercise(
          hanzi: '你好',
          pinyin: 'ni hao',
          choices: const ['hello', 'thanks', 'sorry', 'bye'],
          answerIndex: 0,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          showPinyin: _showPinyin,
          onTogglePinyin: () => setState(() => _showPinyin = !_showPinyin),
          onSelect: (index) => setState(() => _selectedIndex = index),
        );
      case _DebugExerciseKind.characterSelect:
        return CharacterSelectExercise(
          meaning: 'to read',
          pinyin: 'du',
          choices: const ['读', '看', '写', '听'],
          answerIndex: 0,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          showPinyin: _showPinyin,
          onTogglePinyin: () => setState(() => _showPinyin = !_showPinyin),
          onSelect: (index) => setState(() => _selectedIndex = index),
        );
      case _DebugExerciseKind.pinyinSelect:
        return PinyinSelectExercise(
          hanzi: '好',
          choices: const ['hao', 'gao', 'kao', 'nao'],
          answerIndex: 0,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          onSelect: (index) => setState(() => _selectedIndex = index),
        );
      case _DebugExerciseKind.replySelect:
        return ReplySelectExercise(
          prompt: '你好',
          choices: const ['你好', '再见', '谢谢', '不客气'],
          answerIndex: 0,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          onSelect: (index) => setState(() => _selectedIndex = index),
        );
      case _DebugExerciseKind.conversationSimulation:
        return ConversationSimulationExercise(
          scenario: 'First meeting at an office reception.',
          speakerLine: '请问，您是新同事吗？',
          question: 'Choose the best next reply.',
          choices: const ['是的，你好！', '我不客气。', '再见。', '对不起。'],
          answerIndex: 0,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          onSelect: (index) => setState(() => _selectedIndex = index),
        );
      case _DebugExerciseKind.audioSelect:
        return AudioSelectExercise(
          audioUrl: null,
          choiceType: 'hanzi',
          choices: const ['你', '我', '他', '她'],
          answerIndex: 0,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          onSelect: (index) => setState(() => _selectedIndex = index),
        );
      case _DebugExerciseKind.dictationSelect:
        return DictationSelectExercise(
          audioUrl: null,
          promptText: 'Listen and choose the correct sentence',
          options: const ['我喜欢你。', '你喜欢我。', '我们学习。', '他们喝茶。'],
          answerIndex: 0,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          onSelect: (index) => setState(() => _selectedIndex = index),
        );
      case _DebugExerciseKind.listenWrite:
        return ClozeInputExercise(
          sentence: '',
          value: _typedAnswer,
          expectedAnswers: const ['我们今天学习中文。'],
          isAnswered: _isAnswered,
          showSentenceCard: false,
          inputHint: 'Type what you hear',
          onChanged: (v) => setState(() => _typedAnswer = v),
        );
      case _DebugExerciseKind.clozeSelect:
        return ClozeSelectExercise(
          sentence: '我喜欢____。',
          contextPassage: '昨天下午我们去了超市。我买了水果和牛奶，回家后做了晚饭。',
          contextMaxWords: 18,
          choices: const ['苹果', '读书', '看', '听'],
          answerIndex: 0,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          onSelect: (index) => setState(() => _selectedIndex = index),
        );
      case _DebugExerciseKind.orderSentence:
        return OrderSentenceExercise(
          exerciseId: 'debug_sentence_1',
          chunks: _orderChunks,
          onChanged: (updated) => setState(() => _orderBuildResult = updated),
        );
      case _DebugExerciseKind.meaningMatch:
        return MeaningMatchExercise(
          leftItems: const ['你好', '谢谢', '再见'],
          rightItems: const ['Hello', 'Thanks', 'Goodbye'],
          mapping: const [0, 1, 2],
          onStatus: (ready, correct) {
            setState(() {
              _matchReady = ready;
              _matchCorrect = correct;
            });
          },
        );
      case _DebugExerciseKind.audioMatch:
        return AudioMeaningMatchExercise(
          leftItems: const ['Audio 1', 'Audio 2', 'Audio 3'],
          leftAudioUrls: const ['', '', ''],
          rightItems: const ['Hello', 'Thanks', 'Goodbye'],
          mapping: const [0, 1, 2],
          onStatus: (ready, correct) {
            setState(() {
              _matchReady = ready;
              _matchCorrect = correct;
            });
          },
        );
      case _DebugExerciseKind.readingMicro:
        return ReadingMicroExercise(
          titleZh: '小故事',
          titleEn: 'Short story',
          storyZh: '我们今天学习中文。',
          storyEn: 'We study Chinese today.',
          questionIndex: 0,
          questions: const [
            {
              'type': 'detail_select',
              'prompt': {'question': 'What are we studying?'},
              'choices': ['Chinese', 'Math', 'Physics', 'Music'],
              'answer_index': 0,
            },
          ],
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          onSelect: (index) => setState(() => _selectedIndex = index),
        );
      case _DebugExerciseKind.readingSpanSelect:
        return ReadingSpanSelectExercise(
          passage: '我今天在公园跑步，然后去学校学习中文。',
          question: 'Where did I run?',
          choices: const [
            'At the park',
            'At the hospital',
            'At the airport',
            'At home',
          ],
          answerIndex: 0,
          selectedIndex: _selectedIndex,
          isAnswered: _isAnswered,
          onSelect: (index) => setState(() => _selectedIndex = index),
        );
      case _DebugExerciseKind.speakReadAloud:
        return SpeakReadAloudExercise(
          hanzi: '你好',
          pinyin: 'ni hao',
          sampleAnswers: const ['你好', '你好啊'],
          permissionGranted: true,
          isRecording: _recording,
          durationMs: _rating == null ? null : 1200,
          rating: _rating,
          onRequestPermission: () {},
          onStartRecording: () => setState(() => _recording = true),
          onStopRecording: () => setState(() => _recording = false),
          onRate: (rating) => setState(() => _rating = rating),
        );
      case _DebugExerciseKind.speakPromptedReply:
        return SpeakPromptedReplyExercise(
          promptText: '你好',
          sampleAnswers: const ['你好', '你好啊'],
          permissionGranted: true,
          isRecording: _recording,
          durationMs: _rating == null ? null : 1200,
          rating: _rating,
          onRequestPermission: () {},
          onStartRecording: () => setState(() => _recording = true),
          onStopRecording: () => setState(() => _recording = false),
          onRate: (rating) => setState(() => _rating = rating),
        );
    }
  }

  String _instructionFor(_DebugExerciseKind kind) {
    switch (kind) {
      case _DebugExerciseKind.flashcard:
        return 'Study the card';
      case _DebugExerciseKind.characterWriting:
        return 'Write the character';
      case _DebugExerciseKind.trueFalse:
        return 'True or False';
      case _DebugExerciseKind.reverseRecall:
        return 'Type the answer';
      case _DebugExerciseKind.errorCorrection:
        return 'Correct the sentence';
      case _DebugExerciseKind.meaningSelect:
        return 'Choose the meaning';
      case _DebugExerciseKind.characterSelect:
        return 'Choose the characters';
      case _DebugExerciseKind.pinyinSelect:
        return 'Choose the correct pinyin';
      case _DebugExerciseKind.replySelect:
        return 'Choose the best reply';
      case _DebugExerciseKind.conversationSimulation:
        return 'Choose the best next reply';
      case _DebugExerciseKind.audioSelect:
        return 'Choose the characters';
      case _DebugExerciseKind.dictationSelect:
        return 'Listen and choose the correct sentence';
      case _DebugExerciseKind.listenWrite:
        return 'Listen and write';
      case _DebugExerciseKind.clozeSelect:
        return 'Complete the sentence';
      case _DebugExerciseKind.orderSentence:
        return 'Order the sentence';
      case _DebugExerciseKind.meaningMatch:
        return 'Match the pairs';
      case _DebugExerciseKind.audioMatch:
        return 'Match audio to words';
      case _DebugExerciseKind.readingMicro:
        return 'Read the passage and answer';
      case _DebugExerciseKind.readingSpanSelect:
        return 'Read and select the answer';
      case _DebugExerciseKind.speakReadAloud:
        return 'Read aloud';
      case _DebugExerciseKind.speakPromptedReply:
        return 'Respond aloud';
    }
  }

  String _skillFor(_DebugExerciseKind kind) {
    switch (kind) {
      case _DebugExerciseKind.reverseRecall:
      case _DebugExerciseKind.errorCorrection:
      case _DebugExerciseKind.replySelect:
      case _DebugExerciseKind.conversationSimulation:
        return 'Production';
      case _DebugExerciseKind.flashcard:
      case _DebugExerciseKind.characterWriting:
      case _DebugExerciseKind.trueFalse:
      case _DebugExerciseKind.meaningSelect:
      case _DebugExerciseKind.characterSelect:
      case _DebugExerciseKind.pinyinSelect:
      case _DebugExerciseKind.meaningMatch:
      case _DebugExerciseKind.audioMatch:
        return 'Vocab';
      case _DebugExerciseKind.audioSelect:
      case _DebugExerciseKind.dictationSelect:
      case _DebugExerciseKind.listenWrite:
        return 'Listening';
      case _DebugExerciseKind.readingMicro:
      case _DebugExerciseKind.readingSpanSelect:
      case _DebugExerciseKind.clozeSelect:
        return 'Reading';
      case _DebugExerciseKind.orderSentence:
        return 'Grammar';
      case _DebugExerciseKind.speakReadAloud:
      case _DebugExerciseKind.speakPromptedReply:
        return 'Speaking';
    }
  }

  IconData _iconFor(_DebugExerciseKind kind) {
    switch (kind) {
      case _DebugExerciseKind.reverseRecall:
      case _DebugExerciseKind.errorCorrection:
      case _DebugExerciseKind.replySelect:
      case _DebugExerciseKind.conversationSimulation:
        return Icons.edit_rounded;
      case _DebugExerciseKind.flashcard:
      case _DebugExerciseKind.characterWriting:
      case _DebugExerciseKind.trueFalse:
      case _DebugExerciseKind.meaningSelect:
      case _DebugExerciseKind.characterSelect:
      case _DebugExerciseKind.pinyinSelect:
      case _DebugExerciseKind.meaningMatch:
      case _DebugExerciseKind.audioMatch:
        return Icons.translate_rounded;
      case _DebugExerciseKind.audioSelect:
      case _DebugExerciseKind.dictationSelect:
      case _DebugExerciseKind.listenWrite:
        return Icons.headphones_rounded;
      case _DebugExerciseKind.readingMicro:
      case _DebugExerciseKind.readingSpanSelect:
      case _DebugExerciseKind.clozeSelect:
        return Icons.menu_book_rounded;
      case _DebugExerciseKind.orderSentence:
        return Icons.auto_awesome_mosaic_outlined;
      case _DebugExerciseKind.speakReadAloud:
      case _DebugExerciseKind.speakPromptedReply:
        return Icons.mic_rounded;
    }
  }

  String _correctTextFor(_DebugExerciseKind kind) {
    switch (kind) {
      case _DebugExerciseKind.flashcard:
        return 'Card reviewed';
      case _DebugExerciseKind.characterWriting:
        return 'Character writing marked complete';
      case _DebugExerciseKind.trueFalse:
        return 'True';
      case _DebugExerciseKind.reverseRecall:
        return '你好';
      case _DebugExerciseKind.errorCorrection:
        return _errorCorrectionAnswer.join(' ');
      case _DebugExerciseKind.characterSelect:
        return '读';
      case _DebugExerciseKind.pinyinSelect:
        return 'hao';
      case _DebugExerciseKind.replySelect:
        return '你好';
      case _DebugExerciseKind.conversationSimulation:
        return '是的，你好！';
      case _DebugExerciseKind.audioSelect:
        return '你';
      case _DebugExerciseKind.dictationSelect:
        return '我喜欢你。';
      case _DebugExerciseKind.listenWrite:
        return '我们今天学习中文。';
      case _DebugExerciseKind.clozeSelect:
        return '苹果';
      case _DebugExerciseKind.readingMicro:
        return 'Chinese';
      case _DebugExerciseKind.readingSpanSelect:
        return 'At the park';
      case _DebugExerciseKind.audioMatch:
        return 'Audio 1 → Hello';
      default:
        return 'hello';
    }
  }
}

class _DebugFlashcardView extends StatefulWidget {
  final String front;
  final String pinyin;
  final String back;

  const _DebugFlashcardView({
    required this.front,
    required this.pinyin,
    required this.back,
  });

  @override
  State<_DebugFlashcardView> createState() => _DebugFlashcardViewState();
}

class _DebugFlashcardViewState extends State<_DebugFlashcardView> {
  bool _showBack = false;
  bool _flipFromRight = true;

  void _toggleFlip([TapDownDetails? details]) {
    if (details != null) {
      final box = context.findRenderObject() as RenderBox?;
      final local = details.localPosition;
      final width = box?.size.width ?? 0;
      if (width > 0) {
        _flipFromRight = local.dx >= (width / 2);
      }
    }
    setState(() => _showBack = !_showBack);
  }

  @override
  Widget build(BuildContext context) {
    final front = widget.front;
    final pinyin = widget.pinyin;
    final back = widget.back;
    final viewportHeight = MediaQuery.of(context).size.height;
    final stageHeight = (viewportHeight * 0.5).clamp(320.0, 540.0);
    final charCount = front.runes.length;
    final frontSize = charCount <= 2 ? 36.0 : (charCount <= 6 ? 32.0 : 28.0);
    final hasBack = back.trim().isNotEmpty;

    return SizedBox(
      height: stageHeight,
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 300, maxWidth: 430),
          child: AspectRatio(
            aspectRatio: 1.02,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: _toggleFlip,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: 0,
                  end: _showBack && hasBack ? 1 : 0,
                ),
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeInOutCubic,
                builder: (context, value, _) {
                  final angle = value * math.pi;
                  final isPastHalf = angle > (math.pi / 2);
                  final showFrontFace = !isPastHalf;
                  final adjusted = showFrontFace ? angle : angle - math.pi;
                  final signedAngle = (_flipFromRight ? 1.0 : -1.0) * adjusted;

                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0018)
                      ..rotateY(signedAngle),
                    child: _flashcardFace(
                      front: front,
                      pinyin: pinyin,
                      back: hasBack ? back.trim() : null,
                      frontSize: frontSize,
                      showFrontFace: showFrontFace || !hasBack,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _flashcardFace({
    required String front,
    required String pinyin,
    required String? back,
    required double frontSize,
    required bool showFrontFace,
  }) {
    return Container(
      width: double.infinity,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE3E8F1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: showFrontFace
            ? [
                Text(
                  front,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: frontSize,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827),
                  ),
                ),
                if (pinyin.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    pinyin.trim(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                ],
              ]
            : [
                Text(
                  back ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  front,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151),
                  ),
                ),
                if (pinyin.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    pinyin.trim(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ],
      ),
    );
  }
}

class _ExerciseIntakeValidatorScreen extends StatefulWidget {
  const _ExerciseIntakeValidatorScreen();

  @override
  State<_ExerciseIntakeValidatorScreen> createState() =>
      _ExerciseIntakeValidatorScreenState();
}

class _ExerciseIntakeValidatorScreenState
    extends State<_ExerciseIntakeValidatorScreen> {
  late final TextEditingController _controller;
  List<_ValidatedIntakeItem> _rows = const [];
  String? _parseError;
  int _validCount = 0;
  int _invalidCount = 0;
  int _unknownTypeCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _exampleValidatorJson);
    _validateNow();
    _controller.addListener(_validateNow);
  }

  @override
  void dispose() {
    _controller.removeListener(_validateNow);
    _controller.dispose();
    super.dispose();
  }

  void _loadExample() {
    _controller.text = _exampleValidatorJson;
    _validateNow();
  }

  void _loadPhraseClozePreset() {
    _controller.text = _phraseClozeValidatorJson;
    _validateNow();
  }

  void _validateNow() {
    try {
      final items = _parseAnyInputToItems(_controller.text);
      final rows = <_ValidatedIntakeItem>[];
      var valid = 0;
      var invalid = 0;
      var unknown = 0;

      for (final item in items) {
        final normalized = PracticeExerciseEngine.normalizeType(
          item.exerciseType,
        );
        final known = PracticeExerciseEngine.isKnownType(item.exerciseType);
        final contract = PracticeExerciseEngine.contractFor(item.exerciseType);
        final contractIssues = PracticeExerciseEngine.contractIssuesFor(
          item: item,
          resolvedPromptText: item.promptText,
        );
        final missingRequired = _extractMissingRequiredFromIssues(
          contractIssues,
        );
        final engineValid = PracticeExerciseEngine.isItemValid(
          item: item,
          resolvedPromptText: item.promptText,
        );

        final issues = <String>[...contractIssues];
        if (!engineValid) {
          issues.add('engine_validator_failed');
        }

        final row = _ValidatedIntakeItem(
          id: item.id,
          type: item.exerciseType,
          normalizedType: normalized,
          knownType: known,
          engineValid: engineValid,
          missingRequired: missingRequired,
          issues: issues,
          contractName: contract?.uiTemplate,
        );
        rows.add(row);

        if (!known) unknown += 1;
        if (issues.isEmpty) {
          valid += 1;
        } else {
          invalid += 1;
        }
      }

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _parseError = null;
        _validCount = valid;
        _invalidCount = invalid;
        _unknownTypeCount = unknown;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = const [];
        _parseError = e.toString();
        _validCount = 0;
        _invalidCount = 0;
        _unknownTypeCount = 0;
      });
    }
  }

  List<String> _extractMissingRequiredFromIssues(List<String> issues) {
    final out = <String>[];
    for (final issue in issues) {
      if (!issue.startsWith('missing_required: ')) continue;
      final tail = issue.substring('missing_required: '.length);
      for (final part in tail.split(',')) {
        final key = part.trim();
        if (key.isNotEmpty) out.add(key);
      }
    }
    return out.toSet().toList(growable: false);
  }

  List<PilotExerciseItem> _parseAnyInputToItems(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Input JSON is empty');
    }
    final decoded = jsonDecode(trimmed);
    final rawItems = _extractRawItems(decoded);
    if (rawItems.isEmpty) {
      throw const FormatException('No exercises found in provided JSON');
    }
    return rawItems.map(PilotExerciseItem.fromJson).toList(growable: false);
  }

  List<Map<String, dynamic>> _extractRawItems(dynamic decoded) {
    if (decoded is List) {
      final out = <Map<String, dynamic>>[];
      for (var i = 0; i < decoded.length; i++) {
        final row = decoded[i];
        if (row is! Map) continue;
        final map = row.cast<String, dynamic>();
        if (_looksPilotLike(map)) {
          out.add(_ensurePilotDefaults(map, i + 1));
        } else if (_looksUnitExercise(map)) {
          out.add(_convertUnitExerciseToPilot(map, i + 1));
        }
      }
      return out;
    }

    if (decoded is Map) {
      final root = decoded.cast<String, dynamic>();
      final items = root['items'];
      if (items is List) {
        return _extractRawItems(items);
      }

      final circles = root['circles'];
      if (circles is List) {
        final out = <Map<String, dynamic>>[];
        var idx = 1;
        for (final circle in circles) {
          if (circle is! Map) continue;
          final exercises = circle['exercises'];
          if (exercises is! List) continue;
          for (final ex in exercises) {
            if (ex is! Map) continue;
            out.add(
              _convertUnitExerciseToPilot(ex.cast<String, dynamic>(), idx),
            );
            idx += 1;
          }
        }
        return out;
      }

      final exercises = root['exercises'];
      if (exercises is List) {
        return _extractRawItems(exercises);
      }

      if (_looksPilotLike(root)) {
        return [_ensurePilotDefaults(root, 1)];
      }
      if (_looksUnitExercise(root)) {
        return [_convertUnitExerciseToPilot(root, 1)];
      }
    }

    return const [];
  }

  bool _looksPilotLike(Map<String, dynamic> map) {
    return map.containsKey('exercise_type') || map.containsKey('template_id');
  }

  bool _looksUnitExercise(Map<String, dynamic> map) {
    return map.containsKey('type') || map.containsKey('exercise_id');
  }

  Map<String, dynamic> _ensurePilotDefaults(
    Map<String, dynamic> input,
    int idx,
  ) {
    final map = Map<String, dynamic>.from(input);
    map['id'] = (map['id']?.toString().trim().isNotEmpty == true)
        ? map['id'].toString()
        : 'intake_item_$idx';
    map['exercise_type'] =
        map['exercise_type']?.toString() ??
        map['type']?.toString() ??
        'meaning_select';
    map['prompt'] = (map['prompt'] is Map<String, dynamic>)
        ? map['prompt']
        : <String, dynamic>{};
    map['choices'] = _asStringList(map['choices']);
    map['answer_index'] = _deriveAnswerIndex(
      map['answer_index'],
      map['choices'],
    );
    map['payload'] = (map['payload'] is Map<String, dynamic>)
        ? map['payload']
        : <String, dynamic>{};
    map['meta'] = (map['meta'] is Map<String, dynamic>)
        ? map['meta']
        : <String, dynamic>{'hsk_level': 1, 'tags': <String>[]};
    return map;
  }

  Map<String, dynamic> _convertUnitExerciseToPilot(
    Map<String, dynamic> ex,
    int idx,
  ) {
    final prompt = (ex['prompt'] is Map)
        ? Map<String, dynamic>.from(ex['prompt'] as Map)
        : <String, dynamic>{};
    final payload = (ex['payload'] is Map)
        ? Map<String, dynamic>.from(ex['payload'] as Map)
        : <String, dynamic>{};

    for (final entry in prompt.entries) {
      payload.putIfAbsent(entry.key, () => entry.value);
    }

    final type =
        ex['exercise_type']?.toString() ??
        ex['type']?.toString() ??
        'meaning_select';
    final choices = _asStringList(ex['choices']);
    final answerIndex = _deriveUnitAnswerIndex(ex, choices);

    final promptText = _firstNonEmpty([
      ex['instruction_en']?.toString(),
      prompt['question_en']?.toString(),
      prompt['task_en']?.toString(),
      prompt['context_en']?.toString(),
      payload['question']?.toString(),
      payload['prompt']?.toString(),
    ]);

    payload.putIfAbsent(
      'sentence',
      () => _firstNonEmpty([
        prompt['sentence_zh']?.toString(),
        prompt['sentence']?.toString(),
        prompt['text_zh']?.toString(),
        prompt['text']?.toString(),
      ]),
    );

    if ((type == 'order_sentence' || type == 'sentence_building') &&
        payload['chunks'] == null) {
      final tokens = prompt['tokens'];
      if (tokens is List) {
        payload['chunks'] = _asStringList(tokens);
      }
    }

    final unitAnswer = ex['answer'];
    if (payload['answer'] == null && unitAnswer != null) {
      payload['answer'] = unitAnswer;
    }
    final accepted = ex['accepted_answers'];
    if (payload['accepted_answers'] == null && accepted is List) {
      payload['accepted_answers'] = accepted;
    }

    Map<String, dynamic>? reading;
    List<Map<String, dynamic>> questions = const [];
    if (type == 'reading_micro' ||
        type == 'passage_select' ||
        type == 'read_select_passage') {
      final storyZh = _firstNonEmpty([
        prompt['text_zh']?.toString(),
        prompt['passage_zh']?.toString(),
        prompt['story_zh']?.toString(),
        prompt['text']?.toString(),
      ]);
      final storyEn = _firstNonEmpty([
        prompt['text_en']?.toString(),
        prompt['passage_en']?.toString(),
        prompt['story_en']?.toString(),
      ]);
      if (storyZh.isNotEmpty || storyEn.isNotEmpty) {
        reading = <String, dynamic>{
          'title_zh': '',
          'title_en': '',
          'story_zh': storyZh,
          'story_en': storyEn,
        };
      }
      if (choices.isNotEmpty) {
        questions = [
          <String, dynamic>{
            'type': 'detail_select',
            'prompt': <String, dynamic>{
              'question': _firstNonEmpty([
                prompt['question_en']?.toString(),
                prompt['question']?.toString(),
                promptText,
              ]),
            },
            'choices': choices,
            'answer_index': answerIndex,
          },
        ];
      }
    }

    return <String, dynamic>{
      'id': ex['exercise_id']?.toString() ?? 'intake_item_$idx',
      'exercise_type': type,
      'prompt_text': promptText.isEmpty ? null : promptText,
      'prompt': <String, dynamic>{
        'hanzi': _firstNonEmpty([
          prompt['hanzi']?.toString(),
          prompt['word_zh']?.toString(),
          prompt['text_zh']?.toString(),
          prompt['speaker_a_zh']?.toString(),
          payload['front']?.toString(),
        ]),
        'pinyin': _firstNonEmpty([
          prompt['pinyin']?.toString(),
          prompt['pronunciation']?.toString(),
          payload['pinyin']?.toString(),
        ]),
        'meaning': _firstNonEmpty([
          prompt['meaning']?.toString(),
          prompt['translation']?.toString(),
          prompt['question_en']?.toString(),
          prompt['task_en']?.toString(),
          payload['back']?.toString(),
        ]),
      },
      'choices': choices,
      'answer_index': answerIndex,
      'payload': payload,
      if (reading != null) 'reading': reading,
      if (questions.isNotEmpty) 'questions': questions,
      'meta': <String, dynamic>{'hsk_level': 1, 'tags': <String>[]},
    };
  }

  List<String> _asStringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList(growable: false);
  }

  int _deriveAnswerIndex(dynamic rawAnswerIndex, dynamic rawChoices) {
    final choices = _asStringList(rawChoices);
    if (rawAnswerIndex is int) {
      return rawAnswerIndex;
    }
    return choices.isEmpty ? 0 : 0;
  }

  int _deriveUnitAnswerIndex(Map<String, dynamic> ex, List<String> choices) {
    final rawIdx = ex['answer_index'];
    if (rawIdx is int) return rawIdx;
    final answer = ex['answer']?.toString();
    if (answer != null && answer.isNotEmpty) {
      final idx = choices.indexOf(answer);
      if (idx >= 0) return idx;
    }
    return 0;
  }

  String _firstNonEmpty(List<String?> candidates) {
    for (final value in candidates) {
      final text = value?.trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercise Intake Validator'),
        backgroundColor: ExerciseThemeTokens.background,
      ),
      backgroundColor: ExerciseThemeTokens.background,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ExerciseThemeTokens.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ExerciseThemeTokens.border),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _statChip('Items', _rows.length, const Color(0xFF4B5563)),
                  _statChip('Valid', _validCount, const Color(0xFF166534)),
                  _statChip('Invalid', _invalidCount, const Color(0xFFB91C1C)),
                  _statChip(
                    'Unknown Type',
                    _unknownTypeCount,
                    const Color(0xFF92400E),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              flex: 4,
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  labelText: 'Paste exercise JSON / unit JSON',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loadExample,
                    icon: const Icon(Icons.data_array),
                    label: const Text('Load Example'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loadPhraseClozePreset,
                    icon: const Icon(Icons.short_text_rounded),
                    label: const Text('Load Phrase Cloze'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _validateNow,
                icon: const Icon(Icons.rule),
                label: const Text('Validate Now'),
              ),
            ),
            const SizedBox(height: 12),
            if (_parseError != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Text(
                  _parseError!,
                  style: const TextStyle(
                    color: Color(0xFF991B1B),
                    fontSize: 12,
                  ),
                ),
              ),
            Expanded(
              flex: 5,
              child: ListView.builder(
                itemCount: _rows.length,
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  final ok = row.issues.isEmpty;
                  return Card(
                    color: ok
                        ? const Color(0xFFF0FDF4)
                        : const Color(0xFFFEF2F2),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${row.id}  (${row.type} -> ${row.normalizedType})',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'known=${row.knownType} valid=${row.engineValid} template=${row.contractName ?? 'n/a'}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          if (row.missingRequired.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'missing required: ${row.missingRequired.join(', ')}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF991B1B),
                              ),
                            ),
                          ],
                          if (row.issues.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              row.issues.join(' | '),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF7F1D1D),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, int value, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

class _ValidatedIntakeItem {
  final String id;
  final String type;
  final String normalizedType;
  final bool knownType;
  final bool engineValid;
  final List<String> missingRequired;
  final List<String> issues;
  final String? contractName;

  const _ValidatedIntakeItem({
    required this.id,
    required this.type,
    required this.normalizedType,
    required this.knownType,
    required this.engineValid,
    required this.missingRequired,
    required this.issues,
    required this.contractName,
  });
}

const String _exampleValidatorJson = '''
{
  "unit_id": "UNIT_DEMO_001",
  "circles": [
    {
      "circle_id": "C1",
      "exercises": [
        {
          "exercise_id": "E1",
          "type": "meaning_select",
          "instruction_en": "Choose the meaning.",
          "prompt": { "word_zh": "你好", "question_en": "Choose the meaning" },
          "choices": ["hello", "thanks", "bye"],
          "answer": "hello"
        },
        {
          "exercise_id": "E2",
          "type": "sentence_building",
          "prompt": { "tokens": ["I", "like", "math"] },
          "answer": "I like math"
        },
        {
          "exercise_id": "E3",
          "type": "speak_read_aloud",
          "prompt": { "text": "Hydrogen" },
          "accepted_answers": ["Hydrogen"]
        }
      ]
    }
  ]
}
''';

const String _phraseClozeValidatorJson = '''
{
  "items": [
    {
      "id": "cloze_phrase_001",
      "exercise_type": "cloze_select",
      "prompt_text": "Choose the best phrase to complete the sentence.",
      "prompt": {
        "hanzi": "今天下午我们____。",
        "pinyin": "Jintian xiawu women ____.",
        "meaning": "This afternoon we ____."
      },
      "choices": [
        "去公园散步",
        "在家睡觉",
        "看一部电影",
        "写作业"
      ],
      "answer_index": 0,
      "payload": {
        "sentence": "今天下午我们____。",
        "blank_mode": "phrase",
        "choice_mode": "phrase",
        "response_mode": "single_tap",
        "context_passage": "今天天气很好。我们打算先吃午饭，然后去公园散步。",
        "max_context_words": 26
      },
      "meta": {
        "hsk_level": 1,
        "tags": ["cloze", "phrase", "passage"]
      }
    },
    {
      "id": "cloze_phrase_002",
      "exercise_type": "cloze_select",
      "prompt_text": "Pick the phrase that best fits the blank.",
      "prompt": {
        "hanzi": "老师说：明天早上____。",
        "pinyin": "Laoshi shuo: mingtian zaoshang ____.",
        "meaning": "The teacher said: Tomorrow morning ____."
      },
      "choices": [
        "八点集合",
        "天气很好",
        "我很喜欢",
        "你在做什么"
      ],
      "answer_index": 0,
      "payload": {
        "sentence": "老师说：明天早上____。",
        "blank_mode": "phrase",
        "choice_mode": "phrase",
        "variant": "phrase_select",
        "context_passage": "老师通知我们，明天有活动。大家要准时到学校门口。",
        "max_context_words": 24
      },
      "meta": {
        "hsk_level": 2,
        "tags": ["cloze", "phrase", "short_context"]
      }
    }
  ]
}
''';
