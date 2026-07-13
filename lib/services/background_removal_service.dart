import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/app_config.dart';

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
  final token = Supabase.instance.client.auth.currentSession?.accessToken;
  if (token == null || token.isEmpty) {
    throw StateError('Для удаления фона нужно войти в аккаунт');
  }

  final request = http.MultipartRequest(
    'POST',
    Uri.parse(
      '${AppConfig.productAnalyzerUrl.replaceAll(RegExp(r'/$'), '')}/v1/remove-background',
    ),
  );
  request
    ..headers['Authorization'] = 'Bearer $token'
    ..files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
        contentType: _imageMediaType(bytes),
      ),
    );

  final streamed = await request.send().timeout(const Duration(seconds: 90));
  final response = await http.Response.fromStream(streamed);
  if (response.statusCode != 200) {
    throw Exception(
      'Удаление фона временно недоступно (${response.statusCode})',
    );
  }

  return compute(_normalizeCutoutBytes, response.bodyBytes);
}

MediaType _imageMediaType(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return MediaType('image', 'jpeg');
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47) {
    return MediaType('image', 'png');
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return MediaType('image', 'webp');
  }
  return MediaType('application', 'octet-stream');
}

Uint8List _normalizeCutoutBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final image = img.bakeOrientation(decoded).convert(numChannels: 4);
  return Uint8List.fromList(img.encodePng(_centerOnSquare(_cropAlpha(image))));
}

img.Image _cropAlpha(img.Image source) {
  final width = source.width;
  final height = source.height;
  var minX = width;
  var minY = height;
  var maxX = 0;
  var maxY = 0;

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (source.getPixel(x, y).a > 12) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (maxX <= minX || maxY <= minY) return source;
  final padX = ((maxX - minX) * 0.04).round();
  final padY = ((maxY - minY) * 0.04).round();
  final cropX = (minX - padX).clamp(0, width - 1).toInt();
  final cropY = (minY - padY).clamp(0, height - 1).toInt();
  final cropRight = (maxX + padX).clamp(0, width - 1).toInt();
  final cropBottom = (maxY + padY).clamp(0, height - 1).toInt();
  return img.copyCrop(
    source,
    x: cropX,
    y: cropY,
    width: cropRight - cropX + 1,
    height: cropBottom - cropY + 1,
  );
}

img.Image _centerOnSquare(img.Image source) {
  const size = 900;
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 0));

  final targetSide = (size * 0.96).round();
  final fitted = img.copyResize(
    source,
    width: source.width >= source.height ? targetSide : null,
    height: source.height > source.width ? targetSide : null,
    interpolation: img.Interpolation.cubic,
  );
  final dx = ((size - fitted.width) / 2).round();
  final dy = ((size - fitted.height) / 2).round();
  img.compositeImage(canvas, fitted, dstX: dx, dstY: dy);
  return canvas;
}
