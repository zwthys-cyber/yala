// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import '../../../models/rpc_result.dart';

typedef OpenClashExec = Future<dynamic> Function(String command, List<String> args);

class OpenClashException implements Exception {
  final String reason;
  const OpenClashException(this.reason);
}

class OpenClashStatus {
  final bool installed;
  final bool running;
  const OpenClashStatus({required this.installed, required this.running});
}

class OpenClashGroup {
  final String name;
  final String type;
  final String? selected;
  final List<String> choices;
  const OpenClashGroup({required this.name, required this.type, required this.selected, required this.choices});
  bool get canSelect => type == 'Selector';
}

/// Uses the authenticated router RPC session, never a publicly exposed controller.
/// Credentials remain on the router and are never included in RPC output.
class OpenClashService {
  final OpenClashExec execute;
  OpenClashService(this.execute);

  static String shellQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

  Future<String> _run(String script) async {
    final raw = await execute('/bin/sh', ['-c', script]);
    final result = RpcResult.classifyExecResult<String>(raw, (data) => (data['code'] == null || data['code'] == 0) ? data['stdout']?.toString() ?? '' : '');
    if (!result.isSuccess) {
      throw OpenClashException(result.isPermissionDenied ? 'permission' : 'connection');
    }
    return result.data!;
  }

  Future<OpenClashStatus> status() async {
    final output = await _run(r'''
installed=false; running=false
[ ! -x /etc/init.d/openclash ] || installed=true
if pidof clash_meta clash mihomo >/dev/null 2>&1; then running=true; fi
printf '{"installed":%s,"running":%s}' "$installed" "$running"
''');
    final data = jsonDecode(output) as Map<String, dynamic>;
    return OpenClashStatus(installed: data['installed'] == true, running: data['running'] == true);
  }

  Future<Map<String, dynamic>> request(String method, String path, [Map<String, dynamic>? body]) async {
    if (!{'GET', 'PATCH', 'PUT'}.contains(method) || !path.startsWith('/')) {
      throw const OpenClashException('request');
    }
    final payload = body == null ? '' : ' --data-binary ${shellQuote(jsonEncode(body))}';
    final output = await _run(r'''
port=$(uci -q get openclash.config.cn_port)
secret=$(uci -q get openclash.config.dashboard_password)
case "$port" in ''|*[!0-9]*) printf '\n000'; exit 0;; esac
[ "$port" -ge 1 ] && [ "$port" -le 65535 ] || { printf '\n000'; exit 0; }
command -v curl >/dev/null 2>&1 || { printf '\n000'; exit 0; }
curl --silent --connect-timeout 3 --max-time 8 --noproxy '*' \
  -H "Authorization: Bearer $secret" -H 'Content-Type: application/json' \
  -w '\n%{http_code}' ''' + '-X $method$payload "http://127.0.0.1:\$port"${shellQuote(path)} 2>/dev/null');
    final split = output.lastIndexOf('\n');
    if (split < 0) throw const OpenClashException('controller');
    final code = int.tryParse(output.substring(split + 1).trim()) ?? 0;
    if (code == 401 || code == 403) throw const OpenClashException('auth');
    if (code < 200 || code >= 300) throw const OpenClashException('controller');
    final text = output.substring(0, split).trim();
    return text.isEmpty ? {} : jsonDecode(text) as Map<String, dynamic>;
  }

  Future<List<OpenClashGroup>> groups() async {
    final data = await request('GET', '/proxies');
    final proxies = data['proxies'];
    if (proxies is! Map) throw const OpenClashException('controller');
    final groups = <OpenClashGroup>[];
    for (final entry in proxies.entries) {
      final value = entry.value;
      if (value is! Map || value['all'] is! List) continue;
      groups.add(OpenClashGroup(name: entry.key.toString(), type: value['type']?.toString() ?? '', selected: value['now']?.toString(), choices: (value['all'] as List).whereType<String>().toList()));
    }
    return groups;
  }

  Future<void> setMode(String mode) async {
    if (!{'rule', 'global', 'direct'}.contains(mode)) throw const OpenClashException('request');
    await request('PATCH', '/configs', {'mode': mode});
    // Match OpenClash's own mode switch persistence after controller acceptance.
    await _run('uci set openclash.config.proxy_mode=${shellQuote(mode)} || exit 1; '
        'if uci -q get openclash.@overwrite[0] >/dev/null; then '
        'uci set openclash.@overwrite[0].proxy_mode=${shellQuote(mode)} || exit 1; fi; '
        'uci commit openclash && printf OK');
  }

  Future<void> select(OpenClashGroup group, String node) async {
    if (!group.canSelect || !group.choices.contains(node)) throw const OpenClashException('request');
    await request('PUT', '/proxies/${Uri.encodeComponent(group.name)}', {'name': node});
  }

  Future<void> serviceAction(String action) async {
    if (!{'start', 'stop', 'restart'}.contains(action)) throw const OpenClashException('request');
    // Long service actions must outlive the short RPC request. No router reboot.
    final output = await _run('test -x /etc/init.d/openclash || exit 1; '
        'sh -c ${shellQuote('trap "" HUP; exec /etc/init.d/openclash $action')} '
        '> /dev/null 2>&1 < /dev/null & printf ACCEPTED');
    if (output.trim() != 'ACCEPTED') throw const OpenClashException('connection');
  }
}
