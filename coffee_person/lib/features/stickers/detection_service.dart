import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'detection_config.dart';

class StickerCutout {
  const StickerCutout({required this.bbox, required this.alphaMask});

  final Rect? bbox;
  final img.Image? alphaMask;
}

class DetectionService {
  DetectionService({
    YoloDetectionService? yoloDetectionService,
  }) : _yoloDetectionService = yoloDetectionService ?? YoloDetectionService();

  final YoloDetectionService _yoloDetectionService;

  Future<StickerCutout> detectStickerCutout(String imagePath) async {
    return _yoloDetectionService.detectCutout(File(imagePath));
  }

  Future<Rect?> detectFirstBoundingBox(String imagePath) async {
    return _yoloDetectionService.detect(File(imagePath));
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
  static const String _modelAssetPath =
      'assets/models/yolov8n-seg_float16.tflite';
  static const int _fallbackInputSize = 320;
  double _scoreThreshold = 0.15;

  Set<int> _targetClassIds = {39, 40, 41, 45}; // bottle, wine glass, cup, bowl
  bool _enableAllClasses = false;
  int _threads = 4; // 增加到 线程以提升性能
  Interpreter? _interpreter;
  Future<void>? _loadingInterpreter;
  Future<Rect?> detect(File image) async {
    final cutout = await detectCutout(image);
    return cutout.bbox;
  }

  Future<StickerCutout> detectCutout(File image) async {
    try {
      await _ensureInterpreter();
      final interpreter = _interpreter;
      if (interpreter == null) {
        return const StickerCutout(bbox: null, alphaMask: null);
      }
      final bytes = await image.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return const StickerCutout(bbox: null, alphaMask: null);
      }
      final originalWidth = decoded.width.toDouble();
      final originalHeight = decoded.height.toDouble();
      final inputTensor = interpreter.getInputTensor(0);
      final inputHeight = _resolveInputHeight(inputTensor.shape);
      final inputWidth = _resolveInputWidth(inputTensor.shape);
      final letterbox =
          _letterbox(decoded, inputWidth: inputWidth, inputHeight: inputHeight);
      final rgbBytes = letterbox.image.getBytes(order: img.ChannelOrder.rgb);
      final inputBuffer = _buildInputBuffer(rgbBytes, inputTensor);
      if (inputBuffer == null) {
        return const StickerCutout(bbox: null, alphaMask: null);
      }
      await _loadDetectionConfig();
      final inputShape = inputTensor.shape;
      final outputTensors = _resolveOutputTensors(interpreter);
      if (outputTensors.isEmpty) {
        return const StickerCutout(bbox: null, alphaMask: null);
      }
      final buffers = _allocateOutputBuffers(outputTensors);
      if (buffers.raw.isEmpty) {
        return const StickerCutout(bbox: null, alphaMask: null);
      }
      interpreter.runForMultipleInputs(
        [inputBuffer.reshape(inputShape)],
        buffers.shaped,
      );
      final selection = _selectOutputTensors(outputTensors);
      final outputTensor = outputTensors[selection.detIndex];
      if (outputTensor == null) {
        return const StickerCutout(bbox: null, alphaMask: null);
      }
      final outputShape = outputTensor.shape;
      final outputBuffer = buffers.raw[selection.detIndex];
      if (outputBuffer == null) {
        return const StickerCutout(bbox: null, alphaMask: null);
      }
      final protoTensor = selection.protoIndex == null
          ? null
          : outputTensors[selection.protoIndex!];
      final maskDim =
          protoTensor == null ? null : _inferMaskDim(protoTensor.shape);
      final best = _parseBestCandidate(
        outputBuffer,
        outputTensor,
        outputShape,
        originalWidth,
        originalHeight,
        inputWidth,
        inputHeight,
        maskDim,
        letterbox,
      );
      if (best == null) {
        return const StickerCutout(bbox: null, alphaMask: null);
      }
      img.Image? alphaMask;
      final protoBuffer =
          protoTensor == null ? null : buffers.raw[selection.protoIndex!];
      if (maskDim != null &&
          best.maskCoefficients != null &&
          protoTensor != null &&
          protoBuffer != null) {
        final protoLayout = _resolveProtoLayout(protoTensor.shape, maskDim);
        if (protoLayout != null) {
          final maskProto = _decodeMaskProto(
            protoBuffer,
            protoTensor,
            protoLayout,
            best.maskCoefficients!,
          );
          final maskInput = img.copyResize(
            maskProto,
            width: inputWidth,
            height: inputHeight,
            interpolation: img.Interpolation.linear,
          );
          final maskCropped = _cropLetterbox(
            maskInput,
            letterbox,
          );
          alphaMask = img.copyResize(
            maskCropped,
            width: originalWidth.round(),
            height: originalHeight.round(),
            interpolation: img.Interpolation.linear,
          );
          _applyBboxToMask(alphaMask, best.rect);
        }
      }
      return StickerCutout(bbox: best.rect, alphaMask: alphaMask);
    } catch (_) {
      return const StickerCutout(bbox: null, alphaMask: null);
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

  Future<void> _loadDetectionConfig() async {
    _scoreThreshold = await DetectionConfig.getScoreThreshold();
    _targetClassIds = await DetectionConfig.getTargetClassIds();
    _enableAllClasses = await DetectionConfig.isEnableAllClasses();
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
    if (_isFloat16(type)) {
      final buffer = Uint16List(pixelCount);
      for (var i = 0; i < pixelCount; i++) {
        buffer[i] = _float32ToFloat16(rgbBytes[i] / 255.0);
      }
      return buffer;
    }
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
    if (_isFloat16(outputTensor.type)) {
      return Uint16List(outputSize);
    }
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

  Map<int, Tensor> _resolveOutputTensors(Interpreter interpreter) {
    final outputs = <int, Tensor>{};
    try {
      outputs[0] = interpreter.getOutputTensor(0);
    } catch (_) {
      return outputs;
    }
    try {
      outputs[1] = interpreter.getOutputTensor(1);
    } catch (_) {}
    return outputs;
  }

  _AllocatedOutputBuffers _allocateOutputBuffers(
      Map<int, Tensor> outputTensors) {
    final shaped = <int, Object>{};
    final raw = <int, List>{};
    outputTensors.forEach((index, tensor) {
      final buffer = _allocateOutputBuffer(tensor);
      if (buffer != null) {
        raw[index] = buffer;
        shaped[index] = buffer.reshape(tensor.shape);
      }
    });
    return _AllocatedOutputBuffers(shaped: shaped, raw: raw);
  }

  _LetterboxResult _letterbox(
    img.Image image, {
    required int inputWidth,
    required int inputHeight,
  }) {
    final scale = math.min(
      inputWidth / image.width,
      inputHeight / image.height,
    );
    final newW = (image.width * scale).round();
    final newH = (image.height * scale).round();
    final resized = img.copyResize(
      image,
      width: newW,
      height: newH,
      interpolation: img.Interpolation.linear,
    );
    final padX = ((inputWidth - newW) / 2).floor();
    final padY = ((inputHeight - newH) / 2).floor();
    
    // 优化：使用 fill 填充背景色，然后复制图像
    final padded = img.Image(
      width: inputWidth,
      height: inputHeight,
      numChannels: 3,
    );
    
    // 使用 fill 方法填充背景（比双层循环快很多）
    img.fill(padded, color: img.ColorRgb8(114, 114, 114));
    
    // 使用 compositeImage 复制图像（比逐像素复制快）
    img.compositeImage(
      padded,
      resized,
      dstX: padX,
      dstY: padY,
    );
    
    return _LetterboxResult(
      image: padded,
      scale: scale,
      padX: padX,
      padY: padY,
      newWidth: newW,
      newHeight: newH,
    );
  }

  img.Image _cropLetterbox(img.Image mask, _LetterboxResult letterbox) {
    final x = letterbox.padX.clamp(0, mask.width - 1);
    final y = letterbox.padY.clamp(0, mask.height - 1);
    final w = letterbox.newWidth.clamp(1, mask.width - x);
    final h = letterbox.newHeight.clamp(1, mask.height - y);
    return img.copyCrop(mask, x: x, y: y, width: w, height: h);
  }

  _OutputSelection _selectOutputTensors(Map<int, Tensor> outputTensors) {
    var detIndex = outputTensors.keys.first;
    int? protoIndex;
    for (final entry in outputTensors.entries) {
      final shape = entry.value.shape;
      final maskDim = _inferMaskDim(shape);
      if (maskDim != null && (shape.length == 4 || shape.length == 3)) {
        protoIndex = entry.key;
        continue;
      }
      if (shape.length == 3 && shape.any((dim) => dim >= 6)) {
        detIndex = entry.key;
      }
    }
    if (protoIndex == detIndex) {
      protoIndex = null;
    }
    return _OutputSelection(detIndex: detIndex, protoIndex: protoIndex);
  }

  _YoloCandidate? _parseBestCandidate(
    List outputBuffer,
    Tensor outputTensor,
    List<int> outputShape,
    double originalWidth,
    double originalHeight,
    int inputWidth,
    int inputHeight,
    int? maskDim,
    _LetterboxResult letterbox,
  ) {
    var data = outputBuffer;
    final params = outputTensor.params;
    final scale = params.scale;
    final zeroPoint = params.zeroPoint;
    final candidates = <_YoloCandidate>[];
    final layout = _resolveOutputLayout(outputShape);
    if (layout == null) return null;
    final rowCount = layout.rowCount;
    final colCount = layout.colCount;
    var isNbyC = layout.isNbyC;
    if (!isNbyC) {
      data = _transposeOutputBuffer(data, rowCount, colCount);
      isNbyC = true;
    }
    for (var i = 0; i < rowCount; i++) {
      final cx = _readOutputValue(
        data,
        _indexAt(i, 0, rowCount, colCount, isNbyC),
        outputTensor.type,
        scale,
        zeroPoint,
      );
      final cy = _readOutputValue(
        data,
        _indexAt(i, 1, rowCount, colCount, isNbyC),
        outputTensor.type,
        scale,
        zeroPoint,
      );
      final w = _readOutputValue(
        data,
        _indexAt(i, 2, rowCount, colCount, isNbyC),
        outputTensor.type,
        scale,
        zeroPoint,
      );
      final h = _readOutputValue(
        data,
        _indexAt(i, 3, rowCount, colCount, isNbyC),
        outputTensor.type,
        scale,
        zeroPoint,
      );
      final parsed = _readScoreAndClass(
        data,
        i,
        rowCount,
        colCount,
        isNbyC,
        outputTensor.type,
        scale,
        zeroPoint,
        maskDim,
      );
      if (parsed == null) continue;
      if (parsed.score < _scoreThreshold) continue;
      final classCount =
          maskDim != null ? colCount - maskDim - 4 : colCount - 5;
      // 如果是多类别模型，只保留目标类别
      if (classCount > 1 &&
          !_enableAllClasses &&
          !_targetClassIds.contains(parsed.classId)) {
        continue;
      }
      final normalized = cx <= 1.5 && cy <= 1.5 && w <= 1.5 && h <= 1.5;
      final boxCx = normalized ? cx * inputWidth : cx;
      final boxCy = normalized ? cy * inputHeight : cy;
      final boxW = normalized ? w * inputWidth : w;
      final boxH = normalized ? h * inputHeight : h;
      final left = (boxCx - boxW / 2 - letterbox.padX) / letterbox.scale;
      final top = (boxCy - boxH / 2 - letterbox.padY) / letterbox.scale;
      final right = (boxCx + boxW / 2 - letterbox.padX) / letterbox.scale;
      final bottom = (boxCy + boxH / 2 - letterbox.padY) / letterbox.scale;
      final clamped = Rect.fromLTRB(
        left.clamp(0, originalWidth),
        top.clamp(0, originalHeight),
        right.clamp(0, originalWidth),
        bottom.clamp(0, originalHeight),
      );
      Float32List? maskCoefficients;
      if (maskDim != null && parsed.coeffStart >= 0) {
        final coeffs = Float32List(maskDim);
        for (var m = 0; m < maskDim; m++) {
          coeffs[m] = _readOutputValue(
            data,
            _indexAt(
              i,
              parsed.coeffStart + m,
              rowCount,
              colCount,
              isNbyC,
            ),
            outputTensor.type,
            scale,
            zeroPoint,
          ).toDouble();
        }
        maskCoefficients = coeffs;
      }
      candidates.add(_YoloCandidate(
        rect: clamped,
        score: parsed.score,
        classId: parsed.classId,
        maskCoefficients: maskCoefficients,
      ));
    }
    if (candidates.isEmpty) return null;
    final kept = _nmsCandidates(candidates, iouThreshold: 0.7, maxDet: 300);
    if (kept.isEmpty) return null;
    kept.sort((a, b) => b.score.compareTo(a.score));
    return kept.first;
  }

  double _readOutputValue(
    List data,
    int index,
    TensorType type,
    double scale,
    int zeroPoint,
  ) {
    final raw = data[index] as num;
    if (_isFloat16(type)) {
      return _float16ToFloat32(raw.toInt());
    }
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

  List _transposeOutputBuffer(List data, int rowCount, int colCount) {
    final size = rowCount * colCount;
    if (data is Float32List) {
      final out = Float32List(size);
      for (var r = 0; r < rowCount; r++) {
        for (var c = 0; c < colCount; c++) {
          out[r * colCount + c] = data[c * rowCount + r];
        }
      }
      return out;
    }
    if (data is Int8List) {
      final out = Int8List(size);
      for (var r = 0; r < rowCount; r++) {
        for (var c = 0; c < colCount; c++) {
          out[r * colCount + c] = data[c * rowCount + r];
        }
      }
      return out;
    }
    if (data is Uint8List) {
      final out = Uint8List(size);
      for (var r = 0; r < rowCount; r++) {
        for (var c = 0; c < colCount; c++) {
          out[r * colCount + c] = data[c * rowCount + r];
        }
      }
      return out;
    }
    if (data is Uint16List) {
      final out = Uint16List(size);
      for (var r = 0; r < rowCount; r++) {
        for (var c = 0; c < colCount; c++) {
          out[r * colCount + c] = data[c * rowCount + r];
        }
      }
      return out;
    }
    final out = List<num>.filled(size, 0);
    for (var r = 0; r < rowCount; r++) {
      for (var c = 0; c < colCount; c++) {
        out[r * colCount + c] = data[c * rowCount + r] as num;
      }
    }
    return out;
  }

  _OutputLayout? _resolveOutputLayout(List<int> outputShape) {
    if (outputShape.length == 3) {
      final dim1 = outputShape[1];
      final dim2 = outputShape[2];
      if (dim1 < 6 && dim2 < 6) return null;
      if (dim1 <= dim2) {
        return _OutputLayout(rowCount: dim2, colCount: dim1, isNbyC: false);
      }
      return _OutputLayout(rowCount: dim1, colCount: dim2, isNbyC: true);
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
    int? maskDim,
  ) {
    if (maskDim != null) {
      const classStart = 4;
      final classEnd = colCount - maskDim;
      if (classEnd > classStart) {
        const objScore = 1.0;
        return _readClassScores(
          data,
          row,
          rowCount,
          colCount,
          isNbyC,
          type,
          scale,
          zeroPoint,
          classStart,
          classEnd,
          objScore,
          coeffStart: classEnd,
        );
      }
      return null;
    }
    if (colCount == 6) {
      final score = _sigmoid(_readOutputValue(
        data,
        _indexAt(row, 4, rowCount, colCount, isNbyC),
        type,
        scale,
        zeroPoint,
      ));
      final classIdValue = _readOutputValue(
        data,
        _indexAt(row, 5, rowCount, colCount, isNbyC),
        type,
        scale,
        zeroPoint,
      );
      return _ScoreClass(
        score: score,
        classId: classIdValue.round(),
        coeffStart: -1,
      );
    }
    final hasObj = colCount == 85 || (colCount - 5 == 80 && colCount > 6);
    final classStart = hasObj ? 5 : 4;
    final objScore = hasObj
        ? _sigmoid(_readOutputValue(
            data,
            _indexAt(row, 4, rowCount, colCount, isNbyC),
            type,
            scale,
            zeroPoint,
          ))
        : 1.0;
    return _readClassScores(
      data,
      row,
      rowCount,
      colCount,
      isNbyC,
      type,
      scale,
      zeroPoint,
      classStart,
      colCount,
      objScore,
      coeffStart: -1,
    );
  }

  _ScoreClass? _readClassScores(
    List data,
    int row,
    int rowCount,
    int colCount,
    bool isNbyC,
    TensorType type,
    double scale,
    int zeroPoint,
    int classStart,
    int classEnd,
    double objScore, {
    required int coeffStart,
  }) {
    var bestProb = 0.0;
    var bestClass = -1;
    for (var c = classStart; c < classEnd; c++) {
      final prob = _sigmoid(_readOutputValue(
        data,
        _indexAt(row, c, rowCount, colCount, isNbyC),
        type,
        scale,
        zeroPoint,
      ));
      if (prob > bestProb) {
        bestProb = prob;
        bestClass = c - classStart;
      }
    }
    if (bestClass < 0) return null;
    return _ScoreClass(
      score: objScore * bestProb,
      classId: bestClass,
      coeffStart: coeffStart,
    );
  }

  int _resolveInputHeight(List<int> inputShape) {
    if (inputShape.length == 4) {
      final dim1 = inputShape[1];
      final dim3 = inputShape[3];
      if (dim3 == 3) return dim1;
      if (dim1 == 3) return inputShape[2];
    }
    return _fallbackInputSize;
  }

  int _resolveInputWidth(List<int> inputShape) {
    if (inputShape.length == 4) {
      final dim1 = inputShape[1];
      final dim3 = inputShape[3];
      if (dim3 == 3) return inputShape[2];
      if (dim1 == 3) return inputShape[3];
    }
    return _fallbackInputSize;
  }

  int? _inferMaskDim(List<int> protoShape) {
    if (protoShape.isEmpty) return null;
    final candidates = List<int>.from(protoShape);
    candidates.sort();
    for (final value in candidates) {
      if (value > 1 && value <= 64) return value;
    }
    return null;
  }

  int _indexAt(int row, int col, int rowCount, int colCount, bool isNbyC) {
    if (isNbyC) {
      return row * colCount + col;
    }
    return col * rowCount + row;
  }

  double _sigmoid(double x) {
    return 1.0 / (1.0 + math.exp(-x));
  }

  List<_YoloCandidate> _nmsCandidates(
    List<_YoloCandidate> candidates, {
    required double iouThreshold,
    required int maxDet,
  }) {
    final sorted = List<_YoloCandidate>.from(candidates)
      ..sort((a, b) => b.score.compareTo(a.score));
    final kept = <_YoloCandidate>[];
    for (final cand in sorted) {
      var keep = true;
      for (final prev in kept) {
        if (_iou(cand.rect, prev.rect) > iouThreshold) {
          keep = false;
          break;
        }
      }
      if (keep) {
        kept.add(cand);
        if (kept.length >= maxDet) break;
      }
    }
    return kept;
  }

  double _iou(Rect a, Rect b) {
    final left = math.max(a.left, b.left);
    final top = math.max(a.top, b.top);
    final right = math.min(a.right, b.right);
    final bottom = math.min(a.bottom, b.bottom);
    final w = (right - left).clamp(0, double.infinity);
    final h = (bottom - top).clamp(0, double.infinity);
    if (w == 0 || h == 0) return 0.0;
    final intersection = w * h;
    final union = a.width * a.height + b.width * b.height - intersection;
    if (union <= 0) return 0.0;
    return intersection / union;
  }
}

class _AllocatedOutputBuffers {
  const _AllocatedOutputBuffers({required this.shaped, required this.raw});

  final Map<int, Object> shaped;
  final Map<int, List> raw;
}

class _OutputSelection {
  const _OutputSelection({required this.detIndex, required this.protoIndex});

  final int detIndex;
  final int? protoIndex;
}

class _LetterboxResult {
  const _LetterboxResult({
    required this.image,
    required this.scale,
    required this.padX,
    required this.padY,
    required this.newWidth,
    required this.newHeight,
  });

  final img.Image image;
  final double scale;
  final int padX;
  final int padY;
  final int newWidth;
  final int newHeight;
}

class _ProtoLayout {
  const _ProtoLayout({
    required this.maskDim,
    required this.maskHeight,
    required this.maskWidth,
    required this.isCHW,
  });

  final int maskDim;
  final int maskHeight;
  final int maskWidth;
  final bool isCHW;
}

class _YoloCandidate {
  const _YoloCandidate({
    required this.rect,
    required this.score,
    required this.classId,
    required this.maskCoefficients,
  });

  final Rect rect;
  final double score;
  final int classId;
  final Float32List? maskCoefficients;
}

_ProtoLayout? _resolveProtoLayout(List<int> protoShape, int maskDim) {
  if (protoShape.length == 4) {
    if (protoShape[1] == maskDim) {
      return _ProtoLayout(
        maskDim: maskDim,
        maskHeight: protoShape[2],
        maskWidth: protoShape[3],
        isCHW: true,
      );
    }
    if (protoShape[3] == maskDim) {
      return _ProtoLayout(
        maskDim: maskDim,
        maskHeight: protoShape[1],
        maskWidth: protoShape[2],
        isCHW: false,
      );
    }
    return null;
  }
  if (protoShape.length == 3) {
    if (protoShape[0] == maskDim) {
      return _ProtoLayout(
        maskDim: maskDim,
        maskHeight: protoShape[1],
        maskWidth: protoShape[2],
        isCHW: true,
      );
    }
    if (protoShape[2] == maskDim) {
      return _ProtoLayout(
        maskDim: maskDim,
        maskHeight: protoShape[0],
        maskWidth: protoShape[1],
        isCHW: false,
      );
    }
    return null;
  }
  return null;
}

img.Image _decodeMaskProto(
  List protoBuffer,
  Tensor protoTensor,
  _ProtoLayout layout,
  Float32List coefficients,
) {
  final params = protoTensor.params;
  final scale = params.scale;
  final zeroPoint = params.zeroPoint;
  final mask = img.Image(
    width: layout.maskWidth,
    height: layout.maskHeight,
    numChannels: 4,
  );
  final pixelCount = layout.maskHeight * layout.maskWidth;
  for (var i = 0; i < pixelCount; i++) {
    final y = i ~/ layout.maskWidth;
    final x = i - y * layout.maskWidth;
    var sum = 0.0;
    for (var c = 0; c < layout.maskDim; c++) {
      final protoIndex = layout.isCHW
          ? c * pixelCount + i
          : (y * layout.maskWidth + x) * layout.maskDim + c;
      final v = (protoBuffer[protoIndex] as num);
      final value = _isFloat16(protoTensor.type)
          ? _float16ToFloat32(v.toInt())
          : (protoTensor.type == TensorType.float32
              ? v.toDouble()
              : (v - zeroPoint) * scale);
      sum += coefficients[c] * value;
    }
    final prob = 1.0 / (1.0 + math.exp(-sum));
    final alpha = (prob * 255).round().clamp(0, 255);
    mask.setPixelRgba(x, y, 0, 0, 0, alpha);
  }
  return mask;
}

bool _isFloat16(TensorType type) => type.toString() == 'TensorType.float16';

int _float32ToFloat16(double value) {
  final bd = ByteData(4)..setFloat32(0, value, Endian.little);
  final f = bd.getUint32(0, Endian.little);
  final sign = (f >> 16) & 0x8000;
  var exp = ((f >> 23) & 0xff) - 127 + 15;
  var mantissa = f & 0x7fffff;
  if (exp <= 0) {
    if (exp < -10) return sign;
    mantissa = (mantissa | 0x800000) >> (1 - exp);
    return sign | ((mantissa + 0x1000) >> 13);
  }
  if (exp >= 31) {
    return sign | 0x7c00;
  }
  return sign | (exp << 10) | ((mantissa + 0x1000) >> 13);
}

double _float16ToFloat32(int h) {
  final sign = (h & 0x8000) << 16;
  var exp = (h >> 10) & 0x1f;
  var mantissa = h & 0x3ff;
  int f;
  if (exp == 0) {
    if (mantissa == 0) {
      f = sign;
    } else {
      exp = 1;
      while ((mantissa & 0x400) == 0) {
        mantissa <<= 1;
        exp--;
      }
      mantissa &= 0x3ff;
      final exp32 = exp - 15 + 127;
      f = sign | (exp32 << 23) | (mantissa << 13);
    }
  } else if (exp == 31) {
    f = sign | 0x7f800000 | (mantissa << 13);
  } else {
    final exp32 = exp - 15 + 127;
    f = sign | (exp32 << 23) | (mantissa << 13);
  }
  final bd = ByteData(4)..setUint32(0, f, Endian.little);
  return bd.getFloat32(0, Endian.little).toDouble();
}

void _applyBboxToMask(img.Image? mask, Rect rect) {
  if (mask == null) return;
  final left = rect.left.floor().clamp(0, mask.width - 1);
  final top = rect.top.floor().clamp(0, mask.height - 1);
  final right = rect.right.ceil().clamp(0, mask.width);
  final bottom = rect.bottom.ceil().clamp(0, mask.height);
  for (var y = 0; y < mask.height; y++) {
    for (var x = 0; x < mask.width; x++) {
      final inside = x >= left && x < right && y >= top && y < bottom;
      if (inside) continue;
      final p = mask.getPixel(x, y);
      if (p.a == 0) continue;
      mask.setPixelRgba(x, y, p.r, p.g, p.b, 0);
    }
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
  const _ScoreClass({
    required this.score,
    required this.classId,
    required this.coeffStart,
  });

  final double score;
  final int classId;
  final int coeffStart;
}
