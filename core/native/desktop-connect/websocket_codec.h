#pragma once
#include <array>
#include <cstdint>
#include <optional>
#include <stdexcept>
#include <string>
namespace kelpie::connect {
struct SocketFrame { unsigned opcode; bool final; std::string payload; };
inline std::optional<SocketFrame> DecodeFrame(std::string& buffer) {
  if (buffer.size()<2) return {};
  const auto a=static_cast<unsigned char>(buffer[0]),b=static_cast<unsigned char>(buffer[1]);
  if ((a&0x70)||(b&0x80)) throw std::runtime_error("Invalid gateway frame");
  std::uint64_t count=b&127; std::size_t head=2;
  if (count==126) { if (buffer.size()<4)return {}; count=(static_cast<unsigned char>(buffer[2])<<8)|static_cast<unsigned char>(buffer[3]); head=4; }
  if (count==127) { if (buffer.size()<10)return {}; count=0; for(int i=2;i<10;++i) count=(count<<8)|static_cast<unsigned char>(buffer[i]); head=10; }
  if (count>1024*1024 || ((a&8)&&(!(a&128)||count>125))) throw std::runtime_error("Invalid gateway frame size");
  if (buffer.size()<head+count) return {};
  SocketFrame result{static_cast<unsigned>(a&15),(a&128)!=0,buffer.substr(head,static_cast<std::size_t>(count))};
  buffer.erase(0,head+static_cast<std::size_t>(count)); return result;
}
inline std::string EncodeFrame(const std::string& text,unsigned opcode,const std::array<unsigned char,4>& mask) {
  if (text.size()>1024*1024)throw std::runtime_error("Frame too large");
  std::string result(1,static_cast<char>(0x80|opcode));
  if(text.size()<126)result+=static_cast<char>(0x80|text.size());
  else if(text.size()<=65535) { result+=static_cast<char>(0xfe); result+=static_cast<char>(text.size()>>8); result+=static_cast<char>(text.size()); }
  else { result+=static_cast<char>(0xff); for(int i=7;i>=0;--i)result+=static_cast<char>(static_cast<std::uint64_t>(text.size())>>(i*8)); }
  for(auto byte:mask)result+=static_cast<char>(byte);
  for(std::size_t i=0;i<text.size();++i)result+=static_cast<char>(static_cast<unsigned char>(text[i])^mask[i%4]);
  return result;
}
}
