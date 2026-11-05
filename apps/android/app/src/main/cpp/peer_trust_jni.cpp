#include <jni.h>
#include <codecvt>
#include <locale>
#include <string>
#include "kelpie/state_c_api.h"

namespace {
std::string Text(JNIEnv* env, jstring value) {
  if (!value) return {};
  const auto* chars = env->GetStringChars(value, nullptr);
  if (!chars) return {};
  const std::u16string utf16(reinterpret_cast<const char16_t*>(chars), env->GetStringLength(value));
  env->ReleaseStringChars(value, chars);
  std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> converter;
  return converter.to_bytes(utf16);
}
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_peerTrustRequest(
    JNIEnv* env, jobject, jstring path, jstring operation, jstring body) {
  try {
    char* result = kelpie_peer_trust_request(Text(env, path).c_str(), Text(env, operation).c_str(), Text(env, body).c_str());
    if (!result) return nullptr;
    const std::string output(result);
    kelpie_free_string(result);
    std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> converter;
    const auto utf16 = converter.from_bytes(output);
    return env->NewString(reinterpret_cast<const jchar*>(utf16.data()), static_cast<jsize>(utf16.size()));
  } catch (...) { return nullptr; }
}
