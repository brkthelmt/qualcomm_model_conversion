cmake_minimum_required(VERSION 3.22)
project(yolo_runner CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(TFLITE_ROOT "${CMAKE_SOURCE_DIR}/third_party/tflite")
set(TFLITE_INCLUDE_DIR "${TFLITE_ROOT}/include")
set(TF_SRC "${CMAKE_SOURCE_DIR}/../tensorflow/tensorflow")

# ONNX Runtime
set(ONNXRUNTIME_ROOT "${CMAKE_SOURCE_DIR}/third_party/onnxruntime")
set(ONNXRUNTIME_INCLUDE_DIR "${ONNXRUNTIME_ROOT}/include")

if(ANDROID)
  if(NOT ANDROID_ABI)
    set(ANDROID_ABI arm64-v8a)
  endif()
  set(TFLITE_LIB_DIR "${TFLITE_ROOT}/lib/${ANDROID_ABI}")
  set(ONNXRUNTIME_LIB_DIR "${ONNXRUNTIME_ROOT}/lib/${ANDROID_ABI}")
  find_library(ANDROID_LOG log)
  find_library(ANDROID_NNAPI neuralnetworks)
else()
  set(TFLITE_LIB_DIR "${TFLITE_ROOT}/lib/host")
  set(ONNXRUNTIME_LIB_DIR "${ONNXRUNTIME_ROOT}/lib/host")
endif()

find_library(TFLITE_LIB NAMES tensorflowlite PATHS "${TFLITE_LIB_DIR}" NO_DEFAULT_PATH)
find_library(TFLITE_C_LIB NAMES tensorflowlite_c PATHS "${TFLITE_LIB_DIR}" NO_DEFAULT_PATH)
find_library(TFLITE_NNAPI_LIB NAMES tensorflowlite_nnapi_delegate PATHS "${TFLITE_LIB_DIR}" NO_DEFAULT_PATH)

# ONNX Runtime core and providers (optional)
find_library(ONNXRUNTIME_LIB NAMES onnxruntime PATHS "${ONNXRUNTIME_LIB_DIR}" NO_DEFAULT_PATH)
find_library(ONNXRUNTIME_PROVIDERS_SHARED NAMES onnxruntime_providers_shared PATHS "${ONNXRUNTIME_LIB_DIR}" NO_DEFAULT_PATH)
find_library(ONNXRUNTIME_PROVIDERS_NNAPI NAMES onnxruntime_providers_nnapi PATHS "${ONNXRUNTIME_LIB_DIR}" NO_DEFAULT_PATH)
find_library(ONNXRUNTIME_PROVIDERS_QNN NAMES onnxruntime_providers_qnn PATHS "${ONNXRUNTIME_LIB_DIR}" NO_DEFAULT_PATH)

set(HAVE_ORT OFF)
if(NOT ONNXRUNTIME_LIB)
  if(EXISTS "${ONNXRUNTIME_LIB_DIR}/libonnxruntime.so")
    set(ONNXRUNTIME_LIB "${ONNXRUNTIME_LIB_DIR}/libonnxruntime.so")
  endif()
endif()
if(NOT ONNXRUNTIME_PROVIDERS_SHARED)
  if(EXISTS "${ONNXRUNTIME_LIB_DIR}/libonnxruntime_providers_shared.so")
    set(ONNXRUNTIME_PROVIDERS_SHARED "${ONNXRUNTIME_LIB_DIR}/libonnxruntime_providers_shared.so")
  endif()
endif()
if(NOT ONNXRUNTIME_PROVIDERS_NNAPI)
  if(EXISTS "${ONNXRUNTIME_LIB_DIR}/libonnxruntime_providers_nnapi.so")
    set(ONNXRUNTIME_PROVIDERS_NNAPI "${ONNXRUNTIME_LIB_DIR}/libonnxruntime_providers_nnapi.so")
  endif()
endif()
if(NOT ONNXRUNTIME_PROVIDERS_QNN)
  if(EXISTS "${ONNXRUNTIME_LIB_DIR}/libonnxruntime_providers_qnn.so")
    set(ONNXRUNTIME_PROVIDERS_QNN "${ONNXRUNTIME_LIB_DIR}/libonnxruntime_providers_qnn.so")
  endif()
endif()
if((EXISTS "${ONNXRUNTIME_INCLUDE_DIR}/onnxruntime_cxx_api.h" OR EXISTS "${ONNXRUNTIME_INCLUDE_DIR}/onnxruntime/core/session/onnxruntime_cxx_api.h") AND ONNXRUNTIME_LIB)
  set(HAVE_ORT ON)
  add_compile_definitions(HAVE_ORT)
endif()

if(NOT TFLITE_LIB)
  if(EXISTS "${TFLITE_LIB_DIR}/libtensorflowlite.so")
    set(TFLITE_LIB "${TFLITE_LIB_DIR}/libtensorflowlite.so")
  elseif(EXISTS "${TFLITE_LIB_DIR}/libtensorflowlite.a")
    set(TFLITE_LIB "${TFLITE_LIB_DIR}/libtensorflowlite.a")
  endif()
endif()

add_executable(yolo_runner
  src/main.cpp
  src/bmp_io.cpp
  src/tensor_ops.cpp
  src/onnx_runner.cpp
  src/qnn_runner.cpp
  ${TF_SRC}/lite/core/c/c_api.cc
  ${TF_SRC}/lite/core/c/c_api_experimental.cc
  ${TF_SRC}/lite/core/c/c_api_opaque.cc
  ${TF_SRC}/lite/core/c/common.cc
  ${TF_SRC}/lite/core/create_op_resolver_with_builtin_ops.cc
  ${TF_SRC}/lite/delegates/interpreter_utils.cc
  ${TF_SRC}/lite/delegates/nnapi/nnapi_delegate_c_api.cc
  ${TF_SRC}/lite/delegates/nnapi/nnapi_delegate_disabled.cc
)

target_include_directories(yolo_runner PRIVATE
  "${TFLITE_INCLUDE_DIR}"
  "${CMAKE_SOURCE_DIR}/src"
  
  
  "${TF_SRC}"
  "${CMAKE_SOURCE_DIR}/third_party/eigen3"
)

target_include_directories(yolo_runner PRIVATE "${ONNXRUNTIME_INCLUDE_DIR}")

if(APPLE)
  if(EXISTS "/opt/homebrew/include/flatbuffers")
    target_include_directories(yolo_runner PRIVATE "/opt/homebrew/include")
  elseif(EXISTS "/usr/local/include/flatbuffers")
    target_include_directories(yolo_runner PRIVATE "/usr/local/include")
  endif()
  if(EXISTS "/opt/homebrew/include/eigen3")
    include_directories("/opt/homebrew/include/eigen3")
  endif()
endif()

target_link_libraries(yolo_runner
  ${TFLITE_LIB}
)
if(ONNXRUNTIME_LIB)
  target_link_libraries(yolo_runner ${ONNXRUNTIME_LIB})
endif()
if(ONNXRUNTIME_PROVIDERS_SHARED)
  target_link_libraries(yolo_runner ${ONNXRUNTIME_PROVIDERS_SHARED})
endif()

# 链接核心 TFLite（C API 实现在可执行中编译）

if(ANDROID)
  if(TFLITE_NNAPI_LIB)
    target_link_libraries(yolo_runner ${TFLITE_NNAPI_LIB})
  endif()
  if(ANDROID_LOG)
    target_link_libraries(yolo_runner ${ANDROID_LOG})
  endif()
  if(ANDROID_NNAPI)
    target_link_libraries(yolo_runner ${ANDROID_NNAPI})
  endif()
  # Link optional ORT provider libs when present
  if(ONNXRUNTIME_PROVIDERS_NNAPI)
    target_link_libraries(yolo_runner ${ONNXRUNTIME_PROVIDERS_NNAPI})
  endif()
  if(ONNXRUNTIME_PROVIDERS_QNN)
    target_link_libraries(yolo_runner ${ONNXRUNTIME_PROVIDERS_QNN})
  endif()
endif()

# QNN SDK detection and linkage
set(QNN_SDK_ROOT "$ENV{QNN_SDK_ROOT}")
if(QNN_SDK_ROOT)
  set(QNN_INCLUDE_DIR "${QNN_SDK_ROOT}/include")
  include_directories("${QNN_INCLUDE_DIR}")
  set(QNN_LIB_DIR "${QNN_SDK_ROOT}/lib/aarch64-android")
  if(NOT EXISTS "${QNN_LIB_DIR}")
    set(QNN_LIB_DIR "${QNN_SDK_ROOT}/lib/arm64-v8a")
  endif()
  find_library(QNN_HTP_LIB NAMES QnnHtp PATHS "${QNN_LIB_DIR}" NO_DEFAULT_PATH)
  find_library(QNN_SYSTEM_LIB NAMES QnnSystem PATHS "${QNN_LIB_DIR}" NO_DEFAULT_PATH)
  if(QNN_HTP_LIB AND QNN_SYSTEM_LIB)
    add_compile_definitions(HAVE_QNN)
    target_link_libraries(yolo_runner ${QNN_HTP_LIB} ${QNN_SYSTEM_LIB})
  endif()
endif()
