#include "url_bar.h"
#include <commctrl.h>
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
    if (label!=account_label_) {
      account_label_=label; SetWindowTextW(account_button_,label.c_str());
      UpdateAccountTooltip();
    }
    if (changed) InvalidateRect(account_button_,nullptr,FALSE);
  }
}
// Hover text carries sign-in progress, including launch restore, and account errors.
void UrlBar::UpdateAccountTooltip() const {
  if (!tooltip_) return;
  std::wstring text=L"UnlikeOtherAI account — "+account_label_;
  TOOLINFOW tool{sizeof(tool)};
  tool.uFlags=TTF_SUBCLASS|TTF_IDISHWND;
  tool.hwnd=parent_;
  tool.uId=reinterpret_cast<UINT_PTR>(account_button_);
  tool.lpszText=text.data();
  SendMessageW(tooltip_,TTM_UPDATETIPTEXTW,0,reinterpret_cast<LPARAM>(&tool));
}
void UrlBar::DrawAccount(const DRAWITEMSTRUCT& item) const {
  ui::FillSolid(item.hDC,item.rcItem,palette_.bar);
  const bool focused=(item.itemState&ODS_FOCUS)!=0;
  if ((item.itemState&ODS_SELECTED)!=0 || item.hwndItem==hovered_button_ || focused)
    ui::PaintRounded(item.hDC,item.rcItem,palette_.hover,focused?ui::Colors().focus:palette_.hover,
                     ui::Dip(parent_,8),focused?2:0);
  // The macOS account control: a 28-point circle with a hairline at 18% of
  // the toolbar ink, holding the avatar or person.crop.circle.fill.
  const int size=ui::Dip(parent_,30);
  RECT circle{(item.rcItem.left+item.rcItem.right-size)/2,(item.rcItem.top+item.rcItem.bottom-size)/2,0,0};
  circle.right=circle.left+size; circle.bottom=circle.top+size;
  if (account_avatar_) {
    ui::PaintCircularImage(item.hDC,circle,account_avatar_);
  } else {
    // A disc with the person cut out of it, shoulders cropped by its edge.
    const COLORREF disc=ui::Blend(palette_.text,palette_.bar,0.72);
    ui::PaintRounded(item.hDC,circle,disc,disc,size/2,0);
    const int saved=SaveDC(item.hDC);
    HRGN clip=CreateEllipticRgn(circle.left,circle.top,circle.right+1,circle.bottom+1);
    SelectClipRgn(item.hDC,clip);
    RECT person=circle;
    OffsetRect(&person,0,ui::Dip(parent_,6));
    ui::DrawGlyph(item.hDC,parent_,person,ui::icon::kPerson,palette_.bar,27);
    RestoreDC(item.hDC,saved);
    DeleteObject(clip);
    // The clip region is aliased; a ring in the disc colour smooths the cut.
    ui::PaintFocusRing(item.hDC,circle,disc,size/2,1);
  }
  ui::PaintFocusRing(item.hDC,circle,ui::Blend(palette_.text,palette_.bar,0.18),size/2,1);
  if (account_error_ || account_busy_) {
    RECT dot{circle.right-ui::Dip(parent_,8),circle.bottom-ui::Dip(parent_,8),circle.right,circle.bottom};
    const auto color=account_error_?RGB(205,50,45):RGB(40,112,240);
    ui::PaintRounded(item.hDC,dot,color,palette_.bar,ui::Dip(parent_,4),1);
  }
}
}  // namespace kelpie::windows
