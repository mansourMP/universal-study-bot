import 'package:flutter/material.dart';
import 'package:dragon_chinese/features/course/models/lesson_model.dart';
import 'package:dragon_chinese/features/course/services/goal_profile.dart';
import 'package:dragon_chinese/features/course/services/context_template_resolver.dart';

enum LessonState { completed, current, locked }

class LessonVM {
  final Lesson lesson;
  final String title;
  final String promise;
  final String? timeLabel;
  final List<String> skills;
  final LessonState state;
  final IconData icon;
  final double progress;
  final String? imageUrl;
  final String? audioUrl;
  final double goalBias;
  final int orderIndex;

  const LessonVM({
    required this.lesson,
    required this.title,
    required this.promise,
    required this.timeLabel,
    required this.skills,
    required this.state,
    required this.icon,
    required this.progress,
    required this.imageUrl,
    required this.audioUrl,
    required this.goalBias,
    required this.orderIndex,
  });
}

class UnitVM {
  final String realmTitle;
  final String unitTitle;
  final String subtitle;
  final String? focusLabel;
  final int completed;
  final int total;
  final List<LessonVM> lessons;

  const UnitVM({
    required this.realmTitle,
    required this.unitTitle,
    required this.subtitle,
    required this.focusLabel,
    required this.completed,
    required this.total,
    required this.lessons,
  });
}

class PathAdapter {
  final String? personaId;
  final GoalProfile? goalProfile;
  const PathAdapter({this.personaId, this.goalProfile});

  List<UnitVM> buildUnits(List<Lesson> lessons, int unlockedIndex) {
    final resolver = goalProfile == null
        ? null
        : ContextTemplateResolver(goalProfile!);
    final units = <String, List<Lesson>>{};
    final unitOrder = <String>[];
    final metaByUnit = <String, Map<String, String>>{};

    for (final lesson in lessons) {
      final realmTitle = _safeText(
        lesson.metadata?['realm_title'] as String?,
        fallback: 'Foundation Track',
      );
      final unitTitle = _safeText(
        lesson.metadata?['unit_title'] as String?,
        fallback: lesson.cultural?.setting ?? 'Unit',
      );
      final key = '$realmTitle::$unitTitle';
      if (!units.containsKey(key)) {
        units[key] = [];
        unitOrder.add(key);
        metaByUnit[key] = {'realm': realmTitle, 'unit': unitTitle};
      }
      units[key]!.add(lesson);
    }

    final lessonIndex = {
      for (int i = 0; i < lessons.length; i++) lessons[i]: i,
    };

    return unitOrder.map((key) {
      final unitLessons = units[key]!;
      final realmTitle = metaByUnit[key]!['realm']!;
      final unitTitle = metaByUnit[key]!['unit']!;
      final vms = <LessonVM>[];
      for (var i = 0; i < unitLessons.length; i++) {
        final lesson = unitLessons[i];
        final state = _deriveState(lesson, lessonIndex, unlockedIndex);
        final title = _deriveTitle(lesson, unitTitle, i);
        final promise = _derivePromise(
          lesson,
          unitTitle,
          i,
          personaId,
          resolver,
        );
        final timeLabel = _deriveTime(lesson);
        final skills = _deriveSkills(lesson);
        final icon = _deriveIcon(lesson, skills);
        final progress = _deriveProgress(lesson, state);
        final imageUrl = _deriveImageUrl(lesson);
        final audioUrl = _deriveAudioUrl(lesson);
        final goalBias = _goalBias(lesson, skills, goalProfile);
        vms.add(
          LessonVM(
            lesson: lesson,
            title: title,
            promise: promise,
            timeLabel: timeLabel,
            skills: skills,
            state: state,
            icon: icon,
            progress: progress,
            imageUrl: imageUrl,
            audioUrl: audioUrl,
            goalBias: goalBias,
            orderIndex: i,
          ),
        );
      }

      final completed = vms
          .where((l) => l.state == LessonState.completed)
          .length;

      return UnitVM(
        realmTitle: realmTitle,
        unitTitle: unitTitle,
        subtitle: 'Guided mastery in context',
        focusLabel: _goalFocusLabel(goalProfile, personaId),
        completed: completed,
        total: vms.length,
        lessons: _orderLessons(vms),
      );
    }).toList();
  }

  String _safeText(String? value, {required String fallback}) {
    if (value == null) return fallback;
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  LessonState _deriveState(
    Lesson lesson,
    Map<Lesson, int> index,
    int unlockedIndex,
  ) {
    final status = lesson.status ?? '';
    if (status == 'completed') return LessonState.completed;
    if (status == 'review_due') return LessonState.current;
    if (status == 'locked') return LessonState.locked;

    final globalIndex = index[lesson] ?? 0;
    if (globalIndex < unlockedIndex) return LessonState.completed;
    if (globalIndex == unlockedIndex) return LessonState.current;
    return LessonState.locked;
  }

  List<LessonVM> _orderLessons(List<LessonVM> lessons) {
    // Path circles must stay in deterministic lesson order (C1 -> C7).
    // Reordering by goal bias causes confusing jumps (e.g. checkpoint near C1).
    final sorted = List<LessonVM>.from(lessons);
    sorted.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return sorted;
  }

  String _deriveTitle(Lesson lesson, String unitTitle, int index) {
    if (lesson.title.isNotEmpty) return lesson.title;
    final metaTitle = lesson.metadata?['title'];
    if (metaTitle is String && metaTitle.trim().isNotEmpty) return metaTitle;
    if (unitTitle.trim().isNotEmpty) {
      return 'Lesson ${index + 1}: $unitTitle';
    }
    return 'Lesson ${index + 1}';
  }

  String _derivePromise(
    Lesson lesson,
    String unitTitle,
    int index,
    String? personaId,
    ContextTemplateResolver? resolver,
  ) {
    final objective = lesson.cultural?.languageObjective;
    if (objective != null && objective.trim().isNotEmpty) {
      return objective;
    }
    final context = lesson.cultural?.storyContext;
    if (context != null && context.trim().isNotEmpty) {
      return context;
    }
    if (resolver != null) {
      return resolver.resolveObjective(unitTitle: unitTitle, index: index);
    }
    return _personaPromise(unitTitle, personaId, index);
  }

  String? _deriveTime(Lesson lesson) {
    if (lesson.estimatedTimeMinutes > 0) {
      return '${lesson.estimatedTimeMinutes} min';
    }
    final type = lesson.metadata?['type'];
    if (type is String) {
      switch (type) {
        case 'review':
          return '2 min';
        case 'practice':
          return '4 min';
        case 'intro':
          return '3 min';
      }
    }
    return null;
  }

  List<String> _deriveSkills(Lesson lesson) {
    final skills = <String>{};
    final metaSkills = lesson.metadata?['skills'];
    if (metaSkills is List) {
      for (final s in metaSkills) {
        if (s is String && s.isNotEmpty) skills.add(s);
      }
    }
    if (lesson.skillPrimary.isNotEmpty) {
      skills.add(_normalizeSkill(lesson.skillPrimary));
    }
    return skills.where(_skillIconMap.containsKey).toList();
  }

  String _normalizeSkill(String raw) {
    final lowered = raw.toLowerCase();
    if (lowered.contains('listen')) return 'Listening';
    if (lowered.contains('speak')) return 'Speaking';
    if (lowered.contains('read')) return 'Reading';
    if (lowered.contains('write')) return 'Writing';
    return raw;
  }

  IconData _deriveIcon(Lesson lesson, List<String> skills) {
    final type = lesson.metadata?['type'] as String? ?? lesson.mode;
    if (type == 'review') return Icons.refresh_rounded;
    if (type == 'checkpoint') return Icons.emoji_events_rounded;
    if (type == 'practice') return Icons.fitness_center_rounded;
    if (type == 'intro') return Icons.menu_book_rounded;
    if (skills.contains('Listening')) return Icons.headphones_rounded;
    if (skills.contains('Speaking')) return Icons.mic_rounded;
    if (skills.contains('Reading')) return Icons.chrome_reader_mode_rounded;
    if (skills.contains('Writing')) return Icons.edit_rounded;
    return Icons.auto_stories_rounded;
  }

  double _deriveProgress(Lesson lesson, LessonState state) {
    if (state == LessonState.completed) return 1.0;
    final mastery = lesson.masterySummary;
    final total = mastery?['total'] as int? ?? 0;
    final known =
        (mastery?['known'] as int? ?? 0) + (mastery?['learning'] as int? ?? 0);
    if (total <= 0) return 0.0;
    return known / total;
  }

  String? _deriveImageUrl(Lesson lesson) {
    final metaImage = lesson.metadata?['image_url'];
    if (metaImage is String && metaImage.isNotEmpty) return metaImage;
    final cultural = lesson.cultural?.setting;
    if (cultural != null && cultural.isNotEmpty) {
      return null;
    }
    return null;
  }

  String? _deriveAudioUrl(Lesson lesson) {
    final metaAudio = lesson.metadata?['audio_url'];
    if (metaAudio is String && metaAudio.isNotEmpty) return metaAudio;
    return null;
  }

  double _goalBias(Lesson lesson, List<String> skills, GoalProfile? profile) {
    if (profile == null) return 0.0;
    double weight = 0.0;
    for (final skill in skills) {
      final key = _skillKey(skill);
      if (key != null) {
        weight += profile.skillWeights[key] ?? 0.0;
      }
    }
    final typeKey = _lessonTypeKey(lesson);
    weight += (profile.exerciseTypeWeights[typeKey] ?? 0.0) * 0.5;
    return weight;
  }

  String? _skillKey(String skill) {
    switch (skill) {
      case 'Listening':
        return 'listening';
      case 'Speaking':
        return 'production';
      case 'Reading':
        return 'reading';
      case 'Writing':
        return 'characters';
      default:
        return 'meaning';
    }
  }

  String _lessonTypeKey(Lesson lesson) {
    final type = lesson.metadata?['type'] as String? ?? lesson.mode;
    switch (type) {
      case 'review':
        return 'meaning_select';
      case 'practice':
        return 'reply_select';
      case 'intro':
        return 'meaning_select';
      case 'listening':
        return 'audio_select';
      default:
        return 'meaning_select';
    }
  }
}

const Map<String, IconData> _skillIconMap = {
  'Listening': Icons.hearing_rounded,
  'Speaking': Icons.record_voice_over_rounded,
  'Reading': Icons.menu_book_rounded,
  'Writing': Icons.edit_rounded,
};

class PathPersona {
  final String id;
  final String label;
  final List<String> templates;

  const PathPersona({
    required this.id,
    required this.label,
    required this.templates,
  });
}

const Map<String, PathPersona> _personas = {
  'hsk': PathPersona(
    id: 'hsk',
    label: 'Exam Warrior',
    templates: [
      'HSK focus: {unit}',
      'Exam-ready phrases in {unit}',
      'Test drills: {unit}',
    ],
  ),
  'casual': PathPersona(
    id: 'casual',
    label: 'Casual Explorer',
    templates: [
      'Everyday {unit} phrases',
      'Casual chats about {unit}',
      'Speak naturally: {unit}',
    ],
  ),
  'professional': PathPersona(
    id: 'professional',
    label: 'Professional',
    templates: [
      'Work-ready {unit} language',
      'Professional tone: {unit}',
      'Business phrases for {unit}',
    ],
  ),
  'survival': PathPersona(
    id: 'survival',
    label: 'Survivalist',
    templates: [
      'Essential {unit} phrases',
      'Survival basics: {unit}',
      'Stay safe: {unit}',
    ],
  ),
  'cultural': PathPersona(
    id: 'cultural',
    label: 'Culturalist',
    templates: [
      'Culture notes: {unit}',
      'Stories & idioms around {unit}',
      'Understand {unit} in context',
    ],
  ),
  'digital': PathPersona(
    id: 'digital',
    label: 'Digital Nomad',
    templates: [
      'Modern life: {unit}',
      'Tech talk: {unit}',
      'Urban phrases for {unit}',
    ],
  ),
};

String personaLabel(String? personaId) {
  if (personaId == null) return 'Mission: Choose a focus';
  return 'Mission: ${_personas[personaId]?.label ?? 'Choose a focus'}';
}

String? _personaFocusLabel(String? personaId) {
  if (personaId == null) return null;
  final label = _personas[personaId]?.label;
  if (label == null) return null;
  return '$label Focus';
}

String? _goalFocusLabel(GoalProfile? profile, String? personaId) {
  if (profile != null) {
    return '${profile.label}';
  }
  return _personaFocusLabel(personaId);
}

String _personaPromise(String unitTitle, String? personaId, int index) {
  if (unitTitle.trim().isEmpty) return 'Practice core phrases';
  final persona = personaId == null ? null : _personas[personaId];
  final templates =
      persona?.templates ??
      [
        'Practice {unit} phrases',
        'Learn {unit} basics',
        'Build confidence with {unit}',
        'Use {unit} in context',
      ];
  final template = templates[index % templates.length];
  return template.replaceAll('{unit}', unitTitle);
}
