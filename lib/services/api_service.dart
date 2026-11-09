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

  Future<Map<String, dynamic>> _request(String method, String path, [Map<String, dynamic>? body]) async {
    if (!isConfigured) throw Exception('Please configure the server URL in Settings.');
    final uri = _uri(path);
    final response = method == 'GET'
        ? await http.get(uri).timeout(const Duration(seconds: 30))
        : method == 'DELETE'
            ? await http.delete(uri).timeout(const Duration(seconds: 30))
            : await http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 30));
    Map<String, dynamic> data;
    try { data = Map<String, dynamic>.from(jsonDecode(response.body) as Map); }
    catch (_) { throw Exception('Invalid server response (HTTP ${response.statusCode}).'); }
    if (response.statusCode < 200 || response.statusCode >= 300 || data['error'] != null) {
      throw Exception(data['error']?.toString() ?? data['detail']?.toString() ?? 'Server error (HTTP ${response.statusCode}).');
    }
    return data;
  }

  Future<String> startGofileTransfer(String url) async {
    final data = await _request('POST', '/start_gofile_transfer', {'url': url.trim()});
    final id = data['task_id']?.toString() ?? '';
    if (id.isEmpty) throw Exception('Server did not return a task ID.');
    _sessionTaskIds.add(id);
    notifyListeners();
    return id;
  }

  Future<void> deleteTask(String id) async { await _request('DELETE', '/delete/$id'); notifyHistoryChanged(); }
  Future<void> renameTask(String id, String name) async { await _request('POST', '/rename/$id', {'new_name': name}); notifyHistoryChanged(); }
  Future<void> cancelTask(String id) async { await _request('POST', '/cancel/$id'); notifyHistoryChanged(); }
  Future<void> deleteAllTasks() async { await _request('POST', '/delete_all'); notifyHistoryChanged(); }
  Future<Map<String, dynamic>> getFileInfo(String id) => _request('GET', '/file_info/$id');
  Future<Map<String, dynamic>> listZipContents(String id) => _request('GET', '/list_zip/$id');
  Future<void> extractZip(String id) async { await _request('POST', '/extract_zip/$id'); notifyHistoryChanged(); }

  String get uploadEndpoint => '$_baseUrl/upload';

  String downloadUrl(String taskId) => '$_baseUrl/download/$taskId';

  String streamUrl(String taskId) => '$_baseUrl/stream/$taskId';
}
