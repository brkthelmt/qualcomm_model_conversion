#include "onnx_runner.h"
#include <onnxruntime_cxx_api.h>
#include <onnxruntime_c_api.h>
#include <nnapi_provider_factory.h>
#include <vector>
#include <fstream>
#include <iostream>
#include <filesystem>
#include "bmp_io.h"

static void write_shape(const std::string& path, const std::vector<int64_t>& shape){
  std::ofstream os(path);
  if(os){
    for(size_t i=0;i<shape.size();++i){ os<<shape[i]; if(i+1<shape.size()) os<<" "; }
  }
}

static void write_bin(const std::string& path, const void* data, size_t bytes){
  std::ofstream os(path, std::ios::binary);
  if(os && data){ os.write(reinterpret_cast<const char*>(data), bytes); }
}

static std::vector<int64_t> get_input_shape(const Ort::Session& session, size_t index){
  Ort::AllocatorWithDefaultOptions alloc;
  auto info = session.GetInputTypeInfo(index);
  auto tensor_info = info.GetTensorTypeAndShapeInfo();
  auto shape = tensor_info.GetShape();
  return shape;
}

static ONNXTensorElementDataType get_input_type(const Ort::Session& session, size_t index){
  auto info = session.GetInputTypeInfo(index);
  auto tensor_info = info.GetTensorTypeAndShapeInfo();
  return tensor_info.GetElementType();
}

static bool is_nhwc_from_shape(const std::vector<int64_t>& shape){
  if(shape.size()==4){
    // Heuristic: NHWC if last dim == 3 (RGB)
    return shape[3]==3;
  }
  return true;
}

static void preprocess_image_float(const ImageRGB& img, int h, int w, bool nhwc, std::vector<float>& out){
  ImageRGB resized = (img.width==w && img.height==h) ? img : ResizeNearest(img, w, h);
  out.resize(h*w*3);
  if(nhwc){
    for(int y=0;y<h;++y){ for(int x=0;x<w;++x){ const unsigned char* p = resized.data.data() + (y*w + x)*3; float* d = out.data() + (y*w + x)*3; d[0]=p[0]/255.0f; d[1]=p[1]/255.0f; d[2]=p[2]/255.0f; }}
  }else{
    int plane=h*w; for(int y=0;y<h;++y){ for(int x=0;x<w;++x){ const unsigned char* p = resized.data.data() + (y*w + x)*3; int idx=y*w+x; out[idx]=p[0]/255.0f; out[idx+plane]=p[1]/255.0f; out[idx+plane*2]=p[2]/255.0f; }}
  }
}

static uint16_t float_to_half(float v){
  uint32_t x = *(uint32_t*)&v;
  uint16_t h = ((x >> 16) & 0x8000);
  uint32_t m = (x & 0x7fffffff);
  if (m > 0x47ffefff) { h |= 0x7c00; }
  else if (m < 0x38800000) {
    uint32_t t = (m & 0x7fffff) | 0x800000;
    int32_t e = 113 - (int32_t)(m >> 23);
    t = (t >> e);
    h |= (uint16_t)(t + ((t >> 13) & 1) >> 13);
  } else {
    m += 0xC8000000;
    h |= (uint16_t)(((m >> 13) + ((m >> 13) & 1)) & 0x7fff);
  }
  return h;
}

static void enable_provider(Ort::SessionOptions& so, const std::string& provider){
  if(provider=="nnapi"){
    try {
      uint32_t flags = 0; // NNAPI_FLAG_USE_NONE
      OrtSessionOptionsAppendExecutionProvider_Nnapi(so, flags);
    } catch(...) {
      // ignore
    }
  } else {
    // other providers not enabled in this build
  }
}

int RunONNX(const std::string& model_path,
            const std::string& image_path,
            const std::string& out_dir,
            const std::string& provider,
            int threads,
            const std::string& qnn_context_path){
  Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "yolo_runner_onnx");
  Ort::SessionOptions so;
  if(threads>0) so.SetIntraOpNumThreads(threads);
  so.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
  enable_provider(so, provider);
  if(provider=="qnn"){
    if(!qnn_context_path.empty()){
      std::ifstream f(qnn_context_path, std::ios::binary);
      if(f){
        f.seekg(0,std::ios::end); size_t bytes = (size_t)f.tellg(); f.seekg(0,std::ios::beg);
        std::vector<uint8_t> buf(bytes); f.read(reinterpret_cast<char*>(buf.data()), bytes);
        std::cout << "qnn_context_binary loaded, bytes=" << bytes << std::endl;
      } else {
        std::cout << "qnn_context_binary not found: " << qnn_context_path << std::endl;
      }
    } else {
      std::cout << "qnn_context_binary path is empty" << std::endl;
    }
  }

  Ort::Session session(env, model_path.c_str(), so);
  ImageRGB img = LoadBMP24(image_path);

  size_t n_inputs = session.GetInputCount();
  if(n_inputs == 0) throw std::runtime_error("no input");
  auto shape = get_input_shape(session, 0);
  auto in_type = get_input_type(session, 0);
  std::cout << "input_type=" << (int)in_type << std::endl;
  bool nhwc = is_nhwc_from_shape(shape);
  int h = 0, w = 0;
  if(shape.size()==4){
    if(nhwc){ h = (int)shape[1]; w = (int)shape[2]; }
    else { h = (int)shape[2]; w = (int)shape[3]; }
  } else {
    // fallback guess
    h = img.height; w = img.width;
  }

  std::vector<int64_t> input_dims;
  if(nhwc){ input_dims = {1, h, w, 3}; }
  else { input_dims = {1, 3, h, w}; }

  Ort::MemoryInfo mem = Ort::MemoryInfo::CreateCpu(OrtDeviceAllocator, OrtMemTypeDefault);
  Ort::Value input_tensor{nullptr};
  if(in_type == ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT){
    std::vector<float> input_buf;
    preprocess_image_float(img, h, w, nhwc, input_buf);
    input_tensor = Ort::Value::CreateTensor<float>(mem, input_buf.data(), input_buf.size(), input_dims.data(), input_dims.size());
  } else if(in_type == ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT16){
    std::vector<float> tmp;
    preprocess_image_float(img, h, w, nhwc, tmp);
    std::vector<uint16_t> half(tmp.size());
    for(size_t i=0;i<tmp.size();++i) half[i] = float_to_half(tmp[i]);
    input_tensor = Ort::Value::CreateTensor<uint16_t>(mem, half.data(), half.size(), input_dims.data(), input_dims.size());
  } else if(in_type == ONNX_TENSOR_ELEMENT_DATA_TYPE_BFLOAT16){
    std::vector<float> tmp;
    preprocess_image_float(img, h, w, nhwc, tmp);
    std::vector<uint16_t> bf(tmp.size());
    for(size_t i=0;i<tmp.size();++i){
      uint32_t x = *(uint32_t*)&tmp[i];
      bf[i] = (uint16_t)(x >> 16);
    }
    input_tensor = Ort::Value::CreateTensor<uint16_t>(mem, bf.data(), bf.size(), input_dims.data(), input_dims.size());
  } else if(in_type == ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT16){
    std::vector<float> tmp;
    preprocess_image_float(img, h, w, nhwc, tmp);
    std::vector<uint16_t> u(tmp.size());
    for(size_t i=0;i<tmp.size();++i){
      float v = tmp[i]; if(v<0.f) v=0.f; if(v>1.f) v=1.f;
      uint32_t q = (uint32_t)(v * 65535.0f + 0.5f);
      if(q>65535U) q=65535U;
      u[i] = (uint16_t)q;
    }
    input_tensor = Ort::Value::CreateTensor<uint16_t>(mem, u.data(), u.size(), input_dims.data(), input_dims.size());
  } else {
    throw std::runtime_error("unsupported input type");
  }

  std::vector<Ort::AllocatedStringPtr> input_name_ptrs;
  std::vector<const char*> input_names;
  {
    Ort::AllocatorWithDefaultOptions alloc;
    for(size_t i=0;i<n_inputs;++i){ input_name_ptrs.emplace_back(session.GetInputNameAllocated(i, alloc)); }
    for(auto& p: input_name_ptrs){ input_names.push_back(p.get()); }
  }
  size_t n_outputs = session.GetOutputCount();
  std::vector<Ort::AllocatedStringPtr> output_name_ptrs;
  std::vector<const char*> output_names;
  {
    Ort::AllocatorWithDefaultOptions alloc;
    for(size_t i=0;i<n_outputs;++i){ output_name_ptrs.emplace_back(session.GetOutputNameAllocated(i, alloc)); }
    for(auto& p: output_name_ptrs){ output_names.push_back(p.get()); }
  }
  auto output = session.Run(Ort::RunOptions{nullptr}, input_names.data(), &input_tensor, 1, output_names.data(), output_names.size());

  std::filesystem::create_directories(out_dir);
  // Dump all outputs
  for(size_t i=0;i<output.size(); ++i){
    auto& v = output[i];
    auto ti = v.GetTensorTypeAndShapeInfo();
    auto out_shape = ti.GetShape();
    auto elem_type = ti.GetElementType();
    size_t elem_count = ti.GetElementCount();
    std::string base = out_dir + "/output_" + std::to_string(i);
    write_shape(base + ".shape.txt", out_shape);
    if(elem_type == ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT){
      const float* p = v.GetTensorData<float>();
      write_bin(base + ".bin", p, elem_count * sizeof(float));
    } else if(elem_type == ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8){
      const uint8_t* p = v.GetTensorData<uint8_t>();
      write_bin(base + ".bin", p, elem_count * sizeof(uint8_t));
    } else if(elem_type == ONNX_TENSOR_ELEMENT_DATA_TYPE_INT8){
      const int8_t* p = v.GetTensorData<int8_t>();
      write_bin(base + ".bin", p, elem_count * sizeof(int8_t));
    } else {
      // fallback as float via copy
      const float* p = v.GetTensorData<float>();
      write_bin(base + ".bin", p, elem_count * sizeof(float));
    }
  }

  return 0;
}
