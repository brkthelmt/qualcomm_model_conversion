#!/usr/bin/env bash
set -euo pipefail

usage() { echo "Usage: $0 --model-id <name> --model-format <onnx|tflite> [--do-export] [--image-host-path <path>] [--onnx-inputs-host-dir <dir>] [--labels-host-path <path>] [--delegate <cpu|nnapi>] [--abi <abi>] [--stdout-host-path <path>] [--] [export_args...]"; exit 1; }

MODEL_ID=""
MODEL_FORMAT=""
DO_EXPORT=0
IMAGE_HOST_PATH=""
ONNX_INPUTS_HOST_DIR=""
LABELS_HOST_PATH=""
DELEGATE="nnapi"
ABI="arm64-v8a"
STDOUT_HOST_PATH=""
FORWARD_ARGS=()
TMP_ROOT="${TMPDIR:-/tmp}"
REPO_DIR_DEFAULT="${AIHM_REPO_DIR:-$TMP_ROOT/ai-hub-models}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model-id)
      MODEL_ID="$2"; shift 2 ;;
    --model-format)
      MODEL_FORMAT="$2"; shift 2 ;;
    --do-export)
      DO_EXPORT=1; shift 1 ;;
    --image-host-path)
      IMAGE_HOST_PATH="$2"; shift 2 ;;
    --onnx-inputs-host-dir)
      ONNX_INPUTS_HOST_DIR="$2"; shift 2 ;;
    --labels-host-path)
      LABELS_HOST_PATH="$2"; shift 2 ;;
    --delegate)
      DELEGATE="$2"; shift 2 ;;
    --abi)
      ABI="$2"; shift 2 ;;
    --stdout-host-path)
      STDOUT_HOST_PATH="$2"; shift 2 ;;
    --)
      shift; FORWARD_ARGS=("$@"); break ;;
    -h|--help)
      usage ;;
    *)
      usage ;;
  esac
done

if [[ -z "$MODEL_ID" || -z "$MODEL_FORMAT" ]]; then usage; fi

if [[ "$DO_EXPORT" -eq 1 ]]; then
  bash scripts/fetch_model/run_export.sh --model "$MODEL_ID" --repo-dir "$REPO_DIR_DEFAULT" -- "${FORWARD_ARGS[@]}"
fi

OUT_DIR="android_deploy/models/${MODEL_ID}/${MODEL_FORMAT}"
mkdir -p "$OUT_DIR"
FETCH_OUT=$(python3 scripts/fetch_model/get_model_file.py --model "$MODEL_ID" --format "$MODEL_FORMAT" --repo-dir "$REPO_DIR_DEFAULT" --output-dir "$OUT_DIR" --unzip)
SEL=""
if [[ "$MODEL_FORMAT" == "onnx" ]]; then
  SEL=$(echo "$FETCH_OUT" | grep -E "\.onnx$" | head -n1 || true)
elif [[ "$MODEL_FORMAT" == "tflite" ]]; then
  SEL=$(echo "$FETCH_OUT" | grep -E "\.tflite$" | head -n1 || true)
else
  SEL=$(echo "$FETCH_OUT" | head -n1 || true)
fi
if [[ -z "$SEL" || ! -f "$SEL" ]]; then
  echo "Failed to locate model file for $MODEL_ID in format $MODEL_FORMAT" >&2
  exit 2
fi

CMD=( bash run_on_device.sh --model-host-path "$SEL" --delegate "$DELEGATE" --abi "$ABI" )
if [[ -n "$IMAGE_HOST_PATH" ]]; then CMD+=( --image-host-path "$IMAGE_HOST_PATH" ); fi
if [[ -n "$ONNX_INPUTS_HOST_DIR" ]]; then CMD+=( --onnx-inputs-host-dir "$ONNX_INPUTS_HOST_DIR" ); fi
if [[ -n "$LABELS_HOST_PATH" ]]; then CMD+=( --labels-host-path "$LABELS_HOST_PATH" ); fi
if [[ -n "$STDOUT_HOST_PATH" ]]; then CMD+=( --stdout-host-path "$STDOUT_HOST_PATH" ); fi

"${CMD[@]}"
