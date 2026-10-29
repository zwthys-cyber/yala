// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/openclash/screens/openclash_management_screen.dart';
import 'package:yet_another_luci_app/modules/openclash/services/openclash_service.dart';
import 'package:yet_another_luci_app/modules/openclash/services/openclash_management_service.dart';

void main() {
  test(
    'subscription update is refused before launching work on low memory',
    () async {
      var calls = 0;
      final manager = OpenClashManagementService(
        OpenClashService((command, args) async {
          calls++;
          return [
            0,
            {
              'code': 0,
              'stdout':
                  'YALA_RESOURCE_V1\nMemTotal: 174812 kB\nMemAvailable: 1000 kB\n\nYALA_ZRAM_V1\n\nYALA_LOAD_V1\n0 0 0\n',
            },
          ];
        }),
      );
      await expectLater(
        manager.updateSubscription(
          const OpenClashSubscription(
            id: 'cfg123',
            name: 'Main',
            address: 'https://example.com/sub',
            userAgent: 'Clash',
            enabled: true,
            converted: false,
            revision: 'old',
          ),
        ),
        throwsA(
          isA<OpenClashException>().having(
            (e) => e.reason,
            'reason',
            'lowMemory',
          ),
        ),
      );
      expect(calls, 1);
    },
  );
  test('configuration names reject paths and hidden files', () {
    for (final name in [
      '../config.yaml',
      '/etc/config.yaml',
      'a/b.yaml',
      r'a\b.yaml',
      '.hidden.yaml',
      'config.json',
    ]) {
      expect(OpenClashManagementService.validFile(name), isFalse);
    }
    expect(OpenClashManagementService.validFile('香港节点.yaml'), isTrue);
  });

  test('YAML is validated before sending any router command', () async {
    var calls = 0;
    final manager = OpenClashManagementService(
      OpenClashService((command, args) async {
        calls++;
        return null;
      }),
    );
    await expectLater(
      manager.saveConfig('config.yaml', '[broken'),
      throwsA(isA<OpenClashException>()),
    );
    await expectLater(
      manager.saveConfig('config.yaml', '- sequence'),
      throwsA(isA<OpenClashException>()),
    );
    await expectLater(
      manager.saveConfig('config.yaml', 'x: ${'a' * 65536}'),
      throwsA(isA<OpenClashException>()),
    );
    expect(calls, 0);
  });

  test('new subscriptions accept direct HTTP YAML URLs only', () {
    expect(
      () => OpenClashManagementService.validateSubscription(
        'Main',
        'https://example.com/sub?token=private',
        'Clash',
        converted: false,
      ),
      returnsNormally,
    );
    for (final address in [
      'file:///etc/passwd',
      'https://example.com\nhttps://other.example',
      'ss://node',
    ]) {
      expect(
        () => OpenClashManagementService.validateSubscription(
          'Main',
          address,
          'Clash',
          converted: false,
        ),
        throwsA(isA<OpenClashException>()),
      );
    }
  });

  test(
    'controller secrets are not requested for subscription inventory',
    () async {
      final manager = OpenClashManagementService(
        OpenClashService((command, args) async {
          expect(args.last, isNot(contains('dashboard_password')));
          expect(args.last, isNot(contains('uci export')));
          return [
            0,
            {
              'code': 0,
              'stdout': '{"subscriptions":[],"files":[],"active":null}',
            },
          ];
        }),
      );
      expect((await manager.inventory()).subscriptions, isEmpty);
    },
  );

  testWidgets(
    'management follows the app cards and cancels edits without writes',
    (tester) async {
      var calls = 0;
      final service = OpenClashService((command, args) async {
        calls++;
        return [
          0,
          {
            'code': 0,
            'stdout': '{"subscriptions":[],"files":[],"active":null}',
          },
        ];
      });
      await tester.pumpWidget(
        MaterialApp(home: OpenClashManagementScreen(service: service)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Subscriptions'), findsOneWidget);
      expect(find.text('Configuration files'), findsOneWidget);
      expect(calls, 1);
      await tester.tap(find.text('Add subscription'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(minutes: 2));
      expect(calls, 1);
    },
  );

  test(
    'actual router interpreter preserves options and safely manages configuration files',
    () async {
      final fixture = await Directory.systemTemp.createTemp('yala-management-');
      addTearDown(() => fixture.delete(recursive: true));
      final configDir = Directory('${fixture.path}/etc/config')
        ..createSync(recursive: true);
      final filesDir = Directory('${fixture.path}/etc/openclash/config')
        ..createSync(recursive: true);
      final init = File('${fixture.path}/openclash');
      await init.writeAsString('#!/bin/sh\nexit 0\n');
      expect((await Process.run('chmod', ['700', init.path])).exitCode, 0);
      final uciFile = File('${configDir.path}/openclash');
      await uciFile.writeAsString('''config openclash 'config'
 option config_path '${filesDir.path}/active.yaml'
 option dashboard_password 'fixture-secret-never-export'

config config_subscribe 'original'
 option name 'Original'
 option address 'https://example.com/private'
 option sub_convert '1'
 option template 'keep-template'
 list keyword 'keep-filter'
''');
      await File('${filesDir.path}/active.yaml').writeAsString('proxies: []\n');
      await Link('${filesDir.path}/link.yaml').create(uciFile.path);
      final outputs = <String>[];
      final service = OpenClashService((command, args) async {
        final script = args.last
            .replaceAll('/etc/openclash', '${fixture.path}/etc/openclash')
            .replaceAll('/etc/config/openclash', uciFile.path)
            .replaceAll('/etc/init.d/openclash', init.path)
            .replaceAll('cursor(null,', "cursor('${configDir.path}',");
        final result = await Process.run(command, ['-c', script]);
        outputs.add(result.stdout.toString());
        // Include interpreter errors in CI failures; fixture contains no real secrets.
        expect(result.exitCode, 0, reason: result.stderr.toString());
        return [
          0,
          {
            'code': result.exitCode,
            'stdout': result.stdout,
            'stderr': result.stderr,
          },
        ];
      });
      final manager = OpenClashManagementService(service);
      final initial = await manager.inventory();
      expect(initial.files.map((f) => f.name), ['active.yaml']);
      expect(outputs.single, isNot(contains('fixture-secret-never-export')));
      final original = initial.subscriptions.single;
      await manager.saveSubscription(
        original: original,
        name: 'Edited',
        address: 'https://example.com/new',
        userAgent: 'Clash',
        enabled: false,
      );
      final after = await manager.inventory();
      expect(after.subscriptions.single.name, 'Edited');
      expect(after.subscriptions.single.converted, isTrue);
      expect(await uciFile.readAsString(), contains('keep-template'));
      expect(await uciFile.readAsString(), contains('keep-filter'));
      await expectLater(
        manager.deleteSubscription(original),
        throwsA(
          isA<OpenClashException>().having(
            (e) => e.reason,
            'reason',
            'conflict',
          ),
        ),
      );
      await manager.saveSubscription(
        name: 'New',
        address: 'https://example.com/new',
        userAgent: 'Clash',
        enabled: true,
      );
      expect((await manager.inventory()).subscriptions, hasLength(2));
      await manager.saveConfig('new.yaml', 'proxies: []\nrules: []\n');
      final doc = await manager.readConfig('new.yaml');
      expect(doc.content, contains('rules'));
      await manager.saveConfig(
        'new.yaml',
        'proxies: []\nmode: rule\n',
        revision: doc.revision,
      );
      await expectLater(
        manager.saveConfig('new.yaml', doc.content, revision: doc.revision),
        throwsA(
          isA<OpenClashException>().having(
            (e) => e.reason,
            'reason',
            'conflict',
          ),
        ),
      );
      await expectLater(
        manager.deleteConfig('active.yaml'),
        throwsA(
          isA<OpenClashException>().having((e) => e.reason, 'reason', 'active'),
        ),
      );
      await expectLater(
        manager.readConfig('link.yaml'),
        throwsA(
          isA<OpenClashException>().having((e) => e.reason, 'reason', 'path'),
        ),
      );
      await manager.deleteConfig('new.yaml');
      expect(await File('${filesDir.path}/new.yaml').exists(), isFalse);
      expect(
        await File(
          '${fixture.path}/etc/openclash/.yala-backups/new.yaml.bak',
        ).exists(),
        isTrue,
      );
      await manager.saveConfig('switch.yaml', 'proxies: []\n');
      final operation = await manager.activateConfig('switch.yaml');
      var complete = false;
      for (var i = 0; i < 10 && !complete; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        complete = await service.actionComplete(operation);
      }
      expect(complete, isTrue);
      expect(
        await uciFile.readAsString(),
        contains('${filesDir.path}/switch.yaml'),
      );
      expect(jsonDecode(outputs.first)['subscriptions'], hasLength(1));
    },
    skip: Platform.environment['YALA_UCODE_INTEGRATION'] != '1',
  );
}
