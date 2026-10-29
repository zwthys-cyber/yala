// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../../../design/luci_design_system.dart';
import '../../../widgets/luci_app_bar.dart';
import '../../../widgets/luci_collapsible_card.dart';
import '../models/router_resources.dart';
import '../services/openclash_service.dart';

class OpenClashDiagnosticsScreen extends StatefulWidget {
  final OpenClashService service;
  const OpenClashDiagnosticsScreen({super.key, required this.service});

  @override
  State<OpenClashDiagnosticsScreen> createState() =>
      _OpenClashDiagnosticsScreenState();
}

class _OpenClashDiagnosticsScreenState
    extends State<OpenClashDiagnosticsScreen> {
  RouterResources? _resources;
  String? _logs;
  String? _error;
  bool _busy = false;
  bool _system = false;

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';
  String _text(String zh, String en) => _zh ? zh : en;
  String _mib(num kib) => '${(kib / 1024).toStringAsFixed(1)} MiB';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _readResources());
  }

  Future<void> _readResources() => _read(() async {
    final resources = await widget.service.resources();
    if (mounted) setState(() => _resources = resources);
  });

  Future<void> _readLogs() => _read(() async {
    final logs = await widget.service.logs(system: _system);
    if (mounted) setState(() => _logs = logs);
  });

  Future<void> _read(Future<void> Function() action) async {
    if (!mounted || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() {
          _resources = null;
          _logs = null;
          _error = _text(
            '读取失败，请确认仍连接同一路由器，然后重试。',
            'Read failed. Check the selected router connection and retry.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: LuciSpacing.sm),
    child: Wrap(
      spacing: LuciSpacing.md,
      runSpacing: LuciSpacing.xs,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Text(label, style: LuciTextStyles.detailLabel(context)),
        Text(value, style: LuciTextStyles.detailValue(context)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final resources = _resources;
    final available = resources?.availableKiB;
    return Scaffold(
      appBar: LuciAppBar(
        title: _text('运行诊断', 'Diagnostics'),
        showBack: true,
        actions: [
          IconButton(
            tooltip: _text('刷新资源状态', 'Refresh resources'),
            onPressed: _busy ? null : _readResources,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(LuciSpacing.md),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(LuciSpacing.md),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          LuciCollapsibleCard(
            title: _text('路由器资源', 'Router resources'),
            icon: Icons.memory,
            initiallyExpanded: true,
            child: resources == null
                ? Text(_text('暂无资源数据', 'No resource data'))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _row(
                        _text('物理内存总量', 'Physical memory'),
                        _mib(resources.totalKiB),
                      ),
                      _row(
                        _text('可用内存', 'Available memory'),
                        available == null ? '—' : _mib(available),
                      ),
                      if (available != null)
                        LinearProgressIndicator(
                          value: (available / resources.totalKiB).clamp(
                            0.0,
                            1.0,
                          ),
                          semanticsLabel: _text(
                            '可用内存比例',
                            'Available memory ratio',
                          ),
                          color: available < 8192
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                      if (available != null && available < 8192)
                        Padding(
                          padding: const EdgeInsets.only(top: LuciSpacing.sm),
                          child: Text(
                            _text(
                              '可用内存低于 8 MiB，请暂停测速并检查后台任务。',
                              'Available memory is below 8 MiB. Pause speed tests and check background tasks.',
                            ),
                          ),
                        ),
                      _row(
                        _text('交换空间总量', 'Swap capacity'),
                        _mib(resources.swapTotalKiB),
                      ),
                      _row(
                        _text('已用交换空间', 'Swap used'),
                        _mib(
                          (resources.swapTotalKiB - resources.swapFreeKiB)
                              .clamp(0, resources.swapTotalKiB),
                        ),
                      ),
                      if (resources.zramPhysicalBytes != null)
                        _row(
                          _text('zram 实际内存占用', 'zram physical memory'),
                          '${(resources.zramPhysicalBytes! / 1048576).toStringAsFixed(1)} MiB',
                        ),
                      _row(
                        _text('系统负载（1 / 5 / 15 分钟）', 'Load (1 / 5 / 15 min)'),
                        resources.load.isEmpty ? '—' : resources.load,
                      ),
                      Text(
                        _text(
                          '交换空间不等于新增物理内存。状态仅在打开页面或手动刷新时读取。',
                          'Swap is not additional physical RAM. Status updates only when this page opens or you refresh.',
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: LuciSpacing.sm),
          LuciCollapsibleCard(
            title: _text('诊断日志', 'Diagnostic logs'),
            icon: Icons.article_outlined,
            initiallyExpanded: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: LuciSpacing.sm,
                  children: [
                    for (final system in [false, true])
                      ChoiceChip(
                        label: Text(
                          system
                              ? _text('系统与无线', 'System & Wi-Fi')
                              : 'OpenClash',
                        ),
                        selected: _system == system,
                        onSelected: _busy
                            ? null
                            : (selected) {
                                if (selected) {
                                  setState(() {
                                    _system = system;
                                    _logs = null;
                                  });
                                }
                              },
                      ),
                  ],
                ),
                const SizedBox(height: LuciSpacing.sm),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _readLogs,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(_text('读取最近日志', 'Read recent logs')),
                ),
                const SizedBox(height: LuciSpacing.sm),
                SelectableText(
                  _logs == null
                      ? _text(
                          '点击读取，不在后台持续收集。',
                          'Tap to read. No background collection.',
                        )
                      : _logs!.trim().isEmpty
                      ? _text('暂无匹配日志', 'No matching log entries')
                      : _logs!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
