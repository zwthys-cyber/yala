// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:yaml/yaml.dart';
import 'openclash_service.dart';

class OpenClashSubscription {
  final String id;
  final String name;
  final String address;
  final String userAgent;
  final bool enabled;
  final bool converted;
  final String revision;

  const OpenClashSubscription({
    required this.id,
    required this.name,
    required this.address,
    required this.userAgent,
    required this.enabled,
    required this.converted,
    required this.revision,
  });

  factory OpenClashSubscription.fromJson(Map data) => OpenClashSubscription(
    id: data['id'] as String,
    name: data['name'] as String,
    address: data['address'] as String,
    userAgent: data['ua'] as String,
    enabled: data['enabled'] == true,
    converted: data['converted'] == true,
    revision: data['revision'] as String,
  );
}

class OpenClashConfigFile {
  final String name;
  final int bytes;
  const OpenClashConfigFile(this.name, this.bytes);
}

class OpenClashInventory {
  final List<OpenClashSubscription> subscriptions;
  final List<OpenClashConfigFile> files;
  final String? active;
  const OpenClashInventory(this.subscriptions, this.files, this.active);
}

class OpenClashConfigDocument {
  final String content;
  final String revision;
  const OpenClashConfigDocument(this.content, this.revision);
}

class OpenClashManagementService {
  final OpenClashService service;
  OpenClashManagementService(this.service);
  static const maxConfigBytes = 65536;

  static bool validName(String name) =>
      name.isNotEmpty &&
      name.length <= 64 &&
      name.trim() == name &&
      !name.startsWith('.') &&
      !RegExp(r'[/\\\x00-\x1f\x7f]').hasMatch(name);
  static bool validFile(String name) =>
      validName(name) &&
      RegExp(r'\.ya?ml$', caseSensitive: false).hasMatch(name);
  static bool validSection(String id) =>
      RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(id);

  static void validateYaml(String content) {
    if (utf8.encode(content).length > maxConfigBytes) {
      throw const OpenClashException('size');
    }
    try {
      if (loadYaml(content) is! YamlMap) throw const FormatException();
    } catch (_) {
      throw const OpenClashException('yaml');
    }
  }

  static void validateSubscription(
    String name,
    String address,
    String ua, {
    required bool converted,
  }) {
    if (!validName(name) ||
        address.isEmpty ||
        utf8.encode(address).length > 8192 ||
        ua.length > 256 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(ua)) {
      throw const OpenClashException('request');
    }
    if (address.contains('\x00')) throw const OpenClashException('request');
    if (!converted) {
      final uri = Uri.tryParse(address);
      if (uri == null ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty ||
          RegExp(r'\s').hasMatch(address)) {
        throw const OpenClashException('subscriptionUrl');
      }
    }
  }

  static const _prefix = r'''
import * as fs from 'fs';
import { cursor } from 'uci';
import { sha256 } from 'digest';
function fail(reason) { printf('%J', { error: reason }); exit(0); }
let base = '/etc/openclash/config';
if (fs.realpath(base) != base) fail('path');
// An empty delta directory avoids committing another LuCI session's changes.
let c = cursor(null, getenv('YALA_UCI_DELTA'));
function subscription(s) {
  let item = {id:s['.name'], name:s.name || 'config', address:s.address || '', ua:s.sub_ua || '', enabled:s.enabled != '0', converted:s.sub_convert == '1'};
  item.revision = sha256(sprintf('%J', item));
  return item;
}
function backup(path, name) {
  let dir = '/etc/openclash/.yala-backups';
  if (!fs.lstat(dir)) fs.mkdir(dir, 0o700);
  if (fs.realpath(dir) != dir || fs.lstat(dir).type != 'directory') fail('path');
  fs.chmod(dir, 0o700);
  let data = fs.readfile(path, 262145);
  if (data == null || length(data) > 262144) fail('size');
  let target = dir + '/' + name + '.bak';
  if (fs.lstat(target)?.type == 'link') fail('path');
  if (fs.writefile(target, data) != length(data) || !fs.chmod(target, 0o600)) fail('storage');
}
function file(name) {
  let path = base + '/' + name;
  let info = fs.lstat(path);
  if (!info || info.type != 'file') fail('path');
  return path;
}
''';

  Future<Map<String, dynamic>> _call(
    String code, [
    Map<String, dynamic> input = const {},
  ]) async {
    final source = '$_prefix\nlet input = ${jsonEncode(input)};\n$code';
    final result =
        jsonDecode(
              await service.runManagementScript(
                'umask 077; delta=\$(mktemp -d /tmp/yala-uci.XXXXXX) || exit 1; '
                'trap \'rm -rf "\$delta"\' EXIT; '
                'YALA_UCI_DELTA="\$delta" ucode -e ${OpenClashService.shellQuote(source)}',
              ),
            )
            as Map<String, dynamic>;
    if (result['error'] != null) {
      throw OpenClashException(result['error'].toString());
    }
    return result;
  }

  Future<OpenClashInventory> inventory() async {
    final result = await _call(r'''
let subscriptions = [];
c.foreach('openclash', 'config_subscribe', s => push(subscriptions, subscription(s)));
let files = [];
for (let name in (fs.lsdir(base) || [])) {
  let info = fs.lstat(base + '/' + name);
  if (info?.type == 'file' && match(name, /\.ya?ml$/i)) push(files, {name:name, bytes:info.size});
}
printf('%J', {subscriptions:subscriptions, files:files, active:c.get('openclash','config','config_path')});
''');
    final active = result['active']?.toString();
    return OpenClashInventory(
      (result['subscriptions'] as List)
          .map((e) => OpenClashSubscription.fromJson(e as Map))
          .toList(),
      (result['files'] as List)
          .map(
            (e) => OpenClashConfigFile(e['name'] as String, e['bytes'] as int),
          )
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name)),
      active?.startsWith('/etc/openclash/config/') == true
          ? active!.substring('/etc/openclash/config/'.length)
          : null,
    );
  }

  Future<void> saveSubscription({
    OpenClashSubscription? original,
    required String name,
    required String address,
    required String userAgent,
    required bool enabled,
  }) async {
    validateSubscription(
      name,
      address,
      userAgent,
      converted: original?.converted == true,
    );
    if (original != null && !validSection(original.id)) {
      throw const OpenClashException('request');
    }
    await _call(
      r'''
let sid = input.id;
if (sid) {
  let old = c.get_all('openclash', sid);
  if (!old || old['.type'] != 'config_subscribe' || subscription(old).revision != input.revision) fail('conflict');
}
let duplicate = false;
c.foreach('openclash','config_subscribe', s => { if (s['.name'] != sid && (s.name || 'config') == input.name) duplicate = true; });
if (duplicate) fail('duplicate');
backup('/etc/config/openclash', 'uci-openclash');
if (!sid) sid = c.add('openclash', 'config_subscribe');
if (!sid || !c.set('openclash',sid,'name',input.name) || !c.set('openclash',sid,'address',input.address) || !c.set('openclash',sid,'sub_ua',input.ua) || !c.set('openclash',sid,'enabled',input.enabled ? '1' : '0')) fail('storage');
if (!input.id && !c.set('openclash',sid,'sub_convert','0')) fail('storage');
if (!c.commit('openclash')) fail('storage');
printf('%J', {ok:true});
''',
      {
        'id': original?.id,
        'revision': original?.revision,
        'name': name,
        'address': address,
        'ua': userAgent,
        'enabled': enabled,
      },
    );
  }

  Future<void> deleteSubscription(OpenClashSubscription original) async {
    if (!validSection(original.id)) throw const OpenClashException('request');
    await _call(
      r'''
let old = c.get_all('openclash', input.id);
if (!old || old['.type'] != 'config_subscribe' || subscription(old).revision != input.revision) fail('conflict');
backup('/etc/config/openclash','uci-openclash');
if (!c.delete('openclash',input.id) || !c.commit('openclash')) fail('storage');
printf('%J',{ok:true});
''',
      {'id': original.id, 'revision': original.revision},
    );
  }

  Future<String> updateSubscription(OpenClashSubscription subscription) async {
    if (!validSection(subscription.id) || !validName(subscription.name)) {
      throw const OpenClashException('request');
    }
    final resources = await service.resources();
    if (resources.availableKiB != null && resources.availableKiB! < 16384) {
      throw const OpenClashException('lowMemory');
    }
    await _call(
      r'''
let old = c.get_all('openclash',input.id);
if (!old || old['.type'] != 'config_subscribe' || subscription(old).revision != input.revision) fail('conflict');
printf('%J',{ok:true});
''',
      {'id': subscription.id, 'revision': subscription.revision},
    );
    return service.startManagedTask(
      'GOGC=50 GOMEMLIMIT=24MiB /usr/share/openclash/openclash.sh ${OpenClashService.shellQuote(subscription.name)} norestart',
    );
  }

  Future<OpenClashConfigDocument> readConfig(String name) async {
    if (!validFile(name)) throw const OpenClashException('request');
    final result = await _call(
      r'''
let path = file(input.name);
if (fs.lstat(path).size > 65536) fail('size');
let content = fs.readfile(path,65537);
if (content == null || length(content) > 65536) fail('size');
printf('%J',{content:content, revision:sha256(content)});
''',
      {'name': name},
    );
    return OpenClashConfigDocument(
      result['content'] as String,
      result['revision'] as String,
    );
  }

  Future<void> saveConfig(
    String name,
    String content, {
    String? revision,
  }) async {
    if (!validFile(name)) throw const OpenClashException('request');
    validateYaml(content);
    await _call(
      r'''
let path = base + '/' + input.name;
input.content = b64dec(input.content64);
let info = fs.lstat(path);
if (input.revision) {
  file(input.name);
  if (info.size > 65536 || sha256(fs.readfile(path,65537)) != input.revision) fail('conflict');
  backup(path,input.name);
} else if (info) fail('duplicate');
let temporary = base + '/.yala-' + input.nonce;
if (fs.lstat(temporary)) fail('conflict');
if (fs.writefile(temporary,input.content) != length(input.content) || !fs.chmod(temporary,0o600)) { fs.unlink(temporary); fail('storage'); }
if (!fs.rename(temporary,path)) { fs.unlink(temporary); fail('storage'); }
printf('%J',{ok:true});
''',
      {
        'name': name,
        'content64': base64Encode(utf8.encode(content)),
        'revision': revision,
        'nonce': DateTime.now().microsecondsSinceEpoch.toString(),
      },
    );
  }

  Future<void> deleteConfig(String name) async {
    if (!validFile(name)) throw const OpenClashException('request');
    await _call(
      r'''
let path = file(input.name);
if (c.get('openclash','config','config_path') == path) fail('active');
backup(path,input.name);
if (!fs.unlink(path)) fail('storage');
printf('%J',{ok:true});
''',
      {'name': name},
    );
  }

  Future<String> activateConfig(String name) async {
    if (!validFile(name)) throw const OpenClashException('request');
    await _call(
      r'''
let path = file(input.name);
backup('/etc/config/openclash','uci-openclash');
if (!c.set('openclash','config','config_path',path) || !c.set('openclash','config','enable','1') || !c.commit('openclash')) fail('storage');
printf('%J',{ok:true});
''',
      {'name': name},
    );
    return service.serviceAction('restart');
  }
}
