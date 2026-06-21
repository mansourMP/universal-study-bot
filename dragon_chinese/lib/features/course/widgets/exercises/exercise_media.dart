import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dragon_chinese/design_system/exercise_theme.dart';

class ExerciseMediaSlot extends StatelessWidget {
  final String? imageUrl;
  final String? audioUrl;
  final bool showImagePlaceholder;
  final bool showAudio;
  final bool enableAudio;
  final double imageSize;

  const ExerciseMediaSlot({
    super.key,
    this.imageUrl,
    this.audioUrl,
    this.showImagePlaceholder = false,
    this.showAudio = false,
    this.enableAudio = true,
    this.imageSize = ExerciseThemeTokens.mediaMinHeight,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;

    if (!showAudio && !hasImage && !showImagePlaceholder) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: ExerciseThemeTokens.surface,
        borderRadius: BorderRadius.circular(ExerciseThemeTokens.cardRadius),
        border: Border.all(color: ExerciseThemeTokens.border),
        // No shadows per UX rules
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showAudio)
            _MediaAudioHeader(audioUrl: audioUrl, enablePlayback: enableAudio),
          if (hasImage)
            _ImageCard(url: imageUrl!, size: imageSize)
          else if (showImagePlaceholder)
            _ImagePlaceholder(size: imageSize),
        ],
      ),
    );
  }
}

class _MediaAudioHeader extends StatefulWidget {
  final String? audioUrl;
  final bool enablePlayback;

  const _MediaAudioHeader({this.audioUrl, this.enablePlayback = true});

  @override
  State<_MediaAudioHeader> createState() => _MediaAudioHeaderState();
}

class _MediaAudioHeaderState extends State<_MediaAudioHeader>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool _hasPlaybackError = false;
  bool _isPressed = false;
  StreamSubscription<PlayerState>? _stateSub;
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulse = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      final playing = state == PlayerState.playing;
      if (playing) {
        if (!_pulseController.isAnimating) {
          _pulseController.repeat(reverse: true);
        }
      } else {
        _pulseController.stop();
        _pulseController.value = 0;
      }
      if (!mounted) return;
      setState(() => _isPlaying = playing);
    });
  }

  @override
  void didUpdateWidget(covariant _MediaAudioHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioUrl != widget.audioUrl) {
      _player.stop();
      _hasPlaybackError = false;
      _isPlaying = false;
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _player.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _playAudio() async {
    if (!widget.enablePlayback) return;
    final url = widget.audioUrl;
    if (url == null || url.isEmpty) return;
    try {
      HapticFeedback.selectionClick();
      setState(() {
        _isPlaying = true;
        _hasPlaybackError = false;
      });
      await _player.play(UrlSource(url));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _hasPlaybackError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAudio = widget.audioUrl != null && widget.audioUrl!.isNotEmpty;
    final canPlay = hasAudio && widget.enablePlayback;
    final isError = hasAudio && _hasPlaybackError;
    final label = !hasAudio
        ? 'No audio loaded for this exercise'
        : isError
        ? 'Playback failed. Tap to retry.'
        : (_isPlaying ? 'Playing audio...' : 'Tap to play audio');
    final helper = !hasAudio
        ? 'Try another item or regenerate content.'
        : isError
        ? 'Check connection and try again.'
        : 'Listening mode';
    final headerColor = !hasAudio
        ? const Color(0xFFFFF6E8)
        : isError
        ? const Color(0xFFFFF1EC)
        : (_isPlaying
              ? const Color(0xFFEAF2FF)
              : ExerciseThemeTokens.surfaceSubtle);
    final iconBg = !hasAudio
        ? const Color(0xFFFFE9C7)
        : isError
        ? const Color(0xFFFED9CE)
        : (_isPlaying ? const Color(0xFFD9E7FF) : ExerciseThemeTokens.surface);
    final iconColor = !hasAudio
        ? const Color(0xFFB45309)
        : isError
        ? const Color(0xFFC2410C)
        : (_isPlaying
              ? const Color(0xFF1D4ED8)
              : ExerciseThemeTokens.textPrimary);
    final icon = !hasAudio
        ? Icons.volume_off_rounded
        : isError
        ? Icons.refresh_rounded
        : (_isPlaying ? Icons.volume_up_rounded : Icons.play_arrow_rounded);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canPlay ? _playAudio : null,
        onHighlightChanged: (value) {
          if (_isPressed == value) return;
          setState(() => _isPressed = value);
        },
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ExerciseThemeTokens.cardRadius),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: headerColor,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(ExerciseThemeTokens.cardRadius),
            ),
            border: Border(
              bottom: BorderSide(color: ExerciseThemeTokens.border),
            ),
          ),
          child: Row(
            children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  final pulseScale = _isPlaying
                      ? (1 + (_pulse.value * 0.08))
                      : 1;
                  final pressedScale = _isPressed ? 0.96 : 1.0;
                  return Transform.scale(
                    scale: pulseScale * pressedScale,
                    child: child,
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: ExerciseThemeTokens.border),
                    boxShadow: _isPlaying
                        ? [
                            BoxShadow(
                              color: const Color(0x331D4ED8),
                              blurRadius: 12,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : const [],
                  ),
                  alignment: Alignment.center,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(scale: animation, child: child),
                      );
                    },
                    child: Icon(
                      icon,
                      key: ValueKey<IconData>(icon),
                      size: 20,
                      color: iconColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: ExerciseThemeTokens.promptBody.copyWith(
                        color: !hasAudio
                            ? const Color(0xFF92400E)
                            : isError
                            ? const Color(0xFF9A3412)
                            : ExerciseThemeTokens.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 180),
                          opacity: _isPlaying ? 1 : 0,
                          child: Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: const BoxDecoration(
                              color: Color(0xFF2563EB),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            helper,
                            style: ExerciseThemeTokens.caption.copyWith(
                              color: !hasAudio
                                  ? const Color(0xFFB45309)
                                  : isError
                                  ? const Color(0xFFC2410C)
                                  : ExerciseThemeTokens.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageCard extends StatelessWidget {
  final String url;
  final double size;

  const _ImageCard({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final image = _resolveImage(url);
    return ClipRRect(
      borderRadius: BorderRadius.circular(ExerciseThemeTokens.cardRadius),
      child: Container(
        width: double.infinity,
        height: size,
        decoration: BoxDecoration(
          color: ExerciseThemeTokens.surfaceMuted,
          border: Border.all(color: ExerciseThemeTokens.border),
          borderRadius: BorderRadius.circular(ExerciseThemeTokens.cardRadius),
        ),
        child: image,
      ),
    );
  }

  Widget _resolveImage(String url) {
    if (url.startsWith('assets/')) {
      return Image.asset(url, fit: BoxFit.cover);
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stack) => const _ImagePlaceholder(),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  final double size;

  const _ImagePlaceholder({this.size = 140});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ExerciseThemeTokens.cardRadius),
        gradient: const LinearGradient(
          colors: [
            ExerciseThemeTokens.placeholderGradientStart,
            ExerciseThemeTokens.placeholderGradientEnd,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: ExerciseThemeTokens.border),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_outlined,
              color: ExerciseThemeTokens.textMuted,
              size: 32,
            ),
            SizedBox(height: 8),
            Text('Image coming soon', style: ExerciseThemeTokens.caption),
          ],
        ),
      ),
    );
  }
}
