#include "script_media_encoder.h"
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <wincodec.h>
#include <wrl/client.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <algorithm>
using namespace kelpie::windows;
using Microsoft::WRL::ComPtr;
namespace fs=std::filesystem;
void Require(bool value,const char* message) { if(!value) throw std::runtime_error(message); }
void Check(HRESULT value) { if(FAILED(value)) throw std::runtime_error("Native decoder failed"); }
ScriptMediaFrame Frame(double time) {
  ScriptMediaFrame frame{64,48,256,std::vector<std::uint8_t>(64*48*4,255),time};
  for(std::size_t i=0;i<frame.bgra.size();i+=4) {
    frame.bgra[i]=0;frame.bgra[i+1]=static_cast<std::uint8_t>(static_cast<int>(time)%200);
  }
  return frame;
}
std::size_t Decoded(const ScriptMediaOutput& output) {
  if(output.mime_type=="image/gif") {
    ComPtr<IWICImagingFactory> factory;
    Check(CoCreateInstance(CLSID_WICImagingFactory,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&factory)));
    ComPtr<IWICBitmapDecoder> decoder;
    Check(factory->CreateDecoderFromFilename(output.path.c_str(),nullptr,GENERIC_READ,WICDecodeMetadataCacheOnLoad,&decoder));
    UINT count=0;Check(decoder->GetFrameCount(&count));
    for(UINT index=0;index<count;++index) {
      ComPtr<IWICBitmapFrameDecode> frame;Check(decoder->GetFrame(index,&frame));
      ComPtr<IWICFormatConverter> rgba;Check(factory->CreateFormatConverter(&rgba));
      Check(rgba->Initialize(frame.Get(),GUID_WICPixelFormat32bppBGRA,WICBitmapDitherTypeNone,nullptr,0,WICBitmapPaletteTypeCustom));
      UINT width=0,height=0;Check(frame->GetSize(&width,&height));
      std::vector<BYTE> pixels(static_cast<std::size_t>(width)*height*4);
      Check(rgba->CopyPixels(nullptr,width*4,static_cast<UINT>(pixels.size()),pixels.data()));
    }
    return count;
  }
  ComPtr<IMFSourceReader> reader;Check(MFCreateSourceReaderFromURL(output.path.c_str(),nullptr,&reader));
  ComPtr<IMFMediaType> type;Check(MFCreateMediaType(&type));
  Check(type->SetGUID(MF_MT_MAJOR_TYPE,MFMediaType_Video));
  Check(type->SetGUID(MF_MT_SUBTYPE,MFVideoFormat_NV12));
  Check(reader->SetCurrentMediaType(static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM),nullptr,type.Get()));
  std::size_t count=0;LONGLONG last=-1;
  for(;;) {
    DWORD flags=0;LONGLONG time=0;ComPtr<IMFSample> sample;
    Check(reader->ReadSample(static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM),0,nullptr,&flags,&time,&sample));
    if(sample) {
      Require(time>last,"Nonmonotonic decoded video");last=time;
      ComPtr<IMFMediaBuffer> buffer;Check(sample->ConvertToContiguousBuffer(&buffer));
      DWORD length=0;Check(buffer->GetCurrentLength(&length));
      Require(length>=64*48*3/2,"Short decoded video");++count;
    }
    if(flags&MF_SOURCE_READERF_ENDOFSTREAM) return count;
  }
}
void Verify(const std::vector<ScriptMediaOutput>& outputs,std::size_t prefix) {
  for(const auto& output:outputs) {
    const auto count=Decoded(output);
    Require(count==output.frame_count,"Decoded count differs from writer");
    Require(count>=prefix,"Acknowledged frame absent from finalized media");
  }
}
void Normal(const fs::path& root,int frames) {
  const auto path=root/("normal-"+std::to_string(frames));fs::create_directory(path);
  auto encoder=ScriptMediaEncoder::Create(path,{"gif","mp4"},15,8*1024*1024);
  std::size_t previous=0,peak_pending=0;
  for(int index=0;index<frames;++index) {
    Require(encoder->AddFrame(Frame(index*100.0)),"Unexpected admission refusal");
    const auto committed=encoder->committed_movie_frames();
    Require(committed>=previous && committed<=static_cast<std::size_t>(index),"Raw pending frame was acknowledged");
    previous=committed;peak_pending=std::max(peak_pending,static_cast<std::size_t>(index+1)-committed);
  }
  if(frames==1) Require(previous==0,"First raw frame is not encoded yet");
  else Require(previous>0,"Encoders never acknowledge retained output");
  bool invalid=false;
  try { encoder->Finish((frames-1)*100.0); } catch(const std::runtime_error&) { invalid=true; }
  Require(invalid && encoder->committed_movie_frames()==previous,"Refused terminal timestamp changed prefix");
  const auto outputs=encoder->Finish(frames*100.0);
  Require(outputs.size()==2,"Normal format missing");Verify(outputs,previous);
  std::cout<<"frames="<<frames<<" committed-before-finalize="<<previous<<" peak-pending="<<peak_pending<<'\n';
}
void BudgetAndFailure(const fs::path& root) {
  const auto path=root/"budget";fs::create_directory(path);
  auto encoder=ScriptMediaEncoder::Create(path,{"gif","mp4"},15,1024);
  Require(encoder->AddFrame(Frame(0)),"Initial pending frame refused");
  Require(!encoder->AddFrame(Frame(100)),"Tiny combined budget unexpectedly accepted");
  Require(encoder->committed_movie_frames()==0,"One successful format impersonated all-format admission");
  Verify(encoder->Finish(200),0);
  const auto fail=root/"finish-failure";fs::create_directory(fail);
  auto broken=ScriptMediaEncoder::Create(fail,{"gif","mp4"},15,8*1024*1024);
  Require(broken->AddFrame(Frame(0)),"Initial failure-case frame refused");
  { std::ofstream foreign(fail/"capture.mp4");foreign<<"foreign"; }
  bool failed=false;
  try { broken->Finish(100); } catch(const std::runtime_error&) { failed=true; }
  Require(failed,"Finalization collision ignored");
  Require(broken->committed_movie_frames()==0,"Failed finalization fabricated live admission");
  const auto sibling=broken->Finish(100);
  Require(sibling.size()==1 && sibling[0].mime_type=="image/gif","Valid sibling lost");
  Verify(sibling,0);
}
int wmain(int argc,wchar_t** argv) {
  try {
    Require(argc==2,"Provide fresh prefix evidence directory");
    const fs::path root(argv[1]);Require(!fs::exists(root),"Evidence directory exists");fs::create_directories(root);
    Check(CoInitializeEx(nullptr,COINIT_MULTITHREADED));Check(MFStartup(MF_VERSION));
    Normal(root,1);Normal(root,12);BudgetAndFailure(root);
    MFShutdown();CoUninitialize();
    std::cout<<"Encoded all-format committed prefixes match native decoded media\n";return 0;
  } catch(const std::exception& error) { std::cerr<<error.what()<<'\n';return 1; }
}
