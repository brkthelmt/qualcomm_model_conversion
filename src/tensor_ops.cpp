#include "tensor_ops.h"
#ifndef DISABLE_TFLITE
#include <tensorflow/lite/interpreter.h>
#include <tensorflow/lite/model.h>
#include <tensorflow/lite/kernels/register.h>
#include <tensorflow/lite/c/c_api_types.h>
#endif
#include <fstream>
#include <filesystem>

#ifndef DISABLE_TFLITE
static std::vector<int> TensorDims(TfLiteTensor* t) {
  std::vector<int> dims;
  for(int i = 0; i < t->dims->size; ++i) dims.push_back(t->dims->data[i]);
  return dims;
}
#endif

std::vector<int> GetInputShapeNHWCOrNCHW(void* interpreter_void) {
#ifndef DISABLE_TFLITE
  auto* interpreter = reinterpret_cast<tflite::Interpreter*>(interpreter_void);
  int idx = interpreter->inputs()[0];
  TfLiteTensor* t = interpreter->tensor(idx);
  auto dims = TensorDims(t);
  return dims;
#else
  return {};
#endif
}

static void ToNHWC(const ImageRGB& img, float* dst, int h, int w) {
  for(int y = 0; y < h; ++y) {
    for(int x = 0; x < w; ++x) {
      const unsigned char* p = img.data.data() + (y * w + x) * 3;
      float r = p[0] / 255.0f;
      float g = p[1] / 255.0f;
      float b = p[2] / 255.0f;
      float* d = dst + (y * w + x) * 3;
      d[0] = r;
      d[1] = g;
      d[2] = b;
    }
  }
}

static void ToNCHW(const ImageRGB& img, float* dst, int h, int w) {
  int plane = h * w;
  float* dr = dst;
  float* dg = dst + plane;
  float* db = dst + plane * 2;
  for(int y = 0; y < h; ++y) {
    for(int x = 0; x < w; ++x) {
      const unsigned char* p = img.data.data() + (y * w + x) * 3;
      float r = p[0] / 255.0f;
      float g = p[1] / 255.0f;
      float b = p[2] / 255.0f;
      int idx = y * w + x;
      dr[idx] = r;
      dg[idx] = g;
      db[idx] = b;
    }
  }
}

void FillInputTensor(void* interpreter_void, const ImageRGB& img, bool nhwc) {
#ifndef DISABLE_TFLITE
  auto* interpreter = reinterpret_cast<tflite::Interpreter*>(interpreter_void);
  int idx = interpreter->inputs()[0];
  TfLiteTensor* t = interpreter->tensor(idx);
  auto dims = TensorDims(t);
  int h, w, c;
  if(dims.size() == 4 && dims[1] == 3) {
    c = 3; h = dims[2]; w = dims[3];
  } else if(dims.size() == 4 && dims[3] == 3) {
    h = dims[1]; w = dims[2]; c = 3;
  } else {
    h = img.height; w = img.width; c = 3;
  }
  ImageRGB resized = (img.width == w && img.height == h) ? img : ResizeNearest(img, w, h);
  if(t->type == kTfLiteFloat32) {
    float* data = interpreter->typed_tensor<float>(idx);
    if(nhwc) ToNHWC(resized, data, h, w); else ToNCHW(resized, data, h, w);
  } else if(t->type == kTfLiteUInt8) {
    float scale = t->params.scale;
    int32_t zp = t->params.zero_point;
    uint8_t* data = interpreter->typed_tensor<uint8_t>(idx);
    if(nhwc) {
      for(int y = 0; y < h; ++y) {
        for(int x = 0; x < w; ++x) {
          const unsigned char* p = resized.data.data() + (y * w + x) * 3;
          float r = p[0] / 255.0f; float g = p[1] / 255.0f; float b = p[2] / 255.0f;
          int base = (y * w + x) * 3;
          data[base+0] = static_cast<uint8_t>(std::max(0.0f, std::min(255.0f, r/scale + zp)));
          data[base+1] = static_cast<uint8_t>(std::max(0.0f, std::min(255.0f, g/scale + zp)));
          data[base+2] = static_cast<uint8_t>(std::max(0.0f, std::min(255.0f, b/scale + zp)));
        }
      }
    } else {
      int plane = h * w;
      for(int y = 0; y < h; ++y) {
        for(int x = 0; x < w; ++x) {
          const unsigned char* p = resized.data.data() + (y * w + x) * 3;
          float r = p[0] / 255.0f; float g = p[1] / 255.0f; float b = p[2] / 255.0f;
          int idx2 = y * w + x;
          data[idx2] = static_cast<uint8_t>(std::max(0.0f, std::min(255.0f, r/scale + zp)));
          data[idx2+plane] = static_cast<uint8_t>(std::max(0.0f, std::min(255.0f, g/scale + zp)));
          data[idx2+plane*2] = static_cast<uint8_t>(std::max(0.0f, std::min(255.0f, b/scale + zp)));
        }
      }
    }
  }
#else
  (void)interpreter_void; (void)img; (void)nhwc;
#endif
}

void DumpOutputs(void* interpreter_void, const std::string& out_dir) {
#ifndef DISABLE_TFLITE
  auto* interpreter = reinterpret_cast<tflite::Interpreter*>(interpreter_void);
  std::filesystem::create_directories(out_dir);
  auto outs = interpreter->outputs();
  for(size_t i = 0; i < outs.size(); ++i) {
    int idx = outs[i];
    TfLiteTensor* t = interpreter->tensor(idx);
    std::string path = out_dir + "/output_" + std::to_string(i) + ".bin";
    std::ofstream o(path, std::ios::binary);
    if(!o) continue;
    size_t bytes = t->bytes;
    o.write(reinterpret_cast<const char*>(t->data.raw), bytes);
    o.close();
    std::string meta = out_dir + "/output_" + std::to_string(i) + ".shape.txt";
    std::ofstream m(meta);
    if(m) {
      for(int d = 0; d < t->dims->size; ++d) {
        m << t->dims->data[d];
        if(d + 1 < t->dims->size) m << " ";
      }
    }
  }
#else
  (void)interpreter_void; (void)out_dir;
#endif
}
