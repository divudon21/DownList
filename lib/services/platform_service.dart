import 'dart:async';

import 'package:flutter/services.dart';

class PickedFileInfo {
  const PickedFileInfo({
    required this.uri,
    required this.name,
    required this.size,
    required this.mimeType,
  });

  final String uri;
  final String name;
  final int size;
  final String mimeType;
}

class MediaPlayerApp {
  const MediaPlayerApp({
    required this.packageName,
    required this.activityName,
    required this.label,
    required this.iconBytes,
  });

  final String packageName;
  final String activityName;
  final String label;
  final Uint8List iconBytes;
}

class NativeUploadEvent {
  const NativeUploadEvent({
    required this.uploadId,
    required this.status,
    this.uploadedBytes,
    this.totalBytes,
    this.speed,
    this.responseBody,
    this.error,
    this.uri,
    this.fileName,
  });

  final String uploadId;
  final String status;
  final int? uploadedBytes;
  final int? totalBytes;
  final double? speed;
  final String? responseBody;
  final String? error;
  final String? uri;
  final String? fileName;
}

class PlatformService {
  PlatformService._() {
    _channel.setMethodCallHandler(_handleNativeCallback);
  }

  static final PlatformService instance = PlatformService._();

  static const MethodChannel _channel =
      MethodChannel('com.dowlist.com/native');

  final StreamController<NativeUploadEvent> _uploadEvents =
      StreamController<NativeUploadEvent>.broadcast();

  Stream<NativeUploadEvent> get uploadEvents => _uploadEvents.stream;

  Future<dynamic> _handleNativeCallback(MethodCall call) async {
    if (call.method == 'onUploadEvent') {
      final map = Map<dynamic, dynamic>.from(call.arguments as Map);
      final uploadId = (map['uploadId'] ?? '').toString();
      if (uploadId.isEmpty) return null;
      _uploadEvents.add(
        NativeUploadEvent(
          uploadId: uploadId,
          status: (map['status'] ?? '').toString(),
          uploadedBytes: (map['uploadedBytes'] as num?)?.toInt(),
          totalBytes: (map['totalBytes'] as num?)?.toInt(),
          speed: (map['speed'] as num?)?.toDouble(),
          responseBody: map['responseBody']?.toString(),
          error: map['error']?.toString(),
          uri: map['uri']?.toString(),
          fileName: map['fileName']?.toString(),
        ),
      );
    }
    return null;
  }

  Future<List<PickedFileInfo>> pickFiles() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('pickFiles');
    if (raw == null) return const <PickedFileInfo>[];
    return raw.whereType<Map>().map((item) {
      final m = Map<dynamic, dynamic>.from(item);
      return PickedFileInfo(
        uri: (m['uri'] ?? '').toString(),
        name: (m['name'] ?? 'file').toString(),
        size: (m['size'] as num?)?.toInt() ?? 0,
        mimeType: (m['mimeType'] ?? 'application/octet-stream').toString(),
      );
    }).where((f) => f.uri.isNotEmpty).toList();
  }

  Future<void> startUpload({
    required String uploadId,
    required String uri,
    required String fileName,
    required int fileSize,
    required String uploadUrl,
  }) async {
    await _channel.invokeMethod<bool>('startUpload', {
      'uploadId': uploadId,
      'uri': uri,
      'fileName': fileName,
      'fileSize': fileSize,
      'uploadUrl': uploadUrl,
    });
  }

  Future<void> monitorServerTask(String baseUrl, String taskId, {required bool isGofile}) async {
    await _channel.invokeMethod<bool>('startServerMonitor', {'baseUrl': baseUrl, 'taskId': taskId, 'isGofile': isGofile});
  }

  Future<Map<String, bool>> getNotificationSettings() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('getNotificationSettings') ?? {};
    return {'uploads': result['uploads'] == true, 'downloads': result['downloads'] == true, 'enabled': result['enabled'] == true};
  }

  Future<bool> requestNotificationPermission() async => await _channel.invokeMethod<bool>('requestNotificationPermission') ?? false;
  Future<void> setNotificationSetting(String key, bool value) async { await _channel.invokeMethod<bool>('setNotificationSetting', {'key': key, 'value': value}); }
  Future<void> openNotificationSettings() async { await _channel.invokeMethod<bool>('openNotificationSettings'); }
  Future<List<dynamic>> getServerTaskSnapshots() async => await _channel.invokeListMethod<dynamic>('getServerTaskSnapshots') ?? [];

  Future<List<NativeUploadEvent>> getUploadSnapshots() async {
    final raw = await _channel.invokeListMethod<dynamic>('getUploadSnapshots') ?? [];
    return raw.whereType<Map>().map((e) {
      final m = Map<dynamic, dynamic>.from(e);
      return NativeUploadEvent(uploadId: '${m['uploadId'] ?? ''}', status: '${m['status'] ?? ''}',
        uploadedBytes: (m['uploadedBytes'] as num?)?.toInt(), totalBytes: (m['totalBytes'] as num?)?.toInt(),
        speed: (m['speed'] as num?)?.toDouble(), responseBody: m['responseBody']?.toString(), error: m['error']?.toString(),
        uri: m['uri']?.toString(), fileName: m['fileName']?.toString());
    }).toList();
  }

  Future<void> cancelUpload(String uploadId) async {
    await _channel.invokeMethod<bool>('cancelUpload', {
      'uploadId': uploadId,
    });
  }

  Future<void> cancelAllUploads() async {
    await _channel.invokeMethod<bool>('cancelAllUploads');
  }

  Future<List<MediaPlayerApp>> getMediaPlayers({
    required String url,
    required String fileName,
    required String mimeType,
  }) async {
    final raw = await _channel.invokeMethod<List<dynamic>>('getMediaPlayers', {
      'url': url,
      'fileName': fileName,
      'mimeType': mimeType,
    });
    if (raw == null) return const <MediaPlayerApp>[];
    return raw.whereType<Map>().map((entry) {
      final m = Map<dynamic, dynamic>.from(entry);
      final rawIcon = m['icon'];
      final iconBytes =
          rawIcon is Uint8List ? rawIcon : Uint8List(0);
      return MediaPlayerApp(
        packageName: (m['packageName'] ?? '').toString(),
        activityName: (m['activityName'] ?? '').toString(),
        label: (m['label'] ?? '').toString(),
        iconBytes: iconBytes,
      );
    }).where((p) => p.packageName.isNotEmpty).toList();
  }

  Future<void> launchMediaPlayer({
    required String url,
    required String fileName,
    required String mimeType,
    required String packageName,
    required String activityName,
  }) async {
    await _channel.invokeMethod<bool>('launchMediaPlayer', {
      'url': url,
      'fileName': fileName,
      'mimeType': mimeType,
      'packageName': packageName,
      'activityName': activityName,
    });
  }

  Future<void> openExternalPlayer({
    required String url,
    required String fileName,
    required String mimeType,
  }) async {
    await _channel.invokeMethod<bool>('openExternalPlayer', {
      'url': url,
      'fileName': fileName,
      'mimeType': mimeType,
    });
  }

  Future<Map<String, dynamic>> getAppBuildInfo() async =>
      Map<String, dynamic>.from(await _channel.invokeMapMethod<String, dynamic>('getAppBuildInfo') ?? {});
  Future<bool> showUpdateNotification(String version, String url, bool compatible) async =>
      await _channel.invokeMethod<bool>('showUpdateNotification', {'version': version, 'url': url, 'compatible': compatible}) ?? false;
  Future<void> clearUpdateNotification() async { await _channel.invokeMethod<bool>('clearUpdateNotification'); }

  Future<String> getAppVersion() async => await _channel.invokeMethod<String>('getAppVersion') ?? '';

  Future<void> openUrl(String url) async {
    await _channel.invokeMethod<bool>('openUrl', {'url': url});
  }

  static String guessMediaMimeType(String extension, {bool isAudio = false}) {
    switch (extension.toLowerCase()) {
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      case 'avi':
        return 'video/x-msvideo';
      case 'mov':
        return 'video/quicktime';
      case 'flv':
        return 'video/x-flv';
      case '3gp':
        return 'video/3gpp';
      case 'ts':
      case 'm2ts':
        return 'video/mp2t';
      case 'mpg':
      case 'mpeg':
        return 'video/mpeg';
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
      case 'aac':
        return 'audio/mp4';
      case 'wav':
        return 'audio/wav';
      case 'flac':
        return 'audio/flac';
      case 'ogg':
      case 'opus':
        return 'audio/ogg';
      default:
        return isAudio ? 'audio/*' : 'video/*';
    }
  }
}
