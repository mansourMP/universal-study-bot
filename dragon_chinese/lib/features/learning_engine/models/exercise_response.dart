class ExerciseResponse {
  final int? selectedIndex;
  final List<String> orderedTokens;
  final String typedText;
  final Map<String, dynamic> metadata;

  const ExerciseResponse({
    this.selectedIndex,
    this.orderedTokens = const [],
    this.typedText = '',
    this.metadata = const {},
  });

  const ExerciseResponse.selection({required int? selectedIndex})
    : this(selectedIndex: selectedIndex);

  const ExerciseResponse.ordering({required List<String> orderedTokens})
    : this(orderedTokens: orderedTokens);

  const ExerciseResponse.text({required String typedText})
    : this(typedText: typedText);
}
