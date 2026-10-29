// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/router.dart';
import 'package:yet_another_luci_app/services/interfaces/ssh_service_interface.dart';
import 'package:yet_another_luci_app/modules/openclash/services/openclash_service.dart';
import 'package:yet_another_luci_app/modules/openclash/services/openclash_ssh_transport.dart';

class _Ssh extends ISshService {
  int calls = 0;
  String? host;
  String? user;
  String? pass;
  int? portUsed;
  String? script;
  void Function()? onExecute;
  SshCommandResult response = const SshCommandResult(exitCode: 0, stdout: 'OK', stderr: '', success: true);
  @override
  Future<SshCommandResult> executeCommand({required String host, required String username, required String password, required String command, int port = 22, Duration timeout = const Duration(seconds: 15)}) async {
    calls++;
    this.host = host;
    user = username;
    pass = password;
    portUsed = port;
    script = command;
    onExecute?.call();
    return response;
  }
}

void main() {
  Router router({String address = 'https://192.168.10.1:8443', String password = 'fixture-only'}) => Router(id: 'router-A', ipAddress: address, username: 'operator', password: password, useHttps: true);

  test('uses selected profile credentials and SSH port, not LuCI port', () async {
    final ssh = _Ssh();
    final transport = OpenClashSshTransport(router: router(), ssh: ssh, isCurrent: () => true);
    final result = await transport.execute('/bin/sh', ['-c', "printf '%s' 'a b'"]);
    expect(ssh.host, '192.168.10.1');
    expect(ssh.portUsed, 22);
    expect(ssh.user, 'operator');
    expect(ssh.pass, 'fixture-only');
    expect(ssh.script, [ '/bin/sh', '-c', "printf '%s' 'a b'" ].map(OpenClashService.shellQuote).join(' '));
    expect(result, [0, {'code': 0, 'stdout': 'OK', 'stderr': ''}]);
  });

  test('switching router before request prevents use of stale credentials', () async {
    final ssh = _Ssh();
    final transport = OpenClashSshTransport(router: router(), ssh: ssh, isCurrent: () => false);
    await expectLater(transport.execute('/bin/sh', ['-c', 'true']), throwsA(isA<OpenClashException>().having((e) => e.reason, 'reason', 'router')));
    expect(ssh.calls, 0);
  });

  test('switching router during request rejects stale response', () async {
    var current = true;
    final ssh = _Ssh()..onExecute = () { current = false; };
    final transport = OpenClashSshTransport(router: router(), ssh: ssh, isCurrent: () => current);
    await expectLater(transport.execute('/bin/sh', ['-c', 'true']), throwsA(isA<OpenClashException>().having((e) => e.reason, 'reason', 'router')));
  });

  test('invalid transport commands are rejected without connecting', () async {
    final ssh = _Ssh();
    final transport = OpenClashSshTransport(router: router(), ssh: ssh, isCurrent: () => true);
    await expectLater(transport.execute('/sbin/reboot', []), throwsA(isA<OpenClashException>()));
    expect(ssh.calls, 0);
  });

  test('empty credentials and embedded URL credentials are not transmitted', () async {
    for (final profile in [router(password: ''), router(address: 'https://someone:secret@192.168.10.1')]) {
      final ssh = _Ssh();
      final transport = OpenClashSshTransport(router: profile, ssh: ssh, isCurrent: () => true);
      await expectLater(transport.execute('/bin/sh', ['-c', 'true']), throwsA(isA<OpenClashException>().having((e) => e.reason, 'reason', 'ssh')));
      expect(ssh.calls, 0);
    }
  });

  test('connection errors do not expose SSH error details or credentials', () async {
    final ssh = _Ssh()..response = const SshCommandResult(exitCode: -1, stdout: '', stderr: '', success: false, errorMessage: 'fixture-sensitive-detail');
    final transport = OpenClashSshTransport(router: router(), ssh: ssh, isCurrent: () => true);
    await expectLater(transport.execute('/bin/sh', ['-c', 'true']), throwsA(isA<OpenClashException>().having((e) => e.reason, 'reason', 'ssh')));
  });
}
