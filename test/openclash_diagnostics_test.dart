// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/openclash/models/router_resources.dart';
import 'package:yet_another_luci_app/modules/openclash/screens/openclash_diagnostics_screen.dart';
import 'package:yet_another_luci_app/modules/openclash/services/openclash_service.dart';

const snapshot = '''YALA_RESOURCE_V1
MemTotal: 174812 kB
MemAvailable: 25484 kB
SwapTotal: 65532 kB
SwapFree: 64508 kB

YALA_ZRAM_V1
1048576 200000 262144 25165824 262144 0 0 0 0
YALA_LOAD_V1
0.10 0.61 2.24
''';

void main() {
  test('physical memory, swap and compressed RAM remain separate', () {
    final resources = RouterResources.parse(snapshot);
    expect(resources.totalKiB, 174812);
    expect(resources.availableKiB, 25484);
    expect(resources.swapTotalKiB - resources.swapFreeKiB, 1024);
    expect(resources.zramOriginalBytes, 1048576);
    expect(resources.zramPhysicalBytes, 262144);
    expect(resources.load, '0.10 0.61 2.24');
  });

  test(
    'missing optional zram and available memory do not become fake values',
    () {
      final resources = RouterResources.parse('''YALA_RESOURCE_V1
MemTotal: 174812 kB

YALA_ZRAM_V1

YALA_LOAD_V1
0.10 0.61 2.24
''');
      expect(resources.availableKiB, isNull);
      expect(resources.zramPhysicalBytes, isNull);
      expect(resources.swapTotalKiB, 0);
    },
  );

  test('malformed resource snapshots fail instead of displaying zero RAM', () {
    expect(() => RouterResources.parse(''), throwsFormatException);
    expect(
      () =>
          RouterResources.parse(snapshot.replaceFirst('MemTotal:', 'Invalid:')),
      throwsFormatException,
    );
  });

  test('log reads redact credentials and URLs', () async {
    final service = OpenClashService((command, args) async {
      expect(args.last, contains('tail -c 32768'));
      return [
        0,
        {
          'code': 0,
          'stdout':
              'YALA_LOG_V1\nsecret=example-key\nsubscription https://example.com/private\ncore ready\n',
        },
      ];
    });
    final logs = await service.logs(system: false);
    expect(logs, isNot(contains('example-key')));
    expect(logs, isNot(contains('https://example.com/private')));
    expect(logs, contains('core ready'));
  });

  testWidgets(
    'diagnostics use existing cards without polling or reading logs automatically',
    (tester) async {
      var calls = 0;
      final service = OpenClashService((command, args) async {
        calls++;
        return [
          0,
          {'code': 0, 'stdout': snapshot},
        ];
      });
      await tester.pumpWidget(
        MaterialApp(home: OpenClashDiagnosticsScreen(service: service)),
      );
      await tester.pumpAndSettle();
      expect(find.text('24.9 MiB'), findsOneWidget);
      expect(find.text('Read recent logs'), findsOneWidget);
      expect(calls, 1);
      await tester.pump(const Duration(minutes: 2));
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
