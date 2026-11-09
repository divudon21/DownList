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

class NativeUploadEvent {
  const NativeUploadEvent({
    required this.uploadId,
    required this.status,
    this.uploadedBytes,
    this.totalBytes,
    this.speed,
    this.responseBody,
    this.error,
  });

  final String uploadId;
  final String status;
  final int? uploadedBytes;
  final int? totalBytes;
  final double? speed;
  final String? responseBody;
  final String? error;
}

class PlatformService {
  PlatformService._() {
    _channel.setMethodCallHandler(_handleNativeCallback);
  }

  static final PlatformService instance = PlatformService._();

  static const MethodChannel _channel =
      MethodChannel('com.example.ai_agent_downloader/native');

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

  Future<void> cancelUpload(String uploadId) async {
    await _channel.invokeMethod<bool>('cancelUpload', {
      'uploadId': uploadId,
    });
  }

  Future<void> cancelAllUploads() async {
    await _channel.invokeMethod<bool>('cancelAllUploads');
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
