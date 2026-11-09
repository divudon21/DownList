import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'widgets/server_info_sheet.dart';

import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/task_screen.dart';
import 'screens/upload_screen.dart';
import 'services/api_service.dart';
import 'services/settings_service.dart';
import 'services/upload_manager.dart';
import 'services/platform_service.dart';
import 'services/update_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AiAgentApp());
}

class AiAgentApp extends StatefulWidget {
  const AiAgentApp({super.key});

  @override
  State<AiAgentApp> createState() => _AiAgentAppState();
}

class _AiAgentAppState extends State<AiAgentApp> {
  late final SettingsService _settings;
  late final ApiService _api;
  late final UploadManager _uploadManager;
  late final UpdateService _updates;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _settings = SettingsService();
    _api = ApiService();
    _uploadManager = UploadManager(api: _api);
    _updates = UpdateService();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final savedUrl = await _settings.getServerUrl();
    if (!mounted) return;
    _api.baseUrl = savedUrl;
    await _api.restoreMonitoredTasks();
    await _updates.initialize();
    if (!mounted) return;
    setState(() {
      _ready = true;
    });
    if (!await _settings.notificationPermissionAsked()) {
      await _settings.markNotificationPermissionAsked();
      try { await PlatformService.instance.requestNotificationPermission(); } catch (_) {}
    }
  }

  @override
  void dispose() {
    _uploadManager.dispose();
    _updates.dispose();
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DownList',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F46E5),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
      ),
      home: _ready
          ? HomePage(
              settings: _settings,
              api: _api,
              uploadManager: _uploadManager,
              updates: _updates,
            )
          : const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.settings,
    required this.api,
    required this.uploadManager,
    required this.updates,
  });

  final SettingsService settings;
  final ApiService api;
  final UploadManager uploadManager;
  final UpdateService updates;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool _autoChecking = false;
  bool _updateDialogOpen = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdatesOnOpen());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _pausedAt = DateTime.now();
    if (state == AppLifecycleState.resumed && _pausedAt != null) {
      final duration = DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      if (duration >= const Duration(seconds: 10)) _checkUpdatesOnOpen();
    }
  }

  Future<void> _checkUpdatesOnOpen() async {
    if (!mounted || !widget.updates.ready || !widget.updates.autoCheck || _autoChecking) return;
    _autoChecking = true;
    try {
      final release = await widget.updates.check();
      if (!mounted || release == null) return;
      await widget.updates.notifyIfNeeded(release);
      if (!mounted || !widget.updates.popup || _updateDialogOpen || !widget.updates.autoCheck) return;
      final build = widget.updates.installed;
      final compatible = build != null && release.isCompatibleWith(build);
      _updateDialogOpen = true;
      final open = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Update available'),
        content: Text('${release.label} is available.${compatible ? '' : '\n\nThis release has a different signing key. Android may require uninstalling the current app first, which removes local settings.'}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Update')),
        ],
      ));
      _updateDialogOpen = false;
      if (open == true && mounted) {
        try { await widget.updates.openRelease(release); }
        catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the release page.'))); }
      }
    } finally { _autoChecking = false; }
  }

  void _selectTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
    if (index == 2) {
      widget.api.notifyHistoryChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.api, widget.uploadManager]),
      builder: (context, _) {
        final totalActiveCount = widget.uploadManager.activeItems.length +
            widget.api.activeServerTaskCount;

        final pages = <Widget>[
          HomeScreen(
            api: widget.api,
            onViewTasks: () => _selectTab(1),
            onOpenSettings: () => _selectTab(4),
          ),
          TaskScreen(
            api: widget.api,
            uploadManager: widget.uploadManager,
            onGoHome: () => _selectTab(0),
            onOpenSettings: () => _selectTab(4),
          ),
          HistoryScreen(
            api: widget.api,
            onOpenSettings: () => _selectTab(4),
          ),
          UploadScreen(
            api: widget.api,
            uploadManager: widget.uploadManager,
            onOpenSettings: () => _selectTab(4),
          ),
          SettingsScreen(
            settings: widget.settings,
            api: widget.api,
            updates: widget.updates,
          ),
        ];

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: _selectedIndex == 4
                ? const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.3))
                : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/images/downlist_logo.png',
                    width: 30,
                    height: 30,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'DownList',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            centerTitle: false,
            actions: _selectedIndex == 0 ? [
              IconButton(
                tooltip: 'Server Info',
                onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => ServerInfoSheet(api: widget.api)),
                icon: const Icon(Icons.info_outline_rounded),
              ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.8, 0.8)),
            ] : null,
          ),
          body: SafeArea(
            child: IndexedStack(
              index: _selectedIndex,
              children: pages,
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _selectTab,
            animationDuration: const Duration(milliseconds: 300),
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Badge.count(
                  count: totalActiveCount,
                  isLabelVisible: totalActiveCount > 0,
                  child: const Icon(Icons.file_download_outlined),
                ),
                selectedIcon: Badge.count(
                  count: totalActiveCount,
                  isLabelVisible: totalActiveCount > 0,
                  child: const Icon(Icons.file_download),
                ),
                label: 'Task',
              ),
              const NavigationDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history),
                label: 'History',
              ),
              const NavigationDestination(
                icon: Icon(Icons.cloud_upload_outlined),
                selectedIcon: Icon(Icons.cloud_upload),
                label: 'Upload',
              ),
              const NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}
