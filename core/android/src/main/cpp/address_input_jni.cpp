#include <jni.h>

#include <codecvt>
#include <locale>
#include <string>

#include "kelpie/address_input.h"

extern "C" JNIEXPORT jstring JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_resolveAddressInput(JNIEnv* env, jobject, jstring input) {
  if (input == nullptr) return nullptr;
  const jchar* chars = env->GetStringChars(input, nullptr);
  if (chars == nullptr) return nullptr;
  const std::u16string text(reinterpret_cast<const char16_t*>(chars), env->GetStringLength(input));
  env->ReleaseStringChars(input, chars);
  try {
    // JNI modified UTF-8 would corrupt supplementary characters in Google queries.
    std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> converter;
    const auto resolved = kelpie::ResolveAddressInput(converter.to_bytes(text));
    if (resolved.empty()) return nullptr;
    const auto result = converter.from_bytes(resolved);
    return env->NewString(reinterpret_cast<const jchar*>(result.data()), static_cast<jsize>(result.size()));
  } catch (...) {
    return nullptr;
  }
}
