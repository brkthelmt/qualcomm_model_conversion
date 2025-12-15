# Android TFLite YOLO 部署（vivo v1955a）

## 环境准备
- 安装并设置 `ANDROID_NDK` 或使用 `--ndk` 参数指向 NDK 路径
- 确保 `adb` 可用，设备已连接且允许调试
- 第三方依赖通过脚本自动拉取，无需手工放置：
  - ONNX Runtime：AAR（MavenCentral）与头文件（GitHub Release）；额外拉取 `nnapi_provider_factory.h`
  - TFLite：AAR（MavenCentral）提取 `libtensorflowlite_jni.so` 与 C API 头；不需要 `libtensorflowlite.so`
  - FlatBuffers：优先使用本机系统头（如 `/opt/homebrew/include/flatbuffers`），否则自动从 GitHub 拉取头文件

### ONNX Runtime 支持（NPU：NNAPI）
- 自动拉取后目录结构：
  - 头文件：`android_deploy/third_party/onnxruntime/include/`（含 `onnxruntime_*.h` 与 `nnapi_provider_factory.h`）
  - 库文件：`android_deploy/third_party/onnxruntime/lib/arm64-v8a/`（AAR 提供 `libonnxruntime.so`）
  - 说明：部分 AAR 不再包含 `libonnxruntime_providers_nnapi.so` 与 `libonnxruntime_providers_shared.so`，若存在将自动推送；否则按工厂函数注册即可
    

#### 运行选项（ONNX 路径）
- `--delegate nnapi`：启用 NNAPI EP，加速可支持算子，其余自动回退 CPU。
- 工厂函数注册：项目使用 `OrtSessionOptionsAppendExecutionProvider_Nnapi(so, 0)` 注册 NNAPI，稳定形成混合分区（NNAPI+CPU）。
- 图优化：默认启用 `ORT_ENABLE_EXTENDED`，以获得更好的分区与性能。若需对齐原始图做分析，可临时切换 `ORT_DISABLE_ALL`。

#### Profiling 与算子 Provider 映射
- 已启用 ORT profiling，运行后会打印 `profile_path=ort_profile_*.json` 并回拉到本机 `output_pull/`。
- Profiling 文件中 `provider` 字段指示算子归属；默认优化开启时会产生聚合节点（如 `Nnapi_...`），与原始图不一一对应属正常现象。
- 程序打印 `op_provider <op> <provider>` 以快速确认分区命中；也可直接解析 profiling JSON 获取 provider 统计。

## 构建
- 一键交叉编译：`bash android_deploy/build_android.sh`
- 自动拉取 third_party 并生成可执行：`android_deploy/build/android/arm64-v8a/yolo_runner`

## 设备运行
- 推送并运行（示例采用 `android_deploy/models` 中的模型）：
  - ONNX + NNAPI：`./android_deploy/run_on_device.sh --model-host-path android_deploy/models/yolov8s_ir10.onnx --image-host-path android_deploy/sample.jpg --delegate nnapi`
  - TFLite + NNAPI：`./android_deploy/run_on_device.sh --model-host-path android_deploy/models/yolov7_w8a8.tflite --image-host-path android_deploy/sample.jpg --delegate nnapi`
- 说明：非 BMP 图片将自动转为 24-bit BMP；结果回拉到 `android_deploy/output_pull`（含 `output/` 与 `ort_profile_*.json`）

## NNAPI/NPU
- 通过 `--delegate nnapi` 启用；设备支持的算子下发 NPU，其余回退 CPU。
- 设备日志验证：`adb logcat -d | grep -i -E 'onnxruntime|NNAPI|Nnapi|tflite'`

 

 

## 模型归档
- 模型统一放在 `android_deploy/models/`：仅保留 `.onnx` 与 `.tflite`；其他格式已清理。
- 示例：`yolov8s_ir10.onnx`、`yolov8s.onnx`、`yolov7_w8a8.tflite`、`MobileNet-v3-Small_float.tflite`

## 参数摘要
- `--delegate {cpu|nnapi}`：选择推理/加速后端

## 第三方依赖自动拉取
- 构建脚本自动调用：`android_deploy/scripts/fetch_thirdparty.sh`
- 下载源：
  - ORT AAR：MavenCentral（稳定）
  - ORT 头：GitHub Release（支持 `ghfast.top` 与 `ghproxy` 代理回退）
  - NNAPI 工厂头：GitHub raw（支持代理回退）
  - TFLite AAR：MavenCentral
  - FlatBuffers 头：优先使用系统头，否则从 GitHub 拉取

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
- `.gitignore` 已包含：`build/`、`output_pull/`、`logs/`、`.tmp/`、`ort_profile_*.json`、`output/`、二进制输出与中间图像
- 忽略自动拉取的库与临时头：`third_party/onnxruntime/lib/`、`third_party/tflite/lib/`、`third_party/tflite/include/headers/`、`/_tmp_hdr/`、`/_tmp_fb/`

## 备注
- 当前可执行支持 C API（集成到二进制）与 C++ Interpreter 两种路径；运行脚本会自动推送所需 `.so` 并设置 `LD_LIBRARY_PATH`
- 若 NNAPI 日志为空，可能为模型算子未被 NNAPI 后端支持；可使用官方 Mobilenet TFLite 模型进行二次验证

**Shell 脚本用法**
- `build_android.sh`
  - 用途：交叉编译生成 `build/android/<ABI>/yolo_runner`
  - 选项：`--abi <arm64-v8a|armeabi-v7a>`、`--ndk <path>`、`--api <level>`
  - 示例：`bash build_android.sh --ndk ~/Library/Android/sdk/ndk/<ver> --api 29`
- `scripts/fetch_thirdparty.sh`
  - 用途：拉取 TFLite 与 ONNX Runtime 依赖到 `third_party/`
  - 选项：`--abi <arm64-v8a|...>`
  - 示例：`bash scripts/fetch_thirdparty.sh --abi arm64-v8a`
- `run_on_device.sh`
  - 用途：构建、推送到设备并运行模型，回拉输出到 `output_pull/`
  - 必选其一：`--image-host-path <path>` 或 `--onnx-inputs-host-dir <dir>`
  - 常用选项：`--model-host-path <file>`、`--delegate <cpu|nnapi>`、`--abi <arm64-v8a>`、`--labels-host-path <file>`、`--stdout-host-path <file>`
  - 示例：`bash run_on_device.sh --model-host-path models/yolov7_w8a8.tflite --image-host-path sample.jpg --delegate nnapi`
- `profile_nnapi.sh`
  - 用途：开启 `atrace` 采集 NNAPI Trace，并运行一次端侧推理
  - 位置参数：`MODEL`、`IMAGE`、`LABELS`（均可选，有默认值）
  - 示例：`bash profile_nnapi.sh models/yolov7_w8a8.tflite sample_multi.jpg labels_coco.names`
- `scripts/fetch_model/run_export.sh`
  - 用途：调用 `qai_hub_models/models/<model>/export.py` 执行导出/编译/下载工件
  - 选项：`--model <id>`、`--repo-dir <path>`、`--venv-dir <dir>`、`--python <path>`、`--requirements <path>`；`--` 之后为传递给 `export.py` 的参数
  - 仓库路径：必须通过 `--repo-dir` 或环境变量 `AIHM_REPO_DIR` 指定本地 `ai-hub-models` 路径；脚本不进行任何仓库克隆/更新。
  - 自动行为：当 `support/model-runtime-precision.csv` 不存在时，自动调用本地生成脚本写入该文件（优先 `scripts/fetch_model/generate_support_table.sh`，否则回退 `scripts/fetch_model/list_model_support.py` 或仓库内脚本），不触发下载。
  - 示例：`bash scripts/fetch_model/run_export.sh --model beit --repo-dir /data/ai-hub-models -- --target_runtime onnx --precision float`
- `scripts/fetch_model/generate_support_table.sh`
  - 用途：生成模型-精度-运行时支持表（CSV）
  - 选项：`--repo-url <url>`、`--branch <name>`、`--output <path>`、`--repo-dir <path>`、`--clone-dir <name>`、`--list-script <path>`
  - 示例：`bash scripts/fetch_model/generate_support_table.sh --output support/model-runtime-precision.csv`
- `scripts/fetch_model/generate_support_model.sh`
  - 用途：针对单模型列出或批量拉取所有支持组合的工件
  - 选项：`--model-id <id>`、`--action <list|fetch>`、`--repo-dir <path>`、`--output-dir <dir>`、`--runtime-filter <r1,r2>`、`--precision-filter <p1,p2>`、`--unzip`
  - 示例（列出）：`bash scripts/fetch_model/generate_support_model.sh --model-id beit --action list`
  - 示例（拉取）：`bash scripts/fetch_model/generate_support_model.sh --model-id beit --action fetch --unzip`
- `qai_chain_run.sh`
  - 用途：串联导出与端侧运行，自动拉取工件并调用 `run_on_device.sh`
  - 选项：`--model-id <id>`、`--model-format <onnx|tflite>`、`--do-export`、`--image-host-path <path>`、`--onnx-inputs-host-dir <dir>`、`--labels-host-path <path>`、`--delegate <cpu|nnapi>`、`--abi <abi>`、`--stdout-host-path <file>`；`--` 之后为传递给 `export.py` 的参数
  - 示例：`bash qai_chain_run.sh --model-id beit --model-format onnx --do-export -- --target_runtime onnx --precision float --image-host-path sample.jpg`

**环境变量（可选）**
- `AIHM_REPO_DIR`：指定 `ai-hub-models` 仓库本地路径，且必须包含 `qai_hub_models/models`；脚本不会进行任何克隆/拉取。
- `TMPDIR`：不再用于自动克隆仓库，仅作为一般临时文件路径。
