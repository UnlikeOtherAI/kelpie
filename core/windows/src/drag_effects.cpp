#include "drag_effects.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstring>
#include <cmath>
#include <mutex>

// GDI+ headers need IStream and PROPID, which WIN32_LEAN_AND_MEAN excludes,
// and they reference Gdiplus::min/max, which NOMINMAX removes.
#include <objidl.h>

namespace Gdiplus {
using std::max;
using std::min;
}  // namespace Gdiplus
#include <gdiplus.h>

#include "theme/theme.h"

namespace kelpie::windows {
namespace {

constexpr wchar_t kGhostClass[] = L"KelpieFavoriteDragGhost";
constexpr wchar_t kPuffClass[] = L"KelpieFavoriteRemovalPuff";
constexpr UINT_PTR kAnimationTimer = 1;
constexpr UINT kFrameMs = 15;
constexpr DWORD kReturnMs = 170;
constexpr DWORD kPuffMs = 560;
constexpr float kPi = 3.14159265f;

// Same policy as the theme's painter: started once, never shut down, because
// a shutdown races any window still painting during teardown.
void EnsureGdiPlus() {
  static std::once_flag once;
  std::call_once(once, [] {
    Gdiplus::GdiplusStartupInput input;
    ULONG_PTR token = 0;
    Gdiplus::GdiplusStartup(&token, &input, nullptr);
  });
}

// "Show animations in Windows" in Settings > Accessibility > Visual effects.
bool AnimationsEnabled() {
  BOOL enabled = TRUE;
  SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &enabled, 0);
  return enabled != FALSE;
}

float EaseOut(float t) { return 1.0f - std::pow(1.0f - t, 3.0f); }

void RegisterEffectClass(const wchar_t* name, WNDPROC procedure) {
  WNDCLASSEXW window_class{sizeof(window_class)};
  if (GetClassInfoExW(GetModuleHandleW(nullptr), name, &window_class)) return;
  window_class.lpfnWndProc = procedure;
  window_class.hInstance = GetModuleHandleW(nullptr);
  window_class.lpszClassName = name;
  window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  RegisterClassExW(&window_class);
}

// Click-through and never activated: the pointer keeps talking to whatever is
// underneath, and keyboard focus stays where it was.
HWND CreateEffectWindow(const wchar_t* name, WNDPROC procedure, HWND owner, void* state) {
  RegisterEffectClass(name, procedure);
  return CreateWindowExW(WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST,
                         name, L"", WS_POPUP, 0, 0, 1, 1, owner, nullptr, GetModuleHandleW(nullptr), state);
}

// Pushes a premultiplied ARGB bitmap to a layered window with its top-left at
// `origin` in screen coordinates.
void Present(HWND window, Gdiplus::Bitmap& bitmap, POINT origin, BYTE opacity) {
  const int width = static_cast<int>(bitmap.GetWidth());
  const int height = static_cast<int>(bitmap.GetHeight());
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(info.bmiHeader);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  HDC screen = GetDC(nullptr);
  void* bits = nullptr;
  HBITMAP dib = CreateDIBSection(screen, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  if (dib == nullptr || bits == nullptr) {
    ReleaseDC(nullptr, screen);
    return;
  }
  Gdiplus::BitmapData data{};
  Gdiplus::Rect all(0, 0, width, height);
  if (bitmap.LockBits(&all, Gdiplus::ImageLockModeRead, PixelFormat32bppPARGB, &data) == Gdiplus::Ok) {
    for (int row = 0; row < height; ++row) {
      std::memcpy(static_cast<BYTE*>(bits) + static_cast<std::size_t>(row) * width * 4,
                  static_cast<const BYTE*>(data.Scan0) + static_cast<std::ptrdiff_t>(row) * data.Stride,
                  static_cast<std::size_t>(width) * 4);
    }
    bitmap.UnlockBits(&data);
    HDC memory = CreateCompatibleDC(screen);
    HGDIOBJ previous = SelectObject(memory, dib);
    SIZE size{width, height};
    POINT source{0, 0};
    BLENDFUNCTION blend{AC_SRC_OVER, 0, opacity, AC_SRC_ALPHA};
    UpdateLayeredWindow(window, screen, &origin, &size, memory, &source, 0, &blend, ULW_ALPHA);
    SelectObject(memory, previous);
    DeleteDC(memory);
  }
  DeleteObject(dib);
  ReleaseDC(nullptr, screen);
}

void AddRoundedRect(Gdiplus::GraphicsPath* path, Gdiplus::RectF bounds, float radius) {
  const float r = std::clamp(radius, 0.5f, std::min(bounds.Width, bounds.Height) / 2.0f);
  const float d = r * 2.0f;
  path->AddArc(bounds.X, bounds.Y, d, d, 180.0f, 90.0f);
  path->AddArc(bounds.GetRight() - d, bounds.Y, d, d, 270.0f, 90.0f);
  path->AddArc(bounds.GetRight() - d, bounds.GetBottom() - d, d, d, 0.0f, 90.0f);
  path->AddArc(bounds.X, bounds.GetBottom() - d, d, d, 90.0f, 90.0f);
  path->CloseFigure();
}

}  // namespace

// --- DragGhost --------------------------------------------------------------

struct DragGhost::State {
  std::unique_ptr<Gdiplus::Bitmap> content;
  SIZE size{};
  POINT grab{};
  int radius = 0;
  int margin = 0;
  int scale_dip = 1;
  HWND owner = nullptr;
  POINT position{};  // Item top-left, screen coordinates.
  bool removing = false;
  bool returning = false;
  POINT from{};
  POINT to{};
  DWORD started = 0;
  std::function<void()> landed;
};

DragGhost::DragGhost() = default;
// The owner is going away; do not call back into it.
DragGhost::~DragGhost() {
  if (state_) state_->landed = nullptr;
  Hide();
}

bool DragGhost::Show(HWND owner, HBITMAP content, SIZE size, POINT grab, int corner_radius) {
  Hide();
  EnsureGdiPlus();
  std::unique_ptr<Gdiplus::Bitmap> source(Gdiplus::Bitmap::FromHBITMAP(content, nullptr));
  if (!source || source->GetLastStatus() != Gdiplus::Ok) return false;
  state_ = std::make_unique<State>();
  // FromHBITMAP may keep referring to the caller's bitmap; own a copy.
  state_->content.reset(source->Clone(0, 0, size.cx, size.cy, PixelFormat32bppRGB));
  if (!state_->content) {
    state_.reset();
    return false;
  }
  state_->size = size;
  state_->grab = grab;
  state_->radius = corner_radius;
  state_->owner = owner;
  state_->margin = ui::Dip(owner, 16);
  window_ = CreateEffectWindow(kGhostClass, &DragGhost::WindowProc, owner, this);
  if (window_ == nullptr) {
    state_.reset();
    return false;
  }
  POINT cursor{};
  GetCursorPos(&cursor);
  state_->position = {cursor.x - grab.x, cursor.y - grab.y};
  Render();
  ShowWindow(window_, SW_SHOWNOACTIVATE);
  return true;
}

void DragGhost::Render() {
  if (window_ == nullptr || !state_) return;
  const State& s = *state_;
  const int margin = s.margin;
  Gdiplus::Bitmap canvas(s.size.cx + margin * 2, s.size.cy + margin * 2, PixelFormat32bppPARGB);
  Gdiplus::Graphics graphics(&canvas);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  graphics.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHalf);
  graphics.Clear(Gdiplus::Color(0, 0, 0, 0));
  const Gdiplus::RectF item(static_cast<float>(margin), static_cast<float>(margin),
                            static_cast<float>(s.size.cx), static_cast<float>(s.size.cy));

  // A soft drop shadow: stacked, slightly lower and wider translucent shapes.
  // Wide, faint outer layers and a tighter, darker core, each adding a little.
  const float lift = static_cast<float>(ui::Dip(s.owner, 3));
  for (int layer = 8; layer >= 1; --layer) {
    const float spread = static_cast<float>(layer) * static_cast<float>(ui::Dip(s.owner, 1));
    Gdiplus::GraphicsPath shadow;
    AddRoundedRect(&shadow, Gdiplus::RectF(item.X - spread, item.Y - spread + lift, item.Width + spread * 2,
                                           item.Height + spread * 2),
                   static_cast<float>(s.radius) + spread);
    Gdiplus::SolidBrush brush(Gdiplus::Color(static_cast<BYTE>(3 + (8 - layer)), 0, 0, 0));
    graphics.FillPath(&brush, &shadow);
  }

  Gdiplus::GraphicsPath body;
  AddRoundedRect(&body, item, static_cast<float>(s.radius));
  Gdiplus::TextureBrush texture(s.content.get());
  texture.TranslateTransform(item.X, item.Y);
  graphics.FillPath(&texture, &body);
  Gdiplus::Pen edge(Gdiplus::Color(38, 0, 0, 0), 1.0f);
  graphics.DrawPath(&edge, &body);

  if (s.removing) {
    // The remove badge: a red disc with a white minus, at the top-right corner.
    const float badge = static_cast<float>(ui::Dip(s.owner, 18));
    const Gdiplus::RectF disc(item.GetRight() - badge * 0.7f, item.Y - badge * 0.3f, badge, badge);
    Gdiplus::SolidBrush red(Gdiplus::Color(255, 229, 72, 77));
    graphics.FillEllipse(&red, disc);
    Gdiplus::Pen ring(Gdiplus::Color(255, 255, 255, 255), static_cast<float>(ui::Dip(s.owner, 2)) * 0.75f);
    graphics.DrawEllipse(&ring, disc);
    Gdiplus::Pen minus(Gdiplus::Color(255, 255, 255, 255), static_cast<float>(ui::Dip(s.owner, 2)));
    minus.SetStartCap(Gdiplus::LineCapRound);
    minus.SetEndCap(Gdiplus::LineCapRound);
    const float cy = disc.Y + disc.Height / 2.0f;
    graphics.DrawLine(&minus, disc.X + badge * 0.3f, cy, disc.GetRight() - badge * 0.3f, cy);
  }

  Present(window_, canvas, POINT{s.position.x - margin, s.position.y - margin}, s.removing ? 205 : 248);
}

void DragGhost::Move(POINT screen, bool removing) {
  if (window_ == nullptr || !state_ || state_->returning) return;
  state_->position = {screen.x - state_->grab.x, screen.y - state_->grab.y};
  if (removing != state_->removing) {
    state_->removing = removing;
    Render();
    return;
  }
  SetWindowPos(window_, HWND_TOPMOST, state_->position.x - state_->margin, state_->position.y - state_->margin,
               0, 0, SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
}

void DragGhost::ReturnTo(POINT slot, std::function<void()> landed) {
  if (window_ == nullptr || !state_) {
    if (landed) landed();
    return;
  }
  state_->landed = std::move(landed);
  if (!AnimationsEnabled()) {
    Hide();
    return;
  }
  state_->removing = false;
  Render();
  state_->returning = true;
  state_->from = state_->position;
  state_->to = slot;
  state_->started = GetTickCount();
  SetTimer(window_, kAnimationTimer, kFrameMs, nullptr);
}

void DragGhost::Hide() {
  std::function<void()> landed = state_ ? std::move(state_->landed) : nullptr;
  if (window_ != nullptr) {
    HWND window = window_;
    window_ = nullptr;
    SetWindowLongPtrW(window, GWLP_USERDATA, 0);
    DestroyWindow(window);
  }
  state_.reset();
  if (landed) landed();
}

LRESULT CALLBACK DragGhost::WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lparam);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  }
  if (message == WM_NCHITTEST) return HTTRANSPARENT;
  if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
  auto* ghost = reinterpret_cast<DragGhost*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_TIMER && wparam == kAnimationTimer && ghost && ghost->state_) {
    State& s = *ghost->state_;
    const float t = std::min(1.0f, static_cast<float>(GetTickCount() - s.started) / kReturnMs);
    const float p = EaseOut(t);
    s.position = {s.from.x + static_cast<LONG>(std::lround((s.to.x - s.from.x) * p)),
                  s.from.y + static_cast<LONG>(std::lround((s.to.y - s.from.y) * p))};
    SetWindowPos(hwnd, HWND_TOPMOST, s.position.x - s.margin, s.position.y - s.margin, 0, 0,
                 SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
    if (t >= 1.0f) {
      KillTimer(hwnd, kAnimationTimer);
      ghost->Hide();
    }
    return 0;
  }
  if (message == WM_DESTROY) KillTimer(hwnd, kAnimationTimer);
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

// --- Removal puff -----------------------------------------------------------

namespace {

struct PuffState {
  POINT center{};
  int extent = 0;  // Half the window's side, in pixels.
  DWORD started = 0;
};

// One billow of the cloud: where it heads, how big it grows, when it starts.
struct Billow {
  float angle_degrees;
  float distance;      // Fraction of the extent travelled at the end.
  float start_radius;  // Fractions of the extent.
  float end_radius;
  float delay;         // Fraction of the animation before it starts moving.
};

// Hand-placed rather than random so every puff has the same pleasing shape.
constexpr std::array<Billow, 10> kBillows = {{
    {0.0f, 0.0f, 0.26f, 0.40f, 0.00f},   // The core, which swells in place.
    {-8.0f, 0.52f, 0.18f, 0.27f, 0.00f},
    {34.0f, 0.58f, 0.16f, 0.25f, 0.03f},
    {78.0f, 0.50f, 0.19f, 0.28f, 0.01f},
    {118.0f, 0.60f, 0.15f, 0.24f, 0.04f},
    {160.0f, 0.54f, 0.18f, 0.27f, 0.02f},
    {205.0f, 0.57f, 0.16f, 0.26f, 0.03f},
    {246.0f, 0.50f, 0.19f, 0.28f, 0.00f},
    {286.0f, 0.60f, 0.15f, 0.24f, 0.05f},
    {326.0f, 0.53f, 0.17f, 0.26f, 0.02f},
}};

// Small specks thrown further out than the cloud.
constexpr std::array<float, 6> kSpecks = {20.0f, 82.0f, 140.0f, 196.0f, 258.0f, 312.0f};

void RenderPuff(HWND window, const PuffState& state, float t) {
  const int side = state.extent * 2;
  Gdiplus::Bitmap canvas(side, side, PixelFormat32bppPARGB);
  Gdiplus::Graphics graphics(&canvas);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  graphics.Clear(Gdiplus::Color(0, 0, 0, 0));
  const float extent = static_cast<float>(state.extent);
  const float centre = extent;
  // Quick fade in, long fade out.
  const float alpha = t < 0.1f ? t / 0.1f : std::max(0.0f, 1.0f - std::pow((t - 0.1f) / 0.9f, 1.3f));

  struct Disc {
    float x, y, r;
  };
  std::array<Disc, kBillows.size()> discs{};
  for (std::size_t index = 0; index < kBillows.size(); ++index) {
    const Billow& billow = kBillows[index];
    const float local = std::clamp((t - billow.delay) / (1.0f - billow.delay), 0.0f, 1.0f);
    const float p = EaseOut(local);
    const float radians = billow.angle_degrees * kPi / 180.0f;
    const float distance = billow.distance * extent * (0.2f + 0.8f * p);
    discs[index] = {centre + std::cos(radians) * distance, centre + std::sin(radians) * distance,
                    extent * (billow.start_radius + (billow.end_radius - billow.start_radius) * p)};
  }

  // The billows merge into one silhouette, so the cloud has no seams.
  Gdiplus::GraphicsPath cloud(Gdiplus::FillModeWinding);
  for (const Disc& disc : discs) cloud.AddEllipse(disc.x - disc.r, disc.y - disc.r, disc.r * 2.0f, disc.r * 2.0f);
  // A soft shade beneath it so it reads on white pages, then the cool grey body.
  const float drop = extent * 0.03f;
  for (int layer = 3; layer >= 1; --layer) {
    Gdiplus::Matrix offset;
    offset.Translate(0.0f, drop * static_cast<float>(layer));
    std::unique_ptr<Gdiplus::GraphicsPath> shade(cloud.Clone());
    shade->Transform(&offset);
    Gdiplus::SolidBrush brush(Gdiplus::Color(static_cast<BYTE>(16 * alpha), 40, 44, 60));
    graphics.FillPath(&brush, shade.get());
  }
  Gdiplus::SolidBrush body(Gdiplus::Color(static_cast<BYTE>(242 * alpha), 222, 226, 235));
  graphics.FillPath(&body, &cloud);
  // Each billow's lit top-left gives the cloud its volume.
  for (const Disc& disc : discs) {
    Gdiplus::GraphicsPath path;
    path.AddEllipse(disc.x - disc.r, disc.y - disc.r, disc.r * 2.0f, disc.r * 2.0f);
    Gdiplus::PathGradientBrush brush(&path);
    brush.SetCenterPoint(Gdiplus::PointF(disc.x - disc.r * 0.3f, disc.y - disc.r * 0.35f));
    brush.SetCenterColor(Gdiplus::Color(static_cast<BYTE>(250 * alpha), 255, 255, 255));
    Gdiplus::Color rim(0, 255, 255, 255);
    int count = 1;
    brush.SetSurroundColors(&rim, &count);
    graphics.FillPath(&brush, &path);
  }
  // Specks fly out a little further and fade first.
  const float speck_alpha = std::max(0.0f, alpha - 0.15f);
  for (const float angle : kSpecks) {
    const float radians = angle * kPi / 180.0f;
    const float distance = extent * (0.35f + 0.55f * EaseOut(t));
    const float r = extent * 0.045f * (1.0f - 0.5f * t);
    Gdiplus::SolidBrush speck(Gdiplus::Color(static_cast<BYTE>(220 * speck_alpha), 214, 218, 228));
    graphics.FillEllipse(&speck, centre + std::cos(radians) * distance - r, centre + std::sin(radians) * distance - r,
                         r * 2.0f, r * 2.0f);
  }
  Present(window, canvas, POINT{state.center.x - state.extent, state.center.y - state.extent}, 255);
}

LRESULT CALLBACK PuffProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lparam);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  }
  if (message == WM_NCHITTEST) return HTTRANSPARENT;
  if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
  auto* state = reinterpret_cast<PuffState*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_TIMER && wparam == kAnimationTimer && state != nullptr) {
    const float t = std::min(1.0f, static_cast<float>(GetTickCount() - state->started) / kPuffMs);
    RenderPuff(hwnd, *state, t);
    if (t >= 1.0f) DestroyWindow(hwnd);
    return 0;
  }
  if (message == WM_NCDESTROY) {
    KillTimer(hwnd, kAnimationTimer);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
    delete state;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

}  // namespace

void ShowRemovalPuff(HWND owner, POINT screen) {
  if (!AnimationsEnabled()) return;
  EnsureGdiPlus();
  auto* state = new PuffState{screen, ui::Dip(owner, 76), GetTickCount()};
  HWND window = CreateEffectWindow(kPuffClass, &PuffProc, owner, state);
  if (window == nullptr) {
    delete state;
    return;
  }
  RenderPuff(window, *state, 0.0f);
  ShowWindow(window, SW_SHOWNOACTIVATE);
  SetTimer(window, kAnimationTimer, kFrameMs, nullptr);
}

}  // namespace kelpie::windows
