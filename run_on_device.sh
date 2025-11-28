#!/usr/bin/env bash
set -euo pipefail

MODEL_HOST_PATH="android_deploy/models/model.onnx"
IMAGE_HOST_PATH=""
ABI="arm64-v8a"
DELEGATE="nnapi"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model-host-path)
      MODEL_HOST_PATH="$2"; shift 2 ;;
    --image-host-path)
      IMAGE_HOST_PATH="$2"; shift 2 ;;
    --abi)
      ABI="$2"; shift 2 ;;
    --delegate)
      DELEGATE="$2"; shift 2 ;;
    --qnn-context-host-path)
      QNN_CONTEXT_HOST_PATH="$2"; shift 2 ;;
    --qnn-lib-dir-host)
      QNN_LIB_DIR_HOST="$2"; shift 2 ;;
    --labels-host-path)
      LABELS_HOST_PATH="$2"; shift 2 ;;
    *)
      shift 1 ;;
  esac
done

if [ -z "${IMAGE_HOST_PATH}" ]; then
  echo "必须提供 --image-host-path" >&2
  exit 1
fi

pushd android_deploy >/dev/null
chmod +x build_android.sh
./build_android.sh
popd >/dev/null

EXEC_PATH="android_deploy/build/android/${ABI}/yolo_runner"
if [ ! -f "${EXEC_PATH}" ]; then
  echo "未找到可执行文件 ${EXEC_PATH}" >&2
  exit 1
fi

TMP_DIR="/data/local/tmp/yolo_run"
adb shell mkdir -p "${TMP_DIR}"
adb push "${EXEC_PATH}" "${TMP_DIR}/yolo_runner"
MODEL_EXT="${MODEL_HOST_PATH##*.}"
MODEL_DEVICE_NAME="model.tflite"
if [[ "${MODEL_EXT}" == "onnx" ]]; then
  MODEL_DEVICE_NAME="model.onnx"
fi
adb push "${MODEL_HOST_PATH}" "${TMP_DIR}/${MODEL_DEVICE_NAME}"

if [ -n "${QNN_CONTEXT_HOST_PATH:-}" ]; then
  adb push "${QNN_CONTEXT_HOST_PATH}" "${TMP_DIR}/qnn_context.bin"
fi

if [ -n "${QNN_LIB_DIR_HOST:-}" ] && [ -d "${QNN_LIB_DIR_HOST}" ]; then
  for so in $(ls "${QNN_LIB_DIR_HOST}"/*.so 2>/dev/null); do adb push "$so" "${TMP_DIR}/"; done
  LD_PATH_CMD="LD_LIBRARY_PATH=${TMP_DIR}"
fi

IMG_EXT="${IMAGE_HOST_PATH##*.}"
HOST_BMP="android_deploy/.tmp_input.bmp"
rm -f "${HOST_BMP}"
if [[ "${IMG_EXT}" != "bmp" ]]; then
  sips -s format bmp "${IMAGE_HOST_PATH}" --out "${HOST_BMP}" >/dev/null
else
  cp "${IMAGE_HOST_PATH}" "${HOST_BMP}"
fi

adb push "${HOST_BMP}" "${TMP_DIR}/image.bmp"

DELEGATE_SO="android_deploy/third_party/tflite/lib/${ABI}/libtensorflowlite_nnapi_delegate.so"
TFLITE_SO="android_deploy/third_party/tflite/lib/${ABI}/libtensorflowlite.so"
TFLITE_C_SO="android_deploy/third_party/tflite/lib/${ABI}/libtensorflowlite_c.so"

# ONNX Runtime libs (optional)
ONNX_SO="android_deploy/third_party/onnxruntime/lib/${ABI}/libonnxruntime.so"
ONNX_PROVIDERS_SHARED_SO="android_deploy/third_party/onnxruntime/lib/${ABI}/libonnxruntime_providers_shared.so"
ONNX_NNAPI_SO="android_deploy/third_party/onnxruntime/lib/${ABI}/libonnxruntime_providers_nnapi.so"
ONNX_QNN_SO="android_deploy/third_party/onnxruntime/lib/${ABI}/libonnxruntime_providers_qnn.so"
adb shell "chmod +x ${TMP_DIR}/yolo_runner"
LD_PATH_CMD=""
if [ -f "${TFLITE_SO}" ]; then
  adb push "${TFLITE_SO}" "${TMP_DIR}/"
  LD_PATH_CMD="LD_LIBRARY_PATH=${TMP_DIR}"
fi
if [ -f "${DELEGATE_SO}" ]; then
  adb push "${DELEGATE_SO}" "${TMP_DIR}/"
  LD_PATH_CMD="LD_LIBRARY_PATH=${TMP_DIR}"
fi
if [ -f "${TFLITE_C_SO}" ]; then
  adb push "${TFLITE_C_SO}" "${TMP_DIR}/"
  LD_PATH_CMD="LD_LIBRARY_PATH=${TMP_DIR}"
fi

if [ -f "${ONNX_SO}" ]; then
  adb push "${ONNX_SO}" "${TMP_DIR}/"
  LD_PATH_CMD="LD_LIBRARY_PATH=${TMP_DIR}"
fi
if [ -f "${ONNX_PROVIDERS_SHARED_SO}" ]; then
  adb push "${ONNX_PROVIDERS_SHARED_SO}" "${TMP_DIR}/"
  LD_PATH_CMD="LD_LIBRARY_PATH=${TMP_DIR}"
fi
if [ -f "${ONNX_NNAPI_SO}" ]; then
  adb push "${ONNX_NNAPI_SO}" "${TMP_DIR}/"
  LD_PATH_CMD="LD_LIBRARY_PATH=${TMP_DIR}"
fi
if [ -f "${ONNX_QNN_SO}" ]; then
  adb push "${ONNX_QNN_SO}" "${TMP_DIR}/"
  LD_PATH_CMD="LD_LIBRARY_PATH=${TMP_DIR}"
fi
if [ -n "${LABELS_HOST_PATH:-}" ]; then
  adb push "${LABELS_HOST_PATH}" "${TMP_DIR}/labels.txt"
fi
if [ -n "${LD_PATH_CMD}" ]; then
  if [ -n "${LABELS_HOST_PATH:-}" ]; then
    if [ -n "${QNN_CONTEXT_HOST_PATH:-}" ]; then
      adb shell "cd ${TMP_DIR} && ${LD_PATH_CMD} ./yolo_runner --model ${MODEL_DEVICE_NAME} --image image.bmp --output output --delegate ${DELEGATE} --labels labels.txt --qnn-context qnn_context.bin"
    else
      adb shell "cd ${TMP_DIR} && ${LD_PATH_CMD} ./yolo_runner --model ${MODEL_DEVICE_NAME} --image image.bmp --output output --delegate ${DELEGATE} --labels labels.txt"
    fi
  else
    if [ -n "${QNN_CONTEXT_HOST_PATH:-}" ]; then
      adb shell "cd ${TMP_DIR} && ${LD_PATH_CMD} ./yolo_runner --model ${MODEL_DEVICE_NAME} --image image.bmp --output output --delegate ${DELEGATE} --qnn-context qnn_context.bin"
    else
      adb shell "cd ${TMP_DIR} && ${LD_PATH_CMD} ./yolo_runner --model ${MODEL_DEVICE_NAME} --image image.bmp --output output --delegate ${DELEGATE}"
    fi
  fi
else
  if [ -n "${LABELS_HOST_PATH:-}" ]; then
    if [ -n "${QNN_CONTEXT_HOST_PATH:-}" ]; then
      adb shell "cd ${TMP_DIR} && ./yolo_runner --model ${MODEL_DEVICE_NAME} --image image.bmp --output output --delegate ${DELEGATE} --labels labels.txt --qnn-context qnn_context.bin"
    else
      adb shell "cd ${TMP_DIR} && ./yolo_runner --model ${MODEL_DEVICE_NAME} --image image.bmp --output output --delegate ${DELEGATE} --labels labels.txt"
    fi
  else
    if [ -n "${QNN_CONTEXT_HOST_PATH:-}" ]; then
      adb shell "cd ${TMP_DIR} && ./yolo_runner --model ${MODEL_DEVICE_NAME} --image image.bmp --output output --delegate ${DELEGATE} --qnn-context qnn_context.bin"
    else
      adb shell "cd ${TMP_DIR} && ./yolo_runner --model ${MODEL_DEVICE_NAME} --image image.bmp --output output --delegate ${DELEGATE}"
    fi
  fi
fi

LOCAL_OUT_DIR="android_deploy/output_pull"
rm -rf "${LOCAL_OUT_DIR}"
mkdir -p "${LOCAL_OUT_DIR}"
  adb pull "${TMP_DIR}/output" "${LOCAL_OUT_DIR}"

echo "结果已回拉到 ${LOCAL_OUT_DIR}"

# Python decode to boxes.txt
if command -v python3 >/dev/null 2>&1; then
  python3 android_deploy/scripts/decode_yolo.py --output-dir "${LOCAL_OUT_DIR}/output" --image "${IMAGE_HOST_PATH}" --save "${LOCAL_OUT_DIR}/output/annotated_python.jpg" || true
fi

# Push boxes and overlay on device if boxes exists
if [ -f "${LOCAL_OUT_DIR}/output/boxes.txt" ]; then
  adb push "${LOCAL_OUT_DIR}/output/boxes.txt" "${TMP_DIR}/boxes.txt"
  if [ -n "${LABELS_HOST_PATH:-}" ]; then
    adb push "${LABELS_HOST_PATH}" "${TMP_DIR}/labels.txt"
  fi
  if [ -n "${LD_PATH_CMD}" ]; then
    if [ -n "${LABELS_HOST_PATH:-}" ]; then
      adb shell "cd ${TMP_DIR} && ${LD_PATH_CMD} ./yolo_runner --model ${MODEL_DEVICE_NAME} --image image.bmp --output output --overlay-only true --boxes boxes.txt --labels labels.txt"
    else
      adb shell "cd ${TMP_DIR} && ${LD_PATH_CMD} ./yolo_runner --model ${MODEL_DEVICE_NAME} --image image.bmp --output output --overlay-only true --boxes boxes.txt"
    fi
  else
    if [ -n "${LABELS_HOST_PATH:-}" ]; then
      adb shell "cd ${TMP_DIR} && ./yolo_runner --model ${MODEL_DEVICE_NAME} --image image.bmp --output output --overlay-only true --boxes boxes.txt --labels labels.txt"
    else
      adb shell "cd ${TMP_DIR} && ./yolo_runner --model ${MODEL_DEVICE_NAME} --image image.bmp --output output --overlay-only true --boxes boxes.txt"
    fi
  fi
  adb pull "${TMP_DIR}/output/annotated.bmp" "${LOCAL_OUT_DIR}/output/annotated.bmp" || true
fi
