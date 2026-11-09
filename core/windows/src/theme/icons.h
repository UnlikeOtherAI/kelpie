#pragma once

namespace kelpie::windows::ui {

// Segoe Fluent Icons / Segoe MDL2 Assets code points. The two faces share
// these values, so the fallback in metrics.cpp needs no separate table.
// Chosen to match the SF Symbols the macOS toolbar uses.
namespace icon {

constexpr wchar_t kBack = L'\uE72B';          // ChevronLeft   — chevron.left
constexpr wchar_t kForward = L'\uE72A';       // ChevronRight  — chevron.right
constexpr wchar_t kReload = L'\uE72C';        // Refresh       — arrow.clockwise
constexpr wchar_t kStop = L'\uE711';          // Cancel        — xmark
constexpr wchar_t kHome = L'\uE80F';          // Home          — house
constexpr wchar_t kFavoriteStar = L'\uE734';  // FavoriteStar  — star (adds the current page)
// FavoriteList, Edge's Favorites glyph: the saved list, distinct from the
// address-field star that adds to it.
constexpr wchar_t kBookmarks = L'\uE728';     // FavoriteList  — bookmark
constexpr wchar_t kHistory = L'\uE81C';       // History       — clock.arrow.circlepath
// Requests going out and responses coming back. An antenna would read as the
// Nessie connection status that the account menu already reports.
constexpr wchar_t kNetwork = L'\uE8CB';       // Sort (up/down) — network traffic
constexpr wchar_t kSettings = L'\uE712';      // More          — ellipsis
constexpr wchar_t kPerson = L'\uEA8C';        // ContactSolid  — person.crop.circle.fill
constexpr wchar_t kNewTab = L'\uE710';        // Add           — plus
constexpr wchar_t kClose = L'\uE711';         // Cancel        — xmark
constexpr wchar_t kLock = L'\uE72E';          // Lock          — lock
constexpr wchar_t kChevronDown = L'\uE70D';   // ChevronDown   — chevron.down
constexpr wchar_t kClear = L'\uE733';         // Blocked       — DevTools "Clear"
constexpr wchar_t kFilter = L'\uE71C';        // Filter        — line.3.horizontal.decrease

}  // namespace icon

}  // namespace kelpie::windows::ui
