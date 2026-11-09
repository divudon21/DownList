import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/task_model.dart';
import 'api_service.dart';
import 'platform_service.dart';

enum UploadStatus {
  ready,
  queued,
  uploading,
  completed,
  cancelled,
  error,
}

class UploadItem {
  UploadItem({
    required this.id,
    required this.uri,
    required this.fileName,
    required this.totalBytes,
    required this.mimeType,
    required this.addedAt,
    this.uploadedBytes = 0,
    this.speed = 0.0,
    this.status = UploadStatus.ready,
    this.serverTaskId,
    this.errorMessage,
  });

  final String id;
  final String uri;
  final String fileName;
  int totalBytes;
  final String mimeType;
  final DateTime addedAt;
  int uploadedBytes;
  double speed;
  UploadStatus status;
  String? serverTaskId;
  String? errorMessage;

  String get extension {
    final parts = fileName.split('.');
    if (parts.length < 2) return '';
    return parts.last.toLowerCase();
  }

  bool get isVideo => const {
        'mp4',
        'mkv',
        'mov',
        'avi',
        'webm',
        'flv',
        'm4v',
        '3gp',
        'ts',
        'm2ts',
      }.contains(extension);

  bool get isAudio => const {
        'mp3',
        'wav',
        'aac',
        'ogg',
        'flac',
        'm4a',
        'opus',
      }.contains(extension);

  bool get isImage => const {
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'bmp',
        'svg',
      }.contains(extension);

  bool get isZip => extension == 'zip' || extension == 'rar' || extension == '7z';

  bool get isApk => extension == 'apk';

  bool get isActive =>
      status == UploadStatus.uploading || status == UploadStatus.queued;

  double get progress {
    if (status == UploadStatus.completed) return 1.0;
    if (totalBytes <= 0) return 0.0;
    final p = uploadedBytes / totalBytes;
    if (p < 0.0) return 0.0;
    if (p > 1.0) return 1.0;
    return p;
  }

  String get sizeFormatted =>
      totalBytes > 0 ? TaskModel.formatBytes(totalBytes) : 'Unknown size';

  String get uploadedFormatted => TaskModel.formatBytes(uploadedBytes);

  String get speedFormatted =>
      speed > 0 ? '${TaskModel.formatBytes(speed.round())}/s' : '--';

  String get etaFormatted {
    if (status != UploadStatus.uploading || speed <= 0 || totalBytes <= 0) {
      return '--';
    }
    final remaining = totalBytes - uploadedBytes;
    if (remaining <= 0) return '0s';
    return TaskModel.formatDurationSeconds((remaining / speed).ceil());
  }

  String get statusLabel {
    switch (status) {
      case UploadStatus.ready:
        return 'Ready';
      case UploadStatus.queued:
        return 'Queued';
      case UploadStatus.uploading:
        return 'Uploading';
      case UploadStatus.completed:
        return 'Uploaded';
      case UploadStatus.cancelled:
        return 'Cancelled';
      case UploadStatus.error:
        return 'Failed';
    }
  }
}

class UploadManager extends ChangeNotifier {
  UploadManager({required this.api}) {
    _sub = PlatformService.instance.uploadEvents.listen(_onNativeEvent);
  }

  static const int maxConcurrentUploads = 2;

  final ApiService api;
  final List<UploadItem> _items = <UploadItem>[];
  StreamSubscription<NativeUploadEvent>? _sub;
  int _counter = 0;

  List<UploadItem> get items => List<UploadItem>.unmodifiable(_items);

  List<UploadItem> get activeItems =>
      _items.where((i) => i.isActive).toList(growable: false);

  List<UploadItem> get readyItems => _items
      .where((i) => i.status == UploadStatus.ready)
      .toList(growable: false);

  bool get hasActiveUploads => _items.any((i) => i.isActive);

  bool get hasFinishedItems => _items.any(
        (i) =>
            i.status == UploadStatus.completed ||
            i.status == UploadStatus.cancelled,
      );

  int get totalSelectedBytes =>
      _items.fold<int>(0, (sum, item) => sum + item.totalBytes);

  int get totalUploadedBytes => _items.fold<int>(
        0,
        (sum, item) =>
            sum +
            (item.status == UploadStatus.completed
                ? item.totalBytes
                : item.uploadedBytes),
      );

  double get combinedSpeed => _items
      .where((i) => i.status == UploadStatus.uploading)
      .fold<double>(0.0, (sum, i) => sum + i.speed);

  Future<int> pickFiles() async {
    final picked = await PlatformService.instance.pickFiles();
    if (picked.isEmpty) return 0;

    final now = DateTime.now();
    for (final file in picked) {
      _counter++;
      final id = 'up_${now.microsecondsSinceEpoch}_$_counter';
      _items.add(
        UploadItem(
          id: id,
          uri: file.uri,
          fileName: file.name,
          totalBytes: file.size,
          mimeType: file.mimeType,
          addedAt: now,
        ),
      );
    }
    notifyListeners();
    return picked.length;
  }

  void startAll() {
    if (!api.isConfigured) return;
    var changed = false;
    for (final item in _items) {
      if (item.status == UploadStatus.ready) {
        item.status = UploadStatus.queued;
        item.errorMessage = null;
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      _pumpQueue();
    }
  }

  void startSingle(String id) {
    if (!api.isConfigured) return;
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    final item = _items[idx];
    if (item.status == UploadStatus.uploading ||
        item.status == UploadStatus.queued) {
      return;
    }
    item.uploadedBytes = 0;
    item.speed = 0.0;
    item.errorMessage = null;
    item.serverTaskId = null;
    item.status = UploadStatus.queued;
    notifyListeners();
    _pumpQueue();
  }

  Future<void> cancelUpload(String id) async {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    final item = _items[idx];
    final wasUploading = item.status == UploadStatus.uploading;
    if (item.status == UploadStatus.uploading ||
        item.status == UploadStatus.queued) {
      item.status = UploadStatus.cancelled;
      item.speed = 0.0;
      notifyListeners();
    }
    if (wasUploading) {
      try {
        await PlatformService.instance.cancelUpload(id);
      } catch (_) {}
    }
    _pumpQueue();
  }

  Future<void> cancelAll() async {
    var hadUploading = false;
    for (final item in _items) {
      if (item.status == UploadStatus.uploading) {
        hadUploading = true;
        item.status = UploadStatus.cancelled;
        item.speed = 0.0;
      } else if (item.status == UploadStatus.queued) {
        item.status = UploadStatus.cancelled;
        item.speed = 0.0;
      }
    }
    notifyListeners();
    if (hadUploading) {
      try {
        await PlatformService.instance.cancelAllUploads();
      } catch (_) {}
    }
  }

  Future<void> removeItem(String id) async {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    final item = _items[idx];
    if (item.isActive) {
      await cancelUpload(id);
    }
    _items.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  void clearFinished() {
    _items.removeWhere(
      (i) =>
          i.status == UploadStatus.completed ||
          i.status == UploadStatus.cancelled,
    );
    notifyListeners();
  }

  void _pumpQueue() {
    if (!api.isConfigured) return;
    final runningCount =
        _items.where((i) => i.status == UploadStatus.uploading).length;
    var slots = maxConcurrentUploads - runningCount;
    if (slots <= 0) return;

    for (final item in _items) {
      if (slots <= 0) break;
      if (item.status == UploadStatus.queued) {
        slots--;
        _launchUpload(item);
      }
    }
  }

  Future<void> _launchUpload(UploadItem item) async {
    item.status = UploadStatus.uploading;
    item.uploadedBytes = 0;
    item.speed = 0.0;
    item.errorMessage = null;
    notifyListeners();

    try {
      await PlatformService.instance.startUpload(
        uploadId: item.id,
        uri: item.uri,
        fileName: item.fileName,
        fileSize: item.totalBytes,
        uploadUrl: api.uploadEndpoint,
      );
    } catch (e) {
      item.status = UploadStatus.error;
      item.speed = 0.0;
      item.errorMessage = e.toString();
      notifyListeners();
      _pumpQueue();
    }
  }

  void _onNativeEvent(NativeUploadEvent event) {
    final idx = _items.indexWhere((i) => i.id == event.uploadId);
    if (idx == -1) return;
    final item = _items[idx];

    if (item.status == UploadStatus.cancelled && event.status != 'cancelled') {
      return;
    }

    switch (event.status) {
      case 'uploading':
        item.status = UploadStatus.uploading;
        if (event.uploadedBytes != null) {
          item.uploadedBytes = event.uploadedBytes!;
        }
        if (event.totalBytes != null && event.totalBytes! > item.totalBytes) {
          item.totalBytes = event.totalBytes!;
        }
        if (event.speed != null) {
          item.speed = event.speed!;
        }
        notifyListeners();
        break;

      case 'completed':
        item.status = UploadStatus.completed;
        if (event.totalBytes != null && event.totalBytes! > 0) {
          item.totalBytes = event.totalBytes!;
        }
        item.uploadedBytes = item.totalBytes;
        item.speed = 0.0;
        if (event.responseBody != null && event.responseBody!.isNotEmpty) {
          try {
            final decoded = jsonDecode(event.responseBody!);
            if (decoded is Map && decoded['task_id'] != null) {
              item.serverTaskId = decoded['task_id'].toString();
            }
          } catch (_) {}
        }
        notifyListeners();
        api.notifyHistoryChanged();
        _pumpQueue();
        break;

      case 'cancelled':
        item.status = UploadStatus.cancelled;
        item.speed = 0.0;
        notifyListeners();
        _pumpQueue();
        break;

      case 'error':
        item.status = UploadStatus.error;
        item.speed = 0.0;
        item.errorMessage = event.error ?? 'Upload failed';
        notifyListeners();
        _pumpQueue();
        break;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
