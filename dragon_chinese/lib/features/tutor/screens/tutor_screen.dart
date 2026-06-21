import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dragon_chinese/core/config/app_config.dart';
import 'package:dragon_chinese/design_system/design_system.dart';
import 'package:dragon_chinese/core/utils/app_log.dart';
import 'package:dragon_chinese/core/utils/event_tracker.dart';
import 'package:dragon_chinese/features/course/engine/practice_exercise_engine.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/screens/practice_session_screen.dart';
import 'package:dragon_chinese/features/tutor/models/tutor_models.dart';
import 'package:dragon_chinese/features/tutor/services/live_lesson_pack_contract.dart';
import 'package:dragon_chinese/features/tutor/services/tutor_preferences_store.dart';
import 'package:dragon_chinese/features/tutor/services/tutor_service.dart';
import 'package:dragon_chinese/features/tutor/services/voice_input_service.dart';

class TutorScreen extends StatefulWidget {
  const TutorScreen({super.key});

  @override
  State<TutorScreen> createState() => _TutorScreenState();
}

class _TutorScreenState extends State<TutorScreen> {
  static const List<_LiveLessonPreset> _liveLessonPresets = [
    _LiveLessonPreset(
      id: 'live_speaking',
      icon: Icons.graphic_eq_rounded,
      title: 'Live Speaking',
      subtitle: 'Pronunciation and response flow.',
      durationLabel: '2-4 min',
      intent: 'drill',
      focusDimension: 'production',
      exerciseCount: 6,
      targetMinSeconds: 120,
      targetMaxSeconds: 240,
      allowedTypes: [
        'reply_select',
        'cloze_select',
        'meaning_select',
        'true_false',
      ],
    ),
    _LiveLessonPreset(
      id: 'adaptive_listening',
      icon: Icons.hearing_rounded,
      title: 'Adaptive Listening',
      subtitle: 'Instant checks based on mistakes.',
      durationLabel: '2-4 min',
      intent: 'drill',
      focusDimension: 'listening',
      exerciseCount: 6,
      targetMinSeconds: 120,
      targetMaxSeconds: 240,
      allowedTypes: [
        'character_select',
        'pinyin_select',
        'dictation_select',
        'true_false',
        'meaning_select',
      ],
    ),
    _LiveLessonPreset(
      id: 'mixed_ai_drills',
      icon: Icons.auto_fix_high_rounded,
      title: 'Mixed AI Drills',
      subtitle: 'Prompt, answer, correction cycles.',
      durationLabel: '3-5 min',
      intent: 'daily',
      focusDimension: 'usage',
      exerciseCount: 8,
      targetMinSeconds: 180,
      targetMaxSeconds: 300,
      allowedTypes: [
        'meaning_select',
        'character_select',
        'pinyin_select',
        'reply_select',
        'cloze_select',
        'true_false',
      ],
    ),
  ];

  final TutorService _service = TutorService();
  final VoiceInputService _voiceInputService = VoiceInputService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<TutorMessage> _messages = [];
  List<String> _contextWords = const [];

  bool _isSending = false;
  String _selectedProvider = 'gemini';
  String? _requestedProvider;
  String? _resolvedProvider;
  String? _resolvedModel;
  String? _lastTraceId;
  bool? _serverFallbackUsed;
  String? _lastFallbackNoticeKey;
  bool _isVoiceEnabled = false;
  String _voiceInputLanguage = 'auto';
  int _aiModeIndex = 0; // 0 = Chat, 1 = Real-time Lessons
  bool _isLaunchingLiveLesson = false;
  String _selectedLiveLessonId = _liveLessonPresets.first.id;
  bool _isListening = false;
  bool _isVoiceStarting = false;
  bool _isVoiceFinalizing = false;
  String _liveTranscript = '';
  String _voiceStatus = 'Listening...';
  bool _isStreamingReply = false;
  Timer? _assistantStreamTimer;
  Completer<void>? _assistantStreamCompleter;
  int _conversationVersion = 0;

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_handleInputChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _cancelReplyStreaming();
    _voiceInputService.cancel();
    _inputController.removeListener(_handleInputChanged);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isComposerBusy =>
      _isSending || _isStreamingReply || _isVoiceStarting || _isVoiceFinalizing;

  bool get _canSendText =>
      !_isComposerBusy && _inputController.text.trim().isNotEmpty;

  void _handleInputChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _cancelReplyStreaming() {
    _assistantStreamTimer?.cancel();
    _assistantStreamTimer = null;
    final completer = _assistantStreamCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _assistantStreamCompleter = null;
    _isStreamingReply = false;
  }

  Future<void> _bootstrap() async {
    await _loadPreferences();
    await Future.wait([_loadSuggestions(), _loadHistory()]);
  }

  Future<void> _loadPreferences() async {
    final provider = await TutorPreferencesStore.getDefaultProvider();
    final voiceEnabled = await TutorPreferencesStore.getVoiceEnabled();
    final voiceInputLanguage =
        await TutorPreferencesStore.getVoiceInputLanguage();
    final defaultProvider = AppConfig.aiDefaultProvider.trim().toLowerCase();
    if (!mounted) return;
    setState(() {
      _selectedProvider = AppConfig.enableAiModelPicker
          ? provider
          : (defaultProvider.isEmpty ? 'gemini' : defaultProvider);
      _isVoiceEnabled = voiceEnabled;
      _voiceInputLanguage = voiceInputLanguage;
    });
  }

  Future<void> _loadSuggestions() async {
    try {
      final payload = await _service.fetchSuggestions();
      if (!mounted) return;
      setState(() {
        _contextWords = payload.contextWords;
      });
    } catch (_) {
      // Keep default context if suggestions endpoint fails.
    }
  }

  Future<void> _loadHistory() async {
    try {
      final snapshot = await _service.fetchConversationHistory();
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(snapshot.messages);
        if (snapshot.contextWords.isNotEmpty) {
          _contextWords = snapshot.contextWords;
        }
        if ((snapshot.preferredProvider ?? '').isNotEmpty) {
          _selectedProvider = snapshot.preferredProvider!;
        }
      });
      _scrollToBottom();
    } catch (_) {
      // Ignore history load failures and keep empty local state.
    }
  }

  Future<void> _persistHistory() async {
    try {
      await _service.saveConversationHistory(
        messages: _messages,
        contextWords: _contextWords,
        preferredProvider: _selectedProvider,
      );
    } catch (_) {
      // Keep local UX smooth even if persistence fails.
    }
  }

  Future<void> _clearConversation() async {
    _cancelReplyStreaming();
    setState(() {
      _messages.clear();
      _isSending = false;
      _requestedProvider = null;
      _resolvedProvider = null;
      _resolvedModel = null;
      _lastTraceId = null;
      _serverFallbackUsed = null;
      _lastFallbackNoticeKey = null;
      _conversationVersion++;
    });
    try {
      await _service.clearConversationHistory();
    } catch (_) {
      // no-op
    }
  }

  Future<void> _onProviderChanged(String provider) async {
    if (!AppConfig.enableAiModelPicker) return;
    setState(() {
      _selectedProvider = provider;
      _requestedProvider = null;
      _resolvedProvider = null;
      _resolvedModel = null;
      _lastTraceId = null;
      _serverFallbackUsed = null;
    });
    await TutorPreferencesStore.setDefaultProvider(provider);
    if (_messages.isNotEmpty) {
      await _persistHistory();
    }
  }

  Future<void> _onVoiceInputLanguageChanged(String language) async {
    setState(() => _voiceInputLanguage = language);
    await TutorPreferencesStore.setVoiceInputLanguage(language);
  }

  String _voiceInputLanguageLabel(String code) {
    switch (code) {
      case 'zh':
        return 'Chinese';
      case 'en':
        return 'English';
      default:
        return 'Auto';
    }
  }

  String _providerLabel(String provider) {
    final normalized = provider.trim().toLowerCase();
    switch (normalized) {
      case 'openai':
        return 'OpenAI';
      case 'deepseek':
        return 'DeepSeek';
      case 'local_fallback':
        return 'Local fallback';
      case 'unknown':
        return 'Unknown';
      case 'gemini':
        return 'Gemini';
      default:
        final raw = provider.trim();
        if (raw.isEmpty) return 'Unknown';
        return '${raw[0].toUpperCase()}${raw.substring(1)}';
    }
  }

  String _normalizeProviderId(String provider) {
    return provider.trim().toLowerCase();
  }

  String _chatSubtitle() {
    final selectedLabel = _providerLabel(_selectedProvider);
    final requestedProviderRaw = _requestedProvider?.trim();
    final requestedProvider = (requestedProviderRaw?.isNotEmpty ?? false)
        ? requestedProviderRaw!
        : _selectedProvider;
    final activeProviderRaw = _resolvedProvider?.trim() ?? '';
    final activeModel = _resolvedModel?.trim() ?? '';
    if (activeProviderRaw.isEmpty) {
      if (!AppConfig.enableAiModelPicker) {
        return 'Active: ${_providerLabel(requestedProvider)}';
      }
      return 'Selected: $selectedLabel';
    }
    final activeLabel = _providerLabel(activeProviderRaw);
    final requestedLabel = _providerLabel(requestedProvider);
    final modelSuffix = activeModel.isEmpty ? '' : ' • $activeModel';
    final fallbackUsed =
        _serverFallbackUsed ??
        (_normalizeProviderId(activeProviderRaw) !=
            _normalizeProviderId(requestedProvider));
    if (fallbackUsed) {
      return 'Requested: $requestedLabel • Active: $activeLabel$modelSuffix';
    }
    return 'Active: $activeLabel$modelSuffix';
  }

  void _recordResolvedProvider({
    required String provider,
    required String model,
    String? requestedProvider,
    bool? fallbackUsed,
    String? traceId,
    bool showFallbackNotice = false,
  }) {
    final requested = (requestedProvider ?? _selectedProvider).trim();
    final resolvedProvider = provider.trim();
    final resolvedModel = model.trim();
    final didFallback =
        fallbackUsed ??
        resolvedProvider.isNotEmpty &&
            _normalizeProviderId(resolvedProvider) !=
                _normalizeProviderId(requested);

    if (mounted) {
      setState(() {
        _requestedProvider = requested;
        _resolvedProvider = resolvedProvider;
        _resolvedModel = resolvedModel;
        _lastTraceId = traceId;
        _serverFallbackUsed = didFallback;
      });
    } else {
      _requestedProvider = requested;
      _resolvedProvider = resolvedProvider;
      _resolvedModel = resolvedModel;
      _lastTraceId = traceId;
      _serverFallbackUsed = didFallback;
    }

    if (!showFallbackNotice || !didFallback || !mounted) return;
    final noticeKey =
        '${_normalizeProviderId(requested)}->${_normalizeProviderId(resolvedProvider)}::$resolvedModel';
    if (_lastFallbackNoticeKey == noticeKey) return;
    _lastFallbackNoticeKey = noticeKey;
    final modelPart = resolvedModel.isEmpty ? '' : ' ($resolvedModel)';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Fallback in use: ${_providerLabel(resolvedProvider)}$modelPart',
        ),
      ),
    );
  }

  Future<void> _captureVoice() async {
    if (!_isVoiceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voice is disabled. Enable it from Profile > AI.'),
        ),
      );
      return;
    }
    if (_isVoiceStarting || _isVoiceFinalizing) return;
    if (_isListening) {
      await _stopListeningAndSend();
      return;
    }
    await _startListening();
  }

  Future<void> _startListening() async {
    setState(() {
      _isVoiceStarting = true;
      _liveTranscript = '';
      _voiceStatus = 'Starting...';
    });

    final started = await _voiceInputService.startListening(
      preferredLanguage: _voiceInputLanguage,
      onPartialTranscript: (text) {
        if (!mounted) return;
        setState(() => _liveTranscript = text);
      },
      onStatusChanged: (status) {
        if (!mounted) return;
        final normalized = status.toLowerCase();
        if (normalized == 'done' || normalized == 'notlistening') {
          _onVoiceAutoStopped();
          return;
        }
        setState(() => _voiceStatus = _voiceInputService.statusLabel(status));
      },
      onError: (message) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Voice error: $message')));
      },
    );

    if (!mounted) return;
    if (!started) {
      setState(() {
        _isVoiceStarting = false;
        _isListening = false;
        _voiceStatus = 'Listening...';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not start voice capture on this device.'),
        ),
      );
      return;
    }

    HapticFeedback.selectionClick();
    setState(() {
      _isVoiceStarting = false;
      _isListening = true;
      _voiceStatus = 'Listening...';
    });
  }

  void _onVoiceAutoStopped() {
    if (!_isListening || _isVoiceFinalizing) return;
    _stopListeningAndSend(autoStopped: true);
  }

  Future<void> _stopListeningAndSend({bool autoStopped = false}) async {
    if (_isVoiceFinalizing) return;
    _isVoiceFinalizing = true;

    setState(() {
      _voiceStatus = 'Processing...';
    });

    try {
      final result = await _voiceInputService.stopListening();
      if (!mounted) return;

      final transcript = (result?.transcript ?? _liveTranscript).trim();
      setState(() {
        _isListening = false;
        _isVoiceStarting = false;
        _liveTranscript = '';
        _voiceStatus = 'Listening...';
      });

      if (transcript.isEmpty) {
        if (!autoStopped) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No speech detected. Try again.')),
          );
        }
        return;
      }

      await _sendMessage(transcript);
    } finally {
      _isVoiceFinalizing = false;
    }
  }

  Future<void> _sendMessage(String text) async {
    final clean = text.trim();
    if (clean.isEmpty || _isSending || _isStreamingReply) return;
    final requestVersion = _conversationVersion;
    final stopwatch = Stopwatch()..start();

    final history = List<TutorMessage>.from(_messages);
    EventTracker.track(
      'ai_chat_request_sent',
      params: {
        'selected_provider': _selectedProvider,
        'history_count': history.length,
        'context_word_count': _contextWords.length,
        'message_chars': clean.length,
      },
    );

    setState(() {
      _messages.add(TutorMessage(role: 'user', content: clean));
      _isSending = true;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      final response = await _service.sendMessage(
        message: clean,
        history: history,
        contextWords: _contextWords,
        aiProvider: _selectedProvider,
      );
      if (!mounted) return;
      if (requestVersion != _conversationVersion) {
        setState(() => _isSending = false);
        return;
      }
      stopwatch.stop();
      final normalized = _normalizeAssistantText(response.reply);
      final responseProvider = response.provider;
      final responseModel = response.model;
      final requestedProvider = response.requestedProvider;
      final traceId = response.traceId ?? '';
      EventTracker.track(
        'ai_chat_response_received',
        params: {
          'selected_provider': _selectedProvider,
          'requested_provider': requestedProvider,
          'active_provider': responseProvider,
          'active_model': responseModel,
          'fallback_used': response.fallbackUsed,
          'provider_attempts': response.providerAttempts.length,
          'trace_id': traceId,
          'latency_ms': stopwatch.elapsedMilliseconds,
        },
      );
      final assistantIndex = _messages.length;
      setState(() {
        _messages.add(TutorMessage(role: 'assistant', content: ''));
        _isSending = false;
        _isStreamingReply = true;
      });
      _recordResolvedProvider(
        provider: responseProvider,
        model: responseModel,
        requestedProvider: requestedProvider,
        fallbackUsed: response.fallbackUsed,
        traceId: response.traceId,
        showFallbackNotice: true,
      );
      await _streamAssistantReply(
        assistantIndex: assistantIndex,
        fullText: normalized,
      );
      if (!mounted) return;
      if (requestVersion != _conversationVersion) {
        setState(() => _isStreamingReply = false);
        return;
      }
      setState(() => _isStreamingReply = false);
      await _persistHistory();
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      stopwatch.stop();
      EventTracker.track(
        'ai_chat_response_failed',
        params: {
          'selected_provider': _selectedProvider,
          'latency_ms': stopwatch.elapsedMilliseconds,
          'error': error.toString(),
        },
      );
      _cancelReplyStreaming();
      setState(() => _isSending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Tutor request failed: $error')));
    }
  }

  Future<void> _streamAssistantReply({
    required int assistantIndex,
    required String fullText,
  }) async {
    _assistantStreamTimer?.cancel();
    final existing = _assistantStreamCompleter;
    if (existing != null && !existing.isCompleted) {
      existing.complete();
    }

    final completer = Completer<void>();
    _assistantStreamCompleter = completer;

    if (fullText.trim().isEmpty) {
      if (mounted && assistantIndex < _messages.length) {
        setState(() {
          _messages[assistantIndex] = TutorMessage(
            role: 'assistant',
            content: '',
          );
        });
      }
      completer.complete();
      _assistantStreamCompleter = null;
      return;
    }

    final runes = fullText.runes.toList(growable: false);
    final buffer = StringBuffer();
    var cursor = 0;
    var tick = 0;

    _assistantStreamTimer = Timer.periodic(const Duration(milliseconds: 24), (
      timer,
    ) {
      if (!mounted ||
          !_isStreamingReply ||
          assistantIndex >= _messages.length) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
        return;
      }

      final remaining = runes.length - cursor;
      if (remaining <= 0) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
        return;
      }

      final step = remaining > 340
          ? 8
          : remaining > 220
          ? 6
          : remaining > 120
          ? 4
          : 2;

      for (var i = 0; i < step && cursor < runes.length; i++) {
        buffer.writeCharCode(runes[cursor++]);
      }

      final partial = buffer.toString();
      setState(() {
        _messages[assistantIndex] = TutorMessage(
          role: 'assistant',
          content: partial,
        );
      });

      tick++;
      if (tick % 3 == 0 || cursor >= runes.length) {
        _scrollToBottom();
      }

      if (cursor >= runes.length) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });

    await completer.future;
    _assistantStreamTimer?.cancel();
    _assistantStreamTimer = null;
    if (identical(_assistantStreamCompleter, completer)) {
      _assistantStreamCompleter = null;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + AppSpacing.xl,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  String _normalizeAssistantText(String input) {
    var text = input;
    // Remove common markdown markers that look raw in plain text UI.
    text = text.replaceAll(RegExp(r'[*_`#>]'), '');
    // Collapse extra blank lines.
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  Future<void> _copyMessage(String text) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: normalized));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied')));
  }

  void _switchAiMode(int index) {
    if (_aiModeIndex == index) return;
    _dismissKeyboard();
    if (index != 0 && _isListening) {
      _voiceInputService.cancel();
      _isListening = false;
      _liveTranscript = '';
      _voiceStatus = 'Listening...';
    }
    setState(() => _aiModeIndex = index);
  }

  _LiveLessonPreset get _selectedLiveLesson {
    for (final lesson in _liveLessonPresets) {
      if (lesson.id == _selectedLiveLessonId) return lesson;
    }
    return _liveLessonPresets.first;
  }

  Future<void> _launchLiveLesson([_LiveLessonPreset? preset]) async {
    if (_isLaunchingLiveLesson) return;
    final lesson = preset ?? _selectedLiveLesson;
    EventTracker.track(
      'ai_live_lesson_start',
      params: {
        'lesson_id': lesson.id,
        'provider': _selectedProvider,
        'focus': lesson.focusDimension,
      },
    );
    setState(() {
      _selectedLiveLessonId = lesson.id;
      _isLaunchingLiveLesson = true;
    });
    HapticFeedback.mediumImpact();

    try {
      final pack = await _generateLiveLessonPack(lesson);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PracticeSessionScreen(
            seed:
                'ai_live_${lesson.id}_${DateTime.now().millisecondsSinceEpoch}',
            packOverride: pack,
          ),
        ),
      );
      if (mounted) {
        EventTracker.track(
          'ai_live_lesson_opened',
          params: {
            'lesson_id': lesson.id,
            'provider': _selectedProvider,
            'item_count': pack.items.length,
          },
        );
      }
    } catch (error) {
      if (!mounted) return;
      EventTracker.track(
        'ai_live_lesson_launch_failed',
        params: {
          'lesson_id': lesson.id,
          'provider': _selectedProvider,
          'error': error.toString(),
        },
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start live lesson: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLaunchingLiveLesson = false);
      }
    }
  }

  Future<PilotExercisePack> _generateLiveLessonPack(
    _LiveLessonPreset lesson,
  ) async {
    final allowedTypes = _normalizedAllowedTypes(lesson);
    final prompt = _buildLiveLessonPrompt(lesson);
    try {
      final reply = await _service.sendMessage(
        message: prompt,
        history: const [],
        contextWords: _contextWords,
        aiProvider: _selectedProvider,
      );
      _recordResolvedProvider(
        provider: reply.provider,
        model: reply.model,
        requestedProvider: reply.requestedProvider,
        fallbackUsed: reply.fallbackUsed,
        traceId: reply.traceId,
        showFallbackNotice: true,
      );
      final payload = _extractJsonMap(reply.reply);
      if (payload == null) {
        throw const FormatException('No JSON object found in AI response.');
      }

      final pack = _service.buildPilotPackFromSchema(
        provider: reply.provider,
        rawResponse: payload,
      );
      final filteredPack = LiveLessonPackContract.filterSessionEnabled(pack);
      final contractIssues = LiveLessonPackContract.validate(
        pack: filteredPack,
        allowedTypes: allowedTypes,
        expectedItems: lesson.exerciseCount,
      );
      if (contractIssues.isNotEmpty) {
        throw const FormatException('AI live pack failed contract validation.');
      }
      EventTracker.track(
        'ai_live_pack_ready',
        params: {
          'lesson_id': lesson.id,
          'provider': reply.provider,
          'item_count': filteredPack.items.length,
          'fallback': false,
        },
      );
      EventTracker.track(
        'ai_live_pack_generated',
        params: {
          'lesson_id': lesson.id,
          'requested_provider': reply.requestedProvider,
          'active_provider': reply.provider,
          'active_model': reply.model,
          'fallback_used': reply.fallbackUsed,
          'provider_attempts': reply.providerAttempts.length,
          'trace_id': reply.traceId ?? '',
          'item_count': filteredPack.items.length,
        },
      );
      return filteredPack;
    } catch (error, stackTrace) {
      AppLog.w('Live lesson pack fallback: ${lesson.id} error=$error');
      AppLog.d(stackTrace.toString());
      EventTracker.track(
        'ai_live_pack_fallback',
        params: {
          'lesson_id': lesson.id,
          'provider': _selectedProvider,
          'error': error.toString(),
        },
      );
      _recordResolvedProvider(
        provider: 'local_fallback',
        model: 'fallback',
        showFallbackNotice: true,
      );
      final fallback = _buildFallbackLiveLessonPack(lesson);
      final fallbackIssues = LiveLessonPackContract.validate(
        pack: fallback,
        allowedTypes: allowedTypes,
        expectedItems: lesson.exerciseCount,
      );
      if (fallbackIssues.isNotEmpty) {
        throw FormatException(
          'Fallback pack invalid: ${fallbackIssues.join("; ")}',
        );
      }
      EventTracker.track(
        'ai_live_pack_ready',
        params: {
          'lesson_id': lesson.id,
          'provider': 'local_fallback',
          'item_count': fallback.items.length,
          'fallback': true,
        },
      );
      EventTracker.track(
        'ai_live_pack_generated',
        params: {
          'lesson_id': lesson.id,
          'requested_provider': _selectedProvider,
          'active_provider': 'local_fallback',
          'active_model': 'fallback',
          'fallback_used': true,
          'provider_attempts': 0,
          'trace_id': _lastTraceId ?? '',
          'item_count': fallback.items.length,
        },
      );
      return fallback;
    }
  }

  Set<String> _normalizedAllowedTypes(_LiveLessonPreset lesson) {
    return lesson.allowedTypes
        .map(PracticeExerciseEngine.normalizeType)
        .toSet();
  }

  Map<String, dynamic> _fallbackExerciseForType(
    String type,
    int index,
    List<String> seedWords,
  ) {
    final wordA = seedWords[index % seedWords.length];
    final wordB = seedWords[(index + 1) % seedWords.length];
    final wordC = seedWords[(index + 2) % seedWords.length];
    final id = 'fallback_${index + 1}';

    switch (PracticeExerciseEngine.normalizeType(type)) {
      case 'character_select':
        return {
          'id': id,
          'exercise_type': 'character_select',
          'skill': 'characters',
          'prompt_text': 'Select the correct Chinese for "thank you".',
          'choices': ['谢谢', '再见', '你好', '请'],
          'answer_index': 0,
          'payload': {'meaning': 'thank you', 'pinyin': 'xie xie'},
        };
      case 'pinyin_select':
        return {
          'id': id,
          'exercise_type': 'pinyin_select',
          'skill': 'pinyin',
          'prompt_text': 'Choose the correct pinyin for 你好',
          'choices': ['ni hao', 'wo ai', 'xie xie', 'zai jian'],
          'answer_index': 0,
          'payload': {'character': '你好'},
        };
      case 'reply_select':
        return {
          'id': id,
          'exercise_type': 'reply_select',
          'skill': 'production',
          'prompt_text': 'A: 你好吗？',
          'choices': ['我很好，谢谢。', '明天见。', '我叫王明。', '请慢用。'],
          'answer_index': 0,
          'payload': {'scenario': 'greeting'},
        };
      case 'conversation_simulation':
        return {
          'id': id,
          'exercise_type': 'conversation_simulation',
          'skill': 'production',
          'prompt_text': 'You meet a classmate. What do you say first?',
          'choices': ['你好！', '再见！', '谢谢！', '对不起。'],
          'answer_index': 0,
          'payload': {'scenario': 'first greeting in class'},
        };
      case 'cloze_select':
        return {
          'id': id,
          'exercise_type': 'cloze_select',
          'skill': 'reading',
          'prompt_text': 'Complete the sentence.',
          'choices': [wordA, wordB, wordC, '现在'],
          'answer_index': 0,
          'payload': {'sentence': '___ 我去学校。'},
        };
      case 'order_sentence':
        return {
          'id': id,
          'exercise_type': 'order_sentence',
          'skill': 'production',
          'prompt_text': 'Order the sentence.',
          'choices': const [],
          'answer_index': 0,
          'payload': {
            'chunks': ['我', '喜欢', '学习', '中文'],
            'answer': ['我', '喜欢', '学习', '中文'],
          },
        };
      case 'true_false':
        return {
          'id': id,
          'exercise_type': 'true_false',
          'skill': 'reading',
          'prompt_text': 'True or false: 你好 means hello.',
          'choices': ['True', 'False'],
          'answer_index': 0,
          'payload': {'statement': '你好 means hello.'},
        };
      case 'meaning_select':
      default:
        return {
          'id': id,
          'exercise_type': 'meaning_select',
          'skill': 'meaning',
          'prompt_text': 'Choose the meaning: $wordA',
          'choices': ['hello', 'goodbye', 'thank you', 'tomorrow'],
          'answer_index': 0,
          'payload': {'prompt': wordA},
        };
    }
  }

  String _buildLiveLessonPrompt(_LiveLessonPreset lesson) {
    final context = _contextWords.take(8).join(', ');
    final allowedTypes = lesson.allowedTypes.join(', ');

    return '''
Generate a compact AI live lesson exercise pack in strict JSON format.

Return ONLY one JSON object. No markdown. No explanation. No code fences.

Output schema:
{
  "schema_version": 1,
  "source_provider": "$_selectedProvider",
  "generated_at": "ISO-8601 timestamp",
  "context": {
    "mode": "live_lesson",
    "lesson_id": "${lesson.id}",
    "focus_dimension": "${lesson.focusDimension}",
    "target_lang": "zh"
  },
  "items": [
    {
      "id": "item_1",
      "exercise_type": "meaning_select",
      "skill": "meaning",
      "prompt_text": "Chinese or bilingual prompt text",
      "choices": ["A", "B", "C", "D"],
      "answer_index": 0,
      "payload": {
        "sentence": "for cloze_select only",
        "chunks": ["for order_sentence only"],
        "scenario": "for conversation_simulation only",
        "meaning": "for character_select only",
        "pinyin": "for character_select/pinyin_select when useful"
      }
    }
  ]
}

Constraints:
- Generate exactly ${lesson.exerciseCount} items.
- Allowed exercise_type values ONLY: $allowedTypes
- Do NOT use: character_writing, reverse_recall, error_correction, listen_write, meaning_match, audio_match, reading_micro, conversation_simulation, order_sentence
- For choice-based types include 3 or 4 choices and valid answer_index.
- For cloze_select include payload.sentence with a blank like "___".
- For order_sentence include payload.chunks with 4-8 tokens.
- Keep prompts concise and mobile-friendly.
- Target level: beginner/intermediate Chinese learner.
- Prefer practical phrases.
- Include pinyin in payload when useful.

Recent learner context words: ${context.isEmpty ? 'none' : context}
Lesson title: ${lesson.title}
Lesson objective: ${lesson.subtitle}
''';
  }

  PilotExercisePack _buildFallbackLiveLessonPack(_LiveLessonPreset lesson) {
    final allowedTypes = _normalizedAllowedTypes(lesson);
    final words = _contextWords
        .where((w) => w.trim().isNotEmpty)
        .take(4)
        .toList(growable: false);
    final seedWords = words.isNotEmpty ? words : const ['你好', '谢谢', '今天', '学习'];

    const fallbackTypeOrder = <String>[
      'meaning_select',
      'character_select',
      'pinyin_select',
      'reply_select',
      'conversation_simulation',
      'cloze_select',
      'order_sentence',
      'true_false',
    ];
    final activeTypes = fallbackTypeOrder
        .where(allowedTypes.contains)
        .toList(growable: false);
    final typesToUse = activeTypes.isEmpty
        ? const <String>['meaning_select']
        : activeTypes;

    final exercises = List<Map<String, dynamic>>.generate(
      lesson.exerciseCount,
      (index) {
        final type = typesToUse[index % typesToUse.length];
        return _fallbackExerciseForType(type, index, seedWords);
      },
      growable: false,
    );

    final payload = <String, dynamic>{
      'schema_version': 1,
      'source_provider': 'local_fallback',
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'context': {
        'mode': 'live_lesson_fallback',
        'lesson_id': lesson.id,
        'focus_dimension': lesson.focusDimension,
      },
      'items': exercises,
    };

    final pack = _service.buildPilotPackFromSchema(
      provider: 'local_fallback',
      rawResponse: payload,
    );
    return LiveLessonPackContract.filterSessionEnabled(pack);
  }

  Map<String, dynamic>? _extractJsonMap(String rawText) {
    final trimmed = rawText.trim();
    final direct = _decodeMap(trimmed);
    if (direct != null) return direct;

    final fenceRegex = RegExp(r'```(?:json)?\s*([\s\S]*?)```', dotAll: true);
    for (final match in fenceRegex.allMatches(rawText)) {
      final candidate = (match.group(1) ?? '').trim();
      final decoded = _decodeMap(candidate);
      if (decoded != null) return decoded;
    }

    final firstBrace = rawText.indexOf('{');
    if (firstBrace < 0) return null;
    final jsonCandidates = <String>[];
    var depth = 0;
    var inString = false;
    var escaped = false;
    var start = -1;

    for (var i = firstBrace; i < rawText.length; i++) {
      final ch = rawText[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == '\\' && inString) {
        escaped = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (ch == '{') {
        if (depth == 0) start = i;
        depth++;
      } else if (ch == '}') {
        if (depth <= 0) continue;
        depth--;
        if (depth == 0 && start >= 0) {
          jsonCandidates.add(rawText.substring(start, i + 1));
          start = -1;
        }
      }
    }

    for (final candidate in jsonCandidates.reversed) {
      final decoded = _decodeMap(candidate.trim());
      if (decoded != null) return decoded;
    }
    return null;
  }

  Map<String, dynamic>? _decodeMap(String raw) {
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
      if (decoded is List && decoded.isNotEmpty) {
        return {'items': decoded};
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final keyboardOpen = keyboardInset > 0;
    final subtitle = _aiModeIndex == 1
        ? 'AI-guided live practice modes'
        : _chatSubtitle();

    return AppScaffold(
      title: AppConfig.enableAiModelPicker
          ? _providerLabel(_selectedProvider)
          : 'AI',
      titleWidget: AppConfig.enableAiModelPicker
          ? _buildProviderTitlePicker()
          : _buildStaticTitle(),
      subtitle: subtitle,
      actions: [_buildTopMenu()],
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _dismissKeyboard,
        child: Column(
          children: [
            _buildModeSwitcher(),
            Expanded(
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: IndexedStack(
                          index: _aiModeIndex,
                          children: [
                            _buildMessagesList(),
                            _buildRealtimeLessonsView(),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_aiModeIndex == 0)
                        _buildComposer(keyboardOpen: keyboardOpen),
                      if (_aiModeIndex == 1) _buildRealtimeLessonsFooter(),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ),
                  if (_aiModeIndex == 0 && (_isListening || _isVoiceStarting))
                    Positioned(
                      right: AppSpacing.xs,
                      bottom: keyboardInset + 88,
                      child: _VoiceListeningChip(
                        status: _voiceStatus,
                        transcript: _liveTranscript,
                        onTap: _isListening ? _captureVoice : null,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSwitcher() {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: AppSegmentedControl<int>(
        value: _aiModeIndex,
        options: const {0: 'Chat', 1: 'Live Lessons'},
        onChanged: _switchAiMode,
      ),
    );
  }

  Widget _buildTopMenu() {
    return PopupMenuButton<String>(
      tooltip: 'AI options',
      onSelected: (value) {
        switch (value) {
          case 'voice_auto':
            _onVoiceInputLanguageChanged('auto');
            return;
          case 'voice_en':
            _onVoiceInputLanguageChanged('en');
            return;
          case 'voice_zh':
            _onVoiceInputLanguageChanged('zh');
            return;
          case 'clear_chat':
            _clearConversation();
            return;
        }
      },
      itemBuilder: (context) {
        return [
          const PopupMenuItem(value: 'voice_auto', child: Text('Voice: Auto')),
          const PopupMenuItem(value: 'voice_en', child: Text('Voice: English')),
          const PopupMenuItem(value: 'voice_zh', child: Text('Voice: Chinese')),
          if (_aiModeIndex == 0) ...[
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'clear_chat', child: Text('Clear chat')),
          ],
        ];
      },
      icon: const Icon(Icons.more_horiz_rounded),
    );
  }

  Widget _buildProviderTitlePicker() {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Select model',
      initialValue: _selectedProvider,
      onSelected: _onProviderChanged,
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'gemini', child: Text('Gemini')),
        PopupMenuItem(value: 'openai', child: Text('OpenAI')),
        PopupMenuItem(value: 'deepseek', child: Text('DeepSeek')),
      ],
      padding: EdgeInsets.zero,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _providerLabel(_selectedProvider),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _buildStaticTitle() {
    final theme = Theme.of(context);
    return Text(
      'AI',
      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _buildRealtimeLessonsView() {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRealtimeHero(),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: _liveLessonPresets
                  .map(
                    (lesson) => _RealtimeLessonCard(
                      icon: lesson.icon,
                      title: lesson.title,
                      subtitle: lesson.subtitle,
                      durationLabel: lesson.durationLabel,
                      isSelected: lesson.id == _selectedLiveLessonId,
                      onTap: _isLaunchingLiveLesson
                          ? null
                          : () => _launchLiveLesson(lesson),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRealtimeHero() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bolt_rounded,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Real-time Lessons',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Live AI drills with instant feedback across speaking, listening, and mixed practice.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRealtimeLessonsFooter() {
    final selected = _selectedLiveLesson;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isLaunchingLiveLesson ? null : _launchLiveLesson,
        icon: const Icon(Icons.bolt_rounded),
        label: Text(
          _isLaunchingLiveLesson ? 'Starting...' : 'Start ${selected.title}',
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xs,
        horizontal: AppSpacing.xxxs,
      ),
      itemCount: _messages.length + (_isSending ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isSending && index == _messages.length) {
          return const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
            child: _ThinkingIndicator(),
          );
        }

        final message = _messages[index];
        final isUser = message.role == 'user';
        final content = isUser
            ? message.content.trim()
            : _normalizeAssistantText(message.content);

        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: isUser
                  ? GestureDetector(
                      onLongPress: () => _copyMessage(content),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.26),
                          ),
                        ),
                        child: Text(content),
                      ),
                    )
                  : Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xs,
                        AppSpacing.xxxs,
                        AppSpacing.xs,
                        AppSpacing.xxxs,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onLongPress: () => _copyMessage(content),
                            child: Text(
                              content,
                              style: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.copyWith(height: 1.45),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildComposer({required bool keyboardOpen}) {
    final theme = Theme.of(context);
    final isIOS = theme.platform == TargetPlatform.iOS;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.14),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxxs,
        vertical: AppSpacing.xxxs,
      ),
      child: Row(
        children: [
          if (keyboardOpen)
            IconButton(
              tooltip: 'Hide keyboard',
              visualDensity: VisualDensity.compact,
              onPressed: _dismissKeyboard,
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          Expanded(
            child: isIOS
                ? CupertinoTextField(
                    controller: _inputController,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.send,
                    onTapOutside: (_) => _dismissKeyboard(),
                    onSubmitted: (value) {
                      if (_canSendText) {
                        _sendMessage(value);
                      }
                    },
                    placeholder: _isStreamingReply
                        ? 'AI is responding...'
                        : 'Message AI',
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: 10,
                    ),
                    style: theme.textTheme.bodyMedium,
                    placeholderStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.72,
                      ),
                    ),
                    decoration: const BoxDecoration(color: Colors.transparent),
                  )
                : TextField(
                    controller: _inputController,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    onTapOutside: (_) => _dismissKeyboard(),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (value) {
                      if (_canSendText) {
                        _sendMessage(value);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: _isStreamingReply
                          ? 'AI is responding...'
                          : 'Message AI',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: 10,
                      ),
                    ),
                  ),
          ),
          IconButton(
            onPressed: _isComposerBusy ? null : _captureVoice,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              _isListening ? Icons.stop_circle_rounded : Icons.mic_rounded,
              color: _isVoiceEnabled
                  ? (_isListening ? AppColors.error : theme.colorScheme.primary)
                  : theme.colorScheme.onSurfaceVariant,
            ),
            tooltip: _isVoiceEnabled
                ? (_isListening
                      ? 'Stop voice capture'
                      : 'Voice input (${_voiceInputLanguageLabel(_voiceInputLanguage)})')
                : 'Voice disabled (enable in Profile)',
          ),
          Container(
            decoration: BoxDecoration(
              color: !_canSendText
                  ? theme.colorScheme.surfaceContainerHighest
                  : theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: _canSendText
                  ? () => _sendMessage(_inputController.text)
                  : null,
              icon: Icon(
                Icons.send_rounded,
                color: !_canSendText
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RealtimeLessonCard extends StatelessWidget {
  const _RealtimeLessonCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.durationLabel,
    required this.isSelected,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String durationLabel;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width =
        (MediaQuery.of(context).size.width -
        (AppSpacing.md * 2 + AppSpacing.sm));
    final cardWidth = width > 620 ? 300.0 : width;
    return SizedBox(
      width: cardWidth,
      child: AppCard(
        variant: isSelected ? AppCardVariant.hero : AppCardVariant.standard,
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xxs,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: isSelected ? 0.16 : 0.08,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          durationLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveLessonPreset {
  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final String durationLabel;
  final String intent;
  final String focusDimension;
  final int exerciseCount;
  final int targetMinSeconds;
  final int targetMaxSeconds;
  final List<String> allowedTypes;

  const _LiveLessonPreset({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.durationLabel,
    required this.intent,
    required this.focusDimension,
    required this.exerciseCount,
    required this.targetMinSeconds,
    required this.targetMaxSeconds,
    required this.allowedTypes,
  });
}

class _VoiceListeningChip extends StatelessWidget {
  const _VoiceListeningChip({
    required this.status,
    required this.transcript,
    this.onTap,
  });

  final String status;
  final String transcript;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = transcript.trim().isEmpty ? 'Speak now...' : transcript;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _ListeningOrb(),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Icon(
                Icons.stop_circle_rounded,
                color: theme.colorScheme.primary,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListeningOrb extends StatefulWidget {
  const _ListeningOrb();

  @override
  State<_ListeningOrb> createState() => _ListeningOrbState();
}

class _ListeningOrbState extends State<_ListeningOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  late final Animation<double> _pulse = Tween<double>(
    begin: 0.75,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        return Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.22),
          ),
          alignment: Alignment.center,
          child: Transform.scale(
            scale: _pulse.value,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ThinkingIndicator extends StatelessWidget {
  const _ThinkingIndicator();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          'Thinking...',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
