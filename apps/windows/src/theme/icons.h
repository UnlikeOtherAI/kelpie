#pragma once

namespace kelpie::windows::ui {

// Segoe Fluent Icons / Segoe MDL2 Assets code points. The two faces share
// these values, so the fallback in metrics.cpp needs no separate table.
// Chosen to match the SF Symbols the macOS toolbar uses.
namespace icon {

constexpr wchar_t kBack = L'';        // ChevronLeft      — chevron.left
constexpr wchar_t kForward = L'';     // ChevronRight     — chevron.right
constexpr wchar_t kReload = L'';      // Refresh          — arrow.clockwise
constexpr wchar_t kStop = L'';        // Cancel           — xmark
constexpr wchar_t kBookmarks = L'';   // FavoriteStar     — bookmark.fill
constexpr wchar_t kHistory = L'';     // History          — clock.arrow.circlepath
constexpr wchar_t kNetwork = L'';     // NetworkTower     — antenna.radiowaves
constexpr wchar_t kSettings = L'';    // Setting          — gear
constexpr wchar_t kNewTab = L'';      // Add              — plus
constexpr wchar_t kClose = L'';       // Cancel           — xmark
constexpr wchar_t kLock = L'';        // Lock             — lock

}  // namespace icon

}  // namespace kelpie::windows::ui
