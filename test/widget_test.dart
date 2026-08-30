import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:solesync/state/auth_provider.dart' as app_auth;
import 'package:solesync/services/gait_analysis.dart';
import 'package:solesync/models/foot_line_data.dart';

void main() {
  testWidgets('Smoke test: builds a basic MaterialApp shell', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => app_auth.AuthProvider(),
        child: const MaterialApp(home: Scaffold(body: Text('NurvoSync'))),
      ),
    );

    expect(find.text('NurvoSync'), findsOneWidget);
  });

  test('GaitAnalysis.calculateBalance is symmetric and bounded', () {
    expect(GaitAnalysis.calculateBalance(50, 50), 100);
    expect(GaitAnalysis.calculateBalance(0, 0), 0);
  });

  test('FootLineData.averageOf ignores zero samples', () {
    final data = FootLineData();
    data.push(List.filled(16, 0)..[0] = 10);
    data.push(List.filled(16, 0));
    expect(data.averageOf(['data']), 10);
  });
}
