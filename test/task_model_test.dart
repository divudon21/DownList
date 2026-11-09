import 'package:flutter_test/flutter_test.dart';
import 'package:ai_agent_downloader/models/task_model.dart';

void main() {
  test('GoFile stays active through the old server intermediate completed state', () {
    final preparing = TaskModel.fromJson({'task_id': 'a', 'url': 'file', 'status': 'completed', 'task_type': 'gofile'});
    expect(preparing.isActive, isTrue);
    expect(preparing.isCompleted, isFalse);
    expect(preparing.statusLabel, 'Preparing GoFile upload');
    final uploading = TaskModel.fromJson({'task_id': 'a', 'url': 'file', 'status': 'uploading_to_gofile', 'task_type': 'gofile', 'downloaded': 100, 'total_size': 100});
    expect(uploading.isActive, isTrue);
    expect(uploading.gofileUploadProgressKnown, isFalse);
    final live = TaskModel.fromJson({'task_id': 'a', 'url': 'file', 'status': 'uploading_to_gofile', 'task_type': 'gofile', 'downloaded': 40, 'total_size': 100});
    expect(live.gofileUploadProgressKnown, isTrue);
    expect(live.progress, 0.4);
    final done = TaskModel.fromJson({'task_id': 'a', 'url': 'file', 'status': 'completed', 'task_type': 'gofile', 'gofile_url': 'https://gofile.io/d/test'});
    expect(done.isCompleted, isTrue);
    expect(done.isActive, isFalse);
  });

  test('Ordinary download completes without a GoFile link', () {
    final task = TaskModel.fromJson({'task_id': 'b', 'url': 'file', 'status': 'completed'});
    expect(task.isCompleted, isTrue);
  });
}
