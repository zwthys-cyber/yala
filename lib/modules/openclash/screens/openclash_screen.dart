// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../main.dart';
import '../../../services/ssh_service.dart';
import '../../../widgets/luci_app_bar.dart';
import '../services/openclash_service.dart';
import '../services/openclash_ssh_transport.dart';
import 'openclash_diagnostics_screen.dart';

class OpenClashScreen extends ConsumerStatefulWidget {
  const OpenClashScreen({super.key});
  @override
  ConsumerState<OpenClashScreen> createState() => _OpenClashScreenState();
}

class _OpenClashScreenState extends ConsumerState<OpenClashScreen> {
  late final String? _routerId;
  late final OpenClashService _service;
  OpenClashStatus? _status;
  List<OpenClashGroup> _groups = [];
  String? _version;
  String? _mode;
  String? _error;
  bool _busy = true;

  bool get _sameRouter =>
      mounted && ref.read(appStateProvider).selectedRouter?.id == _routerId;
  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';
  String _text(String zh, String en) => _zh ? zh : en;

  @override
  void initState() {
    super.initState();
    _routerId = ref.read(appStateProvider).selectedRouter?.id;
    _service = OpenClashService(
      (command, args) async {
        if (!_sameRouter || _routerId == null) {
          throw const OpenClashException('router');
        }
        return ref.read(appStateProvider).callRpc('file', 'exec', {
          'command': command,
          'params': args,
          'args': args,
        });
      },
      fallbackExecute: (command, args) async {
        if (!_sameRouter || _routerId == null) {
          throw const OpenClashException('router');
        }
        final router = ref.read(appStateProvider).selectedRouter;
        if (router == null) {
          throw const OpenClashException('router');
        }
        return OpenClashSshTransport(
          router: router,
          ssh: RealSshService(),
          isCurrent: () => mounted && _sameRouter,
        ).execute(command, args);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  String _message(Object error) {
    final reason = error is OpenClashException ? error.reason : '';
    return switch (reason) {
      'permission' => _text(
        '路由器未授予命令执行权限，请检查 RPC 权限。',
        'Router command permission denied. Check RPC permissions.',
      ),
      'ssh' => _text(
        'RPC 命令权限受限，SSH 连接也未成功。请确认路由器 SSH（22 端口）已启用，并在 App 中重新保存正确的登录账户和密码。',
        'RPC commands are restricted and SSH could not connect. Enable router SSH on port 22 and check the saved router credentials.',
      ),
      'service' => _text(
        'OpenClash 服务命令执行失败，请查看路由器上的 OpenClash 日志。',
        'The OpenClash service command failed. Check its router logs.',
      ),
      'auth' => _text(
        '控制接口认证失败，请检查 OpenClash 控制密钥。',
        'Controller authentication failed. Check the OpenClash secret.',
      ),
      'router' => _text(
        '路由器已切换，请返回后重新打开。',
        'Router changed. Go back and reopen this page.',
      ),
      'timeout' => _text(
        '操作尚未完成，请稍后刷新确认。',
        'Operation is still pending. Refresh to check its status.',
      ),
      _ => _text(
        '无法读取 OpenClash 控制接口，请确认服务已启动、curl 已安装且 RPC 权限可用。',
        'Cannot reach OpenClash. Check its service, curl installation and RPC permissions.',
      ),
    };
  }

  Future<void> _load() async {
    _status = null;
    _groups = [];
    _version = null;
    _mode = null;
    final snapshot = await _service.loadSnapshot();
    if (!mounted || !_sameRouter) return;
    _status = snapshot.status;
    _groups = snapshot.groups;
    _version = snapshot.version;
    _mode = snapshot.mode;
    if (snapshot.controllerError != null) {
      throw OpenClashException(snapshot.controllerError!);
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _load();
    } catch (error) {
      if (mounted) _error = _message(error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _change(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) _error = _message(error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _action(String action) async {
    final label = switch (action) {
      'start' => _text('启动', 'Start'),
      'stop' => _text('停止', 'Stop'),
      _ => _text('重启', 'Restart'),
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$label OpenClash?'),
        content: Text(
          _text(
            '此操作可能暂时中断代理和网络访问。',
            'This may temporarily interrupt proxy and internet access.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_text('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_sameRouter) return;
    await _change(() async {
      final operation = await _service.serviceAction(action);
      var completed = false;
      // Startup may rebuild firewall/DNS. Keep controls disabled until verified.
      for (var attempt = 0; attempt < 30; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted || !_sameRouter) throw const OpenClashException('router');
        completed = completed || await _service.actionComplete(operation);
        if (!completed) continue;
        final status = await _service.status();
        if (action == 'stop' && !status.running) return;
        if (action != 'stop' && status.running) {
          try {
            await _service.request('GET', '/version');
            return;
          } on OpenClashException {
            /* Still starting. */
          }
        }
      }
      throw const OpenClashException('timeout');
    });
  }

  Future<void> _choose(OpenClashGroup group) async {
    final selection = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  group.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: group.choices.length,
                  itemBuilder: (context, index) {
                    final node = group.choices[index];
                    return ListTile(
                      title: Text(node),
                      trailing: node == group.selected
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.pop(context, node),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selection == null || !mounted || !_sameRouter) return;
    await _change(() => _service.select(group, selection));
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(
      appStateProvider.select((state) => state.selectedRouter),
    );
    final changed = router?.id != _routerId;
    final running = _status?.running == true;
    return Scaffold(
      appBar: LuciAppBar(
        title: 'OpenClash',
        showBack: true,
        actions: [
          IconButton(
            tooltip: _text('刷新', 'Refresh'),
            onPressed: _busy || changed ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: changed
          ? Center(child: Text(_message(const OpenClashException('router'))))
          : RefreshIndicator(
              onRefresh: () async {
                if (!_busy) await _refresh();
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (_busy) const LinearProgressIndicator(),
                  Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.monitor_heart_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(
                        _text('资源与诊断日志', 'Resources and diagnostic logs'),
                      ),
                      subtitle: Text(
                        _text('内存、交换空间与最近日志', 'Memory, swap and recent logs'),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _busy
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => OpenClashDiagnosticsScreen(
                                  service: _service,
                                ),
                              ),
                            ),
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _status == null
                                ? (_busy
                                      ? _text('正在读取状态…', 'Loading status…')
                                      : _text('状态不可用', 'Status unavailable'))
                                : !_status!.installed
                                ? _text(
                                    '未安装 OpenClash',
                                    'OpenClash is not installed',
                                  )
                                : running
                                ? _text('运行中', 'Running')
                                : _text('已停止', 'Stopped'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (_version != null) Text('Mihomo $_version'),
                          if (_service.usingSshFallback)
                            Text(_text('连接方式：SSH', 'Connection: SSH')),
                          if (_status?.installed == true)
                            Wrap(
                              spacing: 8,
                              children: [
                                FilledButton(
                                  onPressed: _busy
                                      ? null
                                      : () =>
                                            _action(running ? 'stop' : 'start'),
                                  child: Text(
                                    running
                                        ? _text('停止', 'Stop')
                                        : _text('启动', 'Start'),
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: _busy || !running
                                      ? null
                                      : () => _action('restart'),
                                  child: Text(_text('重启服务', 'Restart service')),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  if (running && _mode != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _text('代理模式', 'Proxy mode'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final mode in ['rule', 'global', 'direct'])
                                  ChoiceChip(
                                    label: Text(switch (mode) {
                                      'rule' => _text('规则', 'Rule'),
                                      'global' => _text('全局', 'Global'),
                                      _ => _text('直连', 'Direct'),
                                    }),
                                    selected: _mode == mode,
                                    onSelected: _busy
                                        ? null
                                        : (selected) {
                                            if (selected) {
                                              _change(
                                                () => _service.setMode(mode),
                                              );
                                            }
                                          },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_groups.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        _text('代理组与节点', 'Proxy groups and nodes'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  for (final group in _groups)
                    Card(
                      child: ListTile(
                        title: Text(group.name),
                        subtitle: Text(
                          '${group.selected ?? "—"}\n${group.type}',
                        ),
                        isThreeLine: true,
                        trailing: group.canSelect
                            ? const Icon(Icons.chevron_right)
                            : const Icon(Icons.auto_mode),
                        onTap: _busy || !group.canSelect
                            ? null
                            : () => _choose(group),
                      ),
                    ),
                  if (_groups.any((group) => !group.canSelect))
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        _text(
                          '自动测速和故障转移组由内核自动选择节点。',
                          'URL-test and fallback groups select nodes automatically.',
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
