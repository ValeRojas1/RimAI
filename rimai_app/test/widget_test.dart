import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rimai_app/main.dart';

void main() {
  testWidgets('RimAI app boots', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: RimAIApp()));
    await tester.pump();

    expect(find.byType(RimAIApp), findsOneWidget);
  });
}
