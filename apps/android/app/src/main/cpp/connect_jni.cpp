#include <jni.h>
#include <codecvt>
#include <cstdint>
#include <locale>
#include <string>
#include "kelpie/connect.h"
namespace {
std::string Read(JNIEnv* env, jstring value) {
  if (!value) return {};
  const auto* chars = env->GetStringChars(value, nullptr);
  if (!chars) return {};
  const auto count = env->GetStringLength(value);
  std::u16string text(reinterpret_cast<const char16_t*>(chars), count);
  env->ReleaseStringChars(value, chars);
  std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> converter;
  return converter.to_bytes(text);
}
KelpieConnectRef Handle(jlong handle) {
  return reinterpret_cast<KelpieConnectRef>(static_cast<intptr_t>(handle));
}
}
extern "C" {
JNIEXPORT jlong JNICALL Java_com_kelpie_browser_nativecore_NativeCore_connectCreate(
    JNIEnv* env, jobject, jstring state, jstring owner) {
  try {
    return static_cast<jlong>(reinterpret_cast<intptr_t>(kelpie_connect_create(
        Read(env, state).c_str(), Read(env, owner).c_str())));
  } catch (...) { return 0; }
}
JNIEXPORT void JNICALL Java_com_kelpie_browser_nativecore_NativeCore_connectDestroy(
    JNIEnv*, jobject, jlong handle) { kelpie_connect_destroy(Handle(handle)); }
JNIEXPORT jstring JNICALL Java_com_kelpie_browser_nativecore_NativeCore_connectExecute(
    JNIEnv* env, jobject, jlong handle, jstring operation, jstring json) {
  char* raw = nullptr;
  try {
    raw = kelpie_connect_execute(Handle(handle), Read(env, operation).c_str(), Read(env, json).c_str());
    if (!raw) return nullptr;
    std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> converter;
    const auto value = converter.from_bytes(raw);
    kelpie_connect_free(raw);
    raw = nullptr;
    return env->NewString(reinterpret_cast<const jchar*>(value.data()), static_cast<jsize>(value.size()));
  } catch (...) { kelpie_connect_free(raw); return nullptr; }
}
}
