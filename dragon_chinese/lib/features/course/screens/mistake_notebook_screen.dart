import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/path_theme.dart';
import 'package:dragon_chinese/features/course/services/mistake_notebook.dart';

class MistakeNotebookScreen extends StatefulWidget {
  const MistakeNotebookScreen({super.key});

  @override
  State<MistakeNotebookScreen> createState() => _MistakeNotebookScreenState();
}

class _MistakeNotebookScreenState extends State<MistakeNotebookScreen> {
  MistakeNotebook? _notebook;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final notebook = await MistakeNotebook.load();
    setState(() => _notebook = notebook);
  }

  @override
  Widget build(BuildContext context) {
    final notebook = _notebook;
    if (notebook == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final weakest = notebook.weakest(10);
    final streaks = notebook.streaks();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mistake Notebook'),
        backgroundColor: PathThemeTokens.surface,
        foregroundColor: PathThemeTokens.textPrimary,
        elevation: 0,
      ),
      backgroundColor: PathThemeTokens.background,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Your weakest 10', style: PathThemeTokens.title),
          const SizedBox(height: 8),
          if (weakest.isEmpty)
            Text('No mistakes recorded yet.', style: PathThemeTokens.subtitle),
          ...weakest.map((entry) => _entryTile(entry)),
          const SizedBox(height: 24),
          Text('Fix streaks', style: PathThemeTokens.title),
          const SizedBox(height: 8),
          if (streaks.isEmpty)
            Text('No active streaks.', style: PathThemeTokens.subtitle),
          ...streaks.map((entry) => _entryTile(entry)),
        ],
      ),
    );
  }

  Widget _entryTile(MistakeEntry entry) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: PathThemeTokens.border),
      ),
      child: ListTile(
        title: Text(
          'Concept ${entry.conceptId} · ${entry.exerciseType}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Wrong: ${entry.wrongCount} · Streak: ${entry.streak}',
        ),
      ),
    );
  }
}
