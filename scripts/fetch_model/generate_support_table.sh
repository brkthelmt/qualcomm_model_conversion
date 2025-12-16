#!/usr/bin/env bash
set -euo pipefail

usage() { echo "Usage: $0 [--repo-url <url>] [--branch <name>] [--output <path>] [--repo-dir <path>] [--clone-dir <path>] [--list-script <path>]"; exit 1; }

OUTPUT="support/model-runtime-precision.csv"
REPO_DIR=""
CLONE_DIR="ai-hub-models"
LIST_SCRIPT=""

while (( "$#" )); do
  case "$1" in
    --output)
      OUTPUT="$2"; shift 2;
      ;;
    --repo-dir)
      REPO_DIR="$2"; shift 2;
      ;;
    --clone-dir)
      CLONE_DIR="$2"; shift 2;
      ;;
    --list-script)
      LIST_SCRIPT="$2"; shift 2;
      ;;
    -h|--help)
      usage;
      ;;
    *)
      usage;
      ;;
  esac
done

CWD="$(pwd)"
case "$OUTPUT" in
  /*) OUT_PATH="$OUTPUT" ;;
  *) OUT_PATH="$CWD/$OUTPUT" ;;
esac
mkdir -p "$(dirname "$OUT_PATH")"

TMP_ROOT="${TMPDIR:-/tmp}"
DEFAULT_REPO="${AIHM_REPO_DIR:-}"
DEST="${REPO_DIR:-${DEFAULT_REPO:-$TMP_ROOT/$CLONE_DIR}}"
if [[ ! -d "$DEST/.git" ]]; then
  rm -rf "$DEST" 2>/dev/null || true
  git clone --depth 1 -b main https://github.com/quic/ai-hub-models.git "$DEST" || {
    git clone --depth 1 -b main https://ghfast.top/github.com/quic/ai-hub-models.git "$DEST" ||
    git clone --depth 1 -b main https://mirror.ghproxy.com/https://github.com/quic/ai-hub-models.git "$DEST" || true
  }
fi
if [[ ! -d "$DEST/qai_hub_models/models" ]]; then
  echo "Models directory missing: $DEST/qai_hub_models/models" >&2
  exit 2
fi

LS_PATH="$LIST_SCRIPT"
if [[ -z "$LS_PATH" ]]; then
  if [[ -f "$DEST/scripts/list_model_support.py" ]]; then
    LS_PATH="$DEST/scripts/list_model_support.py"
  elif [[ -f "$CWD/scripts/fetch_model/list_model_support.py" ]]; then
    LS_PATH="$CWD/scripts/fetch_model/list_model_support.py"
  elif [[ -f "$CWD/android_deploy/scripts/list_model_support.py" ]]; then
    LS_PATH="$CWD/android_deploy/scripts/list_model_support.py"
  elif [[ -f "$CWD/list_model_support.py" ]]; then
    LS_PATH="$CWD/list_model_support.py"
  else
    echo "Required generator script not found in repo or current directory" >&2
    exit 3
  fi
fi

python3 "$LS_PATH" --repo-dir "$DEST" --format csv > "$OUT_PATH"
echo "$OUT_PATH"
