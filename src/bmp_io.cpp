#include "bmp_io.h"
#include <stdexcept>
#include <fstream>
#include <cstdint>

static uint32_t ReadLE32(const unsigned char* p) {
  return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}

ImageRGB LoadBMP24(const std::string& path) {
  std::ifstream f(path, std::ios::binary);
  if(!f) throw std::runtime_error("open bmp");
  unsigned char header[14];
  f.read(reinterpret_cast<char*>(header), 14);
  if(!f) throw std::runtime_error("read bmp header");
  if(header[0] != 'B' || header[1] != 'M') throw std::runtime_error("not bmp");
  unsigned char dib[40];
  f.read(reinterpret_cast<char*>(dib), 40);
  if(!f) throw std::runtime_error("read dib");
  uint32_t width = ReadLE32(dib + 4);
  int32_t height_signed = static_cast<int32_t>(ReadLE32(dib + 8));
  uint32_t height = height_signed < 0 ? static_cast<uint32_t>(-height_signed) : static_cast<uint32_t>(height_signed);
  uint16_t planes = uint16_t(dib[12] | (dib[13] << 8));
  uint16_t bpp = uint16_t(dib[14] | (dib[15] << 8));
  uint32_t compression = ReadLE32(dib + 16);
  if(planes != 1 || bpp != 24 || compression != 0) throw std::runtime_error("bmp format");
  uint32_t offset = ReadLE32(header + 10);
  f.seekg(offset, std::ios::beg);
  size_t row_stride = ((width * 3 + 3) / 4) * 4;
  std::vector<unsigned char> data(width * height * 3);
  bool top_down = height_signed < 0;
  for(uint32_t y = 0; y < height; ++y) {
    std::vector<unsigned char> row(row_stride);
    f.read(reinterpret_cast<char*>(row.data()), row_stride);
    if(!f) throw std::runtime_error("read row");
    uint32_t dst_y = top_down ? y : (height - 1 - y);
    unsigned char* dst = data.data() + dst_y * width * 3;
    for(uint32_t x = 0; x < width; ++x) {
      unsigned char b = row[x * 3 + 0];
      unsigned char g = row[x * 3 + 1];
      unsigned char r = row[x * 3 + 2];
      dst[x * 3 + 0] = r;
      dst[x * 3 + 1] = g;
      dst[x * 3 + 2] = b;
    }
  }
  ImageRGB img;
  img.width = static_cast<int>(width);
  img.height = static_cast<int>(height);
  img.data = std::move(data);
  return img;
}

ImageRGB ResizeNearest(const ImageRGB& src, int dst_w, int dst_h) {
  ImageRGB out;
  out.width = dst_w;
  out.height = dst_h;
  out.data.resize(dst_w * dst_h * 3);
  for(int y = 0; y < dst_h; ++y) {
    int sy = y * src.height / dst_h;
    for(int x = 0; x < dst_w; ++x) {
      int sx = x * src.width / dst_w;
      const unsigned char* s = src.data.data() + (sy * src.width + sx) * 3;
      unsigned char* d = out.data.data() + (y * dst_w + x) * 3;
      d[0] = s[0];
      d[1] = s[1];
      d[2] = s[2];
    }
  }
  return out;
}

bool SaveBMP24(const std::string& path, const ImageRGB& img) {
  std::ofstream f(path, std::ios::binary);
  if(!f) return false;
  int w = img.width, h = img.height;
  int row_stride = ((w * 3 + 3) / 4) * 4;
  int pixel_array_size = row_stride * h;
  int file_size = 14 + 40 + pixel_array_size;
  unsigned char header[14] = {'B','M',0,0,0,0,0,0,0,0,54,0,0,0};
  header[2] = (unsigned char)(file_size & 0xFF);
  header[3] = (unsigned char)((file_size >> 8) & 0xFF);
  header[4] = (unsigned char)((file_size >> 16) & 0xFF);
  header[5] = (unsigned char)((file_size >> 24) & 0xFF);
  f.write(reinterpret_cast<char*>(header), 14);
  unsigned char dib[40] = {0};
  dib[0] = 40; // DIB header size
  dib[4] = (unsigned char)(w & 0xFF);
  dib[5] = (unsigned char)((w >> 8) & 0xFF);
  dib[6] = (unsigned char)((w >> 16) & 0xFF);
  dib[7] = (unsigned char)((w >> 24) & 0xFF);
  int32_t neg_h = -h; // top-down
  dib[8]  = (unsigned char)(neg_h & 0xFF);
  dib[9]  = (unsigned char)((neg_h >> 8) & 0xFF);
  dib[10] = (unsigned char)((neg_h >> 16) & 0xFF);
  dib[11] = (unsigned char)((neg_h >> 24) & 0xFF);
  dib[12] = 1; // planes
  dib[14] = 24; // bpp
  f.write(reinterpret_cast<char*>(dib), 40);
  std::vector<unsigned char> row(row_stride);
  for(int y = 0; y < h; ++y) {
    const unsigned char* src_row = img.data.data() + y * w * 3;
    for(int x = 0; x < w; ++x) {
      unsigned char r = src_row[x*3+0];
      unsigned char g = src_row[x*3+1];
      unsigned char b = src_row[x*3+2];
      row[x*3+0] = b;
      row[x*3+1] = g;
      row[x*3+2] = r;
    }
    for(int p = w*3; p < row_stride; ++p) row[p] = 0;
    f.write(reinterpret_cast<char*>(row.data()), row_stride);
  }
  return true;
}

void DrawRect(ImageRGB& img, int x0, int y0, int x1, int y1, unsigned char r, unsigned char g, unsigned char b, int thickness) {
  if(x0 > x1) std::swap(x0, x1);
  if(y0 > y1) std::swap(y0, y1);
  x0 = std::max(0, std::min(img.width-1, x0));
  x1 = std::max(0, std::min(img.width-1, x1));
  y0 = std::max(0, std::min(img.height-1, y0));
  y1 = std::max(0, std::min(img.height-1, y1));
  auto plot = [&](int x,int y){ unsigned char* p = img.data.data() + (y*img.width + x)*3; p[0]=r; p[1]=g; p[2]=b; };
  for(int t=0;t<thickness;++t){
    for(int x=x0;x<=x1;++x){ if(y0+t>=0 && y0+t<img.height) plot(x,y0+t); if(y1-t>=0 && y1-t<img.height) plot(x,y1-t); }
    for(int y=y0;y<=y1;++y){ if(x0+t>=0 && x0+t<img.width) plot(x0+t,y); if(x1-t>=0 && x1-t<img.width) plot(x1-t,y); }
  }
}

static const unsigned char FONT5x7[][7] = {
  {0,0,0,0,0,0,0}, // space 32
};

static const unsigned char* glyph(char c) {
  static std::unordered_map<char, std::array<unsigned char,7>> map;
  if(map.empty()) {
    map['A'] = {0x1E,0x11,0x11,0x1F,0x11,0x11,0x11};
    map['B'] = {0x1E,0x11,0x11,0x1E,0x11,0x11,0x1E};
    map['C'] = {0x0E,0x11,0x10,0x10,0x10,0x11,0x0E};
    map['D'] = {0x1C,0x12,0x11,0x11,0x11,0x12,0x1C};
    map['E'] = {0x1F,0x10,0x10,0x1E,0x10,0x10,0x1F};
    map['F'] = {0x1F,0x10,0x10,0x1E,0x10,0x10,0x10};
    map['G'] = {0x0E,0x11,0x10,0x17,0x11,0x11,0x0F};
    map['H'] = {0x11,0x11,0x11,0x1F,0x11,0x11,0x11};
    map['I'] = {0x1F,0x04,0x04,0x04,0x04,0x04,0x1F};
    map['J'] = {0x07,0x02,0x02,0x02,0x02,0x12,0x0C};
    map['K'] = {0x11,0x12,0x14,0x18,0x14,0x12,0x11};
    map['L'] = {0x10,0x10,0x10,0x10,0x10,0x10,0x1F};
    map['M'] = {0x11,0x1B,0x15,0x11,0x11,0x11,0x11};
    map['N'] = {0x11,0x19,0x15,0x13,0x11,0x11,0x11};
    map['O'] = {0x0E,0x11,0x11,0x11,0x11,0x11,0x0E};
    map['P'] = {0x1E,0x11,0x11,0x1E,0x10,0x10,0x10};
    map['Q'] = {0x0E,0x11,0x11,0x11,0x15,0x12,0x0D};
    map['R'] = {0x1E,0x11,0x11,0x1E,0x14,0x12,0x11};
    map['S'] = {0x0F,0x10,0x10,0x0E,0x01,0x01,0x1E};
    map['T'] = {0x1F,0x04,0x04,0x04,0x04,0x04,0x04};
    map['U'] = {0x11,0x11,0x11,0x11,0x11,0x11,0x0E};
    map['V'] = {0x11,0x11,0x11,0x11,0x0A,0x0A,0x04};
    map['W'] = {0x11,0x11,0x11,0x11,0x15,0x1B,0x11};
    map['X'] = {0x11,0x11,0x0A,0x04,0x0A,0x11,0x11};
    map['Y'] = {0x11,0x11,0x0A,0x04,0x04,0x04,0x04};
    map['Z'] = {0x1F,0x01,0x02,0x04,0x08,0x10,0x1F};
    map['0'] = {0x0E,0x11,0x13,0x15,0x19,0x11,0x0E};
    map['1'] = {0x04,0x0C,0x04,0x04,0x04,0x04,0x1F};
    map['2'] = {0x0E,0x11,0x01,0x06,0x08,0x10,0x1F};
    map['3'] = {0x1F,0x01,0x02,0x06,0x01,0x11,0x0E};
    map['4'] = {0x02,0x06,0x0A,0x12,0x1F,0x02,0x02};
    map['5'] = {0x1F,0x10,0x1E,0x01,0x01,0x11,0x0E};
    map['6'] = {0x06,0x08,0x10,0x1E,0x11,0x11,0x0E};
    map['7'] = {0x1F,0x01,0x02,0x04,0x08,0x08,0x08};
    map['8'] = {0x0E,0x11,0x11,0x0E,0x11,0x11,0x0E};
    map['9'] = {0x0E,0x11,0x11,0x0F,0x01,0x02,0x0C};
    map['-'] = {0x00,0x00,0x00,0x1F,0x00,0x00,0x00};
    map['.'] = {0x00,0x00,0x00,0x00,0x00,0x0C,0x0C};
    map[' '] = {0,0,0,0,0,0,0};
  }
  auto it = map.find(c);
  if(it != map.end()) return it->second.data();
  return map[' '].data();
}

void DrawText(ImageRGB& img, int x, int y, const std::string& text, unsigned char r, unsigned char g, unsigned char b) {
  std::string s = text;
  for(char& c : s) if(c >= 'a' && c <= 'z') c = char(c - 'a' + 'A');
  int cx = x, cy = y;
  for(char c : s) {
    if(c == '\n') { cy += 8; cx = x; continue; }
    const unsigned char* rows = glyph(c);
    for(int ry=0; ry<7; ++ry) {
      unsigned char row = rows[ry];
      for(int rx=0; rx<5; ++rx) {
        if(row & (1 << (4 - rx))) {
          int px = cx + rx;
          int py = cy + ry;
          if(px>=0 && px<img.width && py>=0 && py<img.height) {
            unsigned char* p = img.data.data() + (py*img.width + px)*3;
            p[0]=r; p[1]=g; p[2]=b;
          }
        }
      }
    }
    cx += 6;
  }
}
