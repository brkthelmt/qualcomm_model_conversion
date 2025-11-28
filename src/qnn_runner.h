#pragma once
#include <string>

int RunQNN(const std::string& context_bin_path,
           const std::string& image_path,
           const std::string& out_dir,
           int threads);

