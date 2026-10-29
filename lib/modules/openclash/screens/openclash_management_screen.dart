// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../design/luci_design_system.dart';
import '../../../widgets/luci_app_bar.dart';
import '../../../widgets/luci_collapsible_card.dart';
import '../services/openclash_management_service.dart';
import '../services/openclash_service.dart';

class OpenClashManagementScreen extends StatefulWidget {
  final OpenClashService service;
  const OpenClashManagementScreen({super.key, required this.service});
  @override
  State<OpenClashManagementScreen> createState() =>
      _OpenClashManagementScreenState();
}

class _OpenClashManagementScreenState extends State<OpenClashManagementScreen> {
  late final OpenClashManagementService _management;
  OpenClashInventory? _inventory;
  String? _error;
  String? _notice;
  bool _busy = false;
  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';
  String _text(String zh, String en) => _zh ? zh : en;

  @override
  void initState() {
    super.initState();
    _management = OpenClashManagementService(widget.service);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  String _message(Object error) => switch (error is OpenClashException
      ? error.reason
      : '') {
    'yaml' => _text(
      'YAML 语法无效，或顶层不是配置映射。文件未保存。',
      'Invalid YAML or non-mapping document. File was not saved.',
    ),
    'size' => _text(
      '编辑器支持最大 64 KiB 的配置。较大文件仍可在列表中切换。',
      'The editor supports configs up to 64 KiB. Larger files can still be selected.',
    ),
    'conflict' => _text(
      '内容已被其他操作修改，请刷新后重新编辑。',
      'Changed by another operation. Refresh before editing again.',
    ),
    'duplicate' => _text(
      '名称已存在，请使用其他名称。',
      'Name already exists. Choose another name.',
    ),
    'active' => _text(
      '不能删除当前选中的配置，请先切换。',
      'Select another configuration before deleting this one.',
    ),
    'subscriptionUrl' => _text(
      '请输入一个完整的 HTTP/HTTPS YAML 订阅地址。',
      'Enter a complete HTTP/HTTPS YAML subscription URL.',
    ),
    'timeout' => _text(
      '后台任务尚未确认完成，请稍后刷新并查看日志，避免重复提交。',
      'Background task completion is unconfirmed. Refresh and check logs before retrying.',
    ),
    'request' => _text(
      '名称或输入格式无效，请检查。',
      'Invalid name or input. Check the form.',
    ),
    'storage' => _text(
      '保存失败，请检查路由器剩余存储空间。',
      'Save failed. Check router storage space.',
    ),
    'lowMemory' => _text(
      '当前可用内存低于 16 MiB，请暂停视频或测速后再更新订阅。',
      'Available memory is below 16 MiB. Pause streaming or speed tests before updating.',
    ),
    _ => _text(
      '操作未完成，请检查连接和诊断日志。',
      'Operation did not complete. Check the connection and diagnostic logs.',
    ),
  };

  Future<void> _run(Future<void> Function() action, {String? notice}) async {
    if (!mounted || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      final inventory = await _management.inventory();
      if (mounted) {
        setState(() {
          _inventory = inventory;
          _notice = notice;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _message(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() => _run(() async {});

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_text('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_text('确认', 'Confirm')),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _editSubscription([OpenClashSubscription? original]) async {
    final name = TextEditingController(text: original?.name ?? '');
    final address = TextEditingController(text: original?.address ?? '');
    final ua = TextEditingController(
      text: original?.userAgent ?? 'clash-verge/v2.4.5',
    );
    var enabled = original?.enabled ?? true;
    var hidden = true;
    final form = GlobalKey<FormState>();
    DialogRoute<bool>? dialogRoute;
    try {
      dialogRoute = DialogRoute<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(
              _text(
                original == null ? '新增订阅' : '编辑订阅',
                original == null ? 'Add subscription' : 'Edit subscription',
              ),
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: name,
                        maxLength: 64,
                        decoration: InputDecoration(
                          labelText: _text('配置名称', 'Configuration name'),
                        ),
                        validator: (value) =>
                            OpenClashManagementService.validName(value ?? '')
                            ? null
                            : _text(
                                '名称不能包含路径或控制字符',
                                'Use a name without path or control characters',
                              ),
                      ),
                      TextFormField(
                        controller: address,
                        obscureText: hidden,
                        maxLines: hidden ? 1 : 4,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: _text('订阅地址', 'Subscription URL'),
                          suffixIcon: IconButton(
                            tooltip: _text('显示或隐藏地址', 'Show or hide URL'),
                            onPressed: () => update(() => hidden = !hidden),
                            icon: Icon(
                              hidden
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) {
                          try {
                            OpenClashManagementService.validateSubscription(
                              name.text,
                              value?.trim() ?? '',
                              ua.text.trim(),
                              converted: original?.converted == true,
                            );
                            return null;
                          } catch (error) {
                            return _message(error);
                          }
                        },
                      ),
                      TextFormField(
                        controller: ua,
                        maxLength: 256,
                        decoration: const InputDecoration(
                          labelText: 'User-Agent',
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_text('启用订阅', 'Enable subscription')),
                        value: enabled,
                        onChanged: (value) => update(() => enabled = value),
                      ),
                      Text(
                        _text(
                          '保存不自动下载或重启。新订阅使用 YAML 地址；已有转换、过滤等高级设置保持原值。',
                          'Saving does not download or restart. New subscriptions use YAML URLs; existing conversion and filtering options are preserved.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(_text('取消', 'Cancel')),
              ),
              FilledButton(
                onPressed: () {
                  if (form.currentState!.validate()) {
                    Navigator.pop(context, true);
                  }
                },
                child: Text(_text('保存', 'Save')),
              ),
            ],
          ),
        ),
      );
      final accepted = await Navigator.of(context).push(dialogRoute);
      if (accepted == true && mounted) {
        await _run(
          () => _management.saveSubscription(
            original: original,
            name: name.text,
            address: address.text.trim(),
            userAgent: ua.text.trim(),
            enabled: enabled,
          ),
          notice: _text('订阅已保存', 'Subscription saved'),
        );
      }
    } finally {
      await dialogRoute?.completed;
      name.dispose();
      address.dispose();
      ua.dispose();
    }
  }

  Future<void> _wait(String operation, {bool running = false}) async {
    var complete = false;
    for (var attempt = 0; attempt < 90; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) throw const OpenClashException('router');
      complete = complete || await widget.service.actionComplete(operation);
      if (!complete) continue;
      if (!running) return;
      final snapshot = await widget.service.loadSnapshot();
      if (snapshot.status.running && snapshot.controllerError == null) return;
    }
    throw const OpenClashException('timeout');
  }

  Future<void> _updateSubscription(OpenClashSubscription item) async {
    if (!await _confirm(
          _text('更新订阅？', 'Update subscription?'),
          _text(
            '下载并更新配置文件，不自动重启代理。更新后如需应用，请切换配置或重启服务。',
            'Download and update the configuration without restarting the proxy. Select the configuration or restart the service to apply it.',
          ),
        ) ||
        !mounted) {
      return;
    }
    await _run(
      () async => _wait(await _management.updateSubscription(item)),
      notice: _text(
        '订阅更新完成，尚未重启代理',
        'Subscription updated; proxy was not restarted',
      ),
    );
  }

  Future<void> _editConfig([OpenClashConfigFile? item]) async {
    OpenClashConfigDocument? document;
    if (item != null) {
      await _run(() async {
        document = await _management.readConfig(item.name);
      });
      if (document == null || !mounted) return;
    }
    final result = await Navigator.of(context)
        .push<({String name, String content})>(
          MaterialPageRoute(
            builder: (_) => _ConfigEditor(
              initialName: item?.name,
              initialContent:
                  document?.content ??
                  'proxies: []\nproxy-groups: []\nrules: []\n',
            ),
          ),
        );
    if (result == null || !mounted) return;
    await _run(
      () => _management.saveConfig(
        result.name,
        result.content,
        revision: document?.revision,
      ),
      notice: _text(
        '配置已保存，尚未重启代理',
        'Configuration saved; proxy was not restarted',
      ),
    );
  }

  Future<void> _activate(OpenClashConfigFile item) async {
    if (!await _confirm(
          _text('切换并重启代理？', 'Select and restart proxy?'),
          _text(
            '使用 ${item.name} 并重启 OpenClash，网络可能短暂中断。若启动失败，可重新选择之前的配置。',
            'Use ${item.name} and restart OpenClash. Connectivity may pause. If startup fails, select the previous configuration again.',
          ),
        ) ||
        !mounted) {
      return;
    }
    await _run(
      () async =>
          _wait(await _management.activateConfig(item.name), running: true),
      notice: _text(
        '配置已切换，控制接口已就绪',
        'Configuration selected; controller is ready',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventory = _inventory;
    return Scaffold(
      appBar: LuciAppBar(
        title: _text('订阅与配置', 'Subscriptions & configs'),
        showBack: true,
        actions: [
          IconButton(
            tooltip: _text('刷新', 'Refresh'),
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(LuciSpacing.md),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null || _notice != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(LuciSpacing.md),
                child: Text(
                  _error ?? _notice!,
                  style: TextStyle(
                    color: _error == null
                        ? null
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ),
          LuciCollapsibleCard(
            title: _text('订阅管理', 'Subscriptions'),
            icon: Icons.rss_feed,
            initiallyExpanded: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _editSubscription(),
                  icon: const Icon(Icons.add),
                  label: Text(_text('新增订阅', 'Add subscription')),
                ),
                if (inventory != null && inventory.subscriptions.isEmpty)
                  Text(_text('暂无订阅', 'No subscriptions')),
                for (final item
                    in inventory?.subscriptions ?? <OpenClashSubscription>[])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      item.enabled
                          ? Icons.rss_feed
                          : Icons.pause_circle_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(item.name),
                    subtitle: Text(
                      '${item.enabled ? _text('已启用', 'Enabled') : _text('已停用', 'Disabled')} · ${Uri.tryParse(item.address)?.host.isNotEmpty == true ? Uri.parse(item.address).host : _text('地址已保存', 'URL saved')}',
                    ),
                    onTap: _busy ? null : () => _editSubscription(item),
                    trailing: PopupMenuButton<String>(
                      enabled: !_busy,
                      onSelected: (action) async {
                        if (action == 'edit') await _editSubscription(item);
                        if (action == 'update') await _updateSubscription(item);
                        if (action == 'delete' &&
                            await _confirm(
                              _text('删除订阅？', 'Delete subscription?'),
                              _text(
                                '删除 ${item.name} 的订阅记录，保留已下载的配置文件。',
                                'Remove the subscription ${item.name}; keep its downloaded configuration.',
                              ),
                            ) &&
                            mounted) {
                          await _run(
                            () => _management.deleteSubscription(item),
                          );
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(_text('编辑', 'Edit')),
                        ),
                        PopupMenuItem(
                          value: 'update',
                          child: Text(_text('立即更新', 'Update now')),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(_text('删除', 'Delete')),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: LuciSpacing.sm),
          LuciCollapsibleCard(
            title: _text('配置文件', 'Configuration files'),
            icon: Icons.description_outlined,
            initiallyExpanded: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _editConfig(),
                  icon: const Icon(Icons.note_add_outlined),
                  label: Text(
                    _text('新增或导入配置', 'Create or import configuration'),
                  ),
                ),
                if (inventory != null && inventory.files.isEmpty)
                  Text(_text('暂无配置文件', 'No configuration files')),
                for (final file in inventory?.files ?? <OpenClashConfigFile>[])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      file.name == inventory?.active
                          ? Icons.check_circle
                          : Icons.description_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(file.name),
                    subtitle: Text(
                      '${(file.bytes / 1024).toStringAsFixed(1)} KiB${file.name == inventory?.active ? ' · ${_text('当前选中', 'Selected')}' : ''}',
                    ),
                    onTap: _busy ? null : () => _editConfig(file),
                    trailing: PopupMenuButton<String>(
                      enabled: !_busy,
                      onSelected: (action) async {
                        if (action == 'edit') await _editConfig(file);
                        if (action == 'activate') await _activate(file);
                        if (action == 'delete' &&
                            await _confirm(
                              _text('删除配置？', 'Delete configuration?'),
                              _text(
                                '删除前保留一份路由器本地备份。确认删除 ${file.name}？',
                                'A backup remains on the router. Delete ${file.name}?',
                              ),
                            ) &&
                            mounted) {
                          await _run(() => _management.deleteConfig(file.name));
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          enabled:
                              file.bytes <=
                              OpenClashManagementService.maxConfigBytes,
                          child: Text(_text('编辑', 'Edit')),
                        ),
                        PopupMenuItem(
                          value: 'activate',
                          child: Text(_text('切换并重启', 'Select and restart')),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          enabled: file.name != inventory?.active,
                          child: Text(_text('删除', 'Delete')),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigEditor extends StatefulWidget {
  final String? initialName;
  final String initialContent;
  const _ConfigEditor({this.initialName, required this.initialContent});
  @override
  State<_ConfigEditor> createState() => _ConfigEditorState();
}

class _ConfigEditorState extends State<_ConfigEditor> {
  late final TextEditingController _name;
  late final TextEditingController _content;
  String? _error;
  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';
  String _text(String zh, String en) => _zh ? zh : en;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName ?? 'config.yaml');
    _content = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    super.dispose();
  }

  void _save() {
    try {
      if (!OpenClashManagementService.validFile(_name.text)) {
        throw const OpenClashException('request');
      }
      OpenClashManagementService.validateYaml(_content.text);
      Navigator.pop(context, (name: _name.text, content: _content.text));
    } catch (_) {
      setState(
        () => _error = _text(
          '请检查文件名、YAML 语法和大小（最大 64 KiB）。',
          'Check the filename, YAML syntax and size (maximum 64 KiB).',
        ),
      );
    }
  }

  Future<void> _import() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['yaml', 'yml'],
        withData: true,
      );
      if (result == null || !mounted) return;
      final file = result.files.single;
      if (file.size > OpenClashManagementService.maxConfigBytes ||
          file.bytes == null) {
        throw const FormatException();
      }
      final content = utf8.decode(file.bytes!);
      OpenClashManagementService.validateYaml(content);
      setState(() {
        if (widget.initialName == null) _name.text = file.name;
        _content.text = content;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _text(
            '导入失败，请使用不超过 64 KiB 的 UTF-8 YAML 文件。',
            'Import failed. Use a UTF-8 YAML file no larger than 64 KiB.',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: LuciAppBar(
      title: _text('配置编辑', 'Configuration editor'),
      showBack: true,
      actions: [
        IconButton(
          tooltip: _text('导入文件', 'Import file'),
          onPressed: _import,
          icon: const Icon(Icons.file_open_outlined),
        ),
        IconButton(
          tooltip: _text('保存', 'Save'),
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
        ),
      ],
    ),
    body: Padding(
      padding: const EdgeInsets.all(LuciSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            readOnly: widget.initialName != null,
            decoration: InputDecoration(labelText: _text('文件名', 'Filename')),
          ),
          const SizedBox(height: LuciSpacing.sm),
          Text(
            _text(
              '只检查 YAML 语法；内核兼容性在启动时确认。保存不自动重启。',
              'Checks YAML syntax; core compatibility is confirmed at startup. Saving does not restart.',
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: LuciSpacing.sm),
          Expanded(
            child: TextField(
              controller: _content,
              expands: true,
              maxLines: null,
              minLines: null,
              autocorrect: false,
              enableSuggestions: false,
              textAlignVertical: TextAlignVertical.top,
              style: Theme.of(context).textTheme.bodySmall,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
                labelText: 'YAML',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
