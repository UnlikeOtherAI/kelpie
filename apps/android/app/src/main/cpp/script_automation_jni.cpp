#include <jni.h>
#include <codecvt>
#include <locale>
#include <memory>
#include <string>
#include <stdexcept>
#include "kelpie/browser_gateway_c_api.h"
#include "kelpie/mcp_c_api.h"
#include "kelpie/script_presentation.h"
#include "kelpie/script_redaction.h"

namespace {
std::string Input(JNIEnv* env, jstring value) {
  if (!value) return {};
  const auto* chars = env->GetStringChars(value, nullptr);
  if (!chars) return {};
  const auto release_chars = [env, value](const jchar* held) {
    env->ReleaseStringChars(value, held);
  };
  std::unique_ptr<const jchar, decltype(release_chars)> held(chars, release_chars);
  const std::u16string text(reinterpret_cast<const char16_t*>(held.get()),
                            env->GetStringLength(value));
  held.reset();
  // C ABI requests are NUL terminated; reject raw NUL, not a truncated prefix.
  // Escaped JSON NUL remains valid and round-trips through standard UTF-8.
  if (text.find(char16_t{0}) != std::u16string::npos)
    throw std::invalid_argument("SCRIPT_JSON_NUL");
  for (size_t i = 0; i < text.size(); ++i) {
    const auto value = text[i];
    if (value >= 0xd800 && value <= 0xdbff) {
      if (++i >= text.size() || text[i] < 0xdc00 || text[i] > 0xdfff)
        throw std::invalid_argument("SCRIPT_JSON_UTF16");
    } else if (value >= 0xdc00 && value <= 0xdfff) {
      throw std::invalid_argument("SCRIPT_JSON_UTF16");
    }
  }
  std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> converter;
  return converter.to_bytes(text);
}
jstring Output(JNIEnv* env, char* owned, void (*release)(char*) = kelpie_mcp_free_string) {
  if (!owned) return nullptr;
  std::unique_ptr<char, void (*)(char*)> held(owned, release);
  const std::string text(held.get());
  held.reset();
  std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> converter;
  const auto value = converter.from_bytes(text);
  return env->NewString(reinterpret_cast<const jchar*>(value.data()),
                        static_cast<jsize>(value.size()));
}
jdoubleArray Pair(JNIEnv* env, double first, double second) {
  auto result = env->NewDoubleArray(2);
  const jdouble values[] = {first, second};
  if (result) env->SetDoubleArrayRegion(result, 0, 2, values);
  return result;
}
}  // namespace

extern "C" {
JNIEXPORT jstring JNICALL
Java_com_kelpie_browser_automation_ScriptNative_redactOutputs(JNIEnv* env, jobject, jstring request) {
  try {
    const auto input = Input(env, request);
    return Output(env, kelpie_script_redact_outputs_json(input.c_str()), kelpie_script_redaction_free_string);
  } catch (...) {
    return nullptr;
  }
}
JNIEXPORT jstring JNICALL
Java_com_kelpie_browser_automation_ScriptNative_validate(JNIEnv* env, jobject, jstring script) {
  try {
    const auto input = Input(env, script);
    return Output(env, kelpie_browser_validate_script(input.c_str()));
  } catch (...) {
    return env->NewStringUTF("{\"valid\":false}");
  }
}
JNIEXPORT jstring JNICALL
Java_com_kelpie_browser_automation_ScriptNative_targetExpression(JNIEnv* env, jobject, jstring options) {
  try {
    const auto input = Input(env, options);
    return Output(env, kelpie_browser_script_target_expression(input.c_str()));
  } catch (...) {
    return nullptr;
  }
}
JNIEXPORT jstring JNICALL
Java_com_kelpie_browser_automation_ScriptNative_typingPlan(JNIEnv* env, jobject, jstring action) {
  try {
    const auto input = Input(env, action);
    return Output(env, kelpie_browser_script_typing_plan(input.c_str()));
  } catch (...) {
    return nullptr;
  }
}
JNIEXPORT jdoubleArray JNICALL
Java_com_kelpie_browser_automation_ScriptNative_pointerPosition(
    JNIEnv* env, jobject, jdouble from_x, jdouble from_y, jdouble to_x, jdouble to_y,
    jboolean curve_s, jdouble elapsed, jdouble duration) {
  const auto result = kelpie_script_pointer_position(
      {from_x, from_y}, {to_x, to_y}, curve_s != JNI_FALSE,
      kelpie_script_progress(elapsed, duration));
  return Pair(env, result.x, result.y);
}
JNIEXPORT jdoubleArray JNICALL
Java_com_kelpie_browser_automation_ScriptNative_tapPresentation(
    JNIEnv* env, jobject, jdouble elapsed, jdouble duration, jboolean wobble, jboolean fade) {
  const auto result = kelpie_script_tap_presentation(
      kelpie_script_progress(elapsed, duration), wobble != JNI_FALSE, fade != JNI_FALSE);
  return Pair(env, result.scale, result.alpha);
}
}