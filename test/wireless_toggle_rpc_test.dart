// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/services/api_service.dart';

class _WirelessApi extends RealApiService {
  final calls = <String>[];
  final payloads = <Map<String, dynamic>?>[];
  dynamic setResponse = [0];
  dynamic applyResponse = [0];
  bool throwOnSet = false;
  bool throwOnApply = false;

  @override
  Future<dynamic> callWithContext(String ipAddress, String sysauth, bool useHttps, {
    required String object, required String method, Map<String, dynamic>? params,
    BuildContext? context, bool isRetry = false,
  }) async {
    calls.add('$object.$method');
    payloads.add(params);
    switch ('$object.$method') {
      case 'uci.set':
        if (throwOnSet) throw Exception('RPC error: Access denied');
        return setResponse;
      case 'uci.apply':
        if (throwOnApply) throw Exception('RPC error: Access denied');
        return applyResponse;
      case 'uci.revert':
        throw Exception('RPC error: Access denied');
      default:
        throw StateError('Unexpected RPC $object.$method');
    }
  }
}

void main() {
  test('SSID toggle works with default LuCI set/apply permissions only', () async {
    final api = _WirelessApi();
    expect(await api.setSsidEnabled('router', 'token', false, ifaceSection: 'default_radio0', enabled: false), isTrue);
    expect(api.calls, ['uci.set', 'uci.apply']);
    expect(api.payloads.first, {'config': 'wireless', 'section': 'default_radio0', 'values': {'disabled': '1'}});
    expect(api.payloads.last, {'rollback': false});
  });

  test('radio toggle also avoids commit, shell and extra reload permissions', () async {
    final api = _WirelessApi();
    expect(await api.toggleWirelessRadio('router', 'token', false, radioName: 'radio1', enabled: true), isTrue);
    expect(api.calls, ['uci.set', 'uci.apply']);
    expect(api.payloads.first?['values'], {'disabled': '0'});
  });

  test('denied set does not apply, commit or revert other pending edits', () async {
    final api = _WirelessApi()..setResponse = [6];
    await expectLater(api.setSsidEnabled('router', 'token', false, ifaceSection: 'default_radio0', enabled: true), throwsA(isA<WirelessUpdateException>().having((e) => e.stage, 'stage', 'uci.set').having((e) => e.permissionDenied, 'permission', true)));
    expect(api.calls, ['uci.set']);
  });

  test('JSON-RPC access denied errors preserve the failing set stage', () async {
    final api = _WirelessApi()..throwOnSet = true;
    await expectLater(api.setSsidEnabled('router', 'token', false, ifaceSection: 'default_radio0', enabled: true), throwsA(isA<WirelessUpdateException>().having((e) => e.stage, 'stage', 'uci.set').having((e) => e.permissionDenied, 'permission', true)));
  });

  test('denied apply stays visible even when cleanup is also denied', () async {
    final api = _WirelessApi()..throwOnApply = true;
    await expectLater(api.toggleWirelessRadio('router', 'token', false, radioName: 'radio0', enabled: false), throwsA(isA<WirelessUpdateException>().having((e) => e.stage, 'stage', 'uci.apply').having((e) => e.permissionDenied, 'permission', true)));
    expect(api.calls, ['uci.set', 'uci.apply', 'uci.revert']);
  });

  test('transport failure cannot be reported as an applied configuration', () async {
    final api = _WirelessApi()..applyResponse = null;
    await expectLater(api.setSsidEnabled('router', 'token', false, ifaceSection: 'default_radio0', enabled: true), throwsA(isA<WirelessUpdateException>().having((e) => e.stage, 'stage', 'uci.apply')));
  });

  test('nonzero apply reply cannot be treated as successful application', () async {
    final api = _WirelessApi()..applyResponse = [5];
    await expectLater(api.setSsidEnabled('router', 'token', false, ifaceSection: 'default_radio0', enabled: true), throwsA(isA<WirelessUpdateException>().having((e) => e.stage, 'stage', 'uci.apply')));
  });

  test('empty set reply prevents any application request', () async {
    final api = _WirelessApi()..setResponse = null;
    await expectLater(api.setSsidEnabled('router', 'token', false, ifaceSection: 'default_radio0', enabled: true), throwsA(isA<WirelessUpdateException>().having((e) => e.stage, 'stage', 'uci.set')));
    expect(api.calls, ['uci.set']);
  });
}
