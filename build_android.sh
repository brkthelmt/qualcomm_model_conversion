#!/usr/bin/env bash
set -euo pipefail

ABI="arm64-v8a"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_API=29

NDK_ROOT="${ANDROID_NDK:-${ANDROID_NDK_HOME:-}}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --abi)
      ABI="$2"; shift 2 ;;
    --ndk)
      NDK_ROOT="$2"; shift 2 ;;
    --api)
      ANDROID_API="$2"; shift 2 ;;
    *)
      shift 1 ;;
  esac
done

if [ -z "${NDK_ROOT}" ]; then
  if [ -d "$HOME/Library/Android/sdk/ndk" ]; then
    NDK_ROOT="$(ls -d "$HOME/Library/Android/sdk/ndk"/* | sort | tail -n 1)"
  elif [ -d "$HOME/Android/Sdk/ndk" ]; then
    NDK_ROOT="$(ls -d "$HOME/Android/Sdk/ndk"/* | sort | tail -n 1)"
  fi
fi

# 拉取 third_party 依赖（可由环境变量配置版本与下载源）
chmod +x "${SCRIPT_DIR}/scripts/fetch_thirdparty.sh"
"${SCRIPT_DIR}/scripts/fetch_thirdparty.sh" --abi "${ABI}" || true

if [ -z "${NDK_ROOT}" ]; then
  echo "ANDROID_NDK 或 ANDROID_NDK_HOME 未设置，且未在常见路径找到 NDK" >&2
  echo "可通过 --ndk /path/to/ndk 指定，或导出 ANDROID_NDK 环境变量" >&2
  exit 1
fi

TFLITE_ROOT="${SCRIPT_DIR}/third_party/tflite"
INC_PATH="${TFLITE_ROOT}/include/tensorflow/lite/interpreter.h"
LIB_A="${TFLITE_ROOT}/lib/${ABI}/libtensorflowlite.a"
LIB_SO="${TFLITE_ROOT}/lib/${ABI}/libtensorflowlite.so"
if [ -z "${DISABLE_TFLITE:-}" ] || [ "${DISABLE_TFLITE}" != "ON" ]; then
  if [ ! -f "${INC_PATH}" ]; then
    echo "缺少 TFLite 头文件: ${INC_PATH}（如需启用 TFLite 源编译，请提供本地 TF 源）" >&2
  fi
  if [ ! -f "${LIB_A}" ] && [ ! -f "${LIB_SO}" ]; then
    echo "缺少 TFLite 预编译库: ${LIB_A}/${LIB_SO}（已支持从 MavenCentral 自动拉取 AAR）" >&2
  fi
fi

BUILD_DIR="${SCRIPT_DIR}/build/android/${ABI}"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# 自动检测设备 API 级别
if command -v adb >/dev/null 2>&1; then
  if adb get-state >/dev/null 2>&1; then
    DEVICE_SDK="$(adb shell getprop ro.build.version.sdk | tr -d '\r')"
    if [[ "${DEVICE_SDK}" =~ ^[0-9]+$ ]]; then
      ANDROID_API="${DEVICE_SDK}"
    fi
  fi
fi

# 约束范围，NNAPI 需 API>=27，推荐 29+
if [ "${ANDROID_API}" -lt 27 ]; then ANDROID_API=27; fi
if [ "${ANDROID_API}" -gt 34 ]; then ANDROID_API=34; fi

cmake -S "${SCRIPT_DIR}" -B "${BUILD_DIR}" \
  -DANDROID_ABI="${ABI}" \
  -DANDROID_PLATFORM=android-${ANDROID_API} \
  -DCMAKE_TOOLCHAIN_FILE="${NDK_ROOT}/build/cmake/android.toolchain.cmake" \
  -DCMAKE_BUILD_TYPE=Release

cmake --build "${BUILD_DIR}" --config Release -j

echo "可执行文件: ${BUILD_DIR}/yolo_runner"
echo "ABI: ${ABI}, ANDROID_PLATFORM: android-${ANDROID_API}"
