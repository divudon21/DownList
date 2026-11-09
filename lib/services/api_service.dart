import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/task_model.dart';

class ApiService extends ChangeNotifier {
  ApiService({String baseUrl = ''}) : _baseUrl = _normalize(baseUrl);

  String _baseUrl;
  final Set<String> _sessionTaskIds = <String>{};
  int _historyVersion = 0;
  int _activeServerTaskCount = 0;

  String get baseUrl => _baseUrl;

  bool get isConfigured => _baseUrl.isNotEmpty;

  Set<String> get sessionTaskIds => Set<String>.unmodifiable(_sessionTaskIds);

  int get historyVersion => _historyVersion;

  int get activeServerTaskCount => _activeServerTaskCount;

  void updateActiveServerTaskCount(int count) {
    if (_activeServerTaskCount == count) return;
    _activeServerTaskCount = count;
    notifyListeners();
  }

  set baseUrl(String value) {
    final normalized = _normalize(value);
    if (_baseUrl == normalized) return;
    _baseUrl = normalized;
    _sessionTaskIds.clear();
    _activeServerTaskCount = 0;
    _historyVersion++;
    notifyListeners();
  }

  static String _normalize(String url) {
    var cleaned = url.trim();
    while (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    return cleaned;
  }

  void notifyHistoryChanged() {
    _historyVersion++;
    notifyListeners();
  }

  void untrackSessionTask(String taskId) {
    _sessionTaskIds.remove(taskId);
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Future<String> startDownload(String url) async {
    if (!isConfigured) {
      throw Exception('Server URL is not configured. Open Settings to set it.');
    }
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw Exception('Please enter a file URL.');
    }
    final uri = _uri('/start_download');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'url': trimmed}),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final taskId = data['task_id']?.toString();
      if (taskId == null || taskId.isEmpty) {
        final err = data['error']?.toString();
        throw Exception(err ?? 'Server did not return a task_id.');
      }
      _sessionTaskIds.add(taskId);
      notifyListeners();
      return taskId;
    }
    throw Exception('Start download failed (HTTP ${response.statusCode}).');
  }

  Future<TaskModel> getStatus(String taskId) async {
    if (!isConfigured) {
      throw Exception('Server URL is not configured.');
    }
    final uri = _uri('/status/$taskId');
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['task_id'] == null && data['error'] != null) {
        throw Exception(data['error'].toString());
      }
      return TaskModel.fromJson(data);
    }
    if (response.statusCode == 404) {
      throw Exception('Task not found on server.');
    }
    throw Exception('Status check failed (HTTP ${response.statusCode}).');
  }

  Future<List<TaskModel>> getHistory() async {
    if (!isConfigured) {
      return const <TaskModel>[];
    }
    final uri = _uri('/history');
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['history'] as List<dynamic>? ?? const [];
      return list
          .whereType<Map>()
          .map((e) => TaskModel.fromJson(Map<String, dynamic>.from(e)))
          .where((t) => t.taskId.isNotEmpty)
          .toList();
    }
    throw Exception('Failed to fetch tasks (HTTP ${response.statusCode}).');
  }

  Future<ServerStatus> getServerStatus({String? overrideBaseUrl}) async {
    final target = overrideBaseUrl != null ? _normalize(overrideBaseUrl) : _baseUrl;
    if (target.isEmpty) {
      throw Exception('Please enter a Server URL first.');
    }
    final uri = Uri.parse('$target/server_status');
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ServerStatus.fromJson(data);
    }
    throw Exception('Server responded with HTTP ${response.statusCode}.');
  }

  String get uploadEndpoint => '$_baseUrl/upload';

  String downloadUrl(String taskId) => '$_baseUrl/download/$taskId';

  String streamUrl(String taskId) => '$_baseUrl/stream/$taskId';
}
