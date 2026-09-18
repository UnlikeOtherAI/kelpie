#pragma once

#include <cstddef>
#include <string>
#include <string_view>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

// Letter avatars for tabs without a favicon.
//
// This is a byte-for-byte mirror of `LetterAvatarView` in
// `apps/macos/Kelpie/Views/TabBarView.swift`: the same six colours and the same
// domain hash, so a given site gets the same colour on both platforms.
//
// Keep in step with macOS. Changing the palette or the hash on one platform
// without the other silently breaks that guarantee — there is no shared test
// that can catch it.
namespace kelpie::windows {

// The macOS pill reserves a 14 pt square for the favicon or avatar. One macOS
// point equals one Windows DIP, so the strip asks for `LetterAvatarSize(hwnd)`.
inline constexpr int kTabIconDip = 14;

// The 14 DIP box in device pixels for `window`'s current DPI.
int LetterAvatarSize(HWND window);

inline constexpr std::size_t kLetterAvatarPaletteSize = 6;

// `palette[index]` from `LetterAvatarView`, converted from the macOS HSB values
// to RGB. The source HSB triples are in the implementation.
COLORREF LetterAvatarPaletteColor(std::size_t index);

// `abs(domain.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % 6`.
//
// `host` is UTF-8 and is hashed by Unicode scalar, matching Swift. It is used
// exactly as given: Chromium and Foundation both report URL hosts already
// lower-cased, so neither platform normalises before hashing.
std::size_t LetterAvatarColorIndex(std::string_view host);

// Convenience for `LetterAvatarPaletteColor(LetterAvatarColorIndex(host))`.
COLORREF LetterAvatarColor(std::string_view host);

// The first letter of `host`, upper-cased, or `?` when it has none — matching
// `domain.first(where: { $0.isLetter })`.
std::wstring LetterAvatarLetter(std::string_view host);

// Paints the avatar: a `bounds`-filling rounded square in the host's colour with
// a white bold letter centred on it. Corner radius and font size scale with
// `bounds` from the macOS 14 pt reference (corner 3, letter 9 pt bold), so this
// stays correct at any DPI without needing the window.
void DrawLetterAvatar(HDC device_context, const RECT& bounds, std::string_view host);

// Paints the start page marker: the filled star the macOS pill shows in place of
// an avatar when `Tab.isStartPage` is true.
void DrawStartPageIcon(HDC device_context, const RECT& bounds);

}  // namespace kelpie::windows
