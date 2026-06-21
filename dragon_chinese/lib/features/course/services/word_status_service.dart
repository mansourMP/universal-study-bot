import 'package:flutter/material.dart';

enum WordStatus {
  newWord,      // 0: Violet
  learning,     // 1: Gold/Underlined
  known,        // 2: Normal/Black
}

class WordStatusService {
  // Singleton
  static final WordStatusService _instance = WordStatusService._internal();
  factory WordStatusService() => _instance;
  WordStatusService._internal();

  // Mock Database: Map Word ID to Status
  final Map<String, WordStatus> _statusMap = {
    // Let's mock some data for the "Emergency" lesson so you can see the difference immediately
    
    // KNOWN (Black)
    'ZH_W0109': WordStatus.known, // 我 (I)
    
    // LEARNING (Gold)
    'ZH_W0081': WordStatus.learning, // 去 (go)
    'ZH_W0013': WordStatus.learning, // 打电话 (phone)

    // NEW (Violet) - Everything else defaults to this
    // 'ZH_W0131': WordStatus.newWord, // 医院 (hospital)
  };

  WordStatus getStatus(String wordId) {
    return _statusMap[wordId] ?? WordStatus.newWord;
  }

  Color getColor(WordStatus status) {
    switch (status) {
      case WordStatus.newWord:
        return Colors.purple.shade300; // Violet
      case WordStatus.learning:
        return Colors.amber.shade800;  // Gold
      case WordStatus.known:
        return Colors.black87;         // Normal
    }
  }

  TextStyle getStyle(WordStatus status, {double fontSize = 24}) {
    final baseStyle = TextStyle(
      fontSize: fontSize,
      height: 1.5,
      fontWeight: FontWeight.w500,
    );

    switch (status) {
      case WordStatus.newWord:
        return baseStyle.copyWith(
          color: Colors.purple.shade400,
          fontWeight: FontWeight.bold,
        );
      case WordStatus.learning:
        return baseStyle.copyWith(
          color: Colors.amber.shade800,
          decoration: TextDecoration.underline,
          decorationColor: Colors.amber.shade300,
          decorationStyle: TextDecorationStyle.dashed,
        );
      case WordStatus.known:
        return baseStyle.copyWith(
          color: Colors.black87,
        );
    }
  }
}
