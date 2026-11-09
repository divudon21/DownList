import 'package:flutter/material.dart';

import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/task_screen.dart';
import 'screens/upload_screen.dart';
import 'services/api_service.dart';
import 'services/settings_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AiAgentApp());
}

class AppServices extends InheritedWidget {
  const AppServices({
    super.key,
    required this.settings,
    required this.api,
    required super.child,
  });

  final SettingsService settings;
  final ApiService api;

  static AppServices of(BuildContext context) {
    final widget = context.getInheritedWidgetOfExactType<AppServices>();
    assert(widget != null, 'No AppServices found in context');
    return widget!;
  }

  @override
  bool updateShouldNotify(covariant AppServices old) =>
      settings != old.settings || api != old.api;
}

class AiAgentApp extends StatefulWidget {
  const AiAgentApp({super.key});

  @override
  State<AiAgentApp> createState() => _AiAgentAppState();
}

class _AiAgentAppState extends State<AiAgentApp> {
  late final SettingsService _settings;
  late final ApiService _api;

  @override
  void initState() {
    super.initState();
    _settings = SettingsService();
    _api = ApiService(baseUrl: SettingsService.defaultServerUrl);
    _loadSavedServerUrl();
  }

  Future<void> _loadSavedServerUrl() async {
    final savedUrl = await _settings.getServerUrl();
    if (!mounted) return;
    setState(() {
      _api.baseUrl = savedUrl;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppServices(
      settings: _settings,
      api: _api,
      child: MaterialApp(
        title: 'AI Agent Downloader',
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
        home: HomePage(settings: _settings, api: _api),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.settings,
    required this.api,
  });

  final SettingsService settings;
  final ApiService api;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  void _selectTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(
        api: widget.api,
        onViewTasks: () => _selectTab(1),
      ),
      TaskScreen(
        api: widget.api,
        onGoHome: () => _selectTab(0),
      ),
      HistoryScreen(api: widget.api),
      const UploadScreen(),
      SettingsScreen(settings: widget.settings, api: widget.api),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AI Agent Downloader',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
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
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.file_download_outlined),
            selectedIcon: Icon(Icons.file_download),
            label: 'Task',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud_upload_outlined),
            selectedIcon: Icon(Icons.cloud_upload),
            label: 'Upload',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
