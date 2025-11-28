#include "qnn_runner.h"
#include <vector>
#include <string>
#include <fstream>
#include <iostream>
#include <filesystem>
#include "bmp_io.h"

#ifdef HAVE_QNN
#include <QNN/QnnInterface.h>
#include <QNN/HTP/QnnHtpDevice.h>
#include <QNN/QnnBackend.h>
#include <QNN/QnnContext.h>
#include <QNN/QnnGraph.h>
#endif

static std::vector<uint8_t> read_bin(const std::string& path){
  std::ifstream f(path, std::ios::binary);
  if(!f) return {};
  f.seekg(0,std::ios::end); size_t n=(size_t)f.tellg(); f.seekg(0,std::ios::beg);
  std::vector<uint8_t> buf(n); f.read(reinterpret_cast<char*>(buf.data()), n);
  return buf;
}

int RunQNN(const std::string& context_bin_path,
           const std::string& image_path,
           const std::string& out_dir,
           int threads){
  auto ctx = read_bin(context_bin_path);
  if(ctx.empty()){ std::cerr << "qnn_context_binary_read_fail" << std::endl; return 2; }
  std::cout << "qnn_context_bytes=" << ctx.size() << std::endl;

#ifndef HAVE_QNN
  std::cerr << "qnn_sdk_missing" << std::endl;
  return 3;
#else
  // Minimal QNN flow: create backend, device, context from binary, run default graph
  const QnnInterface_t* qnn = QnnInterface_getProviders();
  if(!qnn){ std::cerr << "qnn_interface_null" << std::endl; return 4; }

  Qnn_BackendHandle_t backend = nullptr;
  QnnDevice_Config_t dev_cfg = { QNN_DEVICE_CONFIG_TYPE_HTP, { .htpConfig = { QNN_HTP_PERFORMANCE_MODE_BURST } } };
  if(qnn->qnnBackendCreate(&backend, nullptr) != QNN_SUCCESS){ std::cerr << "backend_create_fail" << std::endl; return 5; }

  Qnn_DeviceHandle_t device = nullptr;
  if(qnn->qnnDeviceCreate(backend, &dev_cfg, 1, &device) != QNN_SUCCESS){ std::cerr << "device_create_fail" << std::endl; return 6; }

  Qnn_ContextHandle_t context = nullptr;
  QnnContext_Config_t ctx_cfg{};
  if(qnn->qnnContextCreateFromBinary(device, &ctx_cfg, 0, ctx.data(), ctx.size(), &context) != QNN_SUCCESS){ std::cerr << "context_create_from_binary_fail" << std::endl; return 7; }

  // Locate first graph
  uint32_t graph_count = 0;
  if(qnn->qnnContextGetGraphsCount(context, &graph_count) != QNN_SUCCESS || graph_count == 0){ std::cerr << "no_graph" << std::endl; return 8; }
  std::vector<Qnn_GraphHandle_t> graphs(graph_count);
  if(qnn->qnnContextGetGraphs(context, graphs.data(), graph_count) != QNN_SUCCESS){ std::cerr << "get_graphs_fail" << std::endl; return 9; }
  Qnn_GraphHandle_t graph = graphs[0];

  // Prepare a dummy execution (actual IO binding depends on context specs)
  // For now, execute with no inputs to validate path; advanced IO mapping would parse tensors from context
  if(qnn->qnnGraphExecute(graph, nullptr, 0, nullptr, 0, nullptr) != QNN_SUCCESS){ std::cerr << "graph_execute_fail" << std::endl; return 10; }

  // Cleanup
  qnn->qnnContextDestroy(context);
  qnn->qnnDeviceDestroy(device);
  qnn->qnnBackendDestroy(backend);
  std::filesystem::create_directories(out_dir);
  std::cout << "done" << std::endl;
  return 0;
#endif
}

