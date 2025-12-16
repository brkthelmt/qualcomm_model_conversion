#!/usr/bin/env bash
set -euo pipefail

usage() { echo "Usage: $0 --model-id <name> [--action list|fetch] [--repo-dir <path>] [--output-dir <dir>] [--runtime-filter <r1,r2>] [--precision-filter <p1,p2>] [--unzip]"; exit 1; }

MODEL_ID=""
ACTION="list"
REPO_DIR=""
OUTPUT_DIR=""
RUNTIME_FILTER=""
PRECISION_FILTER=""
UNZIP_FLAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model-id)
      MODEL_ID="$2"; shift 2 ;;
    --action)
      ACTION="$2"; shift 2 ;;
    --repo-dir)
      REPO_DIR="$2"; shift 2 ;;
    --output-dir)
      OUTPUT_DIR="$2"; shift 2 ;;
    --runtime-filter)
      RUNTIME_FILTER="$2"; shift 2 ;;
    --precision-filter)
      PRECISION_FILTER="$2"; shift 2 ;;
    --unzip)
      UNZIP_FLAG="--unzip"; shift 1 ;;
    -h|--help)
      usage ;;
    *)
      usage ;;
  esac
done

if [[ -z "$MODEL_ID" ]]; then usage; fi

TMP_ROOT="${TMPDIR:-/tmp}"
REPO_DIR_DEFAULT="$TMP_ROOT/ai-hub-models"

PY_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/generate_support_model.py"

CMD=( python3 "$PY_SCRIPT" --model-id "$MODEL_ID" --action "$ACTION" --repo-dir "${REPO_DIR:-$REPO_DIR_DEFAULT}" )
if [[ -n "$OUTPUT_DIR" ]]; then CMD+=( --output-dir "$OUTPUT_DIR" ); fi
if [[ -n "$RUNTIME_FILTER" ]]; then CMD+=( --runtime-filter "$RUNTIME_FILTER" ); fi
if [[ -n "$PRECISION_FILTER" ]]; then CMD+=( --precision-filter "$PRECISION_FILTER" ); fi
if [[ -n "$UNZIP_FLAG" ]]; then CMD+=( --unzip ); fi

"${CMD[@]}"
