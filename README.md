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

### ONNX Runtime 支持（NPU：NNAPI）
- 将 ONNX Runtime 头文件与库放置在：
  - 头文件：`android_deploy/third_party/onnxruntime/include/`
  - 库文件：`android_deploy/third_party/onnxruntime/lib/arm64-v8a/`
    - 必需：`libonnxruntime.so`
    - 建议：`libonnxruntime_providers_shared.so`
    - 可选（NNAPI EP）：`libonnxruntime_providers_nnapi.so`
    

#### 运行选项（ONNX 路径）
- `--delegate nnapi`：启用 NNAPI EP 加速，自动将支持的算子下发到 NPU，其他回退 CPU。
- 程序会打印 `available_providers=...` 以展示当前会话可用 EP 列表。

#### Profiling 与算子 Provider 映射
- 已在代码中启用 ORT profiling，运行后会打印 `profile_path=ort_profile_YYYY-MM-DD_HH-MM-SS.json` 并将文件保存在设备运行目录。
- Profiling 文件包含每个节点的执行信息，其中 `provider` 字段指示算子归属（如 `NnapiExecutionProvider` / `CPUExecutionProvider`）。
- 我们在程序运行后解析并打印 `op_provider <op> <provider>`，便于快速确认算子加速情况（也可将 profiling 拉回主机自行解析）。

## 构建
- 一键交叉编译：
  - `bash android_deploy/build_android.sh`
  - 自动检测设备 API（推荐 29+），生成可执行：`android_deploy/build/android/arm64-v8a/yolo_runner`

## 设备运行
- 推送并运行（示例采用 `android_deploy/models` 中的模型）：
  - NNAPI（ONNX）：`./android_deploy/run_on_device.sh --model-host-path android_deploy/models/model.onnx --image-host-path /path/to/image.jpg --delegate nnapi`
- 说明：
  - 非 BMP 图片将自动用 `sips` 转为 24-bit BMP
  - 结果回拉到 `android_deploy/output_pull`（包含 `output_*.bin` 与 `output_*.shape.txt`）

## NNAPI/NPU
- 通过 `--delegate nnapi` 启用 NNAPI；设备支持的算子将下发到 NPU，不支持的自动回退 CPU
- 如需设备日志验证：
  - `adb logcat -c`
  - 运行推理
  - `adb logcat -d | grep -i -E 'nnapi|neuralnetworks|ANEURALNETWORKS'`

 

 

## 模型归档
- 将模型统一放在 `android_deploy/models/` 目录，例如：
  - `android_deploy/models/model.onnx`
  - 按需放置 `labels.txt`

## 参数摘要
- `--delegate {cpu|nnapi}`：选择推理/加速后端

## 第三方依赖自动拉取
- 构建脚本会尝试自动拉取依赖：`android_deploy/scripts/fetch_thirdparty.sh`
- 可选环境变量：
  - `ORT_VER`/`ORT_ANDROID_AAR_URL`/`ORT_HEADERS_TGZ_URL` 控制 ONNX Runtime 版本与下载源
  - `TFLITE_AAR_URL`/`TFLITE_HEADERS_ZIP_URL` 控制 TFLite AAR 与头文件下载源
  - 若未配置，将尝试默认 ORT 地址；TFLite 需手动提供或配置 URL

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

## 清理与忽略
- 构建与运行产物：
  - 执行清理前已删除：`android_deploy/build/android/`、`android_deploy/output_pull/`、`android_deploy/.tmp/`、`android_deploy/.tmp_input.bmp`
  - `.gitignore` 已添加忽略：`build/`、`output_pull/`、`.tmp/`、`.tmp_input.bmp`、`ort_profile_*.json`、`device_logs.txt`、`output/`、`*.bin`、`*.shape.txt`、`*.quant.txt`、`annotated.bmp`

## 备注
- 当前可执行支持 C API（集成到二进制）与 C++ Interpreter 两种路径；运行脚本会自动推送所需 `.so` 并设置 `LD_LIBRARY_PATH`
- 若 NNAPI 日志为空，可能为模型算子未被 NNAPI 后端支持；可使用官方 Mobilenet TFLite 模型进行二次验证
