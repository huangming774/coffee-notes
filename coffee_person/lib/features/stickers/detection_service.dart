import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class DetectionService {
  static const String useMlKitKey = 'sticker_use_mlkit_detection';

  DetectionService({
    MlKitDetectionService? mlKitDetectionService,
    YoloDetectionService? yoloDetectionService,
  })  : _mlKitDetectionService =
            mlKitDetectionService ?? MlKitDetectionService(),
        _yoloDetectionService = yoloDetectionService ?? YoloDetectionService();

  final MlKitDetectionService _mlKitDetectionService;
  final YoloDetectionService _yoloDetectionService;

  Future<Rect?> detectFirstBoundingBox(String imagePath) async {
    final useMlKit = await loadUseMlKit();
    if (useMlKit) {
      return _mlKitDetectionService.detectFirstBoundingBox(imagePath);
    }
    return _yoloDetectionService.detect(File(imagePath));
  }

  static Future<bool> loadUseMlKit() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(useMlKitKey) ?? false;
  }

  static Future<void> saveUseMlKit(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(useMlKitKey, value);
  }
}

class MlKitDetectionService {
  Future<Rect?> detectFirstBoundingBox(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final options = ObjectDetectorOptions(
      mode: DetectionMode.single,
      classifyObjects: false,
      multipleObjects: true,
    );
    final detector = ObjectDetector(options: options);
    try {
      final objects = await detector.processImage(inputImage);
      if (objects.isEmpty) return null;
      return objects.first.boundingBox;
    } catch (_) {
      return null;
    } finally {
      await detector.close();
    }
  }
}

class YoloDetectionService {
  factory YoloDetectionService({int threads = 2}) {
    _instance._threads = threads;
    return _instance;
  }

  YoloDetectionService._internal();

  static final YoloDetectionService _instance =
      YoloDetectionService._internal();
  static const String _modelAssetPath = 'assets/models/yolov8n_320_int8.tflite';
  static const int _inputSize = 320;
  static const double _scoreThreshold = 0.4;

  final Set<int> _targetClassIds = {0, 1, 2, 39, 40, 41};
  int _threads = 2;
  Interpreter? _interpreter;
  Future<void>? _loadingInterpreter;

  Future<Rect?> detect(File image) async {
    try {
      await _ensureInterpreter();
      final interpreter = _interpreter;
      if (interpreter == null) return null;
      final bytes = await image.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final originalWidth = decoded.width.toDouble();
      final originalHeight = decoded.height.toDouble();
      final resized = img.copyResize(
        decoded,
        width: _inputSize,
        height: _inputSize,
        interpolation: img.Interpolation.linear,
      );
      final rgbBytes = resized.getBytes(order: img.ChannelOrder.rgb);
      final inputTensor = interpreter.getInputTensor(0);
      final inputBuffer = _buildInputBuffer(rgbBytes, inputTensor);
      if (inputBuffer == null) return null;
      final outputTensor = interpreter.getOutputTensor(0);
      final outputShape = outputTensor.shape;
      final outputBuffer = _allocateOutputBuffer(outputTensor);
      if (outputBuffer == null) return null;
      interpreter.run(
        inputBuffer.reshape([1, _inputSize, _inputSize, 3]),
        outputBuffer.reshape(outputShape),
      );
      final best = _parseBestBox(
        outputBuffer,
        outputTensor,
        outputShape,
        originalWidth,
        originalHeight,
      );
      return best;
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureInterpreter() async {
    if (_interpreter != null) return;
    if (_loadingInterpreter != null) {
      await _loadingInterpreter;
      return;
    }
    final loading = _loadInterpreter();
    _loadingInterpreter = loading;
    await loading;
    _loadingInterpreter = null;
  }

  Future<void> _loadInterpreter() async {
    try {
      final options = InterpreterOptions()..threads = _threads;
      _interpreter = await Interpreter.fromAsset(
        _modelAssetPath,
        options: options,
      );
    } catch (_) {
      _interpreter = null;
    }
  }

  List? _buildInputBuffer(Uint8List rgbBytes, Tensor inputTensor) {
    final type = inputTensor.type;
    final params = inputTensor.params;
    final scale = params.scale;
    final zeroPoint = params.zeroPoint;
    final pixelCount = rgbBytes.length;
    if (type == TensorType.float32) {
      final buffer = Float32List(pixelCount);
      for (var i = 0; i < pixelCount; i++) {
        buffer[i] = rgbBytes[i] / 255.0;
      }
      return buffer;
    }
    if (type == TensorType.int8) {
      final buffer = Int8List(pixelCount);
      for (var i = 0; i < pixelCount; i++) {
        final normalized = rgbBytes[i] / 255.0;
        final quantized = (normalized / scale + zeroPoint).round();
        buffer[i] = quantized.clamp(-128, 127).toInt();
      }
      return buffer;
    }
    if (type == TensorType.uint8) {
      final buffer = Uint8List(pixelCount);
      for (var i = 0; i < pixelCount; i++) {
        final normalized = rgbBytes[i] / 255.0;
        final quantized = (normalized / scale + zeroPoint).round();
        buffer[i] = quantized.clamp(0, 255).toInt();
      }
      return buffer;
    }
    return null;
  }

  List? _allocateOutputBuffer(Tensor outputTensor) {
    final outputSize =
        outputTensor.shape.reduce((value, element) => value * element);
    switch (outputTensor.type) {
      case TensorType.float32:
        return Float32List(outputSize);
      case TensorType.int8:
        return Int8List(outputSize);
      case TensorType.uint8:
        return Uint8List(outputSize);
      default:
        return null;
    }
  }

  Rect? _parseBestBox(
    List outputBuffer,
    Tensor outputTensor,
    List<int> outputShape,
    double originalWidth,
    double originalHeight,
  ) {
    final data = outputBuffer;
    final params = outputTensor.params;
    final scale = params.scale;
    final zeroPoint = params.zeroPoint;
    var bestScore = 0.0;
    Rect? bestRect;
    final layout = _resolveOutputLayout(outputShape);
    if (layout == null) return null;
    final rowCount = layout.rowCount;
    final colCount = layout.colCount;
    for (var i = 0; i < rowCount; i++) {
      final cx = _readOutputValue(
        data,
        _indexAt(i, 0, rowCount, colCount, layout.isNbyC),
        outputTensor.type,
        scale,
        zeroPoint,
      );
      final cy = _readOutputValue(
        data,
        _indexAt(i, 1, rowCount, colCount, layout.isNbyC),
        outputTensor.type,
        scale,
        zeroPoint,
      );
      final w = _readOutputValue(
        data,
        _indexAt(i, 2, rowCount, colCount, layout.isNbyC),
        outputTensor.type,
        scale,
        zeroPoint,
      );
      final h = _readOutputValue(
        data,
        _indexAt(i, 3, rowCount, colCount, layout.isNbyC),
        outputTensor.type,
        scale,
        zeroPoint,
      );
      final parsed = _readScoreAndClass(
        data,
        i,
        rowCount,
        colCount,
        layout.isNbyC,
        outputTensor.type,
        scale,
        zeroPoint,
      );
      if (parsed == null) continue;
      if (parsed.score < _scoreThreshold) continue;
      if (!_targetClassIds.contains(parsed.classId)) continue;
      final normalized = cx <= 1.5 && cy <= 1.5 && w <= 1.5 && h <= 1.5;
      final scaleX = normalized ? originalWidth : originalWidth / _inputSize;
      final scaleY = normalized ? originalHeight : originalHeight / _inputSize;
      final left = (cx - w / 2) * scaleX;
      final top = (cy - h / 2) * scaleY;
      final right = (cx + w / 2) * scaleX;
      final bottom = (cy + h / 2) * scaleY;
      final clamped = Rect.fromLTRB(
        left.clamp(0, originalWidth),
        top.clamp(0, originalHeight),
        right.clamp(0, originalWidth),
        bottom.clamp(0, originalHeight),
      );
      if (parsed.score > bestScore) {
        bestScore = parsed.score;
        bestRect = clamped;
      }
    }
    return bestRect;
  }

  double _readOutputValue(
    List data,
    int index,
    TensorType type,
    double scale,
    int zeroPoint,
  ) {
    final raw = data[index] as num;
    switch (type) {
      case TensorType.int8:
      case TensorType.uint8:
        return (raw - zeroPoint) * scale;
      case TensorType.float32:
        return raw.toDouble();
      default:
        return raw.toDouble();
    }
  }

  _OutputLayout? _resolveOutputLayout(List<int> outputShape) {
    if (outputShape.length == 3) {
      final dim1 = outputShape[1];
      final dim2 = outputShape[2];
      if (dim2 >= 6) {
        return _OutputLayout(rowCount: dim1, colCount: dim2, isNbyC: true);
      }
      if (dim1 >= 6) {
        return _OutputLayout(rowCount: dim2, colCount: dim1, isNbyC: false);
      }
      return null;
    }
    if (outputShape.length == 2) {
      final dim0 = outputShape[0];
      final dim1 = outputShape[1];
      if (dim1 >= 6) {
        return _OutputLayout(rowCount: dim0, colCount: dim1, isNbyC: true);
      }
      if (dim0 >= 6) {
        return _OutputLayout(rowCount: dim1, colCount: dim0, isNbyC: false);
      }
    }
    return null;
  }

  _ScoreClass? _readScoreAndClass(
    List data,
    int row,
    int rowCount,
    int colCount,
    bool isNbyC,
    TensorType type,
    double scale,
    int zeroPoint,
  ) {
    if (colCount == 6) {
      final score = _readOutputValue(
        data,
        _indexAt(row, 4, rowCount, colCount, isNbyC),
        type,
        scale,
        zeroPoint,
      );
      final classIdValue = _readOutputValue(
        data,
        _indexAt(row, 5, rowCount, colCount, isNbyC),
        type,
        scale,
        zeroPoint,
      );
      return _ScoreClass(score: score, classId: classIdValue.round());
    }
    final hasObj = colCount == 85 || (colCount - 5 == 80 && colCount > 6);
    final classStart = hasObj ? 5 : 4;
    final objScore = hasObj
        ? _readOutputValue(
            data,
            _indexAt(row, 4, rowCount, colCount, isNbyC),
            type,
            scale,
            zeroPoint,
          )
        : 1.0;
    var bestProb = 0.0;
    var bestClass = -1;
    for (var c = classStart; c < colCount; c++) {
      final prob = _readOutputValue(
        data,
        _indexAt(row, c, rowCount, colCount, isNbyC),
        type,
        scale,
        zeroPoint,
      );
      if (prob > bestProb) {
        bestProb = prob;
        bestClass = c - classStart;
      }
    }
    if (bestClass < 0) return null;
    return _ScoreClass(score: objScore * bestProb, classId: bestClass);
  }

  int _indexAt(int row, int col, int rowCount, int colCount, bool isNbyC) {
    if (isNbyC) {
      return row * colCount + col;
    }
    return col * rowCount + row;
  }
}

class _OutputLayout {
  const _OutputLayout({
    required this.rowCount,
    required this.colCount,
    required this.isNbyC,
  });

  final int rowCount;
  final int colCount;
  final bool isNbyC;
}

class _ScoreClass {
  const _ScoreClass({required this.score, required this.classId});

  final double score;
  final int classId;
}
