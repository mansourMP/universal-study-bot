import 'dart:async';
import 'dart:math' as math;

import 'package:dragon_chinese/core/config/app_config.dart';
import 'package:dragon_chinese/features/course/services/skill_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VocabularyPracticeScreen extends StatefulWidget {
  final int level;
  final int offset;
  final int limit;
  final String setTitle;
  final String sourceLang;
  final String targetLang;

  const VocabularyPracticeScreen({
    super.key,
    required this.level,
    required this.offset,
    required this.limit,
    required this.setTitle,
    this.sourceLang = 'en',
    this.targetLang = AppConfig.targetLang,
  });

  @override
  State<VocabularyPracticeScreen> createState() =>
      _VocabularyPracticeScreenState();
}

class _VocabularyPracticeScreenState extends State<VocabularyPracticeScreen>
    with TickerProviderStateMixin {
  static const int _blockingPrefetchCount = 1;
  static const int _backgroundPrefetchCount = 18;
  static const int _rollingPrefetchCount = 6;

  List<VocabularyWord> _queue = [];
  int _initialCount = 0;
  bool _isLoading = true;
  bool _showBack = false;
  double _flipDirection = 1.0; // 1: right-side flip, -1: left-side flip

  int _knownCount = 0;
  int _againCount = 0;

  Offset _dragOffset = Offset.zero;
  double _cardRotation = 0.0;
  final Set<String> _invalidImageUrls = <String>{};
  late AnimationController _flingController;
  VoidCallback? _activeAnimationListener;

  @override
  void initState() {
    super.initState();
    _loadWords();
    _flingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
  }

  @override
  void dispose() {
    if (_activeAnimationListener != null) {
      _flingController.removeListener(_activeAnimationListener!);
      _activeAnimationListener = null;
    }
    _flingController.dispose();
    super.dispose();
  }

  Future<void> _loadWords() async {
    try {
      final words = await SkillService().fetchVocabularySet(
        widget.level,
        widget.offset,
        widget.limit,
        sourceLang: widget.sourceLang,
        targetLang: widget.targetLang,
      );
      final seen = <String>{};
      final unique = <VocabularyWord>[];
      for (final w in words) {
        final key = '${w.word}|${w.pinyin}|${w.meaning}';
        if (seen.add(key)) unique.add(w);
      }
      if (mounted) {
        setState(() {
          _queue = unique;
          _initialCount = unique.length;
          _knownCount = 0;
          _againCount = 0;
          _dragOffset = Offset.zero;
          _cardRotation = 0.0;
          _showBack = false;
          _invalidImageUrls.clear();
          _isLoading = true;
        });
        await _prefetchWords(
          unique.take(_blockingPrefetchCount).toList(growable: false),
          timeoutPerImage: const Duration(seconds: 5),
        );
        if (!mounted) return;
        setState(() => _isLoading = false);
        unawaited(
          _prefetchWords(
            unique
                .skip(_blockingPrefetchCount)
                .take(_backgroundPrefetchCount)
                .toList(growable: false),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _prefetchWords(
    List<VocabularyWord> words, {
    Duration timeoutPerImage = const Duration(seconds: 5),
  }) async {
    final seen = <String>{};
    final urls = <String>[];
    for (final word in words) {
      final imageUrl = _resolveImageUrl(word.imageUrl);
      if (!_shouldShowImage(imageUrl)) continue;
      if (imageUrl != null && seen.add(imageUrl)) {
        urls.add(imageUrl);
      }
    }

    for (final url in urls) {
      if (!mounted) return;
      try {
        final ImageProvider provider = url.startsWith('assets/')
            ? AssetImage(url)
            : NetworkImage(url);
        await precacheImage(provider, context).timeout(timeoutPerImage);
      } catch (_) {
        // Do not blacklist on prefetch failure; runtime Image.network can still
        // succeed later (e.g., temporary tunnel/network latency).
      }
    }
  }

  void _prefetchUpcomingCards() {
    if (!mounted || _queue.isEmpty) return;
    unawaited(
      _prefetchWords(
        _queue.take(_rollingPrefetchCount).toList(growable: false),
      ),
    );
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      final nextDx = (_dragOffset.dx + (details.delta.dx * 0.78)).clamp(
        -220.0,
        220.0,
      );
      final nextDy = (_dragOffset.dy + (details.delta.dy * 0.35)).clamp(
        -70.0,
        70.0,
      );
      _dragOffset = Offset(nextDx, nextDy);
      _cardRotation = _dragOffset.dx * 0.00045;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    final velocityX = details.velocity.pixelsPerSecond.dx;
    final dx = _dragOffset.dx;
    final shouldCommit = dx.abs() > 110 || velocityX.abs() > 500;
    if (shouldCommit) {
      final toRight = (dx + (velocityX * 0.08)) > 0;
      _flingCard(toRight);
    } else {
      _snapBack();
    }
  }

  void _runOffsetAnimation({
    required Offset begin,
    required Offset end,
    required Curve curve,
    Duration? duration,
    VoidCallback? onCompleted,
  }) {
    _flingController.stop();
    if (_activeAnimationListener != null) {
      _flingController.removeListener(_activeAnimationListener!);
      _activeAnimationListener = null;
    }

    final animation = Tween<Offset>(
      begin: begin,
      end: end,
    ).animate(CurvedAnimation(parent: _flingController, curve: curve));

    void listener() {
      if (!mounted) return;
      setState(() {
        _dragOffset = animation.value;
        _cardRotation = _dragOffset.dx * 0.0006;
      });
    }

    _activeAnimationListener = listener;
    _flingController.duration = duration ?? const Duration(milliseconds: 420);
    _flingController
      ..reset()
      ..addListener(listener);
    _flingController.forward().whenComplete(() {
      if (_activeAnimationListener != null) {
        _flingController.removeListener(_activeAnimationListener!);
        _activeAnimationListener = null;
      }
      onCompleted?.call();
    });
  }

  void _snapBack() {
    _runOffsetAnimation(
      begin: _dragOffset,
      end: Offset.zero,
      curve: Curves.easeOutBack,
      duration: const Duration(milliseconds: 360),
    );
    HapticFeedback.lightImpact();
  }

  void _flingCard(bool known) {
    if (_queue.isEmpty) return;
    final throwX = MediaQuery.of(context).size.width + 220;
    final target = Offset(known ? throwX : -throwX, _dragOffset.dy * 1.2);

    HapticFeedback.mediumImpact();
    _runOffsetAnimation(
      begin: _dragOffset,
      end: target,
      curve: Curves.easeInOutCubic,
      duration: const Duration(milliseconds: 520),
      onCompleted: () {
        if (!mounted) return;
        setState(() {
          _queue.removeAt(0);
          if (known) {
            _knownCount++;
          } else {
            _againCount++;
          }
          _dragOffset = Offset.zero;
          _cardRotation = 0.0;
          _showBack = false;
        });
        _prefetchUpcomingCards();
        if (mounted && _queue.isEmpty) {
          Navigator.pop(context);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_queue.isEmpty) {
      return const Scaffold(body: Center(child: Text('Done!')));
    }

    final progress = _knownCount / _initialCount;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      body: SafeArea(
        child: Column(
          children: [
            _buildGameProgressBar(progress),
            _buildTopNav(),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _SmallTallyDot(color: Colors.orange, count: _againCount),
                  _SmallTallyDot(color: Colors.green, count: _knownCount),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              flex: 15,
              child: Align(
                alignment: Alignment.topCenter,
                child: _buildActiveCard(),
              ),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  Widget _buildGameProgressBar(double value) {
    return Container(
      width: double.infinity,
      height: 12,
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width:
                (MediaQuery.of(context).size.width - 40) *
                value.clamp(0.0, 1.0),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF58CC02), Color(0xFF78D937)],
              ),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withValues(alpha: 0.3),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopNav() {
    final currentCard = (_knownCount + _againCount + 1).clamp(1, _initialCount);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black54),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          Text(
            widget.setTitle.toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 56,
            child: Text(
              '$currentCard/$_initialCount',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: Color(0xFF76859A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveCard() {
    final currentWord = _queue[0];
    return Transform.translate(
      offset: _dragOffset,
      child: Transform.rotate(
        angle: _cardRotation,
        child: Builder(
          builder: (gestureContext) => GestureDetector(
            onPanStart: (_) => HapticFeedback.selectionClick(),
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            onTapUp: (details) {
              final renderBox = gestureContext.findRenderObject() as RenderBox?;
              final width = renderBox?.size.width ?? 0;
              final x = details.localPosition.dx;
              final leftZone = width * 0.33;
              final rightZone = width * 0.67;

              var direction = _flipDirection;
              if (width > 0) {
                if (x <= leftZone) {
                  direction = -1.0;
                } else if (x >= rightZone) {
                  direction = 1.0;
                }
              }

              HapticFeedback.lightImpact();
              setState(() {
                _flipDirection = direction;
                _showBack = !_showBack;
              });
            },
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOutCubic,
              tween: Tween<double>(begin: 0, end: _showBack ? 1 : 0),
              builder: (context, value, _) {
                final progress = value;
                final signedAngle = progress * math.pi * _flipDirection;
                final showBack = progress > 0.5;
                final displayAngle = showBack
                    ? signedAngle - (math.pi * _flipDirection)
                    : signedAngle;

                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateY(displayAngle),
                  child: _CardBase(
                    key: ValueKey<String>(
                      '${showBack ? 'back' : 'front'}|'
                      '${currentWord.word}|'
                      '${currentWord.pinyin}|'
                      '${currentWord.meaning}|'
                      '${currentWord.imageUrl ?? ''}',
                    ),
                    color: Colors.white,
                    child: showBack
                        ? _buildBack(currentWord)
                        : _buildFront(currentWord),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFront(VocabularyWord word) {
    final imageUrl = _resolveImageUrl(word.imageUrl);
    final hasImage = _shouldShowImage(imageUrl);
    final displayWord = word.word.trim().isEmpty ? '—' : word.word.trim();
    final displayPinyin = word.pinyin.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 2),
          if (hasImage) ...[
            Expanded(child: _buildWordImage(imageUrl!)),
            const SizedBox(height: 16),
          ] else ...[
            const Spacer(),
            const SizedBox(height: 8),
          ],
          Text(
            displayWord,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 60,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111111),
              height: 1.05,
            ),
          ),
          if (displayPinyin.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              displayPinyin,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Color(0xFF7B8CA4),
                letterSpacing: 0.6,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBack(VocabularyWord word) {
    final displayMeaning = word.meaning.trim().isEmpty
        ? 'Unknown'
        : word.meaning.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _sectionLabel('MEANING'),
          const SizedBox(height: 12),
          Text(
            displayMeaning,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: Color(0xFF121212),
              height: 1.1,
            ),
          ),
          const SizedBox(height: 28),
          if (word.contextSentence != null) ...[
            _sectionLabel('EXAMPLE'),
            const SizedBox(height: 12),
            _exampleBox(word.contextSentence!),
          ],
        ],
      ),
    );
  }

  Widget _buildWordImage(String imageUrl) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        color: const Color(0xFFF4F7FC),
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) {
            _markImageUnavailable(imageUrl);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  bool _shouldShowImage(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return false;
    return !_invalidImageUrls.contains(imageUrl);
  }

  void _markImageUnavailable(String imageUrl) {
    if (_invalidImageUrls.contains(imageUrl)) return;
    _invalidImageUrls.add(imageUrl);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
    });
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

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: Color(0xFF98A4B6),
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _exampleBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4EAF4)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 17,
          color: Color(0xFF38465A),
          fontStyle: FontStyle.italic,
          height: 1.45,
        ),
      ),
    );
  }
}

class _SmallTallyDot extends StatelessWidget {
  final Color color;
  final int count;
  const _SmallTallyDot({required this.color, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _CardBase extends StatelessWidget {
  final Color color;
  final Widget child;
  const _CardBase({super.key, required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final width = math.min(screen.width - 26, 360.0);
    final height = math.min(screen.height * 0.64, 560.0);
    final top = Color.lerp(color, Colors.white, 0.18) ?? color;
    final bottom = Color.lerp(color, const Color(0xFFF6FAFF), 0.65) ?? color;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFE0E8F4), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 34,
            offset: const Offset(0, 15),
          ),
          BoxShadow(
            color: const Color(0xFF90A4C8).withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.20),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.03),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
