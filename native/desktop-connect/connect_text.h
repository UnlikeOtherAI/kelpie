#pragma once
#include <algorithm>
#include <string>
namespace kelpie::connect {
// Byte bounds stay conservative for character limits, without malformed JSON UTF-8.
inline std::string Utf8Prefix(const std::string& text,std::size_t limit) {
  auto end=std::min(text.size(),limit);
  if(end<text.size())while(end>0 && (static_cast<unsigned char>(text[end])&0xc0)==0x80)--end;
  return text.substr(0,end);
}
}
