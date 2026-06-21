import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/path_theme.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/services/pilot_exercise_pack_loader.dart';
import 'package:dragon_chinese/features/course/services/mastery_store.dart';
import 'package:dragon_chinese/features/course/services/readiness_scorer.dart';
import 'package:dragon_chinese/features/course/services/drill_plan_builder.dart';
import 'package:dragon_chinese/features/course/screens/practice_session_screen.dart';
import 'package:dragon_chinese/features/course/services/practice_models.dart';

class ReadinessScreen extends StatefulWidget {
  const ReadinessScreen({super.key});

  @override
  State<ReadinessScreen> createState() => _ReadinessScreenState();
}

class _ReadinessScreenState extends State<ReadinessScreen> {
  final _loader = PilotExercisePackLoader();
  PilotExercisePack? _pack;
  MasteryStore? _mastery;
  ReadinessScore? _score;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pack = await _loader.loadPack();
      final mastery = await MasteryStore.load();
      final scorer = ReadinessScorer();
      final ids = pack.items.map((e) => e.conceptId).toSet().toList();
      final score = scorer.score(mastery: mastery, conceptIds: ids);
      if (!mounted) return;
      setState(() {
        _pack = pack;
        _mastery = mastery;
        _score = score;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('HSK1 readiness')),
        body: Center(child: Text('Error: $_error')),
      );
    }
    if (_pack == null || _mastery == null || _score == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('HSK1 readiness')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final score = _score!;
    final overall = score.overallRounded;
    final statusLabel = _statusLabel(overall);
    final breakdown = score.breakdown;

    return Scaffold(
      backgroundColor: PathThemeTokens.background,
      appBar: AppBar(
        backgroundColor: PathThemeTokens.surface,
        title: const Text('HSK1 readiness'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ReadinessScoreCard(overall: overall, label: statusLabel),
          const SizedBox(height: 16),
          _SectionBreakdownCard(
            vocab: breakdown.vocab,
            listening: breakdown.listening,
            reading: breakdown.reading,
          ),
          const SizedBox(height: 16),
          _CoverageCard(
            attempted: score.attemptedCoverage,
            solid: score.solidCoverage,
          ),
          const SizedBox(height: 16),
          _WeakWordsCard(
            items: _weakWords(_pack!, _mastery!),
            onTapWord: (wordId) => _startDrill(weakWordId: wordId),
          ),
          const SizedBox(height: 16),
          _ActionRow(
            onWeakSkill: () => _startDrill(mode: DrillMode.weakSkills),
            onDue: () => _startDrill(mode: DrillMode.dueOnly),
            onMistakes: () => _startDrill(mode: DrillMode.mistakes),
          ),
        ],
      ),
    );
  }

  String _statusLabel(int score) {
    if (score >= 80) return 'Ready';
    if (score >= 60) return 'On track';
    return 'Needs work';
  }

  List<_WeakWord> _weakWords(PilotExercisePack pack, MasteryStore mastery) {
    final map = <int, _WeakWord>{};
    for (final item in pack.items) {
      final wordId = item.conceptId;
      if (map.containsKey(wordId)) continue;
      final meaning = mastery.skillStateFor(wordId, 'meaning');
      final character = mastery.skillStateFor(wordId, 'character');
      final avg = (meaning.score + character.score) / 2;
      final label = item.prompt.meaning ?? item.prompt.hanzi ?? 'Word $wordId';
      map[wordId] = _WeakWord(wordId: wordId, label: label, score: avg);
    }
    final list = map.values.toList();
    list.sort((a, b) => a.score.compareTo(b.score));
    return list.take(5).toList();
  }

  void _startDrill({DrillMode mode = DrillMode.weakSkills, int? weakWordId}) {
    final pack = _pack;
    final mastery = _mastery;
    if (pack == null || mastery == null) return;
    final dateBucket = DateTime.now().toIso8601String().substring(0, 10);
    PracticeSessionPlan plan;
    if (weakWordId != null) {
      final items = pack.items
          .where((item) => item.conceptId == weakWordId)
          .take(4)
          .toList();
      plan = PracticeSessionPlan(
        seed: 'readiness-word',
        dateBucket: dateBucket,
        sections: [
          PracticeSessionSection(label: 'Focused word', items: items.map((item) {
            return PracticeSessionItem(
              id: item.id,
              wordId: item.conceptId,
              exerciseType: item.exerciseType,
              skill: _skillForType(item.exerciseType),
              level: item.level,
              why: 'Focused word drill',
              reasonCodes: const ['WEAK_SKILL'],
              meta: {
                'unit_id': item.unitId,
                'skill_target': _skillForType(item.exerciseType),
                'word_stage': mastery
                    .skillStateFor(item.conceptId, _skillForType(item.exerciseType))
                    .stage
                    .name,
              },
            );
          }).toList()),
        ],
        items: items.map((item) {
          return PracticeSessionItem(
            id: item.id,
            wordId: item.conceptId,
            exerciseType: item.exerciseType,
            skill: _skillForType(item.exerciseType),
            level: item.level,
            why: 'Focused word drill',
            reasonCodes: const ['WEAK_SKILL'],
            meta: {
              'unit_id': item.unitId,
              'skill_target': _skillForType(item.exerciseType),
              'word_stage': mastery
                  .skillStateFor(item.conceptId, _skillForType(item.exerciseType))
                  .stage
                  .name,
            },
          );
        }).toList(),
      );
    } else {
      final builder = DrillPlanBuilder();
      final config = _configFor(mode);
      plan = builder.buildPlan(
        pack: pack,
        mastery: mastery,
        seed: 'readiness-drill',
        dateBucket: dateBucket,
        config: config,
      );
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PracticeSessionScreen(
          planOverride: plan,
        ),
      ),
    );
  }

  String _skillForType(String type) {
    switch (type) {
      case 'meaning_select':
      case 'meaning_match':
        return 'meaning';
      case 'character_select':
      case 'order_sentence':
        return 'character';
      case 'audio_select':
      case 'dictation_select':
      case 'pinyin_select':
        return 'listening';
      case 'cloze_select':
      case 'reading_micro':
        return 'reading';
      case 'reply_select':
      case 'speak_prompted_reply':
      case 'speak_read_aloud':
        return 'production';
      default:
        return 'meaning';
    }
  }

  DrillPlanConfig _configFor(DrillMode mode) {
    switch (mode) {
      case DrillMode.dueOnly:
        return const DrillPlanConfig(dueCount: 12, weakCount: 0, newCount: 0);
      case DrillMode.mistakes:
        return const DrillPlanConfig(dueCount: 4, weakCount: 8, newCount: 0);
      case DrillMode.weakSkills:
      default:
        return const DrillPlanConfig(dueCount: 6, weakCount: 6, newCount: 4);
    }
  }
}

enum DrillMode { weakSkills, dueOnly, mistakes }

class _WeakWord {
  final int wordId;
  final String label;
  final double score;

  _WeakWord({required this.wordId, required this.label, required this.score});
}

class ReadinessScoreCard extends StatelessWidget {
  final int overall;
  final String label;

  const ReadinessScoreCard({super.key, required this.overall, required this.label});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 340;
        final scoreText = Text(
          '$overall',
          style: PathThemeTokens.title.copyWith(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: PathThemeTokens.textPrimary,
          ),
        );
        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'HSK1 readiness snapshot',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: PathThemeTokens.sectionLabel,
            ),
            const SizedBox(height: 4),
            Text(label, style: PathThemeTokens.title),
          ],
        );
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: PathThemeTokens.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: PathThemeTokens.borderSubtle),
          ),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    scoreText,
                    const SizedBox(height: 12),
                    info,
                  ],
                )
              : Row(
                  children: [
                    scoreText,
                    const SizedBox(width: 16),
                    Expanded(child: info),
                  ],
                ),
        );
      },
    );
  }
}

class _SectionBreakdownCard extends StatelessWidget {
  final double vocab;
  final double listening;
  final double reading;

  const _SectionBreakdownCard({
    required this.vocab,
    required this.listening,
    required this.reading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PathThemeTokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PathThemeTokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Section breakdown', style: PathThemeTokens.title),
          const SizedBox(height: 12),
          _row('Vocab', vocab),
          _row('Listening', listening),
          _row('Reading', reading),
        ],
      ),
    );
  }

  Widget _row(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: PathThemeTokens.subtitle)),
          Text('${value.toStringAsFixed(0)}%',
              style: PathThemeTokens.subtitle),
        ],
      ),
    );
  }
}

class _CoverageCard extends StatelessWidget {
  final double attempted;
  final double solid;

  const _CoverageCard({
    required this.attempted,
    required this.solid,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PathThemeTokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PathThemeTokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Coverage', style: PathThemeTokens.title),
          const SizedBox(height: 12),
          _row('Attempted', attempted),
          _row('Solid+', solid),
        ],
      ),
    );
  }

  Widget _row(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: PathThemeTokens.subtitle)),
          Text('${(value * 100).toStringAsFixed(0)}%',
              style: PathThemeTokens.subtitle),
        ],
      ),
    );
  }
}

class _WeakWordsCard extends StatelessWidget {
  final List<_WeakWord> items;
  final ValueChanged<int> onTapWord;

  const _WeakWordsCard({required this.items, required this.onTapWord});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PathThemeTokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PathThemeTokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top weak words', style: PathThemeTokens.title),
          const SizedBox(height: 8),
          ...items.map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.label, style: PathThemeTokens.subtitle),
              trailing: Text('${(item.score * 100).toStringAsFixed(0)}%',
                  style: PathThemeTokens.subtitle),
              onTap: () => onTapWord(item.wordId),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final VoidCallback onWeakSkill;
  final VoidCallback onDue;
  final VoidCallback onMistakes;

  const _ActionRow({
    required this.onWeakSkill,
    required this.onDue,
    required this.onMistakes,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Next drills', style: PathThemeTokens.title),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            ElevatedButton(
              onPressed: onWeakSkill,
              child: const Text('Drill weak skills'),
            ),
            OutlinedButton(
              onPressed: onDue,
              child: const Text('Review due words'),
            ),
            OutlinedButton(
              onPressed: onMistakes,
              child: const Text('Fix mistakes'),
            ),
          ],
        ),
      ],
    );
  }
}
