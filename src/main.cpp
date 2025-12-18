#include <string>
#include <vector>
#include <stdexcept>
#include <iostream>
#include <fstream>
#include <sstream>
#include <filesystem>
#ifndef DISABLE_TFLITE
#include <tensorflow/lite/c/c_api.h>
#include <tensorflow/lite/core/c/c_api_experimental.h>
#endif
#include "bmp_io.h"
#include "tensor_ops.h"
#ifdef HAVE_ORT
#include "onnx_runner.h"
#endif

static std::string getArg(int argc, char** argv, const std::string& key, const std::string& defv) {
  for(int i = 1; i < argc - 1; ++i) if(std::string(argv[i]) == key) return argv[i+1];
  return defv;
}

int main(int argc, char** argv) {
  try {
    std::string model_path = getArg(argc, argv, "--model", "model.tflite");
    std::string image_path = getArg(argc, argv, "--image", "image.bmp");
    std::string out_dir = getArg(argc, argv, "--output", "output");
    std::string delegate = getArg(argc, argv, "--delegate", "cpu");
    std::string labels_path = getArg(argc, argv, "--labels", "");
    std::string boxes_path = getArg(argc, argv, "--boxes", "");
    std::string overlay_only = getArg(argc, argv, "--overlay-only", "false");
    int threads = std::stoi(getArg(argc, argv, "--threads", "4"));
    if(!boxes_path.empty() && overlay_only == "true") {
      ImageRGB img_local = LoadBMP24(image_path);
      std::ifstream bf(boxes_path);
      std::vector<std::string> labels;
      if(!labels_path.empty()){
        std::ifstream lf(labels_path);
        std::string l;
        while(std::getline(lf, l)) { if(!l.empty() && l.back()=='\r') l.pop_back(); labels.push_back(l); }
      }
      std::string line;
      while(std::getline(bf, line)){
        if(line.empty()) continue;
        std::istringstream iss(line);
        int x0,y0,x1,y1,cls; float score;
        iss >> x0 >> y0 >> x1 >> y1 >> score >> cls;
        DrawRect(img_local, x0, y0, x1, y1, 255, 0, 0, 2);
        std::string name = (cls >=0 && cls < (int)labels.size()) ? labels[cls] : std::to_string(cls);
        std::ostringstream os; os << name << " " << int(score*100+0.5) << "%";
        DrawText(img_local, x0+2, std::max(0,y0-10), os.str(), 255, 255, 0);
      }
      std::filesystem::create_directories(out_dir);
      SaveBMP24(out_dir + "/annotated.bmp", img_local);
      std::cout << "done" << std::endl;
      return 0;
    }
    // ONNX 部署路径：若模型为 .onnx，使用 ONNX Runtime 执行
    // - Android NNAPI: 通过传入 `--delegate nnapi` 触发在 RunONNX 中启用 NNAPI Execution Provider
    // - CPU: 其它情况走 ORT 默认 CPU
    #ifdef HAVE_ORT
    if(model_path.size()>=5 && model_path.substr(model_path.size()-5)==".onnx"){
      std::cout << "Info: Detected .onnx extension, switching to ONNX Runtime." << std::endl;
      int rc = RunONNX(model_path, image_path, out_dir, delegate, threads);
      if(rc!=0) throw std::runtime_error("onnx_run");
      std::cout << "done" << std::endl;
      return 0;
    }
    #endif

    

#ifndef DISABLE_TFLITE
    std::cout << "Info: Defaulting to TFLite Runtime." << std::endl;
    TfLiteModel* model = TfLiteModelCreateFromFile(model_path.c_str());
    if(!model) throw std::runtime_error("model");
    TfLiteInterpreterOptions* options = TfLiteInterpreterOptionsCreate();
    TfLiteInterpreterOptionsSetNumThreads(options, threads);
    // TFLite 部署路径：使用 TFLite C API 执行 .tflite 模型
    // - Android NNAPI: 传入 `--delegate nnapi` 时启用 NNAPI delegate，使算子在设备神经网络硬件上运行
    // - CPU: 默认在 CPU 上执行
    if(delegate == "nnapi") {
      TfLiteInterpreterOptionsSetUseNNAPI(options, true);
    }
    TfLiteInterpreter* interpreter = TfLiteInterpreterCreate(model, options);
    if(!interpreter) throw std::runtime_error("interpreter");
    if(TfLiteInterpreterAllocateTensors(interpreter) != kTfLiteOk) throw std::runtime_error("allocate");
    TfLiteTensor* input = TfLiteInterpreterGetInputTensor(interpreter, 0);
    std::vector<int> dims;
    int nd = TfLiteTensorNumDims(input);
    for(int i=0;i<nd;++i) dims.push_back(TfLiteTensorDim(input,i));
    bool nhwc = false;
    int h = 0, w = 0;
    if(dims.size() == 4 && dims[3] == 3) { nhwc = true; h = dims[1]; w = dims[2]; }
    else if(dims.size() == 4 && dims[1] == 3) { nhwc = false; h = dims[2]; w = dims[3]; }
    else { nhwc = true; }
    ImageRGB img = LoadBMP24(image_path);
    ImageRGB resized = (img.width == w && img.height == h) ? img : ResizeNearest(img, w, h);
    if(input->type == kTfLiteFloat32) {
      std::vector<float> buf;
      if(nhwc) {
        buf.resize(h*w*3);
        for(int y=0;y<h;++y){ for(int x=0;x<w;++x){ const unsigned char* p = resized.data.data() + (y*w + x)*3; float* d = buf.data() + (y*w + x)*3; d[0]=p[0]/255.0f; d[1]=p[1]/255.0f; d[2]=p[2]/255.0f; }}
      } else {
        buf.resize(h*w*3);
        int plane=h*w; for(int y=0;y<h;++y){ for(int x=0;x<w;++x){ const unsigned char* p = resized.data.data() + (y*w + x)*3; int idx=y*w+x; buf[idx]=p[0]/255.0f; buf[idx+plane]=p[1]/255.0f; buf[idx+plane*2]=p[2]/255.0f; }}
      }
      if(TfLiteTensorCopyFromBuffer(input, buf.data(), buf.size()*sizeof(float)) != kTfLiteOk) throw std::runtime_error("copy input");
    } else if(input->type == kTfLiteUInt8) {
      std::vector<uint8_t> buf;
      float scale = input->params.scale; int32_t zp = input->params.zero_point;
      auto quant = [&](float v)->uint8_t{ float q=v/scale + zp; if(q<0) q=0; if(q>255) q=255; return (uint8_t)q; };
      if(nhwc) {
        buf.resize(h*w*3);
        for(int y=0;y<h;++y){ for(int x=0;x<w;++x){ const unsigned char* p = resized.data.data() + (y*w + x)*3; int base=(y*w + x)*3; buf[base+0]=quant(p[0]/255.0f); buf[base+1]=quant(p[1]/255.0f); buf[base+2]=quant(p[2]/255.0f); }}
      } else {
        buf.resize(h*w*3);
        int plane=h*w; for(int y=0;y<h;++y){ for(int x=0;x<w;++x){ const unsigned char* p = resized.data.data() + (y*w + x)*3; int idx=y*w+x; buf[idx]=quant(p[0]/255.0f); buf[idx+plane]=quant(p[1]/255.0f); buf[idx+plane*2]=quant(p[2]/255.0f); }}
      }
      if(TfLiteTensorCopyFromBuffer(input, buf.data(), buf.size()*sizeof(uint8_t)) != kTfLiteOk) throw std::runtime_error("copy input");
    }

    if(TfLiteInterpreterInvoke(interpreter) != kTfLiteOk) throw std::runtime_error("invoke");
    std::filesystem::create_directories(out_dir);
    int nout = TfLiteInterpreterGetOutputTensorCount(interpreter);
    for(int i=0;i<nout;++i){ const TfLiteTensor* t = TfLiteInterpreterGetOutputTensor(interpreter,i); size_t bytes = TfLiteTensorByteSize(t); const void* data = TfLiteTensorData(t); std::string p = out_dir + "/output_" + std::to_string(i) + ".bin"; std::ofstream o(p, std::ios::binary); if(o && data){ o.write(reinterpret_cast<const char*>(data), bytes); }
      std::string s = out_dir + "/output_" + std::to_string(i) + ".shape.txt"; std::ofstream m(s); if(m){ int nd=TfLiteTensorNumDims(t); for(int d=0; d<nd; ++d){ m<<TfLiteTensorDim(t,d); if(d+1<nd) m<<" "; } }
      std::string q = out_dir + "/output_" + std::to_string(i) + ".quant.txt"; std::ofstream qf(q); if(qf){ qf << (int)t->type << " " << t->params.scale << " " << t->params.zero_point; }
    }

    if(!labels_path.empty()) {
      std::ifstream lf(labels_path);
      std::vector<std::string> labels;
      std::string line;
      while(std::getline(lf, line)) { if(!line.empty() && line.back()=='\r') line.pop_back(); labels.push_back(line); }
      if(TfLiteInterpreterGetOutputTensorCount(interpreter)>0) {
        const TfLiteTensor* t = TfLiteInterpreterGetOutputTensor(interpreter,0);
        std::vector<float> vec;
        if(t->type==kTfLiteFloat32) {
          size_t n = TfLiteTensorByteSize(t)/sizeof(float);
          const float* p = static_cast<const float*>(TfLiteTensorData(t));
          vec.assign(p,p+n);
        } else if(t->type==kTfLiteUInt8) {
          size_t n = TfLiteTensorByteSize(t);
          const uint8_t* p = static_cast<const uint8_t*>(TfLiteTensorData(t));
          vec.resize(n);
          float s=t->params.scale; int zp=t->params.zero_point;
          for(size_t i=0;i<n;++i) vec[i]=(int(p[i])-zp)*s;
        }
        if(!vec.empty()) {
          std::vector<int> idx(vec.size());
          for(size_t i=0;i<idx.size();++i) idx[i]=int(i);
          size_t k = std::min<size_t>(5, idx.size());
          std::partial_sort(idx.begin(), idx.begin()+k, idx.end(), [&](int a,int b){return vec[a]>vec[b];});
          std::filesystem::create_directories(out_dir);
          std::ofstream pf(out_dir+"/predictions_top5.txt");
          for(size_t i=0;i<k;++i){ int id=idx[i]; float score=vec[id]; std::string name=(id<(int)labels.size()?labels[id]:std::to_string(id)); std::cout<<"top"<<(i+1)<<": "<<id<<" "<<score<<" "<<name<<std::endl; if(pf) pf<<id<<"\t"<<score<<"\t"<<name<<"\n"; }
        }
      }
    }
    // YOLO box visualization (best-effort generic decode)
    try {
      bool is_yolo = (model_path.find("yolo") != std::string::npos) || (model_path.find("YOLO") != std::string::npos);
      ImageRGB vis = img; // draw on original image
      if(is_yolo){
        int oc = TfLiteInterpreterGetOutputTensorCount(interpreter);
        const TfLiteTensor* t0 = oc>0 ? TfLiteInterpreterGetOutputTensor(interpreter,0) : nullptr; // boxes [N,4]
        const TfLiteTensor* t1 = oc>1 ? TfLiteInterpreterGetOutputTensor(interpreter,1) : nullptr; // obj [N]
        const TfLiteTensor* t2 = oc>2 ? TfLiteInterpreterGetOutputTensor(interpreter,2) : nullptr; // class id or score [N]
        {
          std::ofstream meta(out_dir + "/yolo_meta.txt");
          if(meta){
            auto dump_t = [&](const TfLiteTensor* t, const char* name){ if(!t){ meta << name << ": none\n"; return; } meta << name << ": type=" << (int)t->type << " dims="; int nd=TfLiteTensorNumDims(t); for(int i=0;i<nd;++i){ meta << TfLiteTensorDim(t,i); if(i+1<nd) meta << ","; } meta << " bytes=" << t->bytes << "\n"; };
            meta << "outputs=" << oc << "\n";
            dump_t(t0, "t0"); dump_t(t1, "t1"); dump_t(t2, "t2");
            // sample values
            auto dump_vals = [&](const TfLiteTensor* t, const char* name){ meta << name << "_sample:"; if(!t){ meta << " none\n"; return;} size_t n = 0; if(t->type==kTfLiteFloat32){ n = std::min<size_t>(12, t->bytes/sizeof(float)); const float* p = reinterpret_cast<const float*>(t->data.raw); for(size_t i=0;i<n;++i) meta << " " << p[i]; } else if(t->type==kTfLiteUInt8){ n = std::min<size_t>(12, t->bytes); const uint8_t* p = reinterpret_cast<const uint8_t*>(t->data.raw); float s=t->params.scale; int zp=t->params.zero_point; for(size_t i=0;i<n;++i) meta << " " << (int(p[i])-zp)*s; } else if(t->type==kTfLiteInt8){ n = std::min<size_t>(12, t->bytes); const int8_t* p = reinterpret_cast<const int8_t*>(t->data.raw); float s=t->params.scale; int zp=t->params.zero_point; for(size_t i=0;i<n;++i) meta << " " << (int(p[i])-zp)*s; } meta << "\n"; };
            dump_vals(t0, "t0"); dump_vals(t1, "t1");
          }
        }
        auto read_tensor = [&](const TfLiteTensor* t){ std::vector<float> v; if(!t) return v; if(t->type==kTfLiteFloat32){ size_t n= t->bytes/sizeof(float); const float* p = reinterpret_cast<const float*>(t->data.raw); v.assign(p,p+n);} else if(t->type==kTfLiteUInt8){ size_t n=t->bytes; const uint8_t* p = reinterpret_cast<const uint8_t*>(t->data.raw); v.resize(n); float s=t->params.scale; int zp=t->params.zero_point; for(size_t i=0;i<n;++i) v[i]=(int(p[i])-zp)*s;} else if(t->type==kTfLiteInt8){ size_t n=t->bytes; const int8_t* p = reinterpret_cast<const int8_t*>(t->data.raw); v.resize(n); float s=t->params.scale; int zp=t->params.zero_point; for(size_t i=0;i<n;++i) v[i]=(int(p[i])-zp)*s;} return v; };
        auto boxes_buf = read_tensor(t0);
        auto obj_buf   = read_tensor(t1);
        auto cls_buf   = read_tensor(t2);
        int N = 0;
        if(t0 && TfLiteTensorNumDims(t0)>=2){ N = TfLiteTensorDim(t0, TfLiteTensorNumDims(t0)==3 ? 1 : 0); }
        auto sigmoid=[](float x){ return 1.0f/(1.0f+std::exp(-x)); };
        struct Box{ float x0,y0,x1,y1,score; int cls; };
        std::vector<Box> boxes;
        if(N>0 && (int)boxes_buf.size() >= N*4){
          for(int i=0;i<N;++i){ float cx=boxes_buf[i*4+0], cy=boxes_buf[i*4+1], w=boxes_buf[i*4+2], h=boxes_buf[i*4+3]; float sx = (cx<=1.f && cy<=1.f && w<=1.f && h<=1.f) ? img.width : 1.f; float sy = (cx<=1.f && cy<=1.f && w<=1.f && h<=1.f) ? img.height : 1.f; float x0=(cx - w*0.5f)*sx, y0=(cy - h*0.5f)*sy, x1=(cx + w*0.5f)*sx, y1=(cy + h*0.5f)*sy; float obj = (int)obj_buf.size()>i ? obj_buf[i] : 0.f; float area = std::max(0.f,(x1-x0)) * std::max(0.f,(y1-y0)); float score = std::max(obj, area / (img.width * img.height)); int cls = (int)cls_buf.size()>i ? (int)std::round(cls_buf[i]) : 0; boxes.push_back({x0,y0,x1,y1,score,cls}); }
          // NMS
          std::vector<int> order(boxes.size()); for(size_t i=0;i<order.size();++i) order[i]=int(i);
          std::sort(order.begin(), order.end(), [&](int a,int b){ return boxes[a].score>boxes[b].score; });
          std::vector<Box> keep; size_t max_keep = std::min<size_t>(100, boxes.size());
          auto iou=[&](const Box& A, const Box& B){ float x0=std::max(A.x0,B.x0), y0=std::max(A.y0,B.y0), x1=std::min(A.x1,B.x1), y1=std::min(A.y1,B.y1); float iw=std::max(0.f,x1-x0), ih=std::max(0.f,y1-y0); float inter=iw*ih; float areaA=(A.x1-A.x0)*(A.y1-A.y0), areaB=(B.x1-B.x0)*(B.y1-B.y0); return inter/(areaA+areaB-inter+1e-6f); };
          for(int idx: order){ bool sup=false; for(const auto& k: keep){ if(iou(boxes[idx],k)>0.45f){ sup=true; break; } } if(!sup) keep.push_back(boxes[idx]); if(keep.size()>=max_keep) break; }
          for(const auto& b: keep){ DrawRect(vis, int(b.x0), int(b.y0), int(b.x1), int(b.y1), 255,0,0,2); }
          SaveBMP24(out_dir + "/annotated.bmp", vis);
        }
      }
    } catch(...) { /* ignore visualization errors */ }
    TfLiteInterpreterDelete(interpreter);
    TfLiteInterpreterOptionsDelete(options);
    TfLiteModelDelete(model);
    std::cout << "done" << std::endl;
    return 0;
#else
    throw std::runtime_error("tflite_disabled");
#endif
  } catch(const std::exception& e) {
    std::cerr << e.what() << std::endl;
    return 1;
  }
}
