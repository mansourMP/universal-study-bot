import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dragon_chinese/core/config/app_config.dart';
import 'package:dragon_chinese/features/course/services/skill_service.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'dart:math' as math;

class VocabularyScrollScreen extends StatefulWidget {
  final String sourceLang;
  const VocabularyScrollScreen({super.key, this.sourceLang = 'en'});

  @override
  State<VocabularyScrollScreen> createState() => _VocabularyScrollScreenState();
}

class _VocabularyScrollScreenState extends State<VocabularyScrollScreen> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  List<SkillGroup> _levelStats = [];
  bool _isLoading = true;
  int _activeLevel = 1;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _itemPositionsListener.itemPositions.addListener(_updateActiveLevel);
  }

  void _updateActiveLevel() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      final firstVisible = positions
          .where((p) => p.itemLeadingEdge < 0.5)
          .toList();
      if (firstVisible.isNotEmpty) {
        int index = firstVisible.last.index;
        int level = (index ~/ 2) + 1;
        if (level != _activeLevel && level >= 1 && level <= 6) {
          setState(() => _activeLevel = level);
        }
      }
    }
  }

  Future<void> _loadStats() async {
    final stats = await SkillService().fetchSkillStats(
      AppConfig.targetLang,
      sourceLang: widget.sourceLang,
    );
    setState(() {
      _levelStats = stats;
      _isLoading = false;
    });
  }

  void _jumpToLevel(int level) {
    _itemScrollController.scrollTo(
      index: (level - 1) * 2,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
    );
    setState(() => _activeLevel = level);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7), // Neutral modern gray-white
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: const Text(
          'Vocabulary Mastery',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : Column(
              children: [
                _buildLevelSelector(),
                Expanded(
                  child: ScrollablePositionedList.builder(
                    itemCount: 12,
                    itemScrollController: _itemScrollController,
                    itemPositionsListener: _itemPositionsListener,
                    itemBuilder: (context, index) {
                      int level = (index ~/ 2) + 1;
                      bool isHeader = index % 2 == 0;
                      if (isHeader) return _buildLevelHeader(level);
                      return _buildSetsGrid(level);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLevelSelector() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4),
        ],
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 6,
        itemBuilder: (context, index) {
          int level = index + 1;
          bool isActive = _activeLevel == level;
          return GestureDetector(
            onTap: () => _jumpToLevel(level),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 50,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: isActive ? Colors.black : Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$level',
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.black54,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLevelHeader(int level) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          Text(
            '${AppConfig.levelPrefix} $level',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(child: Divider(thickness: 1)),
        ],
      ),
    );
  }

  Widget _buildSetsGrid(int level) {
    final stat = _levelStats.firstWhere(
      (s) => s.level == level,
      orElse: () =>
          SkillGroup(level: level, count: 0, label: '', description: ''),
    );
    int totalWords = stat.count > 0 ? stat.count : 150;
    int setCount = (totalWords / 20).ceil();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: setCount,
      itemBuilder: (context, index) {
        return _SetButton(
          label: '${index + 1}',
          onTap: () => _startMasterySession(level, index * 20),
        );
      },
    );
  }

  void _startMasterySession(int level, int offset) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => MasterySessionScreen(
          level: level,
          offset: offset,
          sourceLang: widget.sourceLang,
        ),
      ),
    );
  }
}

class _SetButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SetButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}

class MasterySessionScreen extends StatefulWidget {
  final int level;
  final int offset;
  final String sourceLang;

  const MasterySessionScreen({
    super.key,
    required this.level,
    required this.offset,
    required this.sourceLang,
  });

  @override
  State<MasterySessionScreen> createState() => _MasterySessionScreenState();
}

class _MasterySessionScreenState extends State<MasterySessionScreen> {
  List<VocabularyWord> _sessionPool = [];
  int _initialCount = 0;
  int _masteredCount = 0;
  bool _isLoading = true;
  final CardSwiperController _controller = CardSwiperController();

  @override
  void initState() {
    super.initState();
    _loadInitialWords();
  }

  void _loadInitialWords() async {
    final words = await SkillService().fetchVocabularySet(
      widget.level,
      widget.offset,
      20,
      sourceLang: widget.sourceLang,
    );
    setState(() {
      _sessionPool = words;
      _initialCount = words.length;
      _isLoading = false;
    });
  }

  bool _onSwipe(
    int previousIndex,
    int? currentIndex,
    CardSwiperDirection direction,
  ) {
    final swipedWord = _sessionPool[previousIndex];
    if (direction == CardSwiperDirection.right) {
      HapticFeedback.mediumImpact();
      setState(() => _masteredCount++);
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _sessionPool.add(swipedWord);
      });
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    double progress = _initialCount == 0 ? 0 : _masteredCount / _initialCount;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 10,
            backgroundColor: Colors.white,
            color: Colors.black,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : _masteredCount >= _initialCount
          ? _buildCompletionState()
          : CardSwiper(
              controller: _controller,
              cardsCount: _sessionPool.length,
              onSwipe: _onSwipe,
              numberOfCardsDisplayed: 3,
              scale: 0.9,
              threshold: 50,
              backCardOffset: const Offset(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
              cardBuilder:
                  (
                    context,
                    index,
                    horizontalThresholdPercentage,
                    verticalThresholdPercentage,
                  ) {
                    return _MasteryCard(
                      key: ValueKey(
                        _sessionPool[index].word + index.toString(),
                      ),
                      word: _sessionPool[index],
                    );
                  },
            ),
    );
  }

  Widget _buildCompletionState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 100,
            color: Colors.green,
          ),
          const SizedBox(height: 20),
          const Text(
            'Mastered!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Return', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _MasteryCard extends StatefulWidget {
  final VocabularyWord word;
  const _MasteryCard({super.key, required this.word});

  @override
  State<_MasteryCard> createState() => _MasteryCardState();
}

class _MasteryCardState extends State<_MasteryCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _flipController;
  late Animation<double> _animation;
  bool _isFront = true;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _toggleFlip() {
    HapticFeedback.lightImpact();
    if (_isFront)
      _flipController.forward();
    else
      _flipController.reverse();
    _isFront = !_isFront;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleFlip,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final angle = _animation.value * math.pi;
          return Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            alignment: Alignment.center,
            child: angle < math.pi / 2 ? _buildFront() : _buildBack(),
          );
        },
      ),
    );
  }

  Widget _buildFront() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Text(
          widget.word.word,
          style: const TextStyle(
            fontSize: 80,
            fontWeight: FontWeight.w400,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  Widget _buildBack() {
    return Transform(
      transform: Matrix4.identity()..rotateY(math.pi),
      alignment: Alignment.center,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'PRONUNCIATION',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 2,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.word.pinyin,
              style: const TextStyle(
                color: Colors.blueAccent,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Divider(),
            ),
            const Text(
              'TRANSLATION',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 2,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.word.meaning,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
