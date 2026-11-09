import 'dart:async';

import 'package:flutter/material.dart';

import '../models/task_model.dart';
import '../services/api_service.dart';

class ServerInfoSheet extends StatefulWidget {
  const ServerInfoSheet({super.key, required this.api});
  final ApiService api;

  @override
  State<ServerInfoSheet> createState() => _ServerInfoSheetState();
}

class _ServerInfoSheetState extends State<ServerInfoSheet> {
  ServerStatus? status;
  int? ping;
  String? error;
  bool loading = false;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    refresh();
    timer = Timer.periodic(const Duration(seconds: 10), (_) => refresh());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    if (loading) return;
    setState(() => loading = true);
    final watch = Stopwatch()..start();
    try {
      final result = await widget.api.getServerStatus();
      watch.stop();
      if (!mounted) return;
      setState(() { status = result; ping = watch.elapsedMilliseconds; error = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() { status = null; error = e.toString().replaceFirst('Exception: ', ''); });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = status;
    String bytes(int? n) => n == null ? 'Unavailable' : TaskModel.formatBytes(n);
    final uptime = s?.uptime;
    final duration = uptime == null || uptime < 0 || uptime > 315360000 ? 'Unavailable' : TaskModel.formatDurationSeconds(uptime.toInt());
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Text('Server Info', style: Theme.of(context).textTheme.titleLarge), const Spacer(), IconButton(tooltip: 'Refresh', onPressed: loading ? null : refresh, icon: const Icon(Icons.refresh))]),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (s != null) ...[
            _row('Status', s.serverOnline ? 'Online' : 'Offline'),
            _row('Ping (round trip)', '${ping ?? 0} ms'),
            _row('Storage free / used', '${bytes(s.storageFree)} / ${bytes(s.storageUsed)}'),
            _row('RAM free / used', '${bytes(s.ramFree ?? (s.ramTotal != null && s.ramUsed != null ? s.ramTotal! - s.ramUsed! : null))} / ${bytes(s.ramUsed)}'),
            _row('Active / completed tasks', '${s.activeTasks ?? '—'} / ${s.completedTasks ?? '—'}'),
            _row('Total tasks', '${s.totalTasks ?? '—'}'),
            _row('CPU cores / load', '${s.cpuCores ?? '—'} / ${s.loadAvg ?? '—'}'),
            _row('Uptime', duration),
          ],
        ]),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [Expanded(child: Text(label)), Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)))]),
  );
}
