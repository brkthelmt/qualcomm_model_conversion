# Android TFLite YOLO 部署（vivo v1955a）

## 环境准备
- 安装并设置 `ANDROID_NDK` 或使用 `--ndk` 参数指向 NDK 路径
- 确保 `adb` 可用，设备已连接且允许调试
- 将 TFLite 头文件与库放置在：
  - 头文件：`android_deploy/third_party/tflite/include/tensorflow/lite/...`
  - 库文件：`android_deploy/third_party/tflite/lib/arm64-v8a/`
    - 必需：`libtensorflowlite.so`
    - 可选（C API）：`libtensorflowlite_c.so`
    - 可选（NNAPI delegate 动态库）：`libtensorflowlite_nnapi_delegate.so`

### ONNX Runtime 支持（NPU：NNAPI/QNN）
- 将 ONNX Runtime 头文件与库放置在：
  - 头文件：`android_deploy/third_party/onnxruntime/include/`
  - 库文件：`android_deploy/third_party/onnxruntime/lib/arm64-v8a/`
    - 必需：`libonnxruntime.so`
    - 建议：`libonnxruntime_providers_shared.so`
    - 可选（NNAPI EP）：`libonnxruntime_providers_nnapi.so`
    - 可选（QNN EP）：`libonnxruntime_providers_qnn.so`
  - 若使用 QNN（Qualcomm HTP/NPU），设备需具备 QAIRT/QNN 运行库（例如 `libQnnHtp.so` 及相关 skel 等）；请将其置于设备可加载目录或通过脚本推送到运行目录并设置 `LD_LIBRARY_PATH`

## 构建
- 一键交叉编译：
  - `bash android_deploy/build_android.sh`
  - 自动检测设备 API（推荐 29+），生成可执行：`android_deploy/build/android/arm64-v8a/yolo_runner`

## 设备运行
- 推送并运行（示例采用 `android_deploy/models` 中的模型）：
  - NNAPI（ONNX）：`./android_deploy/run_on_device.sh --model-host-path android_deploy/models/model.onnx --image-host-path /path/to/image.jpg --delegate nnapi`
  - QNN（原生 C API + w8a8 上下文）：`./android_deploy/run_on_device.sh --model-host-path android_deploy/models/model.onnx --image-host-path /path/to/image.jpg --delegate qnn --qnn-context-host-path android_deploy/models/yolov7_w8a8.bin --qnn-lib-dir-host "<QNN_SDK_ROOT>/lib/aarch64-android"`
    - 需确保设备运行目录包含 QAIRT/QNN 库（如 `libQnnHtp.so`），或通过 `--qnn-lib-dir-host` 推送
- 说明：
  - 非 BMP 图片将自动用 `sips` 转为 24-bit BMP
  - 结果回拉到 `android_deploy/output_pull`（包含 `output_*.bin` 与 `output_*.shape.txt`）

## NNAPI/NPU
- 通过 `--delegate nnapi` 启用 NNAPI；设备支持的算子将下发到 NPU，不支持的自动回退 CPU
- 如需设备日志验证：
  - `adb logcat -c`
  - 运行推理
  - `adb logcat -d | grep -i -E 'nnapi|neuralnetworks|ANEURALNETWORKS'`

### QNN（Qualcomm NPU/HTP）
- 通过 `--delegate qnn` 启用 ONNX Runtime 的 QNN EP（若已打包 provider 与 QAIRT 库）
- 默认 provider 选项：`backend_path=libQnnHtp.so`、`htp_performance_mode=burst`、`qnn_context_priority=high`、`enable_htp_shared_memory_allocator=1`
- 设备需为骁龙平台（例如 Snapdragon 865/SM8250），并安装匹配版本的 QAIRT/QNN 运行库

## 原生 QNN C API（推荐在片上加载 w8a8 context）
- 运行入口：当传入 `--delegate qnn` 且提供 `--qnn-context` 时，程序走原生 QNN C API 路径（`qnn_runner.cpp`）。
- SDK 配置：
  - 设置环境变量 `QNN_SDK_ROOT` 指向 QAIRT/QNN SDK 根目录（包含 `include/QNN/*.h` 与 `lib/aarch64-android/*.so` 或 `lib/arm64-v8a/*.so`）
  - 工程会在构建时条件链接 `libQnnHtp.so` 与 `libQnnSystem.so`
- 设备推送：
  - `./android_deploy/run_on_device.sh --model-host-path <your.onnx> --image-host-path <image> --delegate qnn --qnn-context-host-path ./android_deploy/yolov7_w8a8.bin --qnn-lib-dir-host "<QNN_SDK_ROOT>/lib/aarch64-android"`
  - 脚本会推送 `qnn_context.bin` 与 `libQnn*.so` 到 `/data/local/tmp/yolo_run` 并设置 `LD_LIBRARY_PATH`

## 模型归档
- 将模型与上下文文件统一放在 `android_deploy/models/` 目录，例如：
  - `android_deploy/models/model.onnx`
  - `android_deploy/models/yolov7_w8a8.bin`
  - 按需放置 `labels.txt`

## 参数摘要
- `--delegate {cpu|nnapi|qnn}`：选择推理/加速后端
- `--qnn-context <path>`：原生 QNN 路径下加载的 context 二进制（设备端文件名为 `qnn_context.bin`）
- `--qnn-lib-dir-host <dir>`：本机 QNN `.so` 库所在目录，推送到设备运行目录并设置 `LD_LIBRARY_PATH`

## 常用命令
- 指定 NDK 与 API：
  - `bash android_deploy/build_android.sh --ndk /Users/<you>/Library/Android/sdk/ndk/26.1.10909125 --api 29`
- 手动推送运行：
  - `adb shell mkdir -p /data/local/tmp/yolo_run`
  - `adb push android_deploy/build/android/arm64-v8a/yolo_runner /data/local/tmp/yolo_run/`
  - `adb push /path/to/model.tflite /data/local/tmp/yolo_run/model.tflite`
  - `adb push /path/to/image.bmp /data/local/tmp/yolo_run/image.bmp`
  - `adb shell 'cd /data/local/tmp/yolo_run && chmod +x yolo_runner && LD_LIBRARY_PATH=/data/local/tmp/yolo_run ./yolo_runner --model model.tflite --image image.bmp --output output --delegate nnapi'`
  - `adb pull /data/local/tmp/yolo_run/output android_deploy/output_pull`

## 备注
- 当前可执行支持 C API（集成到二进制）与 C++ Interpreter 两种路径；运行脚本会自动推送所需 `.so` 并设置 `LD_LIBRARY_PATH`
- 若 NNAPI 日志为空，可能为模型算子未被 NNAPI 后端支持；可使用官方 Mobilenet TFLite 模型进行二次验证
