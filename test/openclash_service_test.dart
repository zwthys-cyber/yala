// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/openclash/services/openclash_service.dart';

void main() {
  dynamic result(String stdout, {int code = 0}) => [
    0,
    {'code': code, 'stdout': stdout},
  ];

  test(
    'detects installed but stopped service without querying controller',
    () async {
      final service = OpenClashService(
        (command, args) async => result('{"installed":true,"running":false}'),
      );
      final status = await service.status();
      expect(status.installed, isTrue);
      expect(status.running, isFalse);
    },
  );

  test('RPC permission errors remain distinguishable', () async {
    final service = OpenClashService((command, args) async => [6]);
    await expectLater(
      service.status(),
      throwsA(
        isA<OpenClashException>().having(
          (e) => e.reason,
          'reason',
          'permission',
        ),
      ),
    );
  });

  test(
    'controller credentials stay router-side and authentication fails clearly',
    () async {
      final service = OpenClashService((command, args) async {
        expect(
          args.last,
          contains('uci -q get openclash.config.dashboard_password'),
        );
        expect(args.last, contains('http://127.0.0.1:'));
        expect(args.last, contains('--noproxy'));
        return result('{"message":"Unauthorized"}\n401');
      });
      await expectLater(
        service.request('GET', '/version'),
        throwsA(
          isA<OpenClashException>().having((e) => e.reason, 'reason', 'auth'),
        ),
      );
    },
  );

  test('groups parse selectors and leave automatic groups read only', () async {
    final service = OpenClashService(
      (command, args) async => result(
        '${jsonEncode({
          'proxies': {
            'Main': {
              'type': 'Selector',
              'now': 'A',
              'all': ['A', 'B'],
            },
            'Auto': {
              'type': 'URLTest',
              'now': 'B',
              'all': ['B'],
            },
            'A': {'type': 'Shadowsocks'},
          },
        })}\n200',
      ),
    );
    final groups = await service.groups();
    expect(groups.map((g) => g.name), ['Main', 'Auto']);
    expect(groups.first.canSelect, isTrue);
    expect(groups.last.canSelect, isFalse);
  });

  test('node names cannot inject router shell commands', () async {
    const node = "HK'; reboot; echo '";
    const group = OpenClashGroup(
      name: 'Main/中文',
      type: 'Selector',
      selected: null,
      choices: [node],
    );
    final service = OpenClashService((command, args) async {
      expect(args.last, contains('/proxies/Main%2F%E4%B8%AD%E6%96%87'));
      expect(
        args.last,
        contains(OpenClashService.shellQuote(jsonEncode({'name': node}))),
      );
      return result('\n204');
    });
    await service.select(group, node);
  });

  test('invalid changes do not invoke RPC', () async {
    var calls = 0;
    final service = OpenClashService((command, args) async {
      calls++;
      return result('');
    });
    await expectLater(
      service.setMode('invalid'),
      throwsA(isA<OpenClashException>()),
    );
    await expectLater(
      service.serviceAction('reboot'),
      throwsA(isA<OpenClashException>()),
    );
    await expectLater(
      service.select(
        const OpenClashGroup(
          name: 'Auto',
          type: 'URLTest',
          selected: null,
          choices: ['A'],
        ),
        'A',
      ),
      throwsA(isA<OpenClashException>()),
    );
    expect(calls, 0);
  });

  test('controller rejection prevents persistent mode change', () async {
    var calls = 0;
    final service = OpenClashService((command, args) async {
      calls++;
      return result('{}\n400');
    });
    await expectLater(
      service.setMode('global'),
      throwsA(isA<OpenClashException>()),
    );
    expect(calls, 1);
  });

  test('successful mode change persists only the accepted mode', () async {
    final scripts = <String>[];
    final service = OpenClashService((command, args) async {
      scripts.add(args.last);
      return result(scripts.length == 1 ? '\n204' : 'OK');
    });
    await service.setMode('rule');
    expect(scripts, hasLength(2));
    expect(
      scripts.last,
      contains("uci set openclash.config.proxy_mode='rule'"),
    );
  });

  test('service action is detached and restricted to OpenClash', () async {
    final service = OpenClashService((command, args) async {
      expect(args.last, contains('/etc/init.d/openclash restart'));
      expect(args.last, contains('HUP'));
      expect(args.last, isNot(contains('network restart')));
      return result('ACCEPTED');
    });
    await service.serviceAction('restart');
  });
}
