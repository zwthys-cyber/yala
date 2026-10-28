// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yet_another_luci_app/main.dart' as app;
import 'package:yet_another_luci_app/screens/login_screen.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fresh iOS installation reaches the router login screen', (
    tester,
  ) async {
    app.main();
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (find.byType(LoginScreen).evaluate().isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(TextFormField), findsWidgets);
    expect(tester.takeException(), isNull);

    final screenshot = await binding.takeScreenshot('ios-login');
    final directory = await getApplicationDocumentsDirectory();
    await File('${directory.path}/ios-login.png').writeAsBytes(screenshot);
  });
}
