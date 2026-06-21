import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dragon_chinese/design_system/exercise_theme.dart';
import 'package:dragon_chinese/design_system/pressable_keycap.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/exercise_answer_tray.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/exercise_feedback_banner.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/exercise_media.dart';

class MultipleChoiceOptionCard extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isCorrect;
  final bool isAnswered;
  final VoidCallback? onTap;
  final double height;
  final int maxLines;
  final double? fontSize;

  const MultipleChoiceOptionCard({
    super.key,
    required this.label,
    required this.isSelected,
    required this.isCorrect,
    required this.isAnswered,
    this.onTap,
    this.height = ExerciseThemeTokens.optionMinHeight,
    this.maxLines = 2,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final bool showCorrect = isAnswered && isCorrect;
    final bool showIncorrect = isAnswered && isSelected && !isCorrect;
    final bool isDimmed = isAnswered && !isSelected && !isCorrect;

    Color bg = const Color(0xFFF8FAFF);
    Color border = ExerciseThemeTokens.border;
    Color textColor = ExerciseThemeTokens.textPrimary;
    double borderWidth = 1.0;

    if (showCorrect) {
      bg = ExerciseThemeTokens.successBg;
      border = ExerciseThemeTokens.success;
      textColor = ExerciseThemeTokens.success;
      borderWidth = 1.5;
    } else if (showIncorrect) {
      bg = ExerciseThemeTokens.errorBg;
      border = ExerciseThemeTokens.error;
      textColor = ExerciseThemeTokens.error;
      borderWidth = 1.5;
    } else if (isSelected) {
      bg = const Color(0xFFD2E3FC);
      border = ExerciseThemeTokens.accent.withValues(alpha: 0.5);
      borderWidth = 1.5;
    }

    return Opacity(
      opacity: isDimmed ? 0.6 : 1.0,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        scale: isSelected ? 1.01 : 1.0,
        child: PressableOptionCard(
          height: height,
          onTap: isAnswered ? null : onTap,
          enabled: true,
          faceColor: bg,
          baseColor: bg,
          borderColor: border,
          borderWidth: borderWidth,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: height < 52 ? 6 : 10,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: maxLines,
                    style: ExerciseThemeTokens.optionText.copyWith(
                      fontSize: fontSize,
                      color: isAnswered && (showCorrect || showIncorrect)
                          ? textColor
                          : ExerciseThemeTokens.textPrimary,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 170),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: showCorrect
                      ? _statusGlyph(
                          key: const ValueKey('correct'),
                          icon: Icons.check_rounded,
                          color: ExerciseThemeTokens.success,
                          bg: ExerciseThemeTokens.successBg,
                        )
                      : showIncorrect
                      ? _statusGlyph(
                          key: const ValueKey('wrong'),
                          icon: Icons.close_rounded,
                          color: ExerciseThemeTokens.error,
                          bg: ExerciseThemeTokens.errorBg,
                        )
                      : const SizedBox(
                          key: ValueKey('empty'),
                          width: 18,
                          height: 18,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusGlyph({
    required Key key,
    required IconData icon,
    required Color color,
    required Color bg,
  }) {
    return Container(
      key: key,
      width: 18,
      height: 18,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(icon, size: 13, color: color),
    );
  }
}

class _InlineAudioControl extends StatelessWidget {
  final String? audioUrl;
  final EdgeInsetsGeometry margin;
  final bool alwaysShow;

  const _InlineAudioControl({
    required this.audioUrl,
    this.margin = const EdgeInsets.only(bottom: 10),
    this.alwaysShow = false,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = audioUrl?.trim();
    final hasAudio = normalized != null && normalized.isNotEmpty;
    if (!alwaysShow && !hasAudio) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: margin,
      child: ExerciseMediaSlot(
        imageUrl: null,
        audioUrl: hasAudio ? normalized : null,
        showAudio: true,
        enableAudio: hasAudio,
        showImagePlaceholder: false,
      ),
    );
  }
}

class TrueFalseExercise extends StatelessWidget {
  final String statement;
  final int falseIndex;
  final int trueIndex;
  final int answerIndex;
  final int? selectedIndex;
  final bool isAnswered;
  final ValueChanged<int> onSelect;

  const TrueFalseExercise({
    super.key,
    required this.statement,
    required this.falseIndex,
    required this.trueIndex,
    required this.answerIndex,
    required this.selectedIndex,
    required this.isAnswered,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final prompt = statement.trim();
    final choicesRow = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildSquareChoice(
          semanticLabel: 'False',
          icon: Icons.close_rounded,
          optionIndex: falseIndex,
        ),
        const SizedBox(width: 18),
        _buildSquareChoice(
          semanticLabel: 'True',
          icon: Icons.check_rounded,
          optionIndex: trueIndex,
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.maxHeight.isFinite;
        if (!bounded) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (prompt.isNotEmpty) _buildPromptCard(prompt),
              const SizedBox(height: 22),
              choicesRow,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (prompt.isNotEmpty) ...[
              _buildPromptCard(prompt),
              const SizedBox(height: 18),
            ],
            Expanded(
              child: ExerciseAnswerTray(
                maxVisibleItemsWithoutScroll: 2,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: choicesRow,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPromptCard(String text) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: ExerciseThemeTokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ExerciseThemeTokens.border),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: ExerciseThemeTokens.promptDisplay,
      ),
    );
  }

  Widget _buildSquareChoice({
    required String semanticLabel,
    required IconData icon,
    required int optionIndex,
  }) {
    final isSelected = selectedIndex == optionIndex;
    final isCorrect = optionIndex == answerIndex;
    final showCorrect = isAnswered && isCorrect;
    final showIncorrect = isAnswered && isSelected && !isCorrect;
    final isDimmed = isAnswered && !isSelected && !isCorrect;

    Color face = const Color(0xFFF8FAFF);
    Color base = const Color(0xFFE7EDF8);
    Color border = ExerciseThemeTokens.border;
    Color iconColor = ExerciseThemeTokens.textPrimary;
    double borderWidth = 1.0;

    if (showCorrect) {
      face = ExerciseThemeTokens.successBg;
      base = const Color(0xFFB9EED4);
      border = ExerciseThemeTokens.success;
      iconColor = ExerciseThemeTokens.success;
      borderWidth = 1.5;
    } else if (showIncorrect) {
      face = ExerciseThemeTokens.errorBg;
      base = const Color(0xFFF9D0D0);
      border = ExerciseThemeTokens.error;
      iconColor = ExerciseThemeTokens.error;
      borderWidth = 1.5;
    } else if (isSelected) {
      face = const Color(0xFFDDE7FF);
      base = const Color(0xFFC9D7F6);
      border = ExerciseThemeTokens.accent.withValues(alpha: 0.55);
      iconColor = ExerciseThemeTokens.accent;
      borderWidth = 1.5;
    }

    return Opacity(
      opacity: isDimmed ? 0.62 : 1.0,
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: SizedBox.square(
          dimension: 108,
          child: PressableOptionCard(
            height: 108,
            onTap: isAnswered ? null : () => onSelect(optionIndex),
            enabled: true,
            faceColor: face,
            baseColor: base,
            borderColor: border,
            borderWidth: borderWidth,
            child: Icon(icon, size: 44, color: iconColor),
          ),
        ),
      ),
    );
  }
}

class MultipleChoiceExerciseView extends StatelessWidget {
  final String? primaryPrompt;
  final String? secondaryPrompt;
  final List<String> options;
  final int answerIndex;
  final int? selectedIndex;
  final bool isAnswered;
  final VoidCallback? onToggleSecondary;
  final bool showSecondary;
  final String toggleLabel;
  final ValueChanged<int> onSelect;

  const MultipleChoiceExerciseView({
    super.key,
    required this.primaryPrompt,
    required this.secondaryPrompt,
    required this.options,
    required this.answerIndex,
    required this.selectedIndex,
    required this.isAnswered,
    required this.onSelect,
    this.onToggleSecondary,
    this.showSecondary = false,
    this.toggleLabel = 'Pinyin',
  });

  @override
  Widget build(BuildContext context) {
    final optionTiles = List<Widget>.generate(options.length, (index) {
      return Padding(
        padding: EdgeInsets.only(bottom: index == options.length - 1 ? 0 : 12),
        child: MultipleChoiceOptionCard(
          label: options[index],
          isSelected: selectedIndex == index,
          isCorrect: index == answerIndex,
          isAnswered: isAnswered,
          onTap: isAnswered ? null : () => onSelect(index),
        ),
      );
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.maxHeight.isFinite;
        if (!bounded) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (primaryPrompt != null) _buildPromptBlock(),
              const SizedBox(height: 24),
              ...optionTiles,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (primaryPrompt != null) _buildPromptBlock(),
            const SizedBox(height: 18),
            Expanded(child: ExerciseAnswerTray(children: optionTiles)),
          ],
        );
      },
    );
  }

  Widget _buildPromptBlock() {
    final hasSecondary =
        secondaryPrompt != null && secondaryPrompt!.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasSecondary)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 170),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: showSecondary
                ? Text(
                    secondaryPrompt!,
                    key: const ValueKey('secondary-on'),
                    style: ExerciseThemeTokens.caption.copyWith(
                      fontSize: 13,
                      height: 1.12,
                      fontWeight: FontWeight.w400,
                      color: ExerciseThemeTokens.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  )
                : const SizedBox(key: ValueKey('secondary-off'), height: 0),
          ),
        if (hasSecondary && showSecondary) const SizedBox(height: 5),
        Text(
          primaryPrompt!,
          style: ExerciseThemeTokens.promptDisplay,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class AudioSelectExercise extends StatelessWidget {
  final String? audioUrl;
  final String choiceType;
  final List<String> choices;
  final int answerIndex;
  final int? selectedIndex;
  final bool isAnswered;
  final bool showPrompt;
  final ValueChanged<int> onSelect;

  const AudioSelectExercise({
    super.key,
    required this.audioUrl,
    required this.choiceType,
    required this.choices,
    required this.answerIndex,
    required this.selectedIndex,
    required this.isAnswered,
    this.showPrompt = true,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final audioControl = _InlineAudioControl(
      audioUrl: audioUrl,
      alwaysShow: true,
      margin: const EdgeInsets.only(bottom: 0),
    );
    final optionTiles = List<Widget>.generate(choices.length, (i) {
      return Padding(
        padding: EdgeInsets.only(bottom: i == choices.length - 1 ? 0 : 12),
        child: MultipleChoiceOptionCard(
          label: choices[i],
          isSelected: selectedIndex == i,
          isCorrect: i == answerIndex,
          isAnswered: isAnswered,
          onTap: isAnswered ? null : () => onSelect(i),
        ),
      );
    });
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.maxHeight.isFinite) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              audioControl,
              const SizedBox(height: 10),
              ...optionTiles,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            audioControl,
            const SizedBox(height: 10),
            Expanded(child: ExerciseAnswerTray(children: optionTiles)),
          ],
        );
      },
    );
  }
}

class MeaningSelectExercise extends StatelessWidget {
  final String hanzi;
  final String? pinyin;
  final List<String> choices;
  final int answerIndex;
  final int? selectedIndex;
  final bool isAnswered;
  final bool showPinyin;
  final bool showPrompt;
  final VoidCallback onTogglePinyin;
  final ValueChanged<int> onSelect;

  const MeaningSelectExercise({
    super.key,
    required this.hanzi,
    required this.pinyin,
    required this.choices,
    required this.answerIndex,
    required this.selectedIndex,
    required this.isAnswered,
    required this.showPinyin,
    this.showPrompt = true,
    required this.onTogglePinyin,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return MultipleChoiceExerciseView(
      primaryPrompt: showPrompt ? hanzi : null,
      secondaryPrompt: showPrompt ? pinyin : null,
      options: choices,
      answerIndex: answerIndex,
      selectedIndex: selectedIndex,
      isAnswered: isAnswered,
      onSelect: onSelect,
      onToggleSecondary: onTogglePinyin,
      showSecondary: showPinyin,
    );
  }
}

class OrderSentenceExercise extends StatefulWidget {
  final String? exerciseId;
  final List<String> chunks;
  final List<int>? initialSelectedIndices;
  final bool showWordBankShadowForSelected;
  final int maxSentenceLines;
  final ValueChanged<List<String>> onChanged;

  const OrderSentenceExercise({
    super.key,
    this.exerciseId,
    required this.chunks,
    this.initialSelectedIndices,
    this.showWordBankShadowForSelected = true,
    this.maxSentenceLines = 12,
    required this.onChanged,
  });

  @override
  State<OrderSentenceExercise> createState() => _OrderSentenceExerciseState();
}

class _OrderSentenceExerciseState extends State<OrderSentenceExercise> {
  static const double _kSentenceTileHeight = 42.0;
  static const double _kSentenceRowHeight = 52.0;
  static const double _kSentenceSpacing = 8.0;
  static const double _kBankSpacing = 10.0;

  final List<int> _selectedIndices = [];
  int? _draggingChunkIndex;
  int? _previewInsertIndex;

  @override
  void initState() {
    super.initState();
    _seedInitialSelection();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notify();
    });
  }

  @override
  void didUpdateWidget(covariant OrderSentenceExercise oldWidget) {
    super.didUpdateWidget(oldWidget);
    final exerciseChanged = oldWidget.exerciseId != widget.exerciseId;
    final chunksChanged = !_sameChunks(oldWidget.chunks, widget.chunks);
    final initialSelectionChanged = !_sameIndices(
      oldWidget.initialSelectedIndices,
      widget.initialSelectedIndices,
    );
    if (exerciseChanged || chunksChanged || initialSelectionChanged) {
      _seedInitialSelection();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _notify();
      });
    }
  }

  bool _sameChunks(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _sameIndices(List<int>? a, List<int>? b) {
    final left = a ?? const <int>[];
    final right = b ?? const <int>[];
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  void _seedInitialSelection() {
    _selectedIndices.clear();
    final seed = widget.initialSelectedIndices ?? const <int>[];
    for (final index in seed) {
      if (index < 0 || index >= widget.chunks.length) continue;
      if (_selectedIndices.contains(index)) continue;
      _selectedIndices.add(index);
    }
    _draggingChunkIndex = null;
    _previewInsertIndex = null;
  }

  List<int> _validSelectedIndices() {
    return _selectedIndices
        .where((i) => i >= 0 && i < widget.chunks.length)
        .toList(growable: false);
  }

  void _onTapBank(int index) {
    if (_selectedIndices.contains(index)) return;
    setState(() => _selectedIndices.add(index));
    _notify();
    HapticFeedback.lightImpact();
  }

  void _onTapSentenceByIndex(int chunkIndex) {
    setState(() => _selectedIndices.remove(chunkIndex));
    _notify();
    HapticFeedback.lightImpact();
  }

  void _insertIntoSentence(int chunkIndex, int targetPosition) {
    setState(() {
      _selectedIndices.remove(chunkIndex);
      final clamped = targetPosition.clamp(0, _selectedIndices.length);
      _selectedIndices.insert(clamped, chunkIndex);
    });
    _notify();
    HapticFeedback.selectionClick();
  }

  void _nudgeTokenInSentence({
    required int chunkIndex,
    required int direction,
  }) {
    final current = _selectedIndices.indexOf(chunkIndex);
    if (current < 0) return;
    final target = (current + direction).clamp(0, _selectedIndices.length - 1);
    if (target == current) return;
    setState(() {
      _selectedIndices.removeAt(current);
      _selectedIndices.insert(target, chunkIndex);
    });
    _notify();
    HapticFeedback.selectionClick();
  }

  void _notify() {
    final selectedChunks = _validSelectedIndices()
        .map((i) => widget.chunks[i])
        .toList(growable: false);
    widget.onChanged(selectedChunks);
  }

  List<int> _selectedForRender() {
    return _validSelectedIndices();
  }

  void _setPreviewInsertIndex(int value) {
    if (_previewInsertIndex == value) return;
    setState(() => _previewInsertIndex = value);
  }

  void _clearDragState() {
    if (_draggingChunkIndex == null && _previewInsertIndex == null) return;
    setState(() {
      _draggingChunkIndex = null;
      _previewInsertIndex = null;
    });
  }

  void _startDragging(int chunkIndex) {
    final selected = _validSelectedIndices();
    final oldPos = selected.indexOf(chunkIndex);
    setState(() {
      _draggingChunkIndex = chunkIndex;
      _previewInsertIndex = oldPos >= 0 ? oldPos : selected.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedForRender = _selectedForRender();
    final selectedForBank = _validSelectedIndices();
    final wordBank = _buildWordBank(selectedForBank);

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = _uniformTileWidth();
        final lineCount = _resolveSentenceLineCount(
          maxWidth: constraints.maxWidth,
          tileWidth: tileWidth,
        );
        final trayTopOffset = constraints.maxHeight.isFinite
            ? (constraints.maxHeight * 0.22).clamp(56.0, 170.0).toDouble()
            : 96.0;
        final rows = _rowsForTokenCount(
          tokenCount: widget.chunks.where((w) => w.trim().isNotEmpty).length,
          maxWidth: constraints.maxWidth,
          tileWidth: tileWidth,
          spacing: _kBankSpacing,
          maxRows: 12,
        );
        final trayHeight = _trayHeightFor(lineCount);
        final estimatedHeight =
            trayTopOffset +
            trayHeight +
            (wordBank != null ? (rows * 56 + 12).toDouble() : 0);
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: trayTopOffset),
            _buildSentenceTray(selectedForRender, lineCount: lineCount),
            if (wordBank != null) ...[
              const SizedBox(height: 12),
              const Spacer(),
              wordBank,
            ],
          ],
        );

        if (!constraints.maxHeight.isFinite ||
            estimatedHeight <= constraints.maxHeight) {
          return content;
        }

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: trayTopOffset),
              _buildSentenceTray(selectedForRender, lineCount: lineCount),
              if (wordBank != null) ...[const SizedBox(height: 12), wordBank],
            ],
          ),
        );
      },
    );
  }

  int _resolveSentenceLineCount({
    required double maxWidth,
    required double tileWidth,
  }) {
    final words = widget.chunks.where((w) => w.trim().isNotEmpty).toList();
    if (words.isEmpty) return 1;
    final allowedLines = widget.maxSentenceLines.clamp(1, 12);
    if (!maxWidth.isFinite || maxWidth <= 0) {
      return (words.length / 4).ceil().clamp(1, allowedLines);
    }
    final slotsPerLine = _slotsPerLine(
      maxWidth: maxWidth,
      tileWidth: tileWidth,
      spacing: _kSentenceSpacing,
    );
    final lines = (words.length / slotsPerLine).ceil();
    return lines.clamp(1, allowedLines);
  }

  int _rowsForTokenCount({
    required int tokenCount,
    required double maxWidth,
    required double tileWidth,
    required double spacing,
    required int maxRows,
  }) {
    if (tokenCount <= 0) return 1;
    final perLine = _slotsPerLine(
      maxWidth: maxWidth,
      tileWidth: tileWidth,
      spacing: spacing,
    );
    return (tokenCount / perLine).ceil().clamp(1, maxRows);
  }

  int _slotsPerLine({
    required double maxWidth,
    required double tileWidth,
    required double spacing,
  }) {
    if (!maxWidth.isFinite || maxWidth <= 0) return 3;
    final usableWidth = (maxWidth - 2).clamp(120.0, 900.0);
    return ((usableWidth + spacing) / (tileWidth + spacing)).floor().clamp(
      1,
      8,
    );
  }

  double _trayHeightFor(int lineCount) {
    const rowHeight = _kSentenceRowHeight;
    const verticalInset = 10.0;
    final guidesHeight = rowHeight * lineCount;
    return guidesHeight + (verticalInset * 2);
  }

  Widget _buildSentenceTray(List<int> selected, {required int lineCount}) {
    final hasSelection = selected.isNotEmpty;
    final isDragging = _draggingChunkIndex != null;
    const runSpacing = 10.0;
    const rowHeight = _kSentenceRowHeight;
    final trayHeight = _trayHeightFor(lineCount);

    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => true,
      onMove: (_) => _setPreviewInsertIndex(selected.length),
      onAcceptWithDetails: (details) {
        final target = _previewInsertIndex ?? selected.length;
        _insertIntoSentence(details.data, target);
        _clearDragState();
      },
      builder: (context, candidateData, rejectedData) {
        final isActive = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          height: trayHeight,
          width: double.infinity,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SentenceLineGuidesPainter(
                    lineCount: lineCount,
                    rowHeight: rowHeight,
                    isActive: isActive,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Wrap(
                    spacing: _kSentenceSpacing,
                    runSpacing: runSpacing,
                    children: (hasSelection || isDragging)
                        ? _buildSentenceChildren(selected)
                        : (isActive
                              ? [_buildEmptyDropGuide()]
                              : [const SizedBox(height: _kSentenceTileHeight)]),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget? _buildWordBank(List<int> selected) {
    if (widget.chunks.isEmpty) {
      return null;
    }
    final selectedSet = selected.toSet();
    final children = <Widget>[];
    for (var index = 0; index < widget.chunks.length; index++) {
      final word = widget.chunks[index];
      if (word.trim().isEmpty) continue;
      if (selectedSet.contains(index)) {
        if (!widget.showWordBankShadowForSelected) continue;
        children.add(
          KeyedSubtree(
            key: ValueKey('bank-shadow-$index'),
            child: _buildShadowTile(word),
          ),
        );
      } else {
        children.add(
          KeyedSubtree(
            key: ValueKey('bank-tile-$index'),
            child: _buildDraggableTile(
              chunkIndex: index,
              text: word,
              onTap: () => _onTapBank(index),
              tileKey: ValueKey('bank-draggable-$index'),
            ),
          ),
        );
      }
    }
    if (children.isEmpty) {
      return null;
    }

    return Wrap(
      spacing: _kBankSpacing,
      runSpacing: 12,
      alignment: WrapAlignment.start,
      children: children,
    );
  }

  List<Widget> _buildSentenceChildren(List<int> selected) {
    final children = <Widget>[];
    for (var pos = 0; pos < selected.length; pos++) {
      final idx = selected[pos];
      final isDraggingToken = _draggingChunkIndex == idx;
      children.add(
        KeyedSubtree(
          key: ValueKey('sentence-slot-$idx'),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.97, end: 1.0).animate(animation),
                child: child,
              ),
            ),
            child: isDraggingToken
                ? KeyedSubtree(
                    key: ValueKey('sentence-drag-shadow-$idx'),
                    child: _buildShadowTile(widget.chunks[idx]),
                  )
                : KeyedSubtree(
                    key: ValueKey('sentence-token-$pos-$idx'),
                    child: _buildSentenceTokenSlot(
                      position: pos,
                      chunkIndex: idx,
                      showShadow: true,
                    ),
                  ),
          ),
        ),
      );
    }
    return children;
  }

  Widget _buildSentenceTokenSlot({
    required int position,
    required int chunkIndex,
    required bool showShadow,
  }) {
    BuildContext? slotContext;
    final text = widget.chunks[chunkIndex];
    final width = _tileWidth(text);
    return SizedBox(
      width: width,
      height: _kSentenceTileHeight,
      child: DragTarget<int>(
        onWillAcceptWithDetails: (_) => true,
        onMove: (details) {
          final render = slotContext?.findRenderObject();
          if (render is! RenderBox) {
            _setPreviewInsertIndex(position);
            return;
          }
          final local = render.globalToLocal(details.offset);
          final midpoint = render.size.width * 0.5;
          final target = local.dx >= midpoint ? position + 1 : position;
          _setPreviewInsertIndex(target);
        },
        onAcceptWithDetails: (details) {
          final target = _previewInsertIndex ?? position;
          _insertIntoSentence(details.data, target);
          _clearDragState();
        },
        builder: (context, candidateData, rejectedData) {
          slotContext = context;
          final shouldShowShadow = showShadow;
          final draggableTile = _buildDraggableTile(
            chunkIndex: chunkIndex,
            text: text,
            onTap: () => _onTapSentenceByIndex(chunkIndex),
            keepShadowOnDrag: true,
            tileKey: ValueKey('sentence-draggable-$position-$chunkIndex'),
          );
          final tile = GestureDetector(
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity > 160) {
                _nudgeTokenInSentence(chunkIndex: chunkIndex, direction: 1);
              } else if (velocity < -160) {
                _nudgeTokenInSentence(chunkIndex: chunkIndex, direction: -1);
              }
            },
            child: draggableTile,
          );
          return AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            decoration: const BoxDecoration(),
            child: shouldShowShadow
                ? Stack(
                    alignment: Alignment.center,
                    children: [_buildShadowTile(text), tile],
                  )
                : tile,
          );
        },
      ),
    );
  }

  Widget _buildDraggableTile({
    required int chunkIndex,
    required String text,
    required VoidCallback onTap,
    bool keepShadowOnDrag = false,
    Key? tileKey,
  }) {
    final chip = _buildTile(text, onTap);
    return Draggable<int>(
      key: tileKey,
      data: chunkIndex,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      maxSimultaneousDrags: 1,
      onDragStarted: () => _startDragging(chunkIndex),
      onDragCompleted: _clearDragState,
      onDraggableCanceled: (_, __) => _clearDragState(),
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.96,
          child: Transform.scale(scale: 1.02, child: _buildTile(text, null)),
        ),
      ),
      childWhenDragging: keepShadowOnDrag
          ? _buildShadowTile(text)
          : const SizedBox.shrink(),
      child: chip,
    );
  }

  Widget _buildEmptyDropGuide() {
    return SizedBox(
      width: _uniformTileWidth(),
      height: _kSentenceTileHeight,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0x14DCE2EA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x55DCE2EA)),
        ),
      ),
    );
  }

  Widget _buildTile(String text, VoidCallback? onTap) {
    return SizedBox(
      width: _tileWidth(text),
      child: PressableKeycap(
        height: _kSentenceTileHeight,
        depth: 3,
        onTap: onTap,
        faceColor: Colors.white,
        baseColor: const Color(0xFFC9CED6),
        borderColor: const Color(0xFFE1E5EB),
        borderRadius: 12,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ExerciseThemeTokens.optionText.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF3F4650),
          ),
        ),
      ),
    );
  }

  Widget _buildShadowTile(String text) {
    return SizedBox(
      width: _tileWidth(text),
      child: Container(
        height: _kSentenceTileHeight,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F5F8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDCE2EA)),
        ),
      ),
    );
  }

  double _tileWidth(String text) {
    return _uniformTileWidth();
  }

  double _uniformTileWidth() {
    var maxChars = 1;
    for (final chunk in widget.chunks) {
      final size = chunk.trim().runes.length;
      if (size > maxChars) {
        maxChars = size;
      }
    }
    if (maxChars <= 2) return 80;
    if (maxChars <= 5) return 96;
    if (maxChars <= 8) return 112;
    return 128;
  }
}

class _SentenceLineGuidesPainter extends CustomPainter {
  final int lineCount;
  final double rowHeight;
  final bool isActive;

  const _SentenceLineGuidesPainter({
    required this.lineCount,
    required this.rowHeight,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final baseColor = isActive
        ? const Color(0x664A88FF)
        : const Color(0xFFDDE3EA);
    final paint = Paint()
      ..color = baseColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = isActive ? 1.25 : 1.0
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < lineCount; i++) {
      final topY = (i * rowHeight) + 10.0;
      final bottomY = topY + (rowHeight - 10.0);
      canvas.drawLine(Offset(0, topY), Offset(size.width, topY), paint);
      canvas.drawLine(Offset(0, bottomY), Offset(size.width, bottomY), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SentenceLineGuidesPainter oldDelegate) {
    return oldDelegate.lineCount != lineCount ||
        oldDelegate.rowHeight != rowHeight ||
        oldDelegate.isActive != isActive;
  }
}

class MeaningMatchExercise extends StatefulWidget {
  final List<String> leftItems;
  final List<String> rightItems;
  final List<int> mapping;
  final void Function(bool ready, bool correct) onStatus;

  const MeaningMatchExercise({
    super.key,
    required this.leftItems,
    required this.rightItems,
    required this.mapping,
    required this.onStatus,
  });

  @override
  State<MeaningMatchExercise> createState() => _MeaningMatchExerciseState();
}

class _MeaningMatchExerciseState extends State<MeaningMatchExercise> {
  int? _selectedLeft;
  late List<int?> _assigned;
  late Set<int> _usedRight;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant MeaningMatchExercise oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.leftItems, widget.leftItems) ||
        !listEquals(oldWidget.rightItems, widget.rightItems)) {
      _reset();
    }
  }

  void _reset() {
    _selectedLeft = null;
    _assigned = List<int?>.filled(widget.leftItems.length, null);
    _usedRight = <int>{};
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.onStatus(false, false),
    );
  }

  void _selectLeft(int index) {
    setState(() {
      final previous = _assigned[index];
      if (previous != null) {
        _usedRight.remove(previous);
        _assigned[index] = null;
      }
      _selectedLeft = index;
    });
    _emitStatus();
  }

  void _selectRight(int index) {
    if (_selectedLeft == null) return;
    setState(() {
      if (_usedRight.contains(index)) {
        final previousOwner = _assigned.indexOf(index);
        if (previousOwner >= 0) {
          _assigned[previousOwner] = null;
        }
        _usedRight.remove(index);
      }
      _assigned[_selectedLeft!] = index;
      _usedRight.add(index);
      _selectedLeft = null;
    });
    _emitStatus();
  }

  void _emitStatus() {
    final ready = _assigned.every((i) => i != null);
    bool correct = ready;
    if (ready) {
      for (var i = 0; i < _assigned.length; i++) {
        if (_assigned[i] != widget.mapping[i]) {
          correct = false;
          break;
        }
      }
    }
    widget.onStatus(ready, correct);
  }

  bool listEquals(List a, List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: List.generate(
              widget.leftItems.length,
              (i) => _buildTile(
                widget.leftItems[i],
                _selectedLeft == i,
                _assigned[i] != null,
                allowTapWhenFilled: true,
                () => _selectLeft(i),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: List.generate(
              widget.rightItems.length,
              (i) => _buildTile(
                widget.rightItems[i],
                false,
                _usedRight.contains(i),
                allowTapWhenFilled: true,
                () => _selectRight(i),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTile(
    String label,
    bool selected,
    bool filled,
    VoidCallback onTap, {
    bool allowTapWhenFilled = false,
  }) {
    final enabled = allowTapWhenFilled || !filled;
    final opacity = filled ? (allowTapWhenFilled ? 0.72 : 0.4) : 1.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: opacity,
        child: PressableOptionCard(
          height: 64,
          onTap: enabled ? onTap : null,
          enabled: enabled,
          faceColor: selected
              ? const Color(0xFFD2E3FC)
              : const Color(0xFFF8FAFF),
          baseColor: selected
              ? const Color(0xFFB8C8EE)
              : const Color(0xFFE5E5E5),
          borderColor: selected
              ? const Color(0xFF4A6EE0)
              : const Color(0xFFE9ECEF),
          child: Center(
            child: Text(
              label,
              style: ExerciseThemeTokens.optionText.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AudioMeaningMatchExercise extends StatefulWidget {
  final List<String> leftItems;
  final List<String> leftAudioUrls;
  final List<String> rightItems;
  final List<int> mapping;
  final void Function(bool ready, bool correct) onStatus;

  const AudioMeaningMatchExercise({
    super.key,
    required this.leftItems,
    required this.leftAudioUrls,
    required this.rightItems,
    required this.mapping,
    required this.onStatus,
  });

  @override
  State<AudioMeaningMatchExercise> createState() =>
      _AudioMeaningMatchExerciseState();
}

class _AudioMeaningMatchExerciseState extends State<AudioMeaningMatchExercise> {
  int? _selectedLeft;
  late List<int?> _assigned;
  late Set<int> _usedRight;
  final AudioPlayer _player = AudioPlayer();
  int? _playingIndex;
  final Set<int> _audioErrorIndices = <int>{};
  StreamSubscription<PlayerState>? _playerStateSub;

  @override
  void initState() {
    super.initState();
    _playerStateSub = _player.onPlayerStateChanged.listen((state) {
      if (!mounted || state == PlayerState.playing) return;
      if (_playingIndex != null) {
        setState(() => _playingIndex = null);
      }
    });
    _reset();
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AudioMeaningMatchExercise oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_listEquals(oldWidget.leftItems, widget.leftItems) ||
        !_listEquals(oldWidget.rightItems, widget.rightItems) ||
        !_listEquals(oldWidget.leftAudioUrls, widget.leftAudioUrls)) {
      _reset();
    }
  }

  void _reset() {
    _selectedLeft = null;
    _assigned = List<int?>.filled(widget.leftItems.length, null);
    _usedRight = <int>{};
    _audioErrorIndices.clear();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.onStatus(false, false),
    );
  }

  bool _listEquals(List a, List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _playAudio(int leftIndex) async {
    if (leftIndex < 0 || leftIndex >= widget.leftAudioUrls.length) return;
    final url = widget.leftAudioUrls[leftIndex].trim();
    if (url.isEmpty) return;
    try {
      setState(() {
        _playingIndex = leftIndex;
        _audioErrorIndices.remove(leftIndex);
      });
      HapticFeedback.selectionClick();
      await _player.play(UrlSource(url));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _playingIndex = null;
        _audioErrorIndices.add(leftIndex);
      });
    }
  }

  void _selectLeft(int index) {
    setState(() {
      final previous = _assigned[index];
      if (previous != null) {
        _usedRight.remove(previous);
        _assigned[index] = null;
      }
      _selectedLeft = index;
    });
    _emitStatus();
    HapticFeedback.lightImpact();
  }

  void _selectRight(int index) {
    if (_selectedLeft == null) return;
    setState(() {
      if (_usedRight.contains(index)) {
        final previousOwner = _assigned.indexOf(index);
        if (previousOwner >= 0) {
          _assigned[previousOwner] = null;
        }
        _usedRight.remove(index);
      }
      _assigned[_selectedLeft!] = index;
      _usedRight.add(index);
      _selectedLeft = null;
    });
    _emitStatus();
  }

  void _emitStatus() {
    final ready = _assigned.every((i) => i != null);
    bool correct = ready;
    if (ready) {
      for (var i = 0; i < _assigned.length; i++) {
        if (i >= widget.mapping.length || _assigned[i] != widget.mapping[i]) {
          correct = false;
          break;
        }
      }
    }
    widget.onStatus(ready, correct);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: List.generate(
              widget.leftItems.length,
              (i) => _buildLeftAudioTile(
                label: widget.leftItems[i],
                selected: _selectedLeft == i,
                filled: _assigned[i] != null,
                allowTapWhenFilled: true,
                onTap: () => _selectLeft(i),
                onPlayTap: () => _playAudio(i),
                isPlaying: _playingIndex == i,
                hasError: _audioErrorIndices.contains(i),
                hasAudio:
                    i < widget.leftAudioUrls.length &&
                    widget.leftAudioUrls[i].trim().isNotEmpty,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: List.generate(
              widget.rightItems.length,
              (i) => _buildRightTile(
                label: widget.rightItems[i],
                selected: _selectedLeft != null && !_usedRight.contains(i),
                filled: _usedRight.contains(i),
                allowTapWhenFilled: true,
                onTap: () => _selectRight(i),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLeftAudioTile({
    required String label,
    required bool selected,
    required bool filled,
    required bool allowTapWhenFilled,
    required VoidCallback onTap,
    required VoidCallback onPlayTap,
    required bool isPlaying,
    required bool hasError,
    required bool hasAudio,
  }) {
    final enabled = allowTapWhenFilled || !filled;
    final opacity = filled ? (allowTapWhenFilled ? 0.9 : 0.55) : 1.0;
    final linked = filled;
    final faceColor = selected
        ? const Color(0xFFD2E3FC)
        : linked
        ? const Color(0xFFF2F4F8)
        : const Color(0xFFF8FAFF);
    final baseColor = selected
        ? const Color(0xFFB8C8EE)
        : linked
        ? const Color(0xFFD7DDE6)
        : const Color(0xFFE5E5E5);
    final borderColor = selected
        ? const Color(0xFF4A6EE0)
        : linked
        ? const Color(0xFFB6C0CC)
        : const Color(0xFFE9ECEF);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: opacity,
        child: PressableOptionCard(
          height: 64,
          onTap: enabled ? onTap : null,
          enabled: enabled,
          faceColor: faceColor,
          baseColor: baseColor,
          borderColor: borderColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                IconButton(
                  onPressed: hasAudio ? onPlayTap : null,
                  icon: Icon(
                    !hasAudio
                        ? Icons.volume_off
                        : hasError
                        ? Icons.refresh_rounded
                        : (isPlaying ? Icons.volume_up : Icons.play_arrow),
                    color: !hasAudio
                        ? ExerciseThemeTokens.textMuted
                        : hasError
                        ? const Color(0xFFB45309)
                        : const Color(0xFF1E40AF),
                  ),
                ),
                if (hasError)
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: Color(0xFFB45309),
                  ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: hasError
                          ? const Color(0xFF92400E)
                          : ExerciseThemeTokens.textPrimary,
                    ),
                  ),
                ),
                if (linked)
                  const Icon(
                    Icons.link_rounded,
                    size: 16,
                    color: Color(0xFF6B7280),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRightTile({
    required String label,
    required bool selected,
    required bool filled,
    required bool allowTapWhenFilled,
    required VoidCallback onTap,
  }) {
    final enabled = allowTapWhenFilled || !filled;
    final opacity = filled ? (allowTapWhenFilled ? 0.9 : 0.55) : 1.0;
    final faceColor = filled
        ? const Color(0xFFF2F4F8)
        : (selected ? const Color(0xFFEAF2FF) : const Color(0xFFF8FAFF));
    final baseColor = filled
        ? const Color(0xFFD7DDE6)
        : (selected ? const Color(0xFFACC2ED) : const Color(0xFFE5E5E5));
    final borderColor = filled
        ? const Color(0xFFB6C0CC)
        : (selected ? const Color(0xFF7CA4ED) : const Color(0xFFE9ECEF));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: opacity,
        child: PressableOptionCard(
          height: 64,
          onTap: enabled ? onTap : null,
          enabled: enabled,
          faceColor: faceColor,
          baseColor: baseColor,
          borderColor: borderColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: ExerciseThemeTokens.optionText.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (filled)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: Color(0xFF64748B),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CharacterSelectExercise extends StatelessWidget {
  final String meaning;
  final String? pinyin;
  final List<String> choices;
  final int answerIndex;
  final int? selectedIndex;
  final bool isAnswered;
  final bool showPinyin;
  final bool showPrompt;
  final VoidCallback onTogglePinyin;
  final ValueChanged<int> onSelect;

  const CharacterSelectExercise({
    super.key,
    required this.meaning,
    required this.pinyin,
    required this.choices,
    required this.answerIndex,
    required this.selectedIndex,
    required this.isAnswered,
    required this.showPinyin,
    this.showPrompt = true,
    required this.onTogglePinyin,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return MultipleChoiceExerciseView(
      primaryPrompt: showPrompt ? meaning : null,
      secondaryPrompt: showPrompt ? pinyin : null,
      options: choices,
      answerIndex: answerIndex,
      selectedIndex: selectedIndex,
      isAnswered: isAnswered,
      onSelect: onSelect,
      onToggleSecondary: onTogglePinyin,
      showSecondary: showPinyin,
    );
  }
}

class PinyinSelectExercise extends StatelessWidget {
  final String hanzi;
  final List<String> choices;
  final int answerIndex;
  final int? selectedIndex;
  final bool isAnswered;
  final ValueChanged<int> onSelect;

  const PinyinSelectExercise({
    super.key,
    required this.hanzi,
    required this.choices,
    required this.answerIndex,
    required this.selectedIndex,
    required this.isAnswered,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return MultipleChoiceExerciseView(
      primaryPrompt: hanzi,
      secondaryPrompt: null,
      options: choices,
      answerIndex: answerIndex,
      selectedIndex: selectedIndex,
      isAnswered: isAnswered,
      onSelect: onSelect,
    );
  }
}

class ReplySelectExercise extends StatelessWidget {
  final String prompt;
  final List<String> choices;
  final int answerIndex;
  final int? selectedIndex;
  final bool isAnswered;
  final ValueChanged<int> onSelect;

  const ReplySelectExercise({
    super.key,
    required this.prompt,
    required this.choices,
    required this.answerIndex,
    required this.selectedIndex,
    required this.isAnswered,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return MultipleChoiceExerciseView(
      primaryPrompt: prompt,
      secondaryPrompt: null,
      options: choices,
      answerIndex: answerIndex,
      selectedIndex: selectedIndex,
      isAnswered: isAnswered,
      onSelect: onSelect,
    );
  }
}

class ConversationSimulationExercise extends StatelessWidget {
  final String scenario;
  final String speakerLine;
  final String question;
  final List<String> choices;
  final int answerIndex;
  final int? selectedIndex;
  final bool isAnswered;
  final ValueChanged<int> onSelect;

  const ConversationSimulationExercise({
    super.key,
    required this.scenario,
    required this.speakerLine,
    required this.question,
    required this.choices,
    required this.answerIndex,
    required this.selectedIndex,
    required this.isAnswered,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final optionTiles = List<Widget>.generate(choices.length, (i) {
      return Padding(
        padding: EdgeInsets.only(bottom: i == choices.length - 1 ? 0 : 12),
        child: MultipleChoiceOptionCard(
          label: choices[i],
          isSelected: selectedIndex == i,
          isCorrect: i == answerIndex,
          isAnswered: isAnswered,
          onTap: isAnswered ? null : () => onSelect(i),
        ),
      );
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.maxHeight.isFinite;
        final header = <Widget>[
          if (scenario.trim().isNotEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: ExerciseThemeTokens.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ExerciseThemeTokens.border),
              ),
              child: Text(
                scenario,
                style: ExerciseThemeTokens.caption.copyWith(
                  color: ExerciseThemeTokens.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (scenario.trim().isNotEmpty) const SizedBox(height: 12),
          if (speakerLine.trim().isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4FB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFDCE3EE)),
                ),
                child: Text(
                  speakerLine,
                  style: ExerciseThemeTokens.promptBody.copyWith(fontSize: 17),
                ),
              ),
            ),
          const SizedBox(height: 14),
          Text(
            question,
            style: ExerciseThemeTokens.promptBody.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: ExerciseThemeTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
        ];

        if (!bounded) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [...header, ...optionTiles],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...header,
            Expanded(child: ExerciseAnswerTray(children: optionTiles)),
          ],
        );
      },
    );
  }
}

class CharacterWritingExercise extends StatelessWidget {
  final String targetCharacter;
  final String? pinyin;
  final String? meaning;

  const CharacterWritingExercise({
    super.key,
    required this.targetCharacter,
    this.pinyin,
    this.meaning,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: ExerciseThemeTokens.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ExerciseThemeTokens.border),
          ),
          child: Column(
            children: [
              Text(
                targetCharacter,
                style: const TextStyle(
                  fontSize: 62,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937),
                ),
              ),
              if (pinyin != null && pinyin!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    pinyin!,
                    style: ExerciseThemeTokens.caption.copyWith(
                      color: ExerciseThemeTokens.textSecondary,
                    ),
                  ),
                ),
              if (meaning != null && meaning!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    meaning!,
                    style: ExerciseThemeTokens.caption.copyWith(
                      color: ExerciseThemeTokens.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFDCE2EA)),
          ),
          child: CustomPaint(painter: _WritingGridPainter()),
        ),
      ],
    );
  }
}

class _WritingGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = const Color(0xFFDCE2EA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final guidePaint = Paint()
      ..color = const Color(0xFFC9D2E0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(14)),
      borderPaint,
    );

    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      guidePaint,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      guidePaint,
    );

    final dashPaint = Paint()
      ..color = const Color(0xFFB8C4D6)
      ..strokeWidth = 1.0;
    const dash = 6.0;
    const gap = 5.0;
    var t = 0.0;
    while (t < size.width + size.height) {
      final x1 = (t).clamp(0.0, size.width);
      final y1 = (t - size.width).clamp(0.0, size.height);
      final x2 = (t + dash).clamp(0.0, size.width);
      final y2 = (t + dash - size.width).clamp(0.0, size.height);
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), dashPaint);
      t += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ClozeSelectExercise extends StatelessWidget {
  final String sentence;
  final String? contextPassage;
  final int? contextMaxWords;
  final bool phraseMode;
  final List<String> choices;
  final int answerIndex;
  final int? selectedIndex;
  final bool isAnswered;
  final ValueChanged<int> onSelect;

  const ClozeSelectExercise({
    super.key,
    required this.sentence,
    this.contextPassage,
    this.contextMaxWords,
    this.phraseMode = false,
    required this.choices,
    required this.answerIndex,
    required this.selectedIndex,
    required this.isAnswered,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedSentence = _resolvedSentence();
    final resolvedContext = _resolvedContextPassage(resolvedSentence);
    final selected = selectedIndex;
    final selectedWord =
        (selectedIndex != null &&
            selectedIndex! >= 0 &&
            selectedIndex! < choices.length)
        ? choices[selectedIndex!]
        : null;
    final blankIsCorrect =
        isAnswered && selected != null && selected == answerIndex;
    final blankIsWrong =
        isAnswered && selected != null && selected != answerIndex;
    final parts = _splitAroundBlank(resolvedSentence);

    return LayoutBuilder(
      builder: (context, constraints) {
        final finiteHeight = constraints.maxHeight.isFinite;
        final contextText = resolvedContext;
        final hasContext = contextText != null;
        final effectivePhraseMode = phraseMode || _inferPhraseModeFromChoices();
        final contextHeight = finiteHeight
            ? _adaptiveContextHeight(
                maxHeight: constraints.maxHeight,
                choiceCount: choices.length,
              )
            : 112.0;
        final estimatedAnswerWrapHeight = _estimatedAnswerWrapHeight(
          phraseMode: effectivePhraseMode,
        );
        final answerWrap = Wrap(
          spacing: effectivePhraseMode ? 8 : 10,
          runSpacing: 12,
          children: List<Widget>.generate(choices.length, (index) {
            final label = choices[index];
            final isSelected = selectedIndex == index;
            final isCorrect = isAnswered && index == answerIndex;
            final isWrong = isAnswered && isSelected && index != answerIndex;
            return _buildChoiceToken(
              label: label,
              isSelected: isSelected,
              isCorrect: isCorrect,
              isWrong: isWrong,
              phraseMode: effectivePhraseMode,
              onTap: isAnswered ? null : () => onSelect(index),
            );
          }),
        );
        final promptBlock = Center(
          child: Text.rich(
            TextSpan(
              style: ExerciseThemeTokens.promptBody.copyWith(
                fontSize: effectivePhraseMode ? 21 : 24,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1F2937),
              ),
              children: [
                if (parts.$1.isNotEmpty) TextSpan(text: parts.$1),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 340),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.12),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey<String>(
                          '${selectedWord ?? ''}|$blankIsCorrect|$blankIsWrong',
                        ),
                        child: _buildBlankToken(
                          selectedWord,
                          phraseMode: effectivePhraseMode,
                          isCorrect: blankIsCorrect,
                          isWrong: blankIsWrong,
                        ),
                      ),
                    ),
                  ),
                ),
                if (parts.$2.isNotEmpty) TextSpan(text: parts.$2),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        );

        if (!finiteHeight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasContext) ...[
                _PassageSelectablePreview(
                  text: contextText,
                  height: contextHeight,
                  compact: true,
                  showSelectionBanner: false,
                  maxWords: contextMaxWords,
                ),
                const SizedBox(height: 10),
              ],
              promptBlock,
              const SizedBox(height: 12),
              answerWrap,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasContext) ...[
              _PassageSelectablePreview(
                text: contextText,
                height: contextHeight,
                compact: true,
                showSelectionBanner: false,
                maxWords: contextMaxWords,
              ),
              const SizedBox(height: 10),
            ],
            promptBlock,
            const SizedBox(height: 12),
            Expanded(
              child: ExerciseAnswerTray(
                maxVisibleItemsWithoutScroll: 2,
                estimatedChildHeight: estimatedAnswerWrapHeight,
                heightSlackPx: 20,
                children: [
                  Align(alignment: Alignment.bottomCenter, child: answerWrap),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  bool _inferPhraseModeFromChoices() {
    for (final choice in choices) {
      final trimmed = choice.trim();
      if (trimmed.isEmpty) continue;
      if (RegExp(r'\s').hasMatch(trimmed) || trimmed.runes.length > 12) {
        return true;
      }
    }
    return false;
  }

  double _estimatedAnswerWrapHeight({required bool phraseMode}) {
    final rows = choices.length <= 2
        ? 1
        : (choices.length <= 5
              ? 2
              : (choices.length <= 8 ? 3 : math.min(4, (choices.length ~/ 2))));
    final rowHeight = phraseMode ? 56.0 : 46.0;
    return rows * rowHeight + (rows - 1) * 12.0 + 8.0;
  }

  String? _resolvedContextPassage(String resolvedSentence) {
    final raw = contextPassage?.trim();
    if (raw == null || raw.isEmpty) return null;
    final normalizedContext = _normalizeComparable(raw);
    final normalizedSentence = _normalizeComparable(resolvedSentence);
    if (normalizedContext.isEmpty ||
        normalizedContext == normalizedSentence ||
        normalizedContext == _normalizeComparable(sentence)) {
      return null;
    }
    return raw;
  }

  String _normalizeComparable(String value) {
    return value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  double _adaptiveContextHeight({
    required double maxHeight,
    required int choiceCount,
  }) {
    if (!maxHeight.isFinite) return 112.0;
    final rows = choiceCount <= 3
        ? 1
        : (choiceCount <= 6 ? 2 : math.min(3, ((choiceCount + 2) ~/ 3)));
    final estimatedOptionsHeight = rows * 56.0 + (rows - 1) * 12.0;
    const promptBlockHeight = 86.0;
    const chrome = 26.0;
    final available =
        maxHeight - estimatedOptionsHeight - promptBlockHeight - chrome;
    return available.clamp(66.0, 126.0).toDouble();
  }

  String _resolvedSentence() {
    final base = sentence.trim();
    if (base.isEmpty) return '____';
    final hasBlank = RegExp(
      r'_{2,}|\[blank\]|\{blank\}|<blank>',
      caseSensitive: false,
    ).hasMatch(base);
    if (hasBlank) return base;
    if (base.endsWith('。') || base.endsWith('.') || base.endsWith('?')) {
      return '${base.substring(0, base.length - 1)} ____${base.substring(base.length - 1)}';
    }
    return '$base ____';
  }

  (String, String) _splitAroundBlank(String text) {
    final match = RegExp(
      r'_{2,}|\[blank\]|\{blank\}|<blank>',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return (text, '');
    final before = text.substring(0, match.start);
    final after = text.substring(match.end);
    return (before, after);
  }

  Widget _buildBlankToken(
    String? selectedWord, {
    required bool phraseMode,
    required bool isCorrect,
    required bool isWrong,
  }) {
    final hasSelection = selectedWord != null && selectedWord.trim().isNotEmpty;
    final label = hasSelection ? selectedWord.trim() : '____';
    final width = _tokenWidth(label, phraseMode: phraseMode, isBlank: true);
    final faceColor = isCorrect
        ? const Color(0xFFEAF7EC)
        : isWrong
        ? const Color(0xFFFDECEC)
        : (hasSelection ? const Color(0xFFEAF2FF) : Colors.white);
    final borderColor = isCorrect
        ? ExerciseThemeTokens.success
        : isWrong
        ? ExerciseThemeTokens.error
        : (hasSelection ? const Color(0xFFAEC7F8) : const Color(0xFFDCE2EA));
    final textColor = isCorrect
        ? ExerciseThemeTokens.success
        : isWrong
        ? ExerciseThemeTokens.error
        : (hasSelection ? const Color(0xFF295CB8) : const Color(0xFF9CA3AF));

    return SizedBox(
      width: width,
      child: PressableKeycap(
        height: phraseMode ? 46 : 42,
        depth: 2,
        enabled: false,
        onTap: null,
        faceColor: faceColor,
        baseColor: faceColor,
        borderColor: borderColor,
        borderRadius: 12,
        child: Text(
          label,
          maxLines: phraseMode ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: ExerciseThemeTokens.optionText.copyWith(
            fontSize: phraseMode ? 16 : 18,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
    );
  }

  Widget _buildChoiceToken({
    required String label,
    required bool isSelected,
    required bool isCorrect,
    required bool isWrong,
    required bool phraseMode,
    required VoidCallback? onTap,
  }) {
    final faceColor = isCorrect
        ? const Color(0xFFEAF7EC)
        : isWrong
        ? const Color(0xFFFDECEC)
        : (isSelected ? const Color(0xFFEAF2FF) : Colors.white);
    final baseColor = isCorrect
        ? const Color(0xFFBFDDBF)
        : isWrong
        ? const Color(0xFFE7B8B8)
        : (isSelected ? const Color(0xFFACC2ED) : const Color(0xFFC9CED6));
    final borderColor = isCorrect
        ? ExerciseThemeTokens.success
        : isWrong
        ? ExerciseThemeTokens.error
        : (isSelected ? const Color(0xFF7CA4ED) : const Color(0xFFE1E5EB));
    final textColor = isCorrect
        ? ExerciseThemeTokens.success
        : isWrong
        ? ExerciseThemeTokens.error
        : (isSelected ? const Color(0xFF295CB8) : const Color(0xFF3F4650));

    return SizedBox(
      width: _tokenWidth(label, phraseMode: phraseMode),
      child: PressableKeycap(
        height: phraseMode ? 46 : 42,
        depth: 3,
        onTap: onTap,
        faceColor: faceColor,
        baseColor: baseColor,
        borderColor: borderColor,
        borderRadius: 12,
        child: Text(
          label,
          maxLines: phraseMode ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: ExerciseThemeTokens.optionText.copyWith(
            fontSize: phraseMode ? 16 : 18,
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
      ),
    );
  }

  double _tokenWidth(
    String text, {
    required bool phraseMode,
    bool isBlank = false,
  }) {
    final charCount = text.runes.length;
    if (!phraseMode) {
      return charCount <= 1
          ? 56
          : (charCount * 15.0 + 30).clamp(72, 220).toDouble();
    }
    final extra = isBlank ? 26.0 : 20.0;
    return (charCount * 10.0 + extra).clamp(132, 320).toDouble();
  }
}

class ClozeInputExercise extends StatefulWidget {
  final String sentence;
  final String value;
  final List<String> expectedAnswers;
  final bool isAnswered;
  final bool showSentenceCard;
  final String inputHint;
  final String? audioUrl;
  final ValueChanged<String> onChanged;

  const ClozeInputExercise({
    super.key,
    required this.sentence,
    required this.value,
    required this.expectedAnswers,
    required this.isAnswered,
    this.showSentenceCard = true,
    this.inputHint = 'Type your answer',
    this.audioUrl,
    required this.onChanged,
  });

  @override
  State<ClozeInputExercise> createState() => _ClozeInputExerciseState();
}

class _ClozeInputExerciseState extends State<ClozeInputExercise> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(covariant ClozeInputExercise oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedInput = _normalize(widget.value);
    final matchesExpected = widget.expectedAnswers.any(
      (answer) =>
          _normalize(answer) == normalizedInput && normalizedInput != '',
    );
    final primaryExpected = widget.expectedAnswers.isNotEmpty
        ? widget.expectedAnswers.first
        : '';
    final hasPrompt =
        widget.showSentenceCard &&
        widget.sentence.trim().isNotEmpty &&
        widget.sentence.trim() != '_______';
    final inputBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _InlineAudioControl(
          audioUrl: widget.audioUrl,
          margin: const EdgeInsets.only(bottom: 0),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _controller,
          enabled: !widget.isAnswered,
          textInputAction: TextInputAction.done,
          style: ExerciseThemeTokens.promptBody,
          decoration: InputDecoration(
            hintText: widget.inputHint,
            filled: true,
            fillColor: ExerciseThemeTokens.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: ExerciseThemeTokens.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: ExerciseThemeTokens.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: ExerciseThemeTokens.accent,
                width: 1.5,
              ),
            ),
          ),
          onChanged: widget.onChanged,
        ),
        if (widget.isAnswered && widget.expectedAnswers.isNotEmpty) ...[
          const SizedBox(height: 10),
          ExerciseFeedbackBanner(
            tone: matchesExpected
                ? ExerciseFeedbackTone.success
                : ExerciseFeedbackTone.info,
            title: matchesExpected ? 'Nice work' : 'Reference answer',
            details: <String>[
              'Expected: $primaryExpected',
              if (widget.expectedAnswers.length > 1)
                'Also accepted: ${widget.expectedAnswers.skip(1).take(2).join(', ')}',
            ],
          ),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.maxHeight.isFinite;
        final promptCard = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ExerciseThemeTokens.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ExerciseThemeTokens.border),
          ),
          child: Text(
            widget.sentence.isNotEmpty ? widget.sentence : '_______',
            style: ExerciseThemeTokens.promptBody.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: ExerciseThemeTokens.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
        );

        if (!bounded) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasPrompt) ...[promptCard, const SizedBox(height: 12)],
              inputBlock,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasPrompt) ...[promptCard, const SizedBox(height: 12)],
            Expanded(
              child: ExerciseAnswerTray(
                maxVisibleItemsWithoutScroll: 2,
                estimatedChildHeight: widget.isAnswered ? 132 : 72,
                children: [inputBlock],
              ),
            ),
          ],
        );
      },
    );
  }

  String _normalize(String value) {
    return value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }
}

class _PassageSelectablePreview extends StatefulWidget {
  final String text;
  final double height;
  final bool compact;
  final bool showSelectionBanner;
  final int? maxWords;

  const _PassageSelectablePreview({
    required this.text,
    this.height = 228,
    this.compact = true,
    this.showSelectionBanner = false,
    this.maxWords,
  });

  @override
  State<_PassageSelectablePreview> createState() =>
      _PassageSelectablePreviewState();
}

class _PassageSelectablePreviewState extends State<_PassageSelectablePreview> {
  String _selectedWord = '';

  void _onSelectionChanged(
    TextSelection selection,
    SelectionChangedCause? cause,
  ) {
    if (!selection.isValid || selection.isCollapsed) {
      if (_selectedWord.isNotEmpty) setState(() => _selectedWord = '');
      return;
    }

    final raw = _displayText;
    if (raw.isEmpty) {
      if (_selectedWord.isNotEmpty) setState(() => _selectedWord = '');
      return;
    }

    final start = selection.start.clamp(0, raw.length);
    final end = selection.end.clamp(0, raw.length);
    if (end <= start) {
      if (_selectedWord.isNotEmpty) setState(() => _selectedWord = '');
      return;
    }

    final picked = raw.substring(start, end).trim();
    if (picked.isEmpty) {
      if (_selectedWord.isNotEmpty) setState(() => _selectedWord = '');
      return;
    }

    if (_selectedWord != picked) {
      setState(() => _selectedWord = picked);
    }
  }

  String get _displayText {
    final raw = widget.text.trim();
    final maxWords = widget.maxWords;
    if (raw.isEmpty || maxWords == null || maxWords <= 0) return raw;
    final words = raw.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= maxWords) return raw;
    return '${words.take(maxWords).join(' ')}…';
  }

  @override
  Widget build(BuildContext context) {
    final displayText = _displayText;
    if (displayText.isEmpty) return const SizedBox.shrink();
    final hasSelection = _selectedWord.isNotEmpty;
    final displayWord = _selectedWord.length > 32
        ? '${_selectedWord.substring(0, 32)}…'
        : _selectedWord;
    final textPadding = widget.compact
        ? const EdgeInsets.fromLTRB(12, 10, 12, 10)
        : const EdgeInsets.fromLTRB(16, 14, 16, 14);
    final textStyle = ExerciseThemeTokens.promptBody.copyWith(
      fontSize: widget.compact ? 17 : 19,
      height: widget.compact ? 1.56 : 1.68,
      color: ExerciseThemeTokens.textPrimary,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFE),
            borderRadius: BorderRadius.circular(widget.compact ? 14 : 16),
            border: Border.all(color: const Color(0xFFDCE3EC)),
          ),
          child: SizedBox(
            height: widget.height,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: textPadding,
              child: SelectableText(
                displayText,
                onSelectionChanged: _onSelectionChanged,
                style: textStyle,
              ),
            ),
          ),
        ),
        if (widget.showSelectionBanner)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: !hasSelection
                ? const SizedBox.shrink()
                : Container(
                    key: ValueKey(displayWord),
                    margin: const EdgeInsets.only(top: 8),
                    child: ExerciseFeedbackBanner(
                      tone: ExerciseFeedbackTone.info,
                      icon: Icons.menu_book_rounded,
                      title: displayWord,
                      body: 'Dictionary details coming soon',
                    ),
                  ),
          ),
      ],
    );
  }
}

class ReadingMicroExercise extends StatelessWidget {
  final String titleZh;
  final String titleEn;
  final String storyZh;
  final String storyEn;
  final int questionIndex;
  final List<Map<String, dynamic>> questions;
  final int? selectedIndex;
  final bool isAnswered;
  final ValueChanged<int> onSelect;

  const ReadingMicroExercise({
    super.key,
    required this.titleZh,
    required this.titleEn,
    required this.storyZh,
    required this.storyEn,
    required this.questionIndex,
    required this.questions,
    required this.selectedIndex,
    required this.isAnswered,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) return const Center(child: Text('No questions'));
    final q = questions[questionIndex.clamp(0, questions.length - 1)];
    final prompt = (q['prompt'] as Map?)?.cast<String, dynamic>() ?? {};
    final promptText = q['type'] == 'meaning_select'
        ? (prompt['hanzi'] ?? '')
        : (prompt['question'] ?? 'Choose the best answer');
    final choices = (q['choices'] as List?)?.cast<String>() ?? [];
    final answerIndex = (q['answer_index'] ?? 0) as int;

    final passageText = [
      if (titleZh.trim().isNotEmpty) titleZh.trim(),
      if (titleEn.trim().isNotEmpty) titleEn.trim(),
      if (storyZh.trim().isNotEmpty) storyZh.trim(),
      if (storyEn.trim().isNotEmpty) storyEn.trim(),
    ].join('\n');

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.maxHeight.isFinite;
        final hasPassage = passageText.trim().isNotEmpty;
        final compactOptions =
            bounded && constraints.maxHeight <= 520 && choices.length >= 5;
        final optionHeight = compactOptions ? 52.0 : 58.0;
        final optionGap = compactOptions ? 6.0 : 8.0;
        final optionTiles = List<Widget>.generate(choices.length, (i) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: i == choices.length - 1 ? 0 : optionGap,
            ),
            child: MultipleChoiceOptionCard(
              label: choices[i],
              isSelected: selectedIndex == i,
              isCorrect: i == answerIndex,
              isAnswered: isAnswered,
              height: optionHeight,
              maxLines: 2,
              fontSize: 17,
              onTap: isAnswered ? null : () => onSelect(i),
            ),
          );
        });
        final adaptivePassageHeight = hasPassage
            ? _adaptivePassageHeight(
                maxHeight: constraints.maxHeight,
                choiceCount: choices.length,
                optionHeight: optionHeight,
                optionGap: optionGap,
              )
            : 0.0;
        final passagePreview = hasPassage
            ? _PassageSelectablePreview(
                text: passageText,
                height: adaptivePassageHeight,
                compact: false,
              )
            : const SizedBox.shrink();
        if (!bounded) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasPassage) ...[passagePreview, const SizedBox(height: 8)],
              Text(
                promptText.toString(),
                style: ExerciseThemeTokens.promptBody.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: ExerciseThemeTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              ...optionTiles,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasPassage) ...[passagePreview, const SizedBox(height: 8)],
            Text(
              promptText.toString(),
              style: ExerciseThemeTokens.promptBody.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: ExerciseThemeTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ExerciseAnswerTray(
                maxVisibleItemsWithoutScroll: 4,
                estimatedChildHeight: optionHeight + optionGap,
                heightSlackPx: 40,
                mainAxisAlignment: MainAxisAlignment.start,
                children: optionTiles,
              ),
            ),
          ],
        );
      },
    );
  }

  double _adaptivePassageHeight({
    required double maxHeight,
    required int choiceCount,
    required double optionHeight,
    required double optionGap,
  }) {
    if (!maxHeight.isFinite) return 212;
    final options = choiceCount.clamp(2, 6);
    final optionsHeight =
        options * optionHeight + math.max(0, options - 1) * optionGap;
    // Reserve explicit vertical budget for question text + fixed spacers so
    // 4-choice layouts remain fully visible without hidden last options.
    const questionBlockHeight = 48.0;
    const verticalChrome = 46.0;
    final availableForPassage =
        maxHeight - optionsHeight - questionBlockHeight - verticalChrome;
    final maxCap = options <= 4 ? 216.0 : 188.0;
    return availableForPassage.clamp(96.0, maxCap).toDouble();
  }
}

class ReadingSpanSelectExercise extends StatelessWidget {
  final String passage;
  final String question;
  final List<String> choices;
  final int answerIndex;
  final int? selectedIndex;
  final bool isAnswered;
  final ValueChanged<int> onSelect;

  const ReadingSpanSelectExercise({
    super.key,
    required this.passage,
    required this.question,
    required this.choices,
    required this.answerIndex,
    required this.selectedIndex,
    required this.isAnswered,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasPassage = passage.trim().isNotEmpty;
        final bounded = constraints.maxHeight.isFinite;
        final compactOptions =
            bounded && constraints.maxHeight <= 520 && choices.length >= 5;
        final optionHeight = compactOptions ? 52.0 : 58.0;
        final optionGap = compactOptions ? 6.0 : 8.0;
        final optionTiles = List<Widget>.generate(choices.length, (i) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: i == choices.length - 1 ? 0 : optionGap,
            ),
            child: MultipleChoiceOptionCard(
              label: choices[i],
              isSelected: selectedIndex == i,
              isCorrect: i == answerIndex,
              isAnswered: isAnswered,
              height: optionHeight,
              maxLines: 2,
              fontSize: 17,
              onTap: isAnswered ? null : () => onSelect(i),
            ),
          );
        });
        final adaptivePassageHeight = hasPassage
            ? _adaptivePassageHeight(
                maxHeight: constraints.maxHeight,
                choiceCount: choices.length,
                optionHeight: optionHeight,
                optionGap: optionGap,
              )
            : 0.0;
        final passagePreview = hasPassage
            ? _PassageSelectablePreview(
                text: passage,
                height: adaptivePassageHeight,
                compact: false,
              )
            : const SizedBox.shrink();
        if (!bounded) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasPassage) ...[passagePreview, const SizedBox(height: 8)],
              Text(
                question,
                style: ExerciseThemeTokens.promptBody.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: ExerciseThemeTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              ...optionTiles,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasPassage) ...[passagePreview, const SizedBox(height: 8)],
            Text(
              question,
              style: ExerciseThemeTokens.promptBody.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: ExerciseThemeTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ExerciseAnswerTray(
                maxVisibleItemsWithoutScroll: 4,
                estimatedChildHeight: optionHeight + optionGap,
                heightSlackPx: 40,
                mainAxisAlignment: MainAxisAlignment.start,
                children: optionTiles,
              ),
            ),
          ],
        );
      },
    );
  }

  double _adaptivePassageHeight({
    required double maxHeight,
    required int choiceCount,
    required double optionHeight,
    required double optionGap,
  }) {
    if (!maxHeight.isFinite) return 212;
    final options = choiceCount.clamp(2, 6);
    final optionsHeight =
        options * optionHeight + math.max(0, options - 1) * optionGap;
    const questionBlockHeight = 48.0;
    const verticalChrome = 46.0;
    final availableForPassage =
        maxHeight - optionsHeight - questionBlockHeight - verticalChrome;
    final maxCap = options <= 4 ? 216.0 : 188.0;
    return availableForPassage.clamp(96.0, maxCap).toDouble();
  }
}

class DictationSelectExercise extends StatelessWidget {
  final String? audioUrl;
  final String promptText;
  final List<String> options;
  final int answerIndex;
  final int? selectedIndex;
  final bool isAnswered;
  final bool showPrompt;
  final ValueChanged<int> onSelect;

  const DictationSelectExercise({
    super.key,
    this.audioUrl,
    required this.promptText,
    required this.options,
    required this.answerIndex,
    required this.selectedIndex,
    required this.isAnswered,
    this.showPrompt = false,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final audioControl = _InlineAudioControl(
      audioUrl: audioUrl,
      alwaysShow: true,
      margin: const EdgeInsets.only(bottom: 0),
    );
    final optionTiles = List<Widget>.generate(options.length, (i) {
      return Padding(
        padding: EdgeInsets.only(bottom: i == options.length - 1 ? 0 : 12),
        child: MultipleChoiceOptionCard(
          label: options[i],
          isSelected: selectedIndex == i,
          isCorrect: i == answerIndex,
          isAnswered: isAnswered,
          onTap: isAnswered ? null : () => onSelect(i),
        ),
      );
    });
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.maxHeight.isFinite;
        if (!bounded) {
          return Column(
            children: [
              audioControl,
              const SizedBox(height: 10),
              if (showPrompt) ...[
                Text(
                  promptText,
                  style: ExerciseThemeTokens.promptBody.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: ExerciseThemeTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 24),
              ],
              ...optionTiles,
            ],
          );
        }
        return Column(
          children: [
            audioControl,
            const SizedBox(height: 10),
            if (showPrompt) ...[
              Text(
                promptText,
                style: ExerciseThemeTokens.promptBody.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: ExerciseThemeTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
            ],
            Expanded(child: ExerciseAnswerTray(children: optionTiles)),
          ],
        );
      },
    );
  }
}
