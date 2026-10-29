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
      final operation = RegExp(r'printf ACCEPTED:(yala-oc-[0-9]+)').firstMatch(args.last)!.group(1)!;
      return result('ACCEPTED:$operation');
    });
    await service.serviceAction('restart');
  });
  test('denied RPC switches to SSH and avoids repeated denied calls', () async {
    var rpcCalls = 0;
    var sshCalls = 0;
    final service = OpenClashService((command, args) async {
      rpcCalls++;
      return [6];
    }, fallbackExecute: (command, args) async {
      sshCalls++;
      expect(command, '/bin/sh');
      expect(args.first, '-c');
      return result('{"installed":true,"running":true}');
    });
    expect((await service.status()).running, isTrue);
    expect((await service.status()).installed, isTrue);
    expect(rpcCalls, 1);
    expect(sshCalls, 2);
    expect(service.usingSshFallback, isTrue);
  });

  test('JSON-RPC access denied exception also permits SSH fallback', () async {
    final service = OpenClashService((command, args) async {
      throw Exception('RPC error: Access denied');
    }, fallbackExecute: (command, args) async => result('{"installed":true,"running":false}'));
    expect((await service.status()).running, isFalse);
    expect(service.usingSshFallback, isTrue);
  });

  test('ambiguous network failure never retries a command through SSH', () async {
    var sshCalls = 0;
    final service = OpenClashService((command, args) async {
      throw Exception('Connection timed out');
    }, fallbackExecute: (command, args) async { sshCalls++; return result('ACCEPTED'); });
    await expectLater(service.serviceAction('restart'), throwsException);
    expect(sshCalls, 0);
  });

  test('SSH failure remains distinguishable from RPC permission failure', () async {
    final service = OpenClashService((command, args) async => [6], fallbackExecute: (command, args) async {
      throw const OpenClashException('ssh');
    });
    await expectLater(service.status(), throwsA(isA<OpenClashException>().having((e) => e.reason, 'reason', 'ssh')));
  });

  test('controller authentication error does not trigger SSH fallback', () async {
    var sshCalls = 0;
    final service = OpenClashService((command, args) async => result('{"message":"Unauthorized"}\n401'), fallbackExecute: (command, args) async { sshCalls++; return result(''); });
    await expectLater(service.request('GET', '/version'), throwsA(isA<OpenClashException>().having((e) => e.reason, 'reason', 'auth')));
    expect(sshCalls, 0);
  });

  test('one snapshot carries status, version, mode and groups in one command', () async {
    var calls = 0;
    final service = OpenClashService((command, args) async {
      calls++;
      return result(jsonEncode({'installed': true, 'running': true, 'version': {'version': 'v1.19.33'}, 'mode': 'rule', 'proxies': {'proxies': {'Main': {'type': 'Selector', 'all': ['A'], 'now': 'A'}}}}));
    });
    final snapshot = await service.loadSnapshot();
    expect(calls, 1);
    expect(snapshot.status.running, isTrue);
    expect(snapshot.version, 'v1.19.33');
    expect(snapshot.mode, 'rule');
    expect(snapshot.groups.single.selected, 'A');
  });

  test('controller error retains installed/running state for service recovery', () async {
    final service = OpenClashService((command, args) async => result('{"installed":true,"running":true,"controllerError":"auth"}'));
    final snapshot = await service.loadSnapshot();
    expect(snapshot.status.running, isTrue);
    expect(snapshot.controllerError, 'auth');
    expect(snapshot.groups, isEmpty);
  });

  test('stopped plugin has no stale version, mode or groups', () async {
    final service = OpenClashService((command, args) async => result('{"installed":true,"running":false}'));
    final snapshot = await service.loadSnapshot();
    expect(snapshot.status.running, isFalse);
    expect(snapshot.version, isNull);
    expect(snapshot.mode, isNull);
    expect(snapshot.groups, isEmpty);
  });

  test('service completion distinguishes pending from completed action', () async {
    var pending = true;
    final service = OpenClashService((command, args) async {
      final output = pending ? 'PENDING' : '0';
      pending = false;
      return result(output);
    });
    expect(await service.actionComplete('yala-oc-123'), isFalse);
    expect(await service.actionComplete('yala-oc-123'), isTrue);
  });

  test('failed service command is never reported completed successfully', () async {
    final service = OpenClashService((command, args) async => result('1'));
    await expectLater(service.actionComplete('yala-oc-123'), throwsA(isA<OpenClashException>().having((e) => e.reason, 'reason', 'service')));
  });

  test('invalid service operation identifier cannot access arbitrary files', () async {
    var calls = 0;
    final service = OpenClashService((command, args) async { calls++; return result('0'); });
    await expectLater(service.actionComplete('../../etc/shadow'), throwsA(isA<OpenClashException>()));
    expect(calls, 0);
  });

}
