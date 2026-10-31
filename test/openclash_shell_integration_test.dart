// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/openclash/services/openclash_service.dart';

void main() {
  test(
    'router shell snapshot and detached service completion execute correctly',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'yala-openclash-fixture-',
      );
      addTearDown(() async {
        await dir.delete(recursive: true);
      });
      Future<void> executable(String name, String contents) async {
        final file = File('${dir.path}/$name');
        await file.writeAsString('#!/bin/sh\n$contents\n');
        final result = await Process.run('chmod', ['700', file.path]);
        expect(result.exitCode, 0);
      }

      await executable('openclash', 'exit 0');
      await executable('pidof', 'printf 123');
      await executable('uci', r'''
case "$*" in
  *cn_port*) printf 9090;;
  *dashboard_password*) printf fixture-secret-must-stay-on-router;;
esac
''');
      await executable('jsonfilter', 'cat >/dev/null\nprintf rule');
      await executable('curl', r'''
for arg in "$@"; do last="$arg"; done
case "$last" in
  */version) printf '%s\n200\n' '{"version":"v1.19.33"}';;
  */configs) printf '%s\n200\n' '{"mode":"rule","secret":"not-for-client"}';;
  */proxies) printf '%s\n200\n' '{"proxies":{"Main":{"type":"Selector","now":"A","all":["A","B"]}}}';;
  *) printf '\n404\n';;
esac
''');
      final outputs = <String>[];
      final service = OpenClashService((command, args) async {
        final script = args.last.replaceAll(
          '/etc/init.d/openclash',
          '${dir.path}/openclash',
        );
        final result = await Process.run(
          command,
          ['-c', script],
          environment: {'PATH': '${dir.path}:${Platform.environment['PATH']}'},
        );
        outputs.add(result.stdout.toString());
        return [
          0,
          {
            'code': result.exitCode,
            'stdout': result.stdout,
            'stderr': result.stderr,
          },
        ];
      });
      final snapshot = await service.loadSnapshot();
      expect(snapshot.status.installed, isTrue);
      expect(snapshot.status.running, isTrue);
      expect(snapshot.version, 'v1.19.33');
      expect(snapshot.mode, 'rule');
      expect(snapshot.groups.single.choices, ['A', 'B']);
      expect(
        outputs.single,
        isNot(contains('fixture-secret-must-stay-on-router')),
      );
      expect(outputs.single, isNot(contains('not-for-client')));
      final operation = await service.serviceAction('restart');
      var completed = false;
      for (var attempt = 0; attempt < 10 && !completed; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        completed = await service.actionComplete(operation);
      }
      expect(completed, isTrue);
    },
    skip: Platform.isWindows,
  );
}
