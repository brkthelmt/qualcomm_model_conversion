#!/usr/bin/env bash
set -euo pipefail

# Usage examples:
#   bash android_deploy/scripts/run_qnn_net.sh \
#     --dlc-host-path android_deploy/yolov7_w8a8.dlc \
#     --qnn-lib-dir-host "/path/to/QNN_SDK_ROOT/lib/aarch64-android-clang" \
#     --runner-host-path android_deploy/qnn-net-run \
#     --output-dir-host android_deploy/output_pull/qnn_out

DLC_HOST_PATH=""
IMAGE_HOST_PATH=""
INPUT_LIST_HOST_PATH=""
QNN_LIB_DIR_HOST=""
RUNNER_HOST_PATH="android_deploy/qnn-net-run"
OUT_HOST_DIR="android_deploy/output_pull/qnn_out"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dlc-host-path)
      DLC_HOST_PATH="$2"; shift 2 ;;
    --image-host-path)
      IMAGE_HOST_PATH="$2"; shift 2 ;;
    --qnn-lib-dir-host)
      QNN_LIB_DIR_HOST="$2"; shift 2 ;;
    --runner-host-path)
      RUNNER_HOST_PATH="$2"; shift 2 ;;
    --output-dir-host)
      OUT_HOST_DIR="$2"; shift 2 ;;
    --input-list-host)
      INPUT_LIST_HOST_PATH="$2"; shift 2 ;;
    *)
      shift 1 ;;
  esac
done

if [ -z "$DLC_HOST_PATH" ] || [ ! -f "$DLC_HOST_PATH" ]; then
  echo "Missing --dlc-host-path or file not found" >&2
  exit 1
fi
if [ ! -f "$RUNNER_HOST_PATH" ]; then
  echo "Runner not found: $RUNNER_HOST_PATH" >&2
  exit 1
fi

TMP_DIR="/data/local/tmp/qnn_run"
adb shell mkdir -p "$TMP_DIR"
adb push "$RUNNER_HOST_PATH" "$TMP_DIR/qnn-net-run" >/dev/null
adb shell "chmod +x $TMP_DIR/qnn-net-run"
adb push "$DLC_HOST_PATH" "$TMP_DIR/model.dlc" >/dev/null

LD_PATH_CMD=""
if [ -n "$QNN_LIB_DIR_HOST" ] && [ -d "$QNN_LIB_DIR_HOST" ]; then
  for so in $(ls "$QNN_LIB_DIR_HOST"/*.so 2>/dev/null); do adb push "$so" "$TMP_DIR/" >/dev/null; done
  LD_PATH_CMD="LD_LIBRARY_PATH=$TMP_DIR"
fi

INPUT_LIST_OPT=""
if [ -n "$INPUT_LIST_HOST_PATH" ] && [ -f "$INPUT_LIST_HOST_PATH" ]; then
  # Push each referenced input file and generate a device-side input_list with basenames
  DEVICE_INPUT_LIST="android_deploy/.tmp_device_input_list.txt"
  rm -f "$DEVICE_INPUT_LIST"
  while IFS= read -r inpath; do
    [ -z "$inpath" ] && continue
    if [ -f "$inpath" ]; then
      adb push "$inpath" "$TMP_DIR/$(basename "$inpath")" >/dev/null
      echo "$(basename "$inpath")" >> "$DEVICE_INPUT_LIST"
    else
      echo "$inpath" >> "$DEVICE_INPUT_LIST"
    fi
  done < "$INPUT_LIST_HOST_PATH"
  adb push "$DEVICE_INPUT_LIST" "$TMP_DIR/input_list.txt" >/dev/null
  rm -f "$DEVICE_INPUT_LIST"
  INPUT_LIST_OPT="--input_list input_list.txt"
fi

if [ -n "$IMAGE_HOST_PATH" ]; then
  IMG_EXT="${IMAGE_HOST_PATH##*.}"
  HOST_BMP="android_deploy/.tmp_qnn_input.bmp"
  rm -f "$HOST_BMP"
  if [[ "$IMG_EXT" != "bmp" ]]; then
    sips -s format bmp "$IMAGE_HOST_PATH" --out "$HOST_BMP" >/dev/null || true
  else
    cp "$IMAGE_HOST_PATH" "$HOST_BMP"
  fi
  adb push "$HOST_BMP" "$TMP_DIR/image.bmp" >/dev/null || true
fi

BACKEND_OPT=""
if adb shell "ls $TMP_DIR/libQnnHtp.so" >/dev/null 2>&1; then
  BACKEND_OPT="--backend ./libQnnHtp.so"
fi

if [ -n "$INPUT_LIST_OPT" ]; then
  adb shell "cd $TMP_DIR && ${LD_PATH_CMD} ./qnn-net-run --dlc_path model.dlc ${BACKEND_OPT} ${INPUT_LIST_OPT} --output_dir out" || true
else
  echo "已完成推送。未提供 --input-list-host，暂不运行推理。您可在设备上执行："
  echo "adb shell \"cd $TMP_DIR && ${LD_PATH_CMD} ./qnn-net-run --dlc_path model.dlc ${BACKEND_OPT} --help\""
fi

mkdir -p "$OUT_HOST_DIR"
if adb shell "test -d $TMP_DIR/out" >/dev/null 2>&1; then
  adb pull "$TMP_DIR/out" "$OUT_HOST_DIR" >/dev/null || true
  echo "Outputs pulled to $OUT_HOST_DIR"
else
  echo "未检测到设备输出目录，已完成推送，可按需手动运行 qnn-net-run。"
fi
