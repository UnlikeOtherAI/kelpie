// JNI bridge over the core-sync C API (core/native/core-sync). Every call is
// JSON in, JSON out; Kotlin runs all calls for one store on one thread.
#include <jni.h>

#include <codecvt>
#include <cstdint>
#include <locale>
#include <string>

#include "kelpie/sync_c_api.h"

namespace {

KelpieSyncStoreRef Store(jlong handle) {
  return reinterpret_cast<KelpieSyncStoreRef>(static_cast<intptr_t>(handle));
}

std::string Input(JNIEnv* env, jstring input) {
  if (!input) return {};
  const jchar* chars = env->GetStringChars(input, nullptr);
  if (!chars) return {};
  const std::u16string text(reinterpret_cast<const char16_t*>(chars), env->GetStringLength(input));
  env->ReleaseStringChars(input, chars);
  std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> converter;
  try {
    return converter.to_bytes(text);
  } catch (const std::exception&) {
    env->ThrowNew(env->FindClass("java/lang/IllegalArgumentException"), "Invalid UTF-16 sync input");
    return {};
  }
}

jstring Output(JNIEnv* env, char* owned) {
  if (!owned) return nullptr;
  const std::string text(owned);
  kelpie_sync_free_string(owned);
  std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> converter;
  try {
    const auto utf16 = converter.from_bytes(text);
    return env->NewString(reinterpret_cast<const jchar*>(utf16.data()), static_cast<jsize>(utf16.size()));
  } catch (const std::exception&) {
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), "Invalid UTF-8 sync output");
    return nullptr;
  }
}

}  // namespace

#define KELPIE_SYNC_JNI(name) Java_com_kelpie_browser_nativecore_CookieSyncNative_##name

extern "C" {

// Returns {"handle":"<decimal>"} or the core-sync {"error"} object.
JNIEXPORT jstring JNICALL KELPIE_SYNC_JNI(storeOpen)(JNIEnv* env, jobject, jstring path, jstring options) {
  const auto file = Input(env, path);
  const auto parsed = Input(env, options);
  if (env->ExceptionCheck()) return nullptr;
  char* error = nullptr;
  const auto store = kelpie_sync_store_open(file.c_str(), parsed.c_str(), &error);
  if (store == nullptr) return Output(env, error);
  const std::string handle =
      "{\"handle\":\"" + std::to_string(static_cast<long long>(reinterpret_cast<intptr_t>(store))) + "\"}";
  return env->NewStringUTF(handle.c_str());
}

JNIEXPORT void JNICALL KELPIE_SYNC_JNI(storeClose)(JNIEnv*, jobject, jlong handle) {
  kelpie_sync_store_close(Store(handle));
}

JNIEXPORT jstring JNICALL KELPIE_SYNC_JNI(storeStatus)(JNIEnv* env, jobject, jlong handle) {
  return Output(env, kelpie_sync_store_status(Store(handle)));
}

JNIEXPORT void JNICALL KELPIE_SYNC_JNI(storeFinishWarmup)(JNIEnv*, jobject, jlong handle) {
  kelpie_sync_store_finish_warmup(Store(handle));
}

JNIEXPORT jstring JNICALL KELPIE_SYNC_JNI(storeScan)(JNIEnv* env, jobject, jlong handle, jstring cookies,
                                                     jstring coverage, jlong now) {
  const auto engine = Input(env, cookies);
  const auto covered = Input(env, coverage);
  if (env->ExceptionCheck()) return nullptr;
  return Output(env, kelpie_sync_store_scan(Store(handle), engine.c_str(), covered.c_str(), now));
}

JNIEXPORT jstring JNICALL KELPIE_SYNC_JNI(storeAnswerPull)(JNIEnv* env, jobject, jlong handle, jstring pull,
                                                           jstring cookies, jstring coverage, jlong now) {
  const auto request = Input(env, pull);
  const auto engine = Input(env, cookies);
  const auto covered = Input(env, coverage);
  if (env->ExceptionCheck()) return nullptr;
  return Output(env, kelpie_sync_store_answer_pull(Store(handle), request.c_str(), engine.c_str(), covered.c_str(), now));
}

JNIEXPORT jstring JNICALL KELPIE_SYNC_JNI(storeBuildPush)(JNIEnv* env, jobject, jlong handle, jstring watermark,
                                                          jstring cookies, jstring coverage, jlong now) {
  const auto known = Input(env, watermark);
  const auto engine = Input(env, cookies);
  const auto covered = Input(env, coverage);
  if (env->ExceptionCheck()) return nullptr;
  return Output(env, kelpie_sync_store_build_push(Store(handle), known.c_str(), engine.c_str(), covered.c_str(), now));
}

JNIEXPORT jstring JNICALL KELPIE_SYNC_JNI(storePlanMerge)(JNIEnv* env, jobject, jlong handle, jstring records,
                                                          jstring source, jlong now) {
  const auto remote = Input(env, records);
  const auto cursor = Input(env, source);
  if (env->ExceptionCheck()) return nullptr;
  return Output(env, kelpie_sync_store_plan_merge(Store(handle), remote.c_str(), source ? cursor.c_str() : nullptr, now));
}

JNIEXPORT jstring JNICALL KELPIE_SYNC_JNI(storeCommitMerge)(JNIEnv* env, jobject, jlong handle, jstring results) {
  const auto outcome = Input(env, results);
  if (env->ExceptionCheck()) return nullptr;
  return Output(env, kelpie_sync_store_commit_merge(Store(handle), outcome.c_str()));
}

JNIEXPORT void JNICALL KELPIE_SYNC_JNI(storeAbortMerge)(JNIEnv*, jobject, jlong handle) {
  kelpie_sync_store_abort_merge(Store(handle));
}

JNIEXPORT jstring JNICALL KELPIE_SYNC_JNI(storeWatermark)(JNIEnv* env, jobject, jlong handle, jstring replica) {
  const auto peer = Input(env, replica);
  if (env->ExceptionCheck()) return nullptr;
  return Output(env, kelpie_sync_store_watermark(Store(handle), peer.c_str()));
}

JNIEXPORT jstring JNICALL KELPIE_SYNC_JNI(validate)(JNIEnv* env, jobject, jstring kind, jstring json) {
  const auto type = Input(env, kind);
  const auto message = Input(env, json);
  if (env->ExceptionCheck()) return nullptr;
  return Output(env, kelpie_sync_validate(type.c_str(), message.c_str()));
}

JNIEXPORT jstring JNICALL KELPIE_SYNC_JNI(transcript)(JNIEnv* env, jobject, jstring pair) {
  const auto hellos = Input(env, pair);
  if (env->ExceptionCheck()) return nullptr;
  return Output(env, kelpie_sync_transcript(hellos.c_str()));
}

JNIEXPORT jstring JNICALL KELPIE_SYNC_JNI(accountHints)(JNIEnv* env, jobject, jstring subject, jlong now) {
  const auto account = Input(env, subject);
  if (env->ExceptionCheck()) return nullptr;
  return Output(env, kelpie_sync_account_hints(account.c_str(), now));
}

JNIEXPORT jstring JNICALL KELPIE_SYNC_JNI(canonicalCookie)(JNIEnv* env, jobject, jstring cookie) {
  const auto engine = Input(env, cookie);
  if (env->ExceptionCheck()) return nullptr;
  return Output(env, kelpie_sync_canonical_cookie(engine.c_str()));
}

}  // extern "C"
