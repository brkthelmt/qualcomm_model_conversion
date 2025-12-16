#!/usr/bin/env bash
set -euo pipefail

# 用于在编译/运行阶段自动拉取 third_party 依赖（TFLite/ONNX Runtime）
# 依赖：curl 或 wget、unzip、tar

ABI="arm64-v8a"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR%/scripts}"
TP_DIR="${ROOT_DIR}/third_party"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --abi) ABI="$2"; shift 2 ;;
    *) shift 1 ;;
  esac
done

have_cmd() { command -v "$1" >/dev/null 2>&1; }
dl() { if have_cmd curl; then curl -L "$1" -o "$2"; elif have_cmd wget; then wget "$1" -O "$2"; else echo "缺少 curl/wget" >&2; return 1; fi }

# GitHub 加速代理
proxify() {
  local url="$1"
  if [[ "$url" == https://github.com/* ]]; then
    echo "https://ghfast.top/github.com/${url#https://github.com/}"
  elif [[ "$url" == https://raw.githubusercontent.com/* ]]; then
    echo "https://ghfast.top/raw.githubusercontent.com/${url#https://raw.githubusercontent.com/}"
  else
    echo "$url"
  fi
}

mkdir -p "${TP_DIR}"

fetch_onnxruntime() {
  local ver="${ORT_VER:-1.23.2}"
  local aar_url="${ORT_ANDROID_AAR_URL:-https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/${ver}/onnxruntime-android-${ver}.aar}"
  local tgz_url="${ORT_HEADERS_TGZ_URL:-https://github.com/microsoft/onnxruntime/releases/download/v${ver}/onnxruntime-linux-x64-${ver}.tgz}"
  local dst="${TP_DIR}/onnxruntime"
  local libdir="${dst}/lib/${ABI}"
  local incdir="${dst}/include"
  mkdir -p "${libdir}" "${incdir}"
  if [ ! -f "${libdir}/libonnxruntime.so" ]; then
    echo "拉取 ONNX Runtime AAR ${aar_url}"
    tmp_aar="$(mktemp).aar"
    dl "$(proxify "${aar_url}")" "${tmp_aar}" || true
    if ! unzip -t "${tmp_aar}" >/dev/null 2>&1; then
      rm -f "${tmp_aar}"; tmp_aar="$(mktemp).aar";
      # 备用代理路径（ghfast.top/github.com/...）
      alt_url="${aar_url/https:\/\/github.com/https:\/\/ghfast.top\/github.com}"
      dl "${alt_url}" "${tmp_aar}" || true
    fi
    if ! unzip -t "${tmp_aar}" >/dev/null 2>&1; then
      rm -f "${tmp_aar}"; tmp_aar="$(mktemp).aar";
      alt_url2="https://mirror.ghproxy.com/${aar_url}"
      dl "${alt_url2}" "${tmp_aar}" || true
    fi
    unzip -oj "${tmp_aar}" "jni/${ABI}/libonnxruntime.so" -d "${libdir}" || true
    unzip -oj "${tmp_aar}" "jni/${ABI}/libonnxruntime_providers_nnapi.so" -d "${libdir}" || true
    unzip -oj "${tmp_aar}" "jni/${ABI}/libonnxruntime_providers_shared.so" -d "${libdir}" || true
    rm -f "${tmp_aar}"
  fi
  local force_headers="${FORCE_ORT_HEADERS:-}"
  local have_all_hdr=0
  if [ -f "${incdir}/onnxruntime_cxx_api.h" ] && [ -f "${incdir}/onnxruntime_float16.h" ] && [ -f "${incdir}/onnxruntime_ep_c_api.h" ]; then
    have_all_hdr=1
  fi
  if [ "${force_headers}" = "1" ] || [ "${have_all_hdr}" -eq 0 ]; then
    echo "拉取 ONNX Runtime 头文件 ${tgz_url}"
    tmp_tgz="$(mktemp).tgz"
    dl "$(proxify "${tgz_url}")" "${tmp_tgz}" || true
    if ! tar -tzf "${tmp_tgz}" >/dev/null 2>&1; then
      rm -f "${tmp_tgz}"; tmp_tgz="$(mktemp).tgz";
      alt_url="${tgz_url/https:\/\/github.com/https:\/\/ghfast.top\/github.com}"
      dl "${alt_url}" "${tmp_tgz}" || true
    fi
    if ! tar -tzf "${tmp_tgz}" >/dev/null 2>&1; then
      rm -f "${tmp_tgz}"; tmp_tgz="$(mktemp).tgz";
      alt_url2="https://mirror.ghproxy.com/${tgz_url}"
      dl "${alt_url2}" "${tmp_tgz}" || true
    fi
    mkdir -p "${dst}/_tmp_hdr"
    tar -xzf "${tmp_tgz}" -C "${dst}/_tmp_hdr"
    # 复制 include/*.h 到 incdir（展平到根，满足项目的相对包含）
    base_dir=$(find "${dst}/_tmp_hdr" -maxdepth 2 -type d -name 'onnxruntime-linux-x64-*' | head -n 1 || true)
    if [ -n "${base_dir}" ] && [ -d "${base_dir}/include" ]; then
      cp -f "${base_dir}/include/"*.h "${incdir}/" || true
    else
      find "${dst}/_tmp_hdr" -type f -path '*/include/*' -name '*.h' -exec cp {} "${incdir}/" \; || true
    fi
    rm -rf "${dst}/_tmp_hdr" "${tmp_tgz}"
  fi
  # 额外确保 NNAPI 工厂头存在（用于 OrtSessionOptionsAppendExecutionProvider_Nnapi）
  if [ ! -f "${incdir}/nnapi_provider_factory.h" ]; then
    nnapi_hdr_url="https://raw.githubusercontent.com/microsoft/onnxruntime/main/include/onnxruntime/core/providers/nnapi/nnapi_provider_factory.h"
    tmp_hdr="$(mktemp).h"
    echo "拉取 NNAPI provider factory 头 ${nnapi_hdr_url}"
    dl "$(proxify "${nnapi_hdr_url}")" "${tmp_hdr}" || true
    if [ ! -s "${tmp_hdr}" ]; then
      rm -f "${tmp_hdr}"; tmp_hdr="$(mktemp).h";
      alt_hdr="https://mirror.ghproxy.com/${nnapi_hdr_url}"
      dl "${alt_hdr}" "${tmp_hdr}" || true
    fi
    if [ -s "${tmp_hdr}" ]; then mv "${tmp_hdr}" "${incdir}/nnapi_provider_factory.h"; else rm -f "${tmp_hdr}"; fi
  fi
}


fetch_tflite() {
  local dst="${TP_DIR}/tflite"
  local libdir="${dst}/lib/${ABI}"
  local incdir="${dst}/include"
  mkdir -p "${libdir}" "${incdir}"
  # 默认从 MavenCentral 拉取 AAR（无需 GitHub 代理）
  local ver="${TFLITE_VER:-2.13.0}"
  local aar_url_default="https://repo1.maven.org/maven2/org/tensorflow/tensorflow-lite/${ver}/tensorflow-lite-${ver}.aar"
  local aar_url="${TFLITE_AAR_URL:-${aar_url_default}}"
  if [ ! -f "${libdir}/libtensorflowlite.so" ] && [ ! -f "${libdir}/libtensorflowlite.a" ]; then
    echo "拉取 TFLite AAR ${aar_url}"
    tmp_aar="$(mktemp).aar"
    dl "${aar_url}" "${tmp_aar}" || true
    unzip -oj "${tmp_aar}" "jni/${ABI}/libtensorflowlite.so" -d "${libdir}" || true
    unzip -oj "${tmp_aar}" "jni/${ABI}/libtensorflowlite_jni.so" -d "${libdir}" || true
    unzip -oj "${tmp_aar}" "jni/${ABI}/libtensorflowlite_nnapi_delegate.so" -d "${libdir}" || true
    mkdir -p "${incdir}/tensorflow"
    unzip -o "${tmp_aar}" "headers/tensorflow/*" -d "${incdir}" || true
    if [ -d "${incdir}/headers/tensorflow" ]; then
      rsync -a "${incdir}/headers/tensorflow/" "${incdir}/tensorflow/" || cp -R "${incdir}/headers/tensorflow/"* "${incdir}/tensorflow/" || true
      rm -rf "${incdir}/headers"
    fi
    rm -f "${tmp_aar}"
  fi
  # 补齐 c_api.h 依赖的 async/types 头文件（AAR 未提供）
  local async_dir="${incdir}/tensorflow/lite/core/async/c"
  local async_types="${async_dir}/types.h"
  mkdir -p "${async_dir}"
  if [ ! -f "${async_types}" ]; then
    cat > "${async_types}" <<'EOF'
/* Minimal stub for tensorflow/lite/core/async/c/types.h */
#ifndef TENSORFLOW_LITE_CORE_ASYNC_C_TYPES_H_
#define TENSORFLOW_LITE_CORE_ASYNC_C_TYPES_H_
#ifdef __cplusplus
extern "C" {
#endif
typedef struct TfLiteAsyncKernel TfLiteAsyncKernel;
typedef struct TfLiteExecutionTask TfLiteExecutionTask;
typedef enum TfLiteIoType {
  kTfLiteIoTypeUnknown = 0,
  kTfLiteIoTypeInput = 1,
  kTfLiteIoTypeOutput = 2,
} TfLiteIoType;
#ifdef __cplusplus
}
#endif
#endif
EOF
  fi
  # 额外拉取 C++ API 头文件（interpreter.h、model.h、kernels/register.h 等）
  # 来自 TensorFlow 源码标签 v${ver}
  local tf_zip_url="https://github.com/tensorflow/tensorflow/archive/refs/tags/v${ver}.zip"
  local tmp_zip="$(mktemp).zip"
  echo "拉取 TensorFlow 源码头 ${tf_zip_url}"
  dl "$(proxify "${tf_zip_url}")" "${tmp_zip}" || true
  if ! unzip -t "${tmp_zip}" >/dev/null 2>&1; then
    rm -f "${tmp_zip}"; tmp_zip="$(mktemp).zip";
    local alt_url="${tf_zip_url/https:\/\/github.com/https:\/\/ghfast.top\/github.com}"
    dl "${alt_url}" "${tmp_zip}" || true
  fi
  if ! unzip -t "${tmp_zip}" >/dev/null 2>&1; then
    rm -f "${tmp_zip}"; tmp_zip="$(mktemp).zip";
    local alt_url2="https://mirror.ghproxy.com/${tf_zip_url}"
    dl "${alt_url2}" "${tmp_zip}" || true
  fi
  mkdir -p "${TP_DIR}/_tmp_tf"
  unzip -q "${tmp_zip}" -d "${TP_DIR}/_tmp_tf" || true
  local tf_root
  tf_root="$(find "${TP_DIR}/_tmp_tf" -maxdepth 1 -type d -name 'tensorflow-*' | head -n 1 || true)"
  if [ -n "${tf_root}" ] && [ -d "${tf_root}/tensorflow/lite" ]; then
    mkdir -p "${incdir}/tensorflow/lite" "${incdir}/tensorflow/lite/kernels" "${incdir}/tensorflow/lite/core/api" "${incdir}/tensorflow/lite/core"
    for f in interpreter.h model.h signature_runner.h allocation.h error_reporter.h op_resolver.h; do
      if [ -f "${tf_root}/tensorflow/lite/${f}" ]; then cp -f "${tf_root}/tensorflow/lite/${f}" "${incdir}/tensorflow/lite/${f}"; fi
      if [ -f "${tf_root}/tensorflow/lite/core/api/${f}" ]; then cp -f "${tf_root}/tensorflow/lite/core/api/${f}" "${incdir}/tensorflow/lite/core/api/${f}"; fi
    done
    if [ -f "${tf_root}/tensorflow/lite/kernels/register.h" ]; then cp -f "${tf_root}/tensorflow/lite/kernels/register.h" "${incdir}/tensorflow/lite/kernels/register.h"; fi
    # 兼容包含的其它常用头
    for f in model_builder.h model_building.h namespace.h optional_debug_tools.h context.h; do
      if [ -f "${tf_root}/tensorflow/lite/${f}" ]; then cp -f "${tf_root}/tensorflow/lite/${f}" "${incdir}/tensorflow/lite/${f}"; fi
    done
    # 拷贝 core 目录下的所有 .h 头文件（包含 core/interpreter.h 等）
    find "${tf_root}/tensorflow/lite/core" -type f -name '*.h' -print0 | while IFS= read -r -d '' hf; do
      rel="${hf#${tf_root}/tensorflow/lite/core/}"
      mkdir -p "${incdir}/tensorflow/lite/core/$(dirname "${rel}")"
      cp -f "${hf}" "${incdir}/tensorflow/lite/core/${rel}"
    done
    # 拷贝 lite/c 目录下的所有 .h（包含 common_internal.h 等）
    if [ -d "${tf_root}/tensorflow/lite/c" ]; then
      mkdir -p "${incdir}/tensorflow/lite/c"
      find "${tf_root}/tensorflow/lite/c" -type f -name '*.h' -print0 | while IFS= read -r -d '' hf; do
        cp -f "${hf}" "${incdir}/tensorflow/lite/c/$(basename "${hf}")"
      done
    fi
    # 拷贝 experimental 目录头文件
    if [ -d "${tf_root}/tensorflow/lite/experimental" ]; then
      find "${tf_root}/tensorflow/lite/experimental" -type f -name '*.h' -print0 | while IFS= read -r -d '' hf; do
        rel="${hf#${tf_root}/tensorflow/lite/experimental/}"
        mkdir -p "${incdir}/tensorflow/lite/experimental/$(dirname "${rel}")"
        cp -f "${hf}" "${incdir}/tensorflow/lite/experimental/${rel}"
      done
    fi
    # 兜底：拷贝 tensorflow/lite 下所有 .h 到 include（保持相对结构）
    find "${tf_root}/tensorflow/lite" -type f -name '*.h' -print0 | while IFS= read -r -d '' hf; do
      rel="${hf#${tf_root}/tensorflow/lite/}"
      mkdir -p "${incdir}/tensorflow/lite/$(dirname "${rel}")"
      cp -f "${hf}" "${incdir}/tensorflow/lite/${rel}"
    done
  fi
  rm -rf "${TP_DIR}/_tmp_tf" "${tmp_zip}"
  # 额外拉取 C API 动态库（libtensorflowlite_c.so），确保无需外部源码编译
  local aar_c_url_default="https://repo1.maven.org/maven2/org/tensorflow/tensorflow-lite-c/${ver}/tensorflow-lite-c-${ver}.aar"
  local aar_c_url="${TFLITE_C_AAR_URL:-${aar_c_url_default}}"
  if [ ! -f "${libdir}/libtensorflowlite_c.so" ]; then
    echo "拉取 TFLite C AAR ${aar_c_url}"
    tmp_aar_c="$(mktemp).aar"
    dl "${aar_c_url}" "${tmp_aar_c}" || true
    unzip -oj "${tmp_aar_c}" "jni/${ABI}/libtensorflowlite_c.so" -d "${libdir}" || true
    rm -f "${tmp_aar_c}"
  fi
  # 不复制 TensorFlow 源头到 third_party；如需启用 TFLite 源编译，请在本地 TF 源中包含相关头
}

# 仅拉取 FlatBuffers 头文件（不包含 flatc 可执行）
fetch_flatbuffers_headers() {
  local dst="${TP_DIR}/tflite/include/flatbuffers"
  mkdir -p "${dst}"
  # 版本与 TFLite 2.13.0 兼容：FlatBuffers v23.x（默认 v23.5.26，可通过 FLATBUFFERS_VER 覆盖）
  local fb_ver="${FLATBUFFERS_VER:-23.1.21}"
  local fb_zip="https://github.com/google/flatbuffers/archive/refs/tags/v${fb_ver}.zip"
  local tmp_zip="$(mktemp).zip"
  echo "拉取 FlatBuffers(${fb_ver}) 头文件 ${fb_zip}"
  dl "$(proxify "${fb_zip}")" "${tmp_zip}" || true
  if ! unzip -t "${tmp_zip}" >/dev/null 2>&1; then
    rm -f "${tmp_zip}"; tmp_zip="$(mktemp).zip";
    local alt_url="${fb_zip/https:\/\/github.com/https:\/\/ghfast.top\/github.com}"
    dl "${alt_url}" "${tmp_zip}" || true
  fi
  if ! unzip -t "${tmp_zip}" >/dev/null 2>&1; then
    rm -f "${tmp_zip}"; tmp_zip="$(mktemp).zip";
    local alt_url2="https://mirror.ghproxy.com/${fb_zip}"
    dl "${alt_url2}" "${tmp_zip}" || true
  fi
  mkdir -p "${TP_DIR}/_tmp_fb"
  unzip -q "${tmp_zip}" -d "${TP_DIR}/_tmp_fb" || true
  local fb_root
  fb_root="$(find "${TP_DIR}/_tmp_fb" -maxdepth 1 -type d -name 'flatbuffers-*' | head -n 1 || true)"
  if [ -n "${fb_root}" ] && [ -d "${fb_root}/include/flatbuffers" ]; then
    rm -rf "${dst}"/*
    rsync -a "${fb_root}/include/flatbuffers/" "${dst}/" || cp -R "${fb_root}/include/flatbuffers/"* "${dst}/" || true
  fi
  rm -rf "${TP_DIR}/_tmp_fb" "${tmp_zip}"
}

fetch_onnxruntime
fetch_tflite
fetch_flatbuffers_headers

echo "third_party 依赖已检查/拉取：ABI=${ABI}"
