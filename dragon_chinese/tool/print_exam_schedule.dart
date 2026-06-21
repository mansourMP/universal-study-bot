import 'dart:convert';
import 'dart:io';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/services/exam_scheduler.dart';
import 'package:dragon_chinese/features/course/services/mistake_stats.dart';
import 'package:dragon_chinese/features/course/services/performance_models.dart';

Future<void> main(List<String> args) async {
  final path = args.isNotEmpty ? args[0] : 'docs/pilot/hsk1_exercises_v1.json';
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $path');
    exit(1);
  }
  final raw = await file.readAsString();
  final pack = PilotExercisePack.fromJson(jsonDecode(raw));
  final scheduler = ExamScheduler();
  final plan = scheduler.buildPlan(
    pack: pack,
    seed: 'hsk1-exam',
    performance: PerformanceSnapshot({}),
    mistakes: MistakeStats(typeWrongCount: {}),
  );

  print('Session duration: ${plan.duration.inMinutes} min');
  print('Counts: ${plan.counts}');
  for (final item in plan.items.take(12)) {
    print('${item.section} | ${item.item.exerciseType} | ${item.item.conceptId}');
  }
}
