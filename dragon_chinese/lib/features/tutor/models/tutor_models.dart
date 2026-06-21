class TutorSuggestionBundle {
  final String headline;
  final String subtitle;
  final List<String> contextWords;
  final List<String> suggestions;

  TutorSuggestionBundle({
    required this.headline,
    required this.subtitle,
    required this.contextWords,
    required this.suggestions,
  });

  factory TutorSuggestionBundle.fromJson(Map<String, dynamic> json) {
    return TutorSuggestionBundle(
      headline: (json['headline'] as String?) ?? 'Ready to practice?',
      subtitle: (json['subtitle'] as String?) ?? '',
      contextWords: ((json['context_words'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      suggestions: ((json['suggestions'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class TutorMessage {
  final String role; // user | assistant
  final String content;

  TutorMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class TutorProviderAttempt {
  final String provider;
  final String model;
  final bool success;
  final String? error;

  TutorProviderAttempt({
    required this.provider,
    required this.model,
    required this.success,
    this.error,
  });

  factory TutorProviderAttempt.fromJson(Map<String, dynamic> json) {
    final error = (json['error'] as String?)?.trim();
    return TutorProviderAttempt(
      provider: (json['provider'] as String?) ?? 'unknown',
      model: (json['model'] as String?) ?? 'unknown',
      success: (json['success'] as bool?) ?? false,
      error: (error == null || error.isEmpty) ? null : error,
    );
  }
}

class TutorChatReply {
  final String reply;
  final String provider;
  final String model;
  final String requestedProvider;
  final bool fallbackUsed;
  final List<TutorProviderAttempt> providerAttempts;
  final String? traceId;

  TutorChatReply({
    required this.reply,
    required this.provider,
    required this.model,
    required this.requestedProvider,
    required this.fallbackUsed,
    required this.providerAttempts,
    this.traceId,
  });

  factory TutorChatReply.fromJson(Map<String, dynamic> json) {
    final attempts = ((json['provider_attempts'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (item) => TutorProviderAttempt.fromJson(item.cast<String, dynamic>()),
        )
        .toList();

    return TutorChatReply(
      reply: (json['reply'] as String?) ?? '',
      provider: (json['provider'] as String?) ?? 'unknown',
      model: (json['model'] as String?) ?? 'unknown',
      requestedProvider:
          (json['requested_provider'] as String?) ??
          ((json['provider'] as String?) ?? 'unknown'),
      fallbackUsed: (json['fallback_used'] as bool?) ?? false,
      providerAttempts: attempts,
      traceId: (json['trace_id'] as String?)?.trim(),
    );
  }
}

class TutorConversationSnapshot {
  final List<TutorMessage> messages;
  final List<String> contextWords;
  final String? preferredProvider;
  final String? updatedAt;

  TutorConversationSnapshot({
    required this.messages,
    required this.contextWords,
    this.preferredProvider,
    this.updatedAt,
  });

  factory TutorConversationSnapshot.fromJson(Map<String, dynamic> json) {
    final rawMessages = (json['messages'] as List?) ?? const [];
    return TutorConversationSnapshot(
      messages: rawMessages
          .whereType<Map<String, dynamic>>()
          .map(
            (item) => TutorMessage(
              role: (item['role'] as String?) ?? 'user',
              content: (item['content'] as String?) ?? '',
            ),
          )
          .toList(),
      contextWords: ((json['context_words'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      preferredProvider: json['preferred_provider'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }
}
