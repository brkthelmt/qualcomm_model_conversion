#pragma once
#include <string>
#include <vector>

struct ImageRGB {
  int width;
  int height;
  std::vector<unsigned char> data;
};

ImageRGB LoadBMP24(const std::string& path);
ImageRGB ResizeNearest(const ImageRGB& src, int dst_w, int dst_h);
bool SaveBMP24(const std::string& path, const ImageRGB& img);
void DrawRect(ImageRGB& img, int x0, int y0, int x1, int y1, unsigned char r, unsigned char g, unsigned char b, int thickness=2);
void DrawText(ImageRGB& img, int x, int y, const std::string& text, unsigned char r, unsigned char g, unsigned char b);
