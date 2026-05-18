import 'package:antenna_aligner/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App starts and shows Home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MainApp());

    expect(find.text('Manage Access Points'), findsOneWidget);
    expect(find.text('Alignment Display'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
