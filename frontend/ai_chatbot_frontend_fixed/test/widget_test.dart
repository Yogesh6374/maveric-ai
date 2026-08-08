// This is a basic Flutter widget test for MavericksAIApp.

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_chatbot_frontend_fixed/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MavericksAIApp());
  });
}
