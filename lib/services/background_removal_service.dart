import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

final backgroundProcessingService = BackgroundProcessingService();

enum BackgroundProcessingStatus { queued, processing, completed, failed }

class BackgroundRemovalResult {
  const BackgroundRemovalResult({required this.file, required this.preview});

  final XFile file;
  final String preview;
}

class BackgroundProcessingService extends ChangeNotifier {
  BackgroundProcessingService({this.maxConcurrent = 1});

  final int maxConcurrent;
  final Map<String, _BackgroundProcessingTask> _tasks = {};
  final Queue<String> _queue = Queue<String>();
  int _activeCount = 0;

  BackgroundRemovalResult? resultFor(String key) => _tasks[key]?.result;

  BackgroundProcessingStatus? statusFor(String key) => _tasks[key]?.status;

  bool isProcessing(String key) {
    final status = statusFor(key);
    return status == BackgroundProcessingStatus.queued ||
        status == BackgroundProcessingStatus.processing;
  }

  Future<BackgroundRemovalResult> enqueueImageSource(
    String key,
    String imageSource, {
    String fileName = 'outfit-item.png',
  }) {
    final existing = _tasks[key];
    if (existing != null) {
      existing.imageSource = imageSource;
      existing.fileName = fileName;
      if (existing.status == BackgroundProcessingStatus.failed) {
        existing.status = BackgroundProcessingStatus.queued;
        existing.completer = Completer<BackgroundRemovalResult>();
        _queue.add(key);
        _pump();
      }
      return existing.completer.future;
    }

    final task = _BackgroundProcessingTask(
      imageSource: imageSource,
      fileName: fileName,
    );
    _tasks[key] = task;
    _queue.add(key);
    notifyListeners();
    _pump();
    return task.completer.future;
  }

  void _pump() {
    while (_activeCount < maxConcurrent && _queue.isNotEmpty) {
      final key = _queue.removeFirst();
      final task = _tasks[key];
      if (task == null ||
          task.status == BackgroundProcessingStatus.completed ||
          task.status == BackgroundProcessingStatus.processing) {
        continue;
      }
      _run(key, task);
    }
  }

  Future<void> _run(String key, _BackgroundProcessingTask task) async {
    _activeCount++;
    task.status = BackgroundProcessingStatus.processing;
    notifyListeners();

    try {
      final result = await removeBackgroundFromImageSource(
        task.imageSource,
        fileName: task.fileName,
      );
      task.result = result;
      task.status = BackgroundProcessingStatus.completed;
      if (!task.completer.isCompleted) {
        task.completer.complete(result);
      }
    } catch (error, stackTrace) {
      task.status = BackgroundProcessingStatus.failed;
      if (!task.completer.isCompleted) {
        task.completer.completeError(error, stackTrace);
      }
    } finally {
      _activeCount--;
      notifyListeners();
      _pump();
    }
  }
}

class _BackgroundProcessingTask {
  _BackgroundProcessingTask({
    required this.imageSource,
    required this.fileName,
  });

  String imageSource;
  String fileName;
  BackgroundProcessingStatus status = BackgroundProcessingStatus.queued;
  BackgroundRemovalResult? result;
  Completer<BackgroundRemovalResult> completer =
      Completer<BackgroundRemovalResult>();
}

Future<BackgroundRemovalResult> removeBackgroundFromImageSource(
  String imageSource, {
  String fileName = 'outfit-item.png',
}) async {
  final bytes = await bytesFromImageSource(imageSource);
  return removeBackgroundFromBytes(bytes, fileName: fileName);
}

Future<BackgroundRemovalResult> removeBackgroundFromBytes(
  Uint8List bytes, {
  String fileName = 'outfit-item.png',
}) async {
  final resultBytes = await _removeBackgroundWithService(
    bytes,
    fileName: fileName,
  );

  return BackgroundRemovalResult(
    file: XFile.fromData(
      resultBytes,
      name: '${fileName.replaceAll(RegExp(r'\.[^.]+$'), '')}-${_uuid.v4()}.png',
      mimeType: 'image/png',
    ),
    preview: 'data:image/png;base64,${base64Encode(resultBytes)}',
  );
}

Future<Uint8List> bytesFromImageSource(String source) async {
  if (source.startsWith('data:image/')) {
    return base64Decode(source.substring(source.indexOf(',') + 1));
  }
  if (source.startsWith('http://') || source.startsWith('https://')) {
    final response = await http.get(Uri.parse(source));
    if (response.statusCode != 200) {
      throw Exception('Image load ${response.statusCode}');
    }
    return response.bodyBytes;
  }
  if (source.startsWith('assets/')) {
    final data = await rootBundle.load(source);
    return data.buffer.asUint8List();
  }
  if (!kIsWeb) {
    return File(source).readAsBytes();
  }
  throw Exception('Unsupported image source');
}

Future<Uint8List> _removeBackgroundWithService(
  Uint8List bytes, {
  required String fileName,
}) async {
  // Raw image processing is intentionally server-only. Published listings
  // are queued through the authenticated `process-product-image` Edge
  // function, which authenticates to the analyzer service-to-service.
  throw StateError(
    'Удаление фона доступно после безопасной серверной публикации',
  );
}
