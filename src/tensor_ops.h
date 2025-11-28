#pragma once
#include <vector>
#include <string>
#include <cstdint>
#include "bmp_io.h"

std::vector<int> GetInputShapeNHWCOrNCHW(void* tensor);
void FillInputTensor(void* interpreter, const ImageRGB& img, bool nhwc);
void DumpOutputs(void* interpreter, const std::string& out_dir);

