#!/usr/bin/env bash
set -euo pipefail

usage() { echo "Usage: $0 --model <name> [--repo-dir <path>] [--venv-dir <dir>] [--python <path>] [--requirements <path>] [--] [export_args...]"; exit 1; }

MODEL=""
VENV_DIR=""
PYTHON="python3"
REQ_FILE=""
FORWARD_ARGS=()
REPO_DIR=""
DEFAULT_REPO="${AIHM_REPO_DIR:-}"
TMP_ROOT="${TMPDIR:-/tmp}"

ensure_repo_once() {
  local prefer="$1"
  local dest
  if [[ -n "$prefer" ]]; then
    dest="$(cd "$prefer" 2>/dev/null && pwd || echo "$prefer")"
  else
    dest="$TMP_ROOT/ai-hub-models"
  fi
  if [[ -d "$dest/.git" ]]; then
    echo "$dest"
    return 0
  fi
  rm -rf "$dest" 2>/dev/null || true
  git clone --depth 1 -b main https://github.com/quic/ai-hub-models.git "$dest" || {
    # 备用镜像
    git clone --depth 1 -b main https://ghfast.top/github.com/quic/ai-hub-models.git "$dest" ||
    git clone --depth 1 -b main https://mirror.ghproxy.com/https://github.com/quic/ai-hub-models.git "$dest" || return 1
  }
  echo "$dest"
}
while (( "$#" )); do
  case "$1" in
    --model|-m)
      MODEL="$2"; shift 2;
      ;;
    --venv-dir)
      VENV_DIR="$2"; shift 2;
      ;;
    --python)
      PYTHON="$2"; shift 2;
      ;;
    --requirements)
      REQ_FILE="$2"; shift 2;
      ;;
    --repo-dir)
      REPO_DIR="$2"; shift 2;
      ;;
    --)
      shift; FORWARD_ARGS=("$@"); break;
      ;;
    -h|--help)
      echo "Use --model <name>; add -- to pass args to export.py. Example: $0 --model beit -- --help";
      if [[ -n "${MODEL}" ]]; then
        CWD_TMP="$(pwd)"
        SCRIPT_DIR_TMP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [[ -n "$REPO_DIR" ]]; then
          REPO_ROOT_TMP="$(cd "$REPO_DIR" && pwd)"
        else
          if [[ -d "$CWD_TMP/ai-hub-models/.git" ]]; then
            REPO_ROOT_TMP="$(cd "$CWD_TMP/ai-hub-models" && pwd)"
          elif [[ -d "$SCRIPT_DIR_TMP/ai-hub-models/.git" ]]; then
            REPO_ROOT_TMP="$(cd "$SCRIPT_DIR_TMP/ai-hub-models" && pwd)"
          elif [[ -d "$SCRIPT_DIR_TMP/../ai-hub-models/.git" ]]; then
            REPO_ROOT_TMP="$(cd "$SCRIPT_DIR_TMP/../ai-hub-models" && pwd)"
          elif [[ -d "$SCRIPT_DIR_TMP/../../ai-hub-models/.git" ]]; then
            REPO_ROOT_TMP="$(cd "$SCRIPT_DIR_TMP/../../ai-hub-models" && pwd)"
          elif [[ -d "$CWD_TMP/qai_hub_models" ]]; then
            REPO_ROOT_TMP="$(cd "$CWD_TMP" && pwd)"
          elif [[ -d "$SCRIPT_DIR_TMP/../qai_hub_models" ]]; then
            REPO_ROOT_TMP="$(cd "$SCRIPT_DIR_TMP/.." && pwd)"
          else
            REPO_ROOT_TMP="$(ensure_repo_once "$DEFAULT_REPO")"
          fi
        fi
        if [[ -z "$REPO_ROOT_TMP" || ! -d "$REPO_ROOT_TMP/qai_hub_models/models/$MODEL" ]]; then
          echo "Repository not available. Set --repo-dir or AIHM_REPO_DIR to an existing ai-hub-models path." >&2
          exit 2
        fi
        ensure_support_table_tmp() {
          local repo_path="$1"
          local out_csv="$CWD_TMP/support/model-runtime-precision.csv"
          mkdir -p "$CWD_TMP/support"
          if [[ -f "$out_csv" ]]; then echo "$out_csv"; return 0; fi
          local use_repo_dir=""
          if [[ -n "$repo_path" && -d "$repo_path/qai_hub_models" ]]; then use_repo_dir="--repo-dir \"$repo_path\""; fi
          if [[ -f "$CWD_TMP/scripts/fetch_model/generate_support_table.sh" ]]; then
            bash "$CWD_TMP/scripts/fetch_model/generate_support_table.sh" ${use_repo_dir:+$use_repo_dir} --output "$out_csv" || true
            if [[ -f "$out_csv" ]]; then echo "$out_csv"; return 0; fi
          fi
          if [[ -f "$CWD_TMP/scripts/fetch_model/list_model_support.py" ]]; then
            if [[ -n "$use_repo_dir" ]]; then
              python3 "$CWD_TMP/scripts/fetch_model/list_model_support.py" --format csv $use_repo_dir > "$out_csv" || true
            else
              python3 "$CWD_TMP/scripts/fetch_model/list_model_support.py" --format csv > "$out_csv" || true
            fi
            if [[ -f "$out_csv" ]]; then echo "$out_csv"; return 0; fi
          fi
          if [[ -f "$repo_path/scripts/list_model_support.py" ]]; then
            python3 "$repo_path/scripts/list_model_support.py" --repo-dir "$repo_path" --format csv > "$out_csv" || true
            if [[ -f "$out_csv" ]]; then echo "$out_csv"; return 0; fi
          fi
          return 1
        }
        CSV_FILE=""
        if [[ -f "$CWD_TMP/support/model-runtime-precision.csv" ]]; then
          CSV_FILE="$CWD_TMP/support/model-runtime-precision.csv"
        else
          CSV_FILE="$(ensure_support_table_tmp "$REPO_ROOT_TMP" || echo '')"
        fi
        echo "Supported precision/runtime for $MODEL:";
        if [[ -n "$CSV_FILE" && -f "$CSV_FILE" ]]; then
          awk -v m="$MODEL" -F',' 'NR>1 {if ($1==m) {print "  " $2 " -> " $3}}' "$CSV_FILE"
        elif [[ -n "$MD_FILE" ]]; then
          awk -v m="$MODEL" -F'|' 'NR>2 {gsub(/^ +| +$/,"",$2); if ($2==m) {gsub(/^ +| +$/,"",$3); gsub(/^ +| +$/,"",$4); print "  " $3 " -> " $4}}' "$MD_FILE"
        else
          echo "No support table found. Generate CSV with: ./scripts/fetch_model/generate_support_table.sh --output support/model-runtime-precision.csv"
        fi
      else
        echo "Pass --model <name> with --help to show support combos from the table."
      fi
      exit 0;
      ;;
    *)
      FORWARD_ARGS+=("$1"); shift;
      ;;
  esac
done

if [[ -z "$MODEL" ]]; then usage; fi

CWD="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO="${AIHM_REPO_DIR:-}"
if [[ -n "$REPO_DIR" ]]; then
  REPO_ROOT="$(cd "$REPO_DIR" && pwd)"
else
  REPO_ROOT="$(ensure_repo_once "$DEFAULT_REPO")"
fi
if [[ ! -d "$REPO_ROOT/qai_hub_models/models/$MODEL" ]]; then
  echo "Model directory not found under repo: $REPO_ROOT/qai_hub_models/models/$MODEL" >&2
  exit 2
fi
ensure_support_table() {
  local out_csv="$CWD/support/model-runtime-precision.csv"
  mkdir -p "$CWD/support"
  if [[ -f "$out_csv" ]]; then echo "$out_csv"; return 0; fi
  if [[ -f "$CWD/scripts/fetch_model/generate_support_table.sh" ]]; then
    bash "$CWD/scripts/fetch_model/generate_support_table.sh" --repo-dir "$REPO_ROOT" --output "$out_csv" || true
    if [[ -f "$out_csv" ]]; then echo "$out_csv"; return 0; fi
  fi
  if [[ -f "$CWD/scripts/fetch_model/list_model_support.py" ]]; then
    python3 "$CWD/scripts/fetch_model/list_model_support.py" --repo-dir "$REPO_ROOT" --format csv > "$out_csv" || true
    if [[ -f "$out_csv" ]]; then echo "$out_csv"; return 0; fi
  fi
  if [[ -f "$REPO_ROOT/scripts/list_model_support.py" ]]; then
    python3 "$REPO_ROOT/scripts/list_model_support.py" --repo-dir "$REPO_ROOT" --format csv > "$out_csv" || true
  
  if [[ -f "$out_csv" ]]; then echo "$out_csv"; return 0; fi
  fi
  return 1
}
EXPORT_PATH="$REPO_ROOT/qai_hub_models/models/$MODEL/export.py"
REQ_FILE="${REQ_FILE:-}"
for f in "$CWD/.env" "$CWD/.env.local" "$REPO_ROOT/.env" "$REPO_ROOT/.env.local" "$SCRIPT_DIR/.env" "$SCRIPT_DIR/.env.local"; do
  if [[ -f "$f" ]]; then
    set -a
    source "$f"
    set +a
  fi
done

if [[ ! -f "$EXPORT_PATH" ]]; then echo "export.py not found for model $MODEL at $EXPORT_PATH" >&2; exit 2; fi

# Ensure support table exists (auto-generate when missing)
ensure_support_table || true

TMP_VENV_DIR="${VENV_DIR:-${TMP_ROOT}/aihm-venv/${MODEL}}"

NEW_ENV=1
if [[ -d "$TMP_VENV_DIR" && -f "$TMP_VENV_DIR/bin/activate" ]]; then
  NEW_ENV=0
else
  "$PYTHON" -m venv "$TMP_VENV_DIR"
fi

source "$TMP_VENV_DIR/bin/activate"

if [[ "$NEW_ENV" -eq 1 ]]; then
  pip install --upgrade pip setuptools wheel
fi

MODEL_DIR="$REPO_ROOT/qai_hub_models/models/$MODEL"
README=""
if [[ -f "$MODEL_DIR/README.md" ]]; then
  README="$MODEL_DIR/README.md"
elif [[ -f "$MODEL_DIR/readme.md" ]]; then
  README="$MODEL_DIR/readme.md"
else
  cand=$(ls -1 "$MODEL_DIR" 2>/dev/null | grep -i '^readme' | head -n1 || true)
  if [[ -n "$cand" && -f "$MODEL_DIR/$cand" ]]; then
    README="$MODEL_DIR/$cand"
  fi
fi

run_pip_cmds_from_readme() {
  local readme_path="$1"
  local -a raw_cmds=()
  if [[ -f "$readme_path" ]]; then
    mapfile -t raw_cmds < <(awk 'BEGIN{IGNORECASE=1} /pip[[:space:]]+install|python[[:space:]]*-m[[:space:]]*pip[[:space:]]+install/ {print}' "$readme_path")
  fi

  if [[ ${#raw_cmds[@]} -eq 0 ]]; then
    return 1
  fi

  pushd "$MODEL_DIR" >/dev/null
  for raw in "${raw_cmds[@]}"; do
    cmd=$(echo "$raw" | sed -E \
      -e 's/^[[:space:]]*[$!]\s*//' \
      -e 's/^sudo\s+//' \
      -e 's/^python[[:space:]]+-m[[:space:]]+pip\b/pip/' \
      -e 's/`//g' \
      -e 's/\bpip3\b/pip/g' \
      -e 's/[[:space:]]#.*$//' \
    )
    if echo "$cmd" | grep -qiE '^pip[[:space:]]+install'; then
      eval "$cmd"
    fi
  done
  popd >/dev/null
  return 0
}

if [[ "$NEW_ENV" -eq 1 ]]; then
  if ! run_pip_cmds_from_readme "$README"; then
    if [[ -f "$MODEL_DIR/requirements.txt" ]]; then
      pushd "$MODEL_DIR" >/dev/null
      pip install -r requirements.txt
      popd >/dev/null
    else
      echo "No pip install commands found in README and no requirements.txt in $MODEL_DIR" >&2
      deactivate
      exit 3
    fi
  fi
else
  echo "Reusing existing venv at $TMP_VENV_DIR; skipping dependency installation" >&2
fi

python "$EXPORT_PATH" "${FORWARD_ARGS[@]}"
deactivate
PATCHES_DIR="$CWD/scripts/patches"
if [[ -d "$PATCHES_DIR" ]]; then
  export PYTHONPATH="$PATCHES_DIR:${PYTHONPATH:-}"
fi
