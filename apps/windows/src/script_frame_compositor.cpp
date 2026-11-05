#include "script_frame_compositor.h"
#include <windows.h>
#include <wincodec.h>
#include <wrl/client.h>
#include <wincrypt.h>
#include <gdiplus.h>
#include <algorithm>
#include <cmath>
#include <stdexcept>
#include "windows_utf.h"
#include "kelpie/script_presentation.h"
namespace kelpie::windows {
using Microsoft::WRL::ComPtr;
namespace {
void Check(HRESULT value) { if (FAILED(value)) throw std::runtime_error("CAPTURE_DECODE_FAILED"); }
void EnsureGdi() {
  static ULONG_PTR token=[] { ULONG_PTR value=0; Gdiplus::GdiplusStartupInput input;
    if(Gdiplus::GdiplusStartup(&value,&input,nullptr)!=Gdiplus::Ok) throw std::runtime_error("CAPTURE_OVERLAY_FAILED");
    return value; }(); (void)token;
}
}
ScriptMediaFrame DecodeScriptFrame(const std::string& encoded,int max_width,double elapsed_ms,ScriptFrameSourceSize* source_size) {
  if(encoded.size()>67108864) throw std::runtime_error("CAPTURE_FRAME_TOO_LARGE");
  DWORD size=0;
  if(!CryptStringToBinaryA(encoded.data(),static_cast<DWORD>(encoded.size()),CRYPT_STRING_BASE64,nullptr,&size,nullptr,nullptr))
    throw std::runtime_error("CAPTURE_DECODE_FAILED");
  std::vector<BYTE> bytes(size);
  if(!CryptStringToBinaryA(encoded.data(),static_cast<DWORD>(encoded.size()),CRYPT_STRING_BASE64,bytes.data(),&size,nullptr,nullptr))
    throw std::runtime_error("CAPTURE_DECODE_FAILED");
  ComPtr<IWICImagingFactory> factory; Check(CoCreateInstance(CLSID_WICImagingFactory,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&factory)));
  ComPtr<IWICStream> stream; Check(factory->CreateStream(&stream)); Check(stream->InitializeFromMemory(bytes.data(),size));
  ComPtr<IWICBitmapDecoder> decoder; Check(factory->CreateDecoderFromStream(stream.Get(),nullptr,WICDecodeMetadataCacheOnDemand,&decoder));
  ComPtr<IWICBitmapFrameDecode> source; Check(decoder->GetFrame(0,&source));
  UINT width=0,height=0; Check(source->GetSize(&width,&height));
  if(!width||!height||width>16384||height>16384||static_cast<std::uint64_t>(width)*height>8388608) throw std::runtime_error("CAPTURE_FRAME_TOO_LARGE");
  if(source_size) *source_size={static_cast<int>(width),static_cast<int>(height)};
  const double scale=std::min({1.0,static_cast<double>(max_width)/width,1920.0/height});
  if(width*scale<2 || height*scale<2) throw std::runtime_error("CAPTURE_VIEWPORT_UNSUPPORTED");
  ScriptMediaFrame frame; frame.width=std::max(2,static_cast<int>(width*scale)/2*2);
  frame.height=std::max(2,static_cast<int>(height*scale)/2*2); frame.stride=frame.width*4; frame.elapsed_ms=elapsed_ms;
  frame.bgra.resize(static_cast<std::size_t>(frame.stride)*frame.height);
  ComPtr<IWICBitmapScaler> scaler; Check(factory->CreateBitmapScaler(&scaler));
  Check(scaler->Initialize(source.Get(),frame.width,frame.height,WICBitmapInterpolationModeFant));
  ComPtr<IWICFormatConverter> converter; Check(factory->CreateFormatConverter(&converter));
  Check(converter->Initialize(scaler.Get(),GUID_WICPixelFormat32bppBGRA,WICBitmapDitherTypeNone,nullptr,0,WICBitmapPaletteTypeCustom));
  Check(converter->CopyPixels(nullptr,frame.stride,static_cast<UINT>(frame.bgra.size()),frame.bgra.data()));
  return frame;
}
void DrawScriptOverlay(ScriptMediaFrame& frame,const nlohmann::json& shown) {
  EnsureGdi();
  if(frame.width<=0||frame.height<=0||frame.bgra.size()<static_cast<std::size_t>(frame.stride)*frame.height)
    throw std::runtime_error("CAPTURE_OVERLAY_FAILED");
  Gdiplus::Bitmap bitmap(frame.width,frame.height,frame.stride,PixelFormat32bppPARGB,frame.bgra.data());
  if(bitmap.GetLastStatus()!=Gdiplus::Ok) throw std::runtime_error("CAPTURE_OVERLAY_FAILED");
  Gdiplus::Graphics graphics(&bitmap); graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  const auto visual=shown.value("visualViewport",nlohmann::json::object());
  const float width=static_cast<float>(shown.value("viewportWidth",static_cast<double>(frame.width)));
  const float height=static_cast<float>(shown.value("viewportHeight",static_cast<double>(frame.height)));
  const float visible_width=visual.value("width",width),visible_height=visual.value("height",height);
  const float offset_x=visual.value("offsetLeft",0.0f),offset_y=visual.value("offsetTop",0.0f);
  const float scale=visual.value("scale",1.0f);
  if(!std::isfinite(width)||!std::isfinite(height)||width<=0||height<=0||
     !std::isfinite(visible_width)||!std::isfinite(visible_height)||visible_width<=0||visible_height<=0||
     !std::isfinite(offset_x)||!std::isfinite(offset_y)||!std::isfinite(scale)||scale<=0||
     !std::isfinite(frame.width/width*scale)||!std::isfinite(frame.height/height*scale))
    throw std::runtime_error("CAPTURE_OVERLAY_FAILED");
  // The full renderer includes classic scrollbars; visualViewport.width does
  // not. Preserve the full-layout base scale, then apply the observed pinch.
  graphics.ScaleTransform(frame.width/width*scale,frame.height/height*scale);
  if(shown.contains("pointer")) {
    const auto& point=shown["pointer"]; const float x=point.value("x",0.0f)-offset_x,y=point.value("y",0.0f)-offset_y;
    Gdiplus::PointF points[]={{x,y},{x+5,y+19},{x+10,y+12},{x+18,y+10}};
    Gdiplus::SolidBrush fill(Gdiplus::Color(255,255,255,255)); Gdiplus::Pen edge(Gdiplus::Color(255,0,0,0),1.5f);
    graphics.FillPolygon(&fill,points,4); graphics.DrawPolygon(&edge,points,4);
  }
  const double elapsed=shown.value("elapsedMs",frame.elapsed_ms);
  if(shown.contains("marker")) {
    const auto& marker=shown["marker"];
    const double t=kelpie_script_progress(elapsed-marker.value("startedMs",elapsed),marker.value("durationMs",700.0));
    if(t<1) {
      const auto state=kelpie_script_tap_presentation(t,marker.value("wobble",true),marker.value("fade",true));
      const float radius=static_cast<float>(marker.value("radius",20.0)*state.scale);
      unsigned long color=0x3B82F6; try { color=std::stoul(marker.value("color",std::string("#3B82F6")).substr(1),nullptr,16); } catch(...) {}
      const BYTE alpha=static_cast<BYTE>(178*state.alpha);
      Gdiplus::SolidBrush fill(Gdiplus::Color(alpha,static_cast<BYTE>(color>>16),static_cast<BYTE>(color>>8),static_cast<BYTE>(color)));
      const float x=marker.value("x",0.0f)-offset_x,y=marker.value("y",0.0f)-offset_y; graphics.FillEllipse(&fill,x-radius,y-radius,2*radius,2*radius);
    }
  }
  graphics.ResetTransform();
  graphics.ScaleTransform(frame.width/width,frame.height/height);
  if(shown.contains("commentary")) {
    const auto& note=shown["commentary"];
    if(elapsed-note.value("startedMs",elapsed)<note.value("durationMs",3000.0)) {
      const auto text=utf::Utf8ToWideDisplay(note.value("text",std::string()));
      const auto position=note.value("position",std::string("bottom"));
      const float top=position=="top"?24:position=="center"?height/2-30:height-84;
      Gdiplus::RectF box(std::max(8.0f,width/2-200),top,std::min(400.0f,width-16),60);
      Gdiplus::SolidBrush background(Gdiplus::Color(180,0,0,0)),foreground(Gdiplus::Color(255,255,255,255));
      graphics.FillRectangle(&background,box); Gdiplus::Font font(L"Segoe UI",15); Gdiplus::StringFormat format;
      format.SetAlignment(Gdiplus::StringAlignmentCenter); format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
      graphics.DrawString(text.c_str(),static_cast<INT>(text.size()),&font,box,&format,&foreground);
    }
  }
}
}
