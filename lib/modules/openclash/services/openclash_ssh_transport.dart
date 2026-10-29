// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import '../../../models/router.dart';
import '../../../services/interfaces/ssh_service_interface.dart';
import 'openclash_service.dart';

/// A router-scoped adapter; never falls back to another profile's credentials.
class OpenClashSshTransport {
  final Router router;
  final ISshService ssh;
  final bool Function() isCurrent;

  OpenClashSshTransport({required this.router, required this.ssh, required this.isCurrent});

  Future<dynamic> execute(String command, List<String> args) async {
    if (!isCurrent()) {
      throw const OpenClashException('router');
    }
    if (command != '/bin/sh' || args.length != 2 || args.first != '-c') {
      throw const OpenClashException('request');
    }
    final uri = Uri.tryParse(router.ipAddress.contains('://') ? router.ipAddress : 'http://${router.ipAddress}');
    if (uri == null || !{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty || uri.userInfo.isNotEmpty || router.password.isEmpty) {
      throw const OpenClashException('ssh');
    }
    final result = await ssh.executeCommand(
      host: uri.host, username: router.username, password: router.password,
      command: [command, ...args].map(OpenClashService.shellQuote).join(' '),
      port: 22, timeout: const Duration(seconds: 20),
    );
    if (!isCurrent()) {
      throw const OpenClashException('router');
    }
    if (result.exitCode == -1) {
      throw const OpenClashException('ssh');
    }
    return [0, {'code': result.exitCode, 'stdout': result.stdout, 'stderr': ''}];
  }
}
