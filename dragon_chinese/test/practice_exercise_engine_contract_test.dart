import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/engine/practice_exercise_engine.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';

PilotExerciseItem _item({
  required String type,
  List<String> choices = const ['True', 'False'],
  int answerIndex = 0,
  Map<String, dynamic> payload = const {},
}) {
  return PilotExerciseItem.fromJson({
    'id': 'test_$type',
    'exercise_type': type,
    'prompt_text': 'Is this statement true?',
    'prompt': {
      'hanzi': '这是对的吗？',
      'pinyin': 'zhè shì duì de ma',
      'meaning': 'Is this correct?',
    },
    'choices': choices,
    'answer_index': answerIndex,
    'payload': payload,
    'meta': {'hsk_level': 1, 'tags': []},
  });
}

const _state = PracticeExerciseUiState(
  selectedIndex: null,
  textAnswer: '',
  isAnswered: false,
  showPinyin: false,
  readingQuestionIndex: 0,
  orderChunks: [],
  orderAnswer: [],
  matchReady: false,
  matchCorrect: false,
  speakingPermissionGranted: false,
  speakingIsRecording: false,
  speakingRecording: null,
  speakingRating: null,
  speakingScore: null,
);

const _stateTypedHello = PracticeExerciseUiState(
  selectedIndex: null,
  textAnswer: 'hello',
  isAnswered: false,
  showPinyin: false,
  readingQuestionIndex: 0,
  orderChunks: [],
  orderAnswer: [],
  matchReady: false,
  matchCorrect: false,
  speakingPermissionGranted: false,
  speakingIsRecording: false,
  speakingRecording: null,
  speakingRating: null,
  speakingScore: null,
);

const _stateCorrectedSentence = PracticeExerciseUiState(
  selectedIndex: null,
  textAnswer: 'He goes to school.',
  isAnswered: false,
  showPinyin: false,
  readingQuestionIndex: 0,
  orderChunks: [],
  orderAnswer: [],
  matchReady: false,
  matchCorrect: false,
  speakingPermissionGranted: false,
  speakingIsRecording: false,
  speakingRecording: null,
  speakingRating: null,
  speakingScore: null,
);

const _stateMatchReadyCorrect = PracticeExerciseUiState(
  selectedIndex: null,
  textAnswer: '',
  isAnswered: false,
  showPinyin: false,
  readingQuestionIndex: 0,
  orderChunks: [],
  orderAnswer: [],
  matchReady: true,
  matchCorrect: true,
  speakingPermissionGranted: false,
  speakingIsRecording: false,
  speakingRecording: null,
  speakingRating: null,
  speakingScore: null,
);

final _callbacks = PracticeExerciseCallbacks(
  onSelectIndex: (_) {},
  onTextChanged: (_) {},
  onTogglePinyin: () {},
  onOrderChanged: (_) {},
  onMatchStatus: (_, __) {},
  onRequestSpeakingPermission: () {},
  onStartSpeakingRecording: () {},
  onStopSpeakingRecording: () {},
  onSetSpeakingRating: (_) {},
);

void main() {
  test('normalizes engine aliases for legacy/new variants', () {
    expect(
      PracticeExerciseEngine.normalizeType('sentence_fill'),
      'cloze_select',
    );
    expect(
      PracticeExerciseEngine.normalizeType('passage_select'),
      'reading_micro',
    );
    expect(
      PracticeExerciseEngine.normalizeType('read_select_passage'),
      'reading_micro',
    );
    expect(
      PracticeExerciseEngine.normalizeType('read_and_select_in_passage'),
      'reading_span_select',
    );
    expect(
      PracticeExerciseEngine.normalizeType('error_correction'),
      'error_correction',
    );
    expect(
      PracticeExerciseEngine.normalizeType('conversation_simulation'),
      'conversation_simulation',
    );
    expect(
      PracticeExerciseEngine.normalizeType('character_writing'),
      'character_writing',
    );
    expect(PracticeExerciseEngine.normalizeType('tone_select'), 'flashcard');
    expect(
      PracticeExerciseEngine.normalizeType('multiple_choice'),
      'meaning_select',
    );
    expect(PracticeExerciseEngine.normalizeType('mcq'), 'meaning_select');
    expect(
      PracticeExerciseEngine.normalizeType('single_select'),
      'meaning_select',
    );
    expect(
      PracticeExerciseEngine.normalizeType('fill_in_blank'),
      'cloze_select',
    );
    expect(
      PracticeExerciseEngine.normalizeType('sentence_blank_select'),
      'cloze_select',
    );
    expect(
      PracticeExerciseEngine.normalizeType('context_cloze_select'),
      'cloze_select',
    );
    expect(
      PracticeExerciseEngine.normalizeType('passage_blank_select'),
      'cloze_select',
    );
    expect(
      PracticeExerciseEngine.normalizeType('phrase_blank_select'),
      'cloze_select',
    );
    expect(
      PracticeExerciseEngine.normalizeType('clause_blank_select'),
      'cloze_select',
    );
    expect(
      PracticeExerciseEngine.normalizeType('sentence_building'),
      'order_sentence',
    );
    expect(PracticeExerciseEngine.normalizeType('pair_match'), 'meaning_match');
    expect(
      PracticeExerciseEngine.normalizeType('listen_and_choose'),
      'audio_select',
    );
    expect(
      PracticeExerciseEngine.normalizeType('listen_and_write'),
      'listen_write',
    );
    expect(
      PracticeExerciseEngine.normalizeType('dictation_input'),
      'listen_write',
    );
    expect(
      PracticeExerciseEngine.normalizeType('short_answer'),
      'reverse_recall',
    );
    expect(
      PracticeExerciseEngine.normalizeType('pronunciation_read_aloud'),
      'speak_read_aloud',
    );
  });

  test('PilotPrompt parses generic cross-subject keys', () {
    final prompt = PilotPrompt.fromJson({
      'text': 'Hydrogen',
      'pronunciation': 'HY-druh-jen',
      'definition': 'A chemical element',
    });
    expect(prompt.hanzi, 'Hydrogen');
    expect(prompt.pinyin, 'HY-druh-jen');
    expect(prompt.meaning, 'A chemical element');
  });

  test('supports and validates true_false contract', () {
    final item = _item(
      type: 'true_false',
      payload: {'statement': 'The sky is blue.'},
    );

    expect(PracticeExerciseEngine.isKnownType(item.exerciseType), isTrue);
    expect(
      PracticeExerciseEngine.isItemValid(item: item, resolvedPromptText: null),
      isTrue,
    );
    expect(
      PracticeExerciseEngine.instructionFor(
        item: item,
        resolvedPromptText: null,
      ),
      'True or False',
    );
  });

  test('delegates reading_span_select to core engine', () {
    final item = _item(
      type: 'read_and_select_in_passage',
      choices: const ['I go to school.', 'I go to the park.'],
      answerIndex: 0,
      payload: {
        'passage': '我去学校学习。',
        'question': 'Which sentence matches the passage?',
      },
    );

    expect(
      PracticeExerciseEngine.normalizeType(item.exerciseType),
      'reading_span_select',
    );
    expect(PracticeExerciseEngine.isKnownType(item.exerciseType), isTrue);
    expect(
      PracticeExerciseEngine.isItemValid(item: item, resolvedPromptText: null),
      isTrue,
    );
    expect(
      PracticeExerciseEngine.instructionFor(
        item: item,
        resolvedPromptText: null,
      ),
      'Read and select the answer',
    );

    final selectedState = PracticeExerciseUiState(
      selectedIndex: 0,
      textAnswer: '',
      isAnswered: false,
      showPinyin: false,
      readingQuestionIndex: 0,
      orderChunks: const [],
      orderAnswer: const [],
      matchReady: false,
      matchCorrect: false,
      speakingPermissionGranted: false,
      speakingIsRecording: false,
      speakingRecording: null,
      speakingRating: null,
      speakingScore: null,
    );
    expect(
      PracticeExerciseEngine.isReady(item: item, state: selectedState),
      isTrue,
    );
    expect(
      PracticeExerciseEngine.isCorrect(item: item, state: selectedState),
      isTrue,
    );
  });

  test('fails reading_span_select contract when passage is missing', () {
    final item = _item(
      type: 'reading_span_select',
      choices: const ['A', 'B'],
      answerIndex: 0,
      payload: const {'question': 'Pick from passage'},
    );

    expect(
      PracticeExerciseEngine.isItemValid(item: item, resolvedPromptText: null),
      isFalse,
    );
  });

  test('supports flashcard as first-class renderer', () {
    final item = _item(
      type: 'flashcard',
      choices: const [],
      payload: {'front': '你好', 'back': 'hello', 'pinyin': 'ni hao'},
    );

    expect(PracticeExerciseEngine.isKnownType(item.exerciseType), isTrue);
    expect(
      PracticeExerciseEngine.isItemValid(item: item, resolvedPromptText: null),
      isTrue,
    );
    expect(PracticeExerciseEngine.isReady(item: item, state: _state), isTrue);
    expect(PracticeExerciseEngine.isCorrect(item: item, state: _state), isTrue);
    expect(PracticeExerciseEngine.revealFor(item), contains('Meaning:'));
  });

  test('flashcard validation supports generic payload keys', () {
    final item = PilotExerciseItem.fromJson({
      'id': 'test_flash_generic',
      'exercise_type': 'flashcard',
      'prompt': {'text': 'Neuron'},
      'choices': const [],
      'answer_index': 0,
      'payload': {
        'term': 'Neuron',
        'definition': 'A nerve cell that transmits signals.',
      },
      'meta': {'hsk_level': 1, 'tags': []},
    });

    expect(PracticeExerciseEngine.isKnownType(item.exerciseType), isTrue);
    expect(
      PracticeExerciseEngine.isItemValid(item: item, resolvedPromptText: null),
      isTrue,
    );
    expect(PracticeExerciseEngine.revealFor(item), contains('Meaning:'));
  });

  test('buildExercise returns concrete widgets for new core types', () {
    final tf = _item(type: 'true_false', payload: {'statement': 'Test'});
    final flash = _item(
      type: 'tone_select',
      choices: const [],
      payload: {'front': '好', 'back': 'good', 'pinyin': 'hǎo'},
    );

    final tfWidget = PracticeExerciseEngine.buildExercise(
      item: tf,
      state: _state,
      callbacks: _callbacks,
      resolvedPromptText: 'Is this true?',
    );
    final flashWidget = PracticeExerciseEngine.buildExercise(
      item: flash,
      state: _state,
      callbacks: _callbacks,
      resolvedPromptText: null,
    );

    expect(tfWidget, isNotNull);
    expect(flashWidget, isNotNull);
  });

  test('supports reading_span_select contract and renderer', () {
    final item = _item(
      type: 'reading_span_select',
      choices: const ['A', 'B', 'C'],
      answerIndex: 1,
      payload: {'passage': '我今天去学校。', 'question': 'Where did I go?'},
    );

    expect(PracticeExerciseEngine.isKnownType(item.exerciseType), isTrue);
    expect(
      PracticeExerciseEngine.isItemValid(item: item, resolvedPromptText: null),
      isTrue,
    );
    expect(
      PracticeExerciseEngine.instructionFor(
        item: item,
        resolvedPromptText: null,
      ),
      'Read and select the answer',
    );

    final widget = PracticeExerciseEngine.buildExercise(
      item: item,
      state: _state,
      callbacks: _callbacks,
      resolvedPromptText: null,
    );
    expect(widget, isNotNull);
  });

  test('supports audio_match contract and renderer', () {
    final item = _item(
      type: 'audio_match',
      choices: const [],
      payload: {
        'left': ['Audio 1', 'Audio 2'],
        'left_audio_urls': ['https://example.com/a1.mp3', ''],
        'right': ['Hello', 'Thanks'],
        'mapping': [0, 1],
      },
    );

    expect(PracticeExerciseEngine.isKnownType(item.exerciseType), isTrue);
    expect(
      PracticeExerciseEngine.isItemValid(item: item, resolvedPromptText: null),
      isTrue,
    );
    expect(
      PracticeExerciseEngine.instructionFor(
        item: item,
        resolvedPromptText: null,
      ),
      'Match audio to words',
    );
    expect(
      PracticeExerciseEngine.isReady(
        item: item,
        state: _stateMatchReadyCorrect,
      ),
      isTrue,
    );
    expect(
      PracticeExerciseEngine.isCorrect(
        item: item,
        state: _stateMatchReadyCorrect,
      ),
      isTrue,
    );

    final widget = PracticeExerciseEngine.buildExercise(
      item: item,
      state: _state,
      callbacks: _callbacks,
      resolvedPromptText: null,
    );
    expect(widget, isNotNull);
  });

  test('contractIssuesFor flags missing mapping for meaning_match', () {
    final item = _item(
      type: 'meaning_match',
      choices: const [],
      payload: {
        'left': ['你好', '谢谢'],
        'right': ['Hello', 'Thanks'],
      },
    );

    final issues = PracticeExerciseEngine.contractIssuesFor(
      item: item,
      resolvedPromptText: null,
    );
    expect(issues, contains('mapping_missing'));
    expect(
      PracticeExerciseEngine.isItemValid(item: item, resolvedPromptText: null),
      isFalse,
    );
  });

  test('isItemValid fails audio_match when mapping is incomplete', () {
    final item = _item(
      type: 'audio_match',
      choices: const [],
      payload: {
        'left': ['Audio 1', 'Audio 2'],
        'left_audio_urls': [
          'https://example.com/a1.mp3',
          'https://example.com/a2.mp3',
        ],
        'right': ['Hello', 'Thanks'],
        // Missing one mapping target on purpose.
        'mapping': [0],
      },
    );

    expect(
      PracticeExerciseEngine.isItemValid(item: item, resolvedPromptText: null),
      isFalse,
    );
  });

  test('contractIssuesFor flags unknown type', () {
    final item = _item(
      type: 'non_existing_type',
      choices: const [],
      payload: const {},
    );

    final issues = PracticeExerciseEngine.contractIssuesFor(
      item: item,
      resolvedPromptText: null,
    );
    expect(issues, contains('unknown_exercise_type'));
  });

  test('supports reverse_recall text flow', () {
    final item = _item(
      type: 'reverse_recall',
      choices: const [],
      payload: {
        'question': 'Type the English meaning',
        'answer': 'hello',
        'accepted_answers': ['hello', 'hi'],
      },
    );

    expect(PracticeExerciseEngine.isKnownType(item.exerciseType), isTrue);
    expect(
      PracticeExerciseEngine.isItemValid(item: item, resolvedPromptText: null),
      isTrue,
    );
    expect(
      PracticeExerciseEngine.instructionFor(
        item: item,
        resolvedPromptText: null,
      ),
      'Type the answer',
    );
    expect(
      PracticeExerciseEngine.isReady(item: item, state: _stateTypedHello),
      isTrue,
    );
    expect(
      PracticeExerciseEngine.isCorrect(item: item, state: _stateTypedHello),
      isTrue,
    );
    expect(PracticeExerciseEngine.revealFor(item), contains('Correct:'));

    final widget = PracticeExerciseEngine.buildExercise(
      item: item,
      state: _stateTypedHello,
      callbacks: _callbacks,
      resolvedPromptText: null,
    );
    expect(widget, isNotNull);
  });

  test('supports listen_write text flow', () {
    final item = _item(
      type: 'listen_and_write',
      choices: const [],
      payload: {
        'prompt_text': 'Listen and write',
        'answer': '我们今天学习中文。',
        'accepted_answers': ['我们今天学习中文', '我们今天学习中文。'],
      },
    );

    const typedState = PracticeExerciseUiState(
      selectedIndex: null,
      textAnswer: '我们今天学习中文',
      isAnswered: false,
      showPinyin: false,
      readingQuestionIndex: 0,
      orderChunks: [],
      orderAnswer: [],
      matchReady: false,
      matchCorrect: false,
      speakingPermissionGranted: false,
      speakingIsRecording: false,
      speakingRecording: null,
      speakingRating: null,
      speakingScore: null,
    );

    expect(PracticeExerciseEngine.isKnownType(item.exerciseType), isTrue);
    expect(
      PracticeExerciseEngine.isItemValid(item: item, resolvedPromptText: null),
      isFalse,
    );
    final validWithAudio = PilotExerciseItem.fromJson({
      'id': 'test_listen_write_with_audio',
      'exercise_type': 'listen_write',
      'prompt_text': 'Listen and write',
      'prompt': {'hanzi': '', 'pinyin': '', 'meaning': ''},
      'choices': const [],
      'answer_index': 0,
      'audio_url': '/audio/demo.mp3',
      'payload': {
        'prompt_text': 'Listen and write',
        'answer': '我们今天学习中文。',
        'accepted_answers': ['我们今天学习中文', '我们今天学习中文。'],
      },
      'meta': {'hsk_level': 1, 'tags': []},
    });
    expect(
      PracticeExerciseEngine.isKnownType(validWithAudio.exerciseType),
      isTrue,
    );
    expect(
      PracticeExerciseEngine.isItemValid(
        item: validWithAudio,
        resolvedPromptText: null,
      ),
      isTrue,
    );
    expect(
      PracticeExerciseEngine.instructionFor(
        item: validWithAudio,
        resolvedPromptText: null,
      ),
      'Listen and write',
    );
    expect(
      PracticeExerciseEngine.isReady(item: validWithAudio, state: typedState),
      isTrue,
    );
    expect(
      PracticeExerciseEngine.isCorrect(item: validWithAudio, state: typedState),
      isTrue,
    );
    expect(
      PracticeExerciseEngine.revealFor(validWithAudio),
      contains('Correct:'),
    );

    final widget = PracticeExerciseEngine.buildExercise(
      item: validWithAudio,
      state: typedState,
      callbacks: _callbacks,
      resolvedPromptText: null,
    );
    expect(widget, isNotNull);
  });

  test('supports error_correction text flow', () {
    final item = _item(
      type: 'error_correction',
      choices: const [],
      payload: {
        'question': 'Correct this sentence',
        'incorrect_sentence': 'He go to school.',
        'answer': 'He goes to school.',
      },
    );

    expect(PracticeExerciseEngine.isKnownType(item.exerciseType), isTrue);
    expect(
      PracticeExerciseEngine.isItemValid(item: item, resolvedPromptText: null),
      isTrue,
    );
    expect(
      PracticeExerciseEngine.instructionFor(
        item: item,
        resolvedPromptText: null,
      ),
      'Correct the sentence',
    );
    expect(
      PracticeExerciseEngine.isReady(
        item: item,
        state: _stateCorrectedSentence,
      ),
      isTrue,
    );
    expect(
      PracticeExerciseEngine.isCorrect(
        item: item,
        state: _stateCorrectedSentence,
      ),
      isTrue,
    );
    expect(PracticeExerciseEngine.revealFor(item), contains('Correct:'));

    final widget = PracticeExerciseEngine.buildExercise(
      item: item,
      state: _stateCorrectedSentence,
      callbacks: _callbacks,
      resolvedPromptText: null,
    );
    expect(widget, isNotNull);
  });

  test('supports conversation_simulation selection flow', () {
    final item = _item(
      type: 'conversation_simulation',
      choices: const ['你好', '再见', '谢谢'],
      answerIndex: 0,
      payload: {
        'scenario': 'You meet a colleague for the first time.',
        'question': 'What should you say first?',
      },
    );

    expect(PracticeExerciseEngine.isKnownType(item.exerciseType), isTrue);
    expect(
      PracticeExerciseEngine.isItemValid(item: item, resolvedPromptText: null),
      isTrue,
    );
    expect(
      PracticeExerciseEngine.instructionFor(
        item: item,
        resolvedPromptText: null,
      ),
      'Choose the best next reply',
    );

    final stateSelected = PracticeExerciseUiState(
      selectedIndex: 0,
      textAnswer: '',
      isAnswered: false,
      showPinyin: false,
      readingQuestionIndex: 0,
      orderChunks: const [],
      orderAnswer: const [],
      matchReady: false,
      matchCorrect: false,
      speakingPermissionGranted: false,
      speakingIsRecording: false,
      speakingRecording: null,
      speakingRating: null,
      speakingScore: null,
    );
    expect(
      PracticeExerciseEngine.isReady(item: item, state: stateSelected),
      isTrue,
    );
    expect(
      PracticeExerciseEngine.isCorrect(item: item, state: stateSelected),
      isTrue,
    );

    final widget = PracticeExerciseEngine.buildExercise(
      item: item,
      state: stateSelected,
      callbacks: _callbacks,
      resolvedPromptText: null,
    );
    expect(widget, isNotNull);
  });

  test('supports character_writing skeleton flow', () {
    final item = _item(
      type: 'character_writing',
      choices: const [],
      payload: {'target_character': '学', 'pinyin': 'xue', 'meaning': 'study'},
    );

    expect(PracticeExerciseEngine.isKnownType(item.exerciseType), isTrue);
    expect(
      PracticeExerciseEngine.isItemValid(item: item, resolvedPromptText: null),
      isTrue,
    );
    expect(
      PracticeExerciseEngine.instructionFor(
        item: item,
        resolvedPromptText: null,
      ),
      'Write the character',
    );
    expect(PracticeExerciseEngine.isReady(item: item, state: _state), isTrue);
    expect(PracticeExerciseEngine.isCorrect(item: item, state: _state), isTrue);
    expect(PracticeExerciseEngine.revealFor(item), contains('complete'));

    final widget = PracticeExerciseEngine.buildExercise(
      item: item,
      state: _state,
      callbacks: _callbacks,
      resolvedPromptText: null,
    );
    expect(widget, isNotNull);
  });
}
