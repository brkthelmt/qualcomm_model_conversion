#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   bash android_deploy/tools/build_ort_qnn_android.sh \
#     --qnn-sdk /path/to/QAIRT_or_QNN_SDK \
#     --ndk /Users/<you>/Library/Android/sdk/ndk/<version> \
#     --api 29 \
#     --abi arm64-v8a

QNN_SDK=""
NDK_ROOT="${ANDROID_NDK:-${ANDROID_NDK_HOME:-}}"
API=29
ABI=arm64-v8a

while [[ $# -gt 0 ]]; do
  case "$1" in
    --qnn-sdk)
      QNN_SDK="$2"; shift 2 ;;
    --ndk)
      NDk_ROOT="$2"; shift 2 ;;
    --api)
      API="$2"; shift 2 ;;
    --abi)
      ABI="$2"; shift 2 ;;
    *)
      shift 1 ;;
  esac
done

if [ -z "$QNN_SDK" ] || [ ! -d "$QNN_SDK" ]; then
  echo "Missing --qnn-sdk path to QAIRT/QNN SDK" >&2
  exit 1
fi

if [ -z "$NDK_ROOT" ]; then
  if [ -d "$HOME/Library/Android/sdk/ndk" ]; then
    NDK_ROOT="$(ls -d "$HOME/Library/Android/sdk/ndk"/* | sort | tail -n 1)"
  elif [ -d "$HOME/Android/Sdk/ndk" ]; then
    NDK_ROOT="$(ls -d "$HOME/Android/Sdk/ndk"/* | sort | tail -n 1)"
  fi
fi
if [ -z "$NDK_ROOT" ]; then
  echo "Missing ANDROID_NDK; provide --ndk or export ANDROID_NDK" >&2
  exit 1
fi

WORK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS_DIR="$WORK_ROOT/.deps"
ORT_SRC="$DEPS_DIR/onnxruntime"
BUILD_DIR="$DEPS_DIR/ort_qnn_build"

mkdir -p "$DEPS_DIR"
if [ ! -d "$ORT_SRC" ]; then
  git clone --depth=1 https://github.com/microsoft/onnxruntime.git "$ORT_SRC"
fi

pushd "$ORT_SRC" >/dev/null
./build.sh --android \
  --android_api "$API" \
  --android_abi "$ABI" \
  --android_ndk_path "$NDK_ROOT" \
  --config Release \
  --parallel \
  --build_shared_lib \
  --skip_tests \
  --use_qnn \
  --qnn_home "$QNN_SDK"
popd >/dev/null

# Copy artifacts into third_party/onnxruntime
OUT_LIB_DIR="$WORK_ROOT/third_party/onnxruntime/lib/$ABI"
OUT_INC_DIR="$WORK_ROOT/third_party/onnxruntime/include"
mkdir -p "$OUT_LIB_DIR" "$OUT_INC_DIR"

# Find built libs
LIB_ORT="$(find "$ORT_SRC" -name libonnxruntime.so | head -n 1 || true)"
LIB_QNN_PROVIDER="$(find "$ORT_SRC" -name libonnxruntime_providers_qnn.so | head -n 1 || true)"
HEADERS_DIR="$ORT_SRC/include"

if [ -f "$LIB_ORT" ]; then cp "$LIB_ORT" "$OUT_LIB_DIR/"; fi
if [ -f "$LIB_QNN_PROVIDER" ]; then cp "$LIB_QNN_PROVIDER" "$OUT_LIB_DIR/"; fi
if [ -d "$HEADERS_DIR" ]; then cp -R "$HEADERS_DIR"/* "$OUT_INC_DIR"/; fi

echo "ORT with QNN build finished. libs at: $OUT_LIB_DIR"
ls -la "$OUT_LIB_DIR"
