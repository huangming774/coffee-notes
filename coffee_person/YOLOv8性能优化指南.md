# 🚀 YOLOv8 性能优化指南

## 当前配置

```dart
YoloDetectionService(threads: 2)  // 当前使用 2 个线程
```

---

## 优化方案对比

### 方案 1: 增加 CPU 线程数 ⭐ 推荐

**优点**：
- ✅ 简单，只需改一行代码
- ✅ 兼容性好，所有设备都支持
- ✅ 稳定可靠

**缺点**：
- ⚠️ 提升有限（2-3倍）
- ⚠️ 耗电增加

**实现**：
```dart
// 在 detection_service.dart 第 95 行附近
int _threads = 4;  // 从 2 改为 4
```

**预期效果**：
- 2 线程：~1.5-2 秒
- 4 线程：~0.8-1 秒
- 8 线程：~0.5-0.8 秒（但耗电明显增加）

---

### 方案 2: 使用 GPU 加速 🔥 最快

**优点**：
- ✅ 速度提升巨大（5-10倍）
- ✅ CPU 占用低

**缺点**：
- ❌ Android 需要 GPU delegate
- ❌ 需要额外配置
- ❌ 部分设备不支持
- ❌ 模型可能需要重新导出

**实现步骤**：

#### 1. 添加 GPU delegate 依赖

在 `pubspec.yaml` 中：
```yaml
dependencies:
  tflite_flutter: ^0.11.0
  tflite_flutter_helper: ^0.3.1  # 添加这个
```

#### 2. 修改代码使用 GPU

```dart
Future<void> _loadInterpreter() async {
  try {
    final options = InterpreterOptions()..threads = _threads;
    
    // 尝试使用 GPU
    if (Platform.isAndroid) {
      try {
        final gpuDelegate = GpuDelegateV2(
          options: GpuDelegateOptionsV2(
            isPrecisionLossAllowed: false,
            inferencePreference: TfLiteGpuInferenceUsage.fastSingleAnswer,
            inferencePriority1: TfLiteGpuInferencePriority.minLatency,
            inferencePriority2: TfLiteGpuInferencePriority.auto,
            inferencePriority3: TfLiteGpuInferencePriority.auto,
          ),
        );
        options.addDelegate(gpuDelegate);
      } catch (e) {
        // GPU 不可用，回退到 CPU
      }
    }
    
    _interpreter = await Interpreter.fromAsset(
      _modelAssetPath,
      options: options,
    );
  } catch (_) {
    _interpreter = null;
  }
}
```

**预期效果**：
- CPU (2线程)：~1.5-2 秒
- GPU：~0.2-0.4 秒

---

### 方案 3: 降低输入分辨率 ⚡ 最简单

**优点**：
- ✅ 非常简单
- ✅ 速度提升明显
- ✅ 兼容性好

**缺点**：
- ⚠️ 检测精度略有下降
- ⚠️ 小物体可能检测不到

**实现**：
```dart
// 在 camera_service.dart 中
Future<XFile?> pickFromCamera() {
  return _picker.pickImage(
    source: ImageSource.camera,
    maxWidth: 1024,  // 从 2048 降低到 1024
    imageQuality: 85,
  );
}
```

**预期效果**：
- 2048px：~1.5-2 秒
- 1024px：~0.8-1 秒
- 640px：~0.4-0.6 秒

---

### 方案 4: 使用更小的模型 📦

**优点**：
- ✅ 速度提升巨大
- ✅ 内存占用少

**缺点**：
- ⚠️ 精度下降
- ⚠️ 需要重新导出模型

**模型对比**：
- `yolov8n-seg` (当前)：7MB，~1.5秒
- `yolov8n` (无分割)：6MB，~0.5秒（但没有 mask）
- `yolov5n`：4MB，~0.3秒（但精度较低）

---

## 🎯 推荐方案

### 快速优化（立即可用）

#### 方案 A: 增加线程 + 降低分辨率
```dart
// detection_service.dart
int _threads = 4;  // 增加到 4 线程

// camera_service.dart
maxWidth: 1024,  // 降低到 1024
```

**预期效果**：~0.5-0.8 秒（提升 2-3倍）

---

### 最佳性能（需要配置）

#### 方案 B: GPU + 多线程 + 优化分辨率
```dart
// 1. 使用 GPU delegate
// 2. 4 线程作为备选
// 3. 1024px 输入
```

**预期效果**：~0.2-0.4 秒（提升 5-8倍）

---

## 📝 具体实现代码

### 立即优化（推荐）

修改 `detection_service.dart`：

```dart
// 第 95 行附近
int _threads = 4;  // 从 2 改为 4
```

修改 `camera_service.dart`：

```dart
Future<XFile?> pickFromCamera() {
  return _picker.pickImage(
    source: ImageSource.camera,
    maxWidth: 1024,  // 从 2048 改为 1024
    imageQuality: 85,
  );
}

Future<XFile?> pickFromGallery() {
  return _picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 1024,  // 从 2048 改为 1024
    imageQuality: 85,
  );
}
```

---

### GPU 加速（高级）

创建新文件 `lib/features/stickers/gpu_detection_service.dart`：

```dart
import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';

class GpuDetectionHelper {
  static Future<InterpreterOptions> createOptions({
    required int threads,
    bool enableGpu = true,
  }) async {
    final options = InterpreterOptions()..threads = threads;
    
    if (enableGpu && Platform.isAndroid) {
      try {
        // 尝试使用 GPU
        final gpuDelegate = GpuDelegateV2(
          options: GpuDelegateOptionsV2(
            isPrecisionLossAllowed: false,
            inferencePreference: TfLiteGpuInferenceUsage.fastSingleAnswer,
            inferencePriority1: TfLiteGpuInferencePriority.minLatency,
          ),
        );
        options.addDelegate(gpuDelegate);
      } catch (e) {
        // GPU 不可用，使用 CPU
      }
    }
    
    return options;
  }
}
```

然后在 `detection_service.dart` 中使用：

```dart
Future<void> _loadInterpreter() async {
  try {
    final options = await GpuDetectionHelper.createOptions(
      threads: _threads,
      enableGpu: true,
    );
    
    _interpreter = await Interpreter.fromAsset(
      _modelAssetPath,
      options: options,
    );
  } catch (_) {
    _interpreter = null;
  }
}
```

---

## 📊 性能对比表

| 方案 | 速度 | 精度 | 难度 | 兼容性 |
|------|------|------|------|--------|
| 当前（2线程，2048px） | 1.5-2s | ⭐⭐⭐⭐⭐ | - | ✅ |
| 4线程 | 0.8-1s | ⭐⭐⭐⭐⭐ | ⭐ | ✅ |
| 4线程 + 1024px | 0.5-0.8s | ⭐⭐⭐⭐ | ⭐ | ✅ |
| GPU | 0.2-0.4s | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⚠️ |
| GPU + 1024px | 0.1-0.2s | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⚠️ |

---

## 💡 我的建议

### 第一步：立即优化（5分钟）
```dart
// detection_service.dart
int _threads = 4;

// camera_service.dart  
maxWidth: 1024,
```

### 第二步：测试效果
运行应用，测试检测速度和精度是否满意。

### 第三步：如果还不够快
考虑 GPU 加速（需要额外配置）。

---

## ⚠️ 注意事项

1. **线程数不是越多越好**
   - 4-8 线程是最佳平衡
   - 超过 8 线程反而可能变慢

2. **GPU 加速的限制**
   - 需要设备支持
   - 部分老设备可能不支持
   - iOS 需要使用 Metal delegate

3. **分辨率权衡**
   - 1024px 是很好的平衡点
   - 低于 640px 可能影响检测效果

---

**需要我帮你直接修改代码实现快速优化吗？**


