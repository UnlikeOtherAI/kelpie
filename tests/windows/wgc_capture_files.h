#pragma once
#include "script_media_owned_file.h"
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Storage.Streams.h>
#include <wincodec.h>
#include <MemoryBuffer.h>
#include <functional>
#include <bcrypt.h>
#include <nlohmann/json.hpp>
#include <chrono>
#include <cstring>
#include <iomanip>
#include <sstream>

namespace wgc_test {
using Clock=std::chrono::steady_clock;
using Json=nlohmann::json;
inline thread_local const char* Stage="initialization";
inline void Check(HRESULT result) { winrt::check_hresult(result); }
inline void Deadline(Clock::time_point end) {
  if(Clock::now()>=end) throw std::runtime_error("WGC_DEADLINE");
}
template<class Operation> inline auto Wait(Operation const& operation,Clock::time_point end) {
  Deadline(end);
  if(operation.wait_for(std::chrono::duration_cast<winrt::Windows::Foundation::TimeSpan>(end-Clock::now()))==winrt::Windows::Foundation::AsyncStatus::Started) {
    operation.Cancel(); throw std::runtime_error("WGC_OPERATION_TIMEOUT");
  }
  return operation.GetResults();
}
inline std::string Text(std::filesystem::path const& path) {return winrt::to_string(path.wstring());}
inline std::string Hash(IStream* stream) {
  BCRYPT_ALG_HANDLE algorithm=nullptr; BCRYPT_HASH_HANDLE hash=nullptr;
  Check(HRESULT_FROM_NT(BCryptOpenAlgorithmProvider(&algorithm,BCRYPT_SHA256_ALGORITHM,nullptr,0)));
  struct Release { BCRYPT_ALG_HANDLE* a;BCRYPT_HASH_HANDLE* h;~Release(){if(*h)BCryptDestroyHash(*h);if(*a)BCryptCloseAlgorithmProvider(*a,0);} } release{&algorithm,&hash};
  DWORD bytes=0,size=0;
  Check(HRESULT_FROM_NT(BCryptGetProperty(algorithm,BCRYPT_OBJECT_LENGTH,reinterpret_cast<PUCHAR>(&size),sizeof(size),&bytes,0)));
  if(size>65536) throw std::runtime_error("WGC_HASH_BOUND");
  std::vector<UCHAR> object(size);
  Check(HRESULT_FROM_NT(BCryptCreateHash(algorithm,&hash,object.data(),size,nullptr,0,0)));
  LARGE_INTEGER beginning{};Check(stream->Seek(beginning,STREAM_SEEK_SET,nullptr));
  std::vector<UCHAR> block(65536); ULONG read=0;
  do {Check(stream->Read(block.data(),static_cast<ULONG>(block.size()),&read));if(read)Check(HRESULT_FROM_NT(BCryptHashData(hash,block.data(),read,0)));} while(read);
  UCHAR digest[32]{};Check(HRESULT_FROM_NT(BCryptFinishHash(hash,digest,sizeof(digest),0)));
  std::ostringstream text;for(auto value:digest)text<<std::hex<<std::setw(2)<<std::setfill('0')<<static_cast<unsigned>(value);
  return text.str();
}
inline Json RawFile(std::filesystem::path const& path,std::vector<BYTE> const& bytes,std::function<void()> const& fence) {
  fence();
  Microsoft::WRL::ComPtr<kelpie::windows::media::OwnedMediaStream> stream;
  stream.Attach(new kelpie::windows::media::OwnedMediaStream(path));
  ULONG written=0;
  Check(stream->Write(bytes.data(),static_cast<ULONG>(bytes.size()),&written));
  if(written!=bytes.size()) throw std::runtime_error("WGC_SHORT_WRITE");
  fence();const auto hash=Hash(stream.Get());fence();Check(stream->Complete());
  return {{"path",Text(path)},{"sha256",hash},{"byteLength",bytes.size()}};
}
inline std::vector<BYTE> CopyBytes(winrt::Windows::Graphics::Imaging::SoftwareBitmap const& bitmap) {
  using namespace winrt::Windows::Graphics::Imaging;
  Stage="software-bitmap-lock";
  auto buffer=bitmap.LockBuffer(BitmapBufferAccessMode::Read);
  auto plane=buffer.GetPlaneDescription(0);auto reference=buffer.CreateReference();
  BYTE* data=nullptr;UINT32 capacity=0;Stage="sdk-memory-buffer-byte-access";
  Check(reference.as<::Windows::Foundation::IMemoryBufferByteAccess>()->GetBuffer(&data,&capacity));
  Stage="memory-buffer-copy";
  const auto width=bitmap.PixelWidth(),height=bitmap.PixelHeight();
  const std::uint64_t required=static_cast<std::uint64_t>(plane.StartIndex)+static_cast<std::uint64_t>(plane.Stride)*(height-1)+width*4ULL;
  if(plane.StartIndex<0||plane.Stride<width*4||plane.Stride>20480||required>capacity)
    throw std::runtime_error("WGC_BUFFER_LAYOUT");
  std::vector<BYTE> pixels(static_cast<std::size_t>(width)*height*4);
  for(int y=0;y<height;++y)std::memcpy(pixels.data()+static_cast<std::size_t>(y)*width*4,data+plane.StartIndex+static_cast<std::size_t>(y)*plane.Stride,static_cast<std::size_t>(width)*4);
  reference.Close();buffer.Close();return pixels;
}
inline Json PngFile(std::filesystem::path const& path,int width,int height,std::vector<BYTE> const& pixels,
                    std::string const& alpha,std::function<void()> const& fence) {
  fence();
  Microsoft::WRL::ComPtr<kelpie::windows::media::OwnedMediaStream> stream;
  stream.Attach(new kelpie::windows::media::OwnedMediaStream(path));
  Microsoft::WRL::ComPtr<IWICImagingFactory> factory;
  Check(CoCreateInstance(CLSID_WICImagingFactory,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&factory)));
  Microsoft::WRL::ComPtr<IWICBitmap> bitmap;
  const auto format=alpha=="premultiplied"?GUID_WICPixelFormat32bppPBGRA:GUID_WICPixelFormat32bppBGRA;
  Check(factory->CreateBitmapFromMemory(static_cast<UINT>(width),static_cast<UINT>(height),format,
    static_cast<UINT>(width*4),static_cast<UINT>(pixels.size()),const_cast<BYTE*>(pixels.data()),&bitmap));
  Microsoft::WRL::ComPtr<IWICBitmapSource> source;
  Check(WICConvertBitmapSource(GUID_WICPixelFormat32bppBGRA,bitmap.Get(),&source));
  Microsoft::WRL::ComPtr<IWICBitmapEncoder> encoder;
  Check(factory->CreateEncoder(GUID_ContainerFormatPng,nullptr,&encoder));
  Check(encoder->Initialize(stream.Get(),WICBitmapEncoderNoCache));
  Microsoft::WRL::ComPtr<IWICBitmapFrameEncode> frame;Microsoft::WRL::ComPtr<IPropertyBag2> options;
  Check(encoder->CreateNewFrame(&frame,&options));Check(frame->Initialize(options.Get()));
  Check(frame->SetSize(static_cast<UINT>(width),static_cast<UINT>(height)));
  auto outputFormat=GUID_WICPixelFormat32bppBGRA;Check(frame->SetPixelFormat(&outputFormat));
  if(outputFormat!=GUID_WICPixelFormat32bppBGRA)throw std::runtime_error("WGC_PNG_FORMAT");
  Check(frame->WriteSource(source.Get(),nullptr));Check(frame->Commit());Check(encoder->Commit());
  frame.Reset();encoder.Reset();source.Reset();bitmap.Reset();factory.Reset();
  fence();const auto hash=Hash(stream.Get());
  STATSTG stat{};Check(stream->Stat(&stat,STATFLAG_NONAME));
  if(stat.cbSize.QuadPart>67108864)throw std::runtime_error("WGC_PNG_BOUND");
  fence();Check(stream->Complete());
  return {{"path",Text(path)},{"sha256",hash},{"byteLength",stat.cbSize.QuadPart}};
}
}
