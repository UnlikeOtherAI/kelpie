#include "url_bar.h"
#include <objidl.h>
#include <gdiplus.h>
#include "theme/theme.h"

namespace kelpie::windows {
void UrlBar::SetAccount(const std::string& avatar,const std::wstring& label,bool error,bool busy) {
  const bool changed=avatar!=account_avatar_source_ || account_error_!=error || account_busy_!=busy;
  account_error_=error; account_busy_=busy;
  if (avatar!=account_avatar_source_) {
    account_avatar_source_=avatar;
    if (account_avatar_) DeleteObject(account_avatar_);
    account_avatar_=nullptr;
    if (!avatar.empty() && avatar.size()<=2*1024*1024) {
      HGLOBAL memory=GlobalAlloc(GMEM_MOVEABLE,avatar.size());
      if (memory) {
        void* bytes=GlobalLock(memory);
        if (bytes) { memcpy(bytes,avatar.data(),avatar.size()); GlobalUnlock(memory); }
        IStream* stream=nullptr;
        if (bytes && SUCCEEDED(CreateStreamOnHGlobal(memory,TRUE,&stream))) {
          {
          Gdiplus::Bitmap source(stream);
          if (source.GetLastStatus()==Gdiplus::Ok && source.GetWidth()<=2048 && source.GetHeight()<=2048) {
            Gdiplus::Bitmap scaled(64,64,PixelFormat32bppARGB);
            { Gdiplus::Graphics graphics(&scaled);
              graphics.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
              graphics.DrawImage(&source,0,0,64,64); }
            scaled.GetHBITMAP(Gdiplus::Color(255,255,255),&account_avatar_);
          }
          }
          stream->Release();
        } else GlobalFree(memory);
      }
    }
  }
  if (account_button_) {
    SetWindowTextW(account_button_,label.c_str());
    if (changed) InvalidateRect(account_button_,nullptr,FALSE);
  }
}
void UrlBar::DrawAccount(const DRAWITEMSTRUCT& item) const {
  ui::FillSolid(item.hDC,item.rcItem,palette_.bar);
  const int size=ui::Dip(parent_,34);
  RECT circle{(item.rcItem.right-size)/2,(item.rcItem.bottom-size)/2,0,0};
  circle.right=circle.left+size; circle.bottom=circle.top+size;
  if (account_avatar_) {
    const int saved=SaveDC(item.hDC);
    HRGN clip=CreateEllipticRgn(circle.left,circle.top,circle.right,circle.bottom);
    SelectClipRgn(item.hDC,clip);
    HDC source=CreateCompatibleDC(item.hDC);
    auto previous=SelectObject(source,account_avatar_);
    SetStretchBltMode(item.hDC,HALFTONE);
    StretchBlt(item.hDC,circle.left,circle.top,size,size,source,0,0,64,64,SRCCOPY);
    SelectObject(source,previous); DeleteDC(source); DeleteObject(clip); RestoreDC(item.hDC,saved);
  } else ui::DrawGlyph(item.hDC,parent_,circle,L'\uE77B',palette_.text,27);
  if (account_error_ || account_busy_) {
    RECT dot{circle.right-ui::Dip(parent_,8),circle.bottom-ui::Dip(parent_,8),circle.right,circle.bottom};
    const auto color=account_error_?RGB(205,50,45):RGB(40,112,240);
    ui::PaintRounded(item.hDC,dot,color,color,ui::Dip(parent_,4));
  }
  if (item.itemState&ODS_FOCUS) DrawFocusRect(item.hDC,&item.rcItem);
}
}  // namespace kelpie::windows
