import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

const removeBgApiKey = String.fromEnvironment(
  'REMOVE_BG_API_KEY',
  defaultValue: '',
);

const _uuid = Uuid();

final backgroundProcessingService = BackgroundProcessingService();

enum BackgroundProcessingStatus { queued, processing, completed, failed }

class BackgroundRemovalResult {
  const BackgroundRemovalResult({required this.file, required this.preview});

  final XFile file;
  final String preview;
}

class BackgroundProcessingService extends ChangeNotifier {
  BackgroundProcessingService({this.maxConcurrent = 2});

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
  late final Uint8List resultBytes;
  try {
    resultBytes = await _removeBackgroundWithApi(bytes, fileName: fileName);
  } catch (_) {
    resultBytes = await compute(_removeBackgroundBytes, bytes);
  }

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

Future<Uint8List> _removeBackgroundWithApi(
  Uint8List bytes, {
  required String fileName,
}) async {
  final request = http.MultipartRequest(
    'POST',
    Uri.parse('https://api.remove.bg/v1.0/removebg'),
  );
  request.headers['X-Api-Key'] = removeBgApiKey;
  request.fields['size'] = 'auto';
  request.fields['format'] = 'png';
  request.files.add(
    http.MultipartFile.fromBytes('image_file', bytes, filename: fileName),
  );

  final streamed = await request.send().timeout(const Duration(seconds: 18));
  final response = await http.Response.fromStream(streamed);
  if (response.statusCode != 200) {
    throw Exception('remove.bg ${response.statusCode}: ${response.body}');
  }

  return compute(_normalizeCutoutBytes, response.bodyBytes);
}

Uint8List _normalizeCutoutBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final image = img.bakeOrientation(decoded).convert(numChannels: 4);
  return Uint8List.fromList(img.encodePng(_centerOnSquare(_cropAlpha(image))));
}

Uint8List _removeBackgroundBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  var image = img.bakeOrientation(decoded);
  image = _resizeToMaxSide(image, 820);

  final result = image.convert(numChannels: 4);
  final width = result.width;
  final height = result.height;
  final bg = _estimateBackgroundColor(result);
  final foreground = Uint8List(width * height);
  var minX = width;
  var minY = height;
  var maxX = 0;
  var maxY = 0;

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final index = y * width + x;
      final pixel = result.getPixel(x, y);
      final isBackground = _isBackgroundPixel(pixel, bg);
      pixel.a = isBackground ? 0 : 255;
      if (!isBackground) {
        foreground[index] = 1;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (maxX <= minX || maxY <= minY) {
    return Uint8List.fromList(img.encodePng(_centerOnSquare(result)));
  }

  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final index = y * width + x;
      if (foreground[index] == 0) continue;
      var backgroundNeighbors = 0;
      for (var oy = -1; oy <= 1; oy++) {
        for (var ox = -1; ox <= 1; ox++) {
          if (foreground[(y + oy) * width + x + ox] == 0) {
            backgroundNeighbors++;
          }
        }
      }
      if (backgroundNeighbors >= 3) {
        result.getPixel(x, y).a = 205;
      }
    }
  }

  return Uint8List.fromList(img.encodePng(_centerOnSquare(_cropAlpha(result))));
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

img.Image _resizeToMaxSide(img.Image image, int maxSide) {
  if (image.width <= maxSide && image.height <= maxSide) return image;
  return img.copyResize(
    image,
    width: image.width >= image.height ? maxSide : null,
    height: image.height > image.width ? maxSide : null,
    interpolation: img.Interpolation.average,
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

({int r, int g, int b}) _estimateBackgroundColor(img.Image image) {
  final samples = <img.Pixel>[];
  final width = image.width;
  final height = image.height;
  final stepX = (width / 24).ceil().clamp(1, width).toInt();
  final stepY = (height / 24).ceil().clamp(1, height).toInt();

  for (var x = 0; x < width; x += stepX) {
    samples.add(image.getPixel(x, 0));
    samples.add(image.getPixel(x, height - 1));
  }
  for (var y = 0; y < height; y += stepY) {
    samples.add(image.getPixel(0, y));
    samples.add(image.getPixel(width - 1, y));
  }

  int avg(num Function(img.Pixel p) pick) {
    final total = samples.fold<num>(0, (sum, pixel) => sum + pick(pixel));
    return (total / samples.length).round();
  }

  return (r: avg((p) => p.r), g: avg((p) => p.g), b: avg((p) => p.b));
}

bool _isBackgroundPixel(img.Pixel pixel, ({int r, int g, int b}) bg) {
  final dr = (pixel.r - bg.r).abs();
  final dg = (pixel.g - bg.g).abs();
  final db = (pixel.b - bg.b).abs();
  final distance = dr + dg + db;
  final brightness = (pixel.r + pixel.g + pixel.b) / 3;
  final bgBrightness = (bg.r + bg.g + bg.b) / 3;

  return distance < 88 ||
      (distance < 128 && (brightness - bgBrightness).abs() < 34);
}
