import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/design_system.dart';
import 'package:dragon_chinese/core/utils/loadable.dart';
import 'package:dragon_chinese/features/course/controllers/reading_controller.dart';

class ReadingScreen extends StatefulWidget {
  final String sourceLang;
  const ReadingScreen({super.key, required this.sourceLang});

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> {
  final ReadingController _controller = ReadingController();
  Loadable<List<ReadingUnit>> _state = const Loading();

  @override
  void initState() {
    super.initState();
    _fetchUnits();
  }

  Future<void> _fetchUnits() async {
    try {
      setState(() => _state = const Loading());
      final units = await _controller.loadUnits();
      if (!mounted) return;
      setState(() => _state = Data(units));
    } catch (e, st) {
      print("Error fetching units: $e\n$st");
      if (!mounted) return;
      setState(() => _state = ErrorState("Failed to load stories.", error: e));
    }
  }

  void _openStory(ReadingUnit unit) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _StoryReader(
          unitId: unit.id,
          title: unit.title,
          guideId: unit.guideId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Story Library',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final state = _state;
    if (state is Loading<List<ReadingUnit>>) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state is ErrorState<List<ReadingUnit>>) {
      return _buildErrorState(state.message);
    }
    final units = (state as Data<List<ReadingUnit>>).value;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: units.length,
      itemBuilder: (context, index) {
        final unit = units[index];
        return _ReadingCard(
          title: unit.title,
          subtitle: unit.subtitle,
          guideId: unit.guideId,
          onTap: () => _openStory(unit),
        );
      },
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _fetchUnits, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _ReadingCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String guideId;
  final VoidCallback onTap;

  const _ReadingCard({
    required this.title,
    required this.subtitle,
    required this.guideId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isLongLong = guideId == "CHAR_LONGLONG";
    final Color themeColor = isLongLong ? Colors.amber : Colors.green;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isLongLong ? Icons.auto_awesome : Icons.menu_book,
                color: themeColor,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

class _StoryReader extends StatefulWidget {
  final String unitId;
  final String title;
  final String guideId;
  final StoryController? controller;

  const _StoryReader({
    required this.unitId,
    required this.title,
    required this.guideId,
    this.controller,
  });

  @override
  State<_StoryReader> createState() => _StoryReaderState();
}

class _StoryReaderState extends State<_StoryReader> {
  late final StoryController _controller;
  Loadable<Map<String, dynamic>> _state = const Loading();
  bool _showPinyin = true;
  bool _showTranslation = true;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? StoryController();
    _fetchStory();
  }

  Future<void> _fetchStory() async {
    try {
      setState(() => _state = const Loading());
      final story = await _controller.loadStory(widget.unitId);
      if (!mounted) return;
      setState(() => _state = Data(story));
    } catch (e, st) {
      print("Error fetching story: $e\n$st");
      if (!mounted) return;
      setState(() => _state = ErrorState("Failed to load story.", error: e));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Character Logic
    final bool isHuaHua = widget.guideId == "CHAR_HUAHUA";
    final bool isLongLong = widget.guideId == "CHAR_LONGLONG";
    final String guideName = isHuaHua
        ? "Hua Hua"
        : (isLongLong ? "Long Long" : "Shifu");
    final Color guideColor = isHuaHua
        ? AppColors.primary
        : (isLongLong ? Colors.amber : Colors.grey);

    // In a real app, use asset images: 'assets/images/characters/${widget.guideId}.png'
    final IconData guideIcon = isHuaHua
        ? Icons.face_3
        : (isLongLong ? Icons.auto_awesome : Icons.self_improvement);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.translate,
              color: _showTranslation ? AppColors.primary : Colors.grey,
            ),
            onPressed: () =>
                setState(() => _showTranslation = !_showTranslation),
          ),
          IconButton(
            icon: Icon(
              Icons.text_fields,
              color: _showPinyin ? AppColors.primary : Colors.grey,
            ),
            onPressed: () => setState(() => _showPinyin = !_showPinyin),
          ),
        ],
      ),
      body: _buildStoryBody(guideColor, guideName, guideIcon),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // Future: Play Audio
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Audio playback will be available soon"),
            ),
          );
        },
        backgroundColor: guideColor,
        icon: const Icon(Icons.play_arrow),
        label: const Text("Listen"),
      ),
    );
  }

  Widget _buildStoryBody(
    Color guideColor,
    String guideName,
    IconData guideIcon,
  ) {
    final state = _state;
    if (state is Loading<Map<String, dynamic>>) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state is ErrorState<Map<String, dynamic>>) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.message, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _fetchStory, child: const Text('Retry')),
          ],
        ),
      );
    }
    final story = (state as Data<Map<String, dynamic>>).value;
    if (story.isEmpty) {
      return const Center(child: Text("Story not available."));
    }
    return SingleChildScrollView(
      child: Column(
        children: [
          // --- NARRATOR HEADER ---
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: guideColor.withOpacity(0.05),
              border: Border(
                bottom: BorderSide(color: guideColor.withOpacity(0.1)),
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: guideColor.withOpacity(0.2),
                        blurRadius: 15,
                      ),
                    ],
                  ),
                  child: Icon(guideIcon, size: 48, color: guideColor),
                ),
                const SizedBox(height: 12),
                Text(
                  "NARRATED BY $guideName",
                  style: TextStyle(
                    color: guideColor,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // --- CONTENT ---
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  story['title_zh'] ?? '',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  story['title_en'] ?? widget.title,
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 32),

                // Story
                Text(
                  story['story_zh'] ?? '',
                  style: const TextStyle(
                    fontSize: 24,
                    height: 1.8,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                if (_showPinyin && story['story_pinyin'] != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      story['story_pinyin'] ?? '',
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.blueGrey,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],

                if (_showTranslation && story['story_en'] != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      story['story_en'] ?? '',
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.black87,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
