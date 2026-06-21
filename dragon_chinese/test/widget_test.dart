import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/main.dart';

void main() {
  testWidgets('App launches', (WidgetTester tester) async {
    await tester.pumpWidget(const DragonChineseApp());
    expect(find.text('SELECT YOUR GOAL'), findsOneWidget);
  });
}
