import 'package:flutter_test/flutter_test.dart';

import 'package:classroom/app.dart';

void main() {
  testWidgets('ClassRoomApp shows the home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ClassRoomApp());

    expect(find.text('ClassRoom'), findsOneWidget);
    expect(find.text('Take Attendance'), findsOneWidget);
  });
}
