#pragma once
#include <string>

int RunONNX(const std::string& model_path,
            const std::string& image_path,
            const std::string& out_dir,
            const std::string& provider,
            int threads,
            const std::string& qnn_context_path="",
            const std::string& qnn_vtcm_mb="0");
