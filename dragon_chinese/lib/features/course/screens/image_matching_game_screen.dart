import 'package:dragon_chinese/core/config/app_config.dart';
import 'package:dragon_chinese/core/utils/loadable.dart';
import 'package:dragon_chinese/design_system/design_system.dart';
import 'package:dragon_chinese/features/course/controllers/image_matching_controller.dart';
import 'package:dragon_chinese/features/course/services/skill_service.dart';
import 'package:flutter/material.dart';

class ImageMatchingGameScreen extends StatefulWidget {
  final int level;
  final int setIndex;
  final String sourceLang;
  final String targetLang;

  const ImageMatchingGameScreen({
    super.key,
    required this.level,
    required this.setIndex,
    required this.sourceLang,
    this.targetLang = AppConfig.targetLang,
  });

  @override
  State<ImageMatchingGameScreen> createState() =>
      _ImageMatchingGameScreenState();
}

class _ImageMatchingGameScreenState extends State<ImageMatchingGameScreen> {
  static const int _setSize = 10;

  final ImageMatchingController _controller = ImageMatchingController();
  final Set<String> _invalidImageUrls = <String>{};

  List<VocabularyWord> _allLevelWords = <VocabularyWord>[];
  List<VocabularyWord> _gameWords = <VocabularyWord>[];
  Loadable<List<VocabularyWord>> _state = const Loading();

  int _currentIndex = 0;
  List<String> _currentOptions = <String>[];
  String? _selectedOption;
  String? _correctOption;
  bool? _isCorrect;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() => _state = const Loading());
      final words = await _controller.loadWords(
        widget.level,
        widget.sourceLang,
        targetLang: widget.targetLang,
      );
      if (!mounted) return;

      _allLevelWords = words;
      _currentIndex = 0;

      if (words.isEmpty) {
        setState(() {
          _gameWords = <VocabularyWord>[];
          _state = Data(words);
        });
        return;
      }

      if (words.length <= _setSize) {
        _gameWords = List<VocabularyWord>.from(words);
      } else {
        final start = (widget.setIndex * _setSize) % words.length;
        _gameWords = words.skip(start).take(_setSize).toList();
        if (_gameWords.length < _setSize) {
          _gameWords = words.take(_setSize).toList();
        }
      }

      setState(() => _state = Data(words));
      _prepareQuestion();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _state = ErrorState('Failed to load image set.', error: e),
      );
    }
  }

  String _choiceLabel(VocabularyWord word) {
    final meaning = word.meaning.trim();
    if (meaning.isNotEmpty && meaning.toLowerCase() != 'unknown') {
      return meaning;
    }
    final context = word.contextSentence?.trim() ?? '';
    if (context.isNotEmpty) return context;
    return word.word;
  }

  void _prepareQuestion() {
    if (_gameWords.isEmpty) return;
    final correctWord = _gameWords[_currentIndex];
    final correct = _choiceLabel(correctWord);

    final distractors =
        _allLevelWords
            .where((w) => w.word != correctWord.word)
            .map(_choiceLabel)
            .where((label) => label.trim().isNotEmpty && label != correct)
            .toSet()
            .toList()
          ..shuffle();

    final options = <String>[correct, ...distractors.take(3)]..shuffle();

    setState(() {
      _currentOptions = options;
      _selectedOption = null;
      _correctOption = correct;
      _isCorrect = null;
    });
  }

  void _checkAnswer(String option) {
    if (_isCorrect != null) return;
    setState(() {
      _selectedOption = option;
      _isCorrect = option == _correctOption;
    });
  }

  void _nextQuestion() {
    if (_currentIndex < _gameWords.length - 1) {
      setState(() => _currentIndex++);
      _prepareQuestion();
      return;
    }
    _showCompletion();
  }

  void _showCompletion() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Set complete'),
          content: const Text('You finished this image-matching set.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
  }

  String? _resolveImageUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.trim().isEmpty) return null;
    final normalized = imageUrl.trim();
    if (normalized.startsWith('http') || normalized.startsWith('assets/')) {
      return normalized;
    }
    if (normalized.startsWith('/')) {
      return '${AppConfig.apiBaseUrl}$normalized';
    }
    return normalized;
  }

  void _markImageUnavailable(String imageUrl) {
    if (!_invalidImageUrls.add(imageUrl)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;

    if (state is Loading<List<VocabularyWord>>) {
      return const Scaffold(body: Center(child: AppProgressIndicator()));
    }

    if (state is ErrorState<List<VocabularyWord>>) {
      return AppScaffold(
        title: 'Image Matching',
        subtitle: 'Set ${widget.setIndex + 1}',
        body: Center(
          child: AppCard(
            variant: AppCardVariant.flat,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.error),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  state.message,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                GameButton(
                  text: 'Retry',
                  onPressed: _loadData,
                  variant: GameButtonVariant.primary,
                  fullWidth: true,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_gameWords.isEmpty) {
      return AppScaffold(
        title: 'Image Matching',
        subtitle: 'Set ${widget.setIndex + 1}',
        body: Center(
          child: Text(
            'No images available for this level yet.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    final currentWord = _gameWords[_currentIndex];
    final progress = (_currentIndex + 1) / _gameWords.length;

    return AppScaffold(
      title: 'Image Matching',
      subtitle:
          'Set ${widget.setIndex + 1} • ${AppConfig.levelPrefix} ${widget.level}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            variant: AppCardVariant.flat,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: Colors.grey[200],
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '${_currentIndex + 1}/${_gameWords.length}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(flex: 5, child: _buildImageCard(currentWord)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Choose the best match',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            flex: 6,
            child: ListView.separated(
              itemCount: _currentOptions.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, index) {
                final option = _currentOptions[index];
                return _buildOptionTile(option);
              },
            ),
          ),
          if (_selectedOption != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _buildFeedbackRow(),
            const SizedBox(height: AppSpacing.xs),
            GameButton(
              text: 'Continue',
              onPressed: _nextQuestion,
              variant: _isCorrect == true
                  ? GameButtonVariant.correct
                  : GameButtonVariant.wrong,
              fullWidth: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImageCard(VocabularyWord word) {
    final imageUrl = _resolveImageUrl(word.imageUrl);
    final showImage =
        imageUrl != null &&
        imageUrl.isNotEmpty &&
        !_invalidImageUrls.contains(imageUrl);

    return AppCard(
      variant: AppCardVariant.hero,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.heroCard),
        child: Container(
          color: const Color(0xFFF5F7FB),
          width: double.infinity,
          child: showImage
              ? Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) {
                    _markImageUnavailable(imageUrl);
                    return _buildImagePlaceholder();
                  },
                )
              : _buildImagePlaceholder(),
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return const Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 52,
        color: Color(0xFFB8C1CF),
      ),
    );
  }

  Widget _buildOptionTile(String option) {
    final theme = Theme.of(context);
    final isSelected = _selectedOption == option;
    final isAnswerKnown = _isCorrect != null;
    final isRightOption = option == _correctOption;

    Color background = theme.colorScheme.surface;
    Color border = theme.colorScheme.outline.withValues(alpha: 0.25);

    if (isAnswerKnown && isSelected) {
      if (_isCorrect == true) {
        background = const Color(0xFFEAF9F0);
        border = AppColors.success;
      } else {
        background = const Color(0xFFFDECEC);
        border = AppColors.error;
      }
    } else if (isAnswerKnown && _isCorrect == false && isRightOption) {
      background = const Color(0xFFEAF9F0);
      border = AppColors.success.withValues(alpha: 0.45);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isAnswerKnown ? null : () => _checkAnswer(option),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: 1.2),
          ),
          child: Text(
            option,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeedbackRow() {
    final correct = _isCorrect == true;
    final icon = correct ? Icons.check_circle_rounded : Icons.info_rounded;
    final color = correct ? AppColors.success : AppColors.error;
    final text = correct ? 'Correct' : 'Not quite';

    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.xxxs),
        Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
