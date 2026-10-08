#include <jni.h>
#include <codecvt>
#include <locale>
#include <string>
#include "kelpie/local_inference.h"

namespace {
kelpie::ai::LocalInference engine;
std::string Utf8(JNIEnv* env, jstring input) {
  if (!input) return {};
  const auto* chars = env->GetStringChars(input, nullptr);
  if (!chars) throw std::bad_alloc();
  std::u16string copy(reinterpret_cast<const char16_t*>(chars), env->GetStringLength(input));
  env->ReleaseStringChars(input, chars);
  return std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t>().to_bytes(copy);
}
}
extern "C" JNIEXPORT jstring JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_localInference(JNIEnv* env, jobject, jstring operation, jstring body) {
  try {
    const auto result = engine.Execute(Utf8(env, operation), nlohmann::json::parse(Utf8(env, body)));
    const auto text = result.dump(-1, ' ', false, nlohmann::json::error_handler_t::replace);
    const auto utf16 = std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t>().from_bytes(text);
    return env->NewString(reinterpret_cast<const jchar*>(utf16.data()), utf16.size());
  } catch (...) { return env->NewStringUTF("{\"success\":false,\"error\":{\"code\":\"INVALID_PARAM\",\"message\":\"Invalid inference request\"}}"); }
}
extern "C" JNIEXPORT void JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_cancelLocalInference(JNIEnv*, jobject) { engine.Cancel(); }
