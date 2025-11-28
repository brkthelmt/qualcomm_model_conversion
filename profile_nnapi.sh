#!/usr/bin/env bash
set -euo pipefail

MODEL=${1:-android_deploy/yolov7_w8a8.tflite}
IMAGE=${2:-android_deploy/sample_multi.jpg}
LABELS=${3:-android_deploy/labels_coco.names}

OUT_DIR="android_deploy/profile"
mkdir -p "${OUT_DIR}"

echo "Start atrace async capture (nnapi/neuralnetworks/sched/freq/hal)"
adb shell atrace -z -b 8192 nnapi neuralnetworks sched freq hal --async_start || true

./android_deploy/run_on_device.sh --model-host-path "${MODEL}" --image-host-path "${IMAGE}" --delegate nnapi --labels-host-path "${LABELS}" || true

TRACE_TMP="/data/local/tmp/nnapi_trace.html"
adb shell atrace --async_stop -z -b 8192 -o "${TRACE_TMP}" nnapi neuralnetworks sched freq hal || true

adb pull "${TRACE_TMP}" "${OUT_DIR}/nnapi_trace.html" || true

echo "Trace saved to ${OUT_DIR}/nnapi_trace.html"
echo "Outputs at android_deploy/output_pull/output"

