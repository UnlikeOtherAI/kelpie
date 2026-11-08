#include <jni.h>
#include <codecvt>
#include <cstdint>
#include <locale>
#include <string>
#include "kelpie/browser_gateway_c_api.h"
#include "kelpie/mcp_c_api.h"

namespace {
KelpieBrowserGatewayRef Gateway(jlong handle) {
  return reinterpret_cast<KelpieBrowserGatewayRef>(static_cast<intptr_t>(handle));
}
std::string Input(JNIEnv* env, jstring input) {
  if (!input) return {};
  const jchar* chars = env->GetStringChars(input, nullptr);
  if (!chars) return {};
  const std::u16string text(reinterpret_cast<const char16_t*>(chars), env->GetStringLength(input));
  env->ReleaseStringChars(input, chars);
  std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> converter;
  try { return converter.to_bytes(text); }
  catch (const std::exception&) {
    env->ThrowNew(env->FindClass("java/lang/IllegalArgumentException"), "Invalid UTF-16 browser input");
    return {};
  }
}
jstring Output(JNIEnv* env, char* owned) {
  if (!owned) return nullptr;
  const std::string text(owned);
  kelpie_mcp_free_string(owned);
  std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> converter;
  try {
    const auto utf16 = converter.from_bytes(text);
    return env->NewString(reinterpret_cast<const jchar*>(utf16.data()), static_cast<jsize>(utf16.size()));
  } catch (const std::exception&) {
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), "Invalid UTF-8 browser response");
    return nullptr;
  }
}
}  // namespace

extern "C" {
JNIEXPORT jstring JNICALL Java_com_kelpie_browser_nativecore_BrowserGatewayNative_selectorSnapshotExpression(JNIEnv* env, jobject, jstring options) {
  const auto input = Input(env, options);
  return Output(env, kelpie_browser_selector_snapshot_expression(input.c_str()));
}
JNIEXPORT jlong JNICALL Java_com_kelpie_browser_nativecore_BrowserGatewayNative_create(JNIEnv* env, jobject, jstring config) {
  const auto input = Input(env, config);
  return static_cast<jlong>(reinterpret_cast<intptr_t>(kelpie_browser_gateway_create(input.c_str())));
}
JNIEXPORT void JNICALL Java_com_kelpie_browser_nativecore_BrowserGatewayNative_destroy(JNIEnv*, jobject, jlong handle) {
  kelpie_browser_gateway_destroy(Gateway(handle));
}
JNIEXPORT jstring JNICALL Java_com_kelpie_browser_nativecore_BrowserGatewayNative_begin(JNIEnv* env, jobject, jlong handle, jstring request, jboolean mcp) {
  const auto input = Input(env, request);
  return Output(env, mcp ? kelpie_browser_gateway_begin_mcp(Gateway(handle), input.c_str()) : kelpie_browser_gateway_begin(Gateway(handle), input.c_str()));
}
JNIEXPORT jstring JNICALL Java_com_kelpie_browser_nativecore_BrowserGatewayNative_advance(JNIEnv* env, jobject, jlong handle, jstring result) {
  const auto input = Input(env, result);
  return Output(env, kelpie_browser_gateway_advance(Gateway(handle), input.c_str()));
}
JNIEXPORT jstring JNICALL Java_com_kelpie_browser_nativecore_BrowserGatewayNative_cancel(JNIEnv* env, jobject, jlong handle) {
  return Output(env, kelpie_browser_gateway_cancel(Gateway(handle)));
}
JNIEXPORT void JNICALL Java_com_kelpie_browser_nativecore_BrowserGatewayNative_invalidate(JNIEnv* env, jobject, jlong handle, jstring tab) {
  const auto input = Input(env, tab);
  kelpie_browser_gateway_invalidate_refs(Gateway(handle), tab ? input.c_str() : nullptr);
}
JNIEXPORT jstring JNICALL Java_com_kelpie_browser_nativecore_BrowserGatewayNative_extensions(JNIEnv* env, jobject) {
  const auto registry = kelpie_mcp_registry_create();
  char* tools = kelpie_mcp_registry_tools_for_platform(registry, KELPIE_PLATFORM_ANDROID);
  kelpie_mcp_registry_destroy(registry);
  return Output(env, tools);
}
}
