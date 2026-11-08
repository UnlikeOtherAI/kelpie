#include <jni.h>

#include <codecvt>
#include <cstdint>
#include <locale>
#include <string>

#include "kelpie/state_c_api.h"
#include "kelpie/ai_c_api.h"

namespace {

using BookmarkStoreRef = KelpieBookmarkStoreRef;
using HistoryStoreRef = KelpieHistoryStoreRef;
using NetworkTrafficStoreRef = KelpieNetworkTrafficStoreRef;

template <typename T>
T HandleFromJLong(jlong handle) {
  return reinterpret_cast<T>(static_cast<intptr_t>(handle));
}

template <typename T>
jlong JLongFromHandle(T handle) {
  return static_cast<jlong>(reinterpret_cast<intptr_t>(handle));
}

std::string JStringToUtf8(JNIEnv* env, jstring value) {
  if (value == nullptr) {
    return {};
  }

  const jchar* chars = env->GetStringChars(value, nullptr);
  if (chars == nullptr) {
    return {};
  }

  const jsize length = env->GetStringLength(value);
  const auto* utf16 = reinterpret_cast<const char16_t*>(chars);
  std::u16string utf16_string(utf16, utf16 + length);
  env->ReleaseStringChars(value, chars);

  try {
    std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> converter;
    return converter.to_bytes(utf16_string);
  } catch (...) {
    return {};
  }
}

jstring Utf8ToJString(JNIEnv* env, const std::string& value) {
  try {
    std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> converter;
    const std::u16string utf16 = converter.from_bytes(value);
    return env->NewString(reinterpret_cast<const jchar*>(utf16.data()),
                          static_cast<jsize>(utf16.size()));
  } catch (...) {
    return nullptr;
  }
}

jstring TakeOwnedCString(JNIEnv* env, char* value) {
  if (value == nullptr) {
    return nullptr;
  }

  const std::string utf8(value);
  kelpie_free_string(value);
  return Utf8ToJString(env, utf8);
}

jstring TakeOwnedAiString(JNIEnv* env, char* value) {
  if (value == nullptr) {
    return nullptr;
  }

  const std::string utf8(value);
  kelpie_ai_free_string(value);
  return Utf8ToJString(env, utf8);
}

}  // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_bookmarkStoreCreateNative(JNIEnv*, jobject) {
  return JLongFromHandle(kelpie_bookmark_store_create());
}

JNIEXPORT void JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_bookmarkStoreDestroyNative(JNIEnv*,
                                                                           jobject,
                                                                           jlong handle) {
  kelpie_bookmark_store_destroy(HandleFromJLong<BookmarkStoreRef>(handle));
}

JNIEXPORT void JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_bookmarkStoreAdd(JNIEnv* env,
                                                                 jobject,
                                                                 jlong handle,
                                                                 jstring title,
                                                                 jstring url) {
  const std::string native_title = JStringToUtf8(env, title);
  const std::string native_url = JStringToUtf8(env, url);
  kelpie_bookmark_store_add(HandleFromJLong<BookmarkStoreRef>(handle),
                              native_title.c_str(),
                              native_url.c_str());
}

JNIEXPORT void JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_bookmarkStoreRemove(JNIEnv* env,
                                                                    jobject,
                                                                    jlong handle,
                                                                    jstring id) {
  const std::string native_id = JStringToUtf8(env, id);
  kelpie_bookmark_store_remove(HandleFromJLong<BookmarkStoreRef>(handle), native_id.c_str());
}

JNIEXPORT void JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_bookmarkStoreRemoveAll(JNIEnv*,
                                                                       jobject,
                                                                       jlong handle) {
  kelpie_bookmark_store_remove_all(HandleFromJLong<BookmarkStoreRef>(handle));
}

JNIEXPORT jstring JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_bookmarkStoreToJson(JNIEnv* env,
                                                                    jobject,
                                                                    jlong handle) {
  return TakeOwnedCString(env,
                          kelpie_bookmark_store_to_json(
                              HandleFromJLong<BookmarkStoreRef>(handle)));
}

JNIEXPORT jint JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_bookmarkStoreCount(JNIEnv*,
                                                                   jobject,
                                                                   jlong handle) {
  return kelpie_bookmark_store_count(HandleFromJLong<BookmarkStoreRef>(handle));
}

JNIEXPORT void JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_bookmarkStoreLoadJson(JNIEnv* env,
                                                                      jobject,
                                                                      jlong handle,
                                                                      jstring json) {
  const std::string native_json = JStringToUtf8(env, json);
  kelpie_bookmark_store_load_json(HandleFromJLong<BookmarkStoreRef>(handle),
                                    native_json.c_str());
}

JNIEXPORT jlong JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_historyStoreCreateNative(JNIEnv*, jobject) {
  return JLongFromHandle(kelpie_history_store_create());
}

JNIEXPORT void JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_historyStoreDestroyNative(JNIEnv*,
                                                                          jobject,
                                                                          jlong handle) {
  kelpie_history_store_destroy(HandleFromJLong<HistoryStoreRef>(handle));
}

JNIEXPORT void JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_historyStoreRecord(JNIEnv* env,
                                                                   jobject,
                                                                   jlong handle,
                                                                   jstring url,
                                                                   jstring title) {
  const std::string native_url = JStringToUtf8(env, url);
  const std::string native_title = JStringToUtf8(env, title);
  kelpie_history_store_record(HandleFromJLong<HistoryStoreRef>(handle),
                                native_url.c_str(),
                                native_title.c_str());
}

JNIEXPORT void JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_historyStoreClear(JNIEnv*,
                                                                  jobject,
                                                                  jlong handle) {
  kelpie_history_store_clear(HandleFromJLong<HistoryStoreRef>(handle));
}

JNIEXPORT void JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_historyStoreUpdateLatestTitle(JNIEnv* env,
                                                                              jobject,
                                                                              jlong handle,
                                                                              jstring url,
                                                                              jstring title) {
  const std::string native_url = JStringToUtf8(env, url);
  const std::string native_title = JStringToUtf8(env, title);
  kelpie_history_store_update_latest_title(HandleFromJLong<HistoryStoreRef>(handle),
                                             native_url.c_str(),
                                             native_title.c_str());
}

JNIEXPORT jstring JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_historyStoreToJson(JNIEnv* env,
                                                                   jobject,
                                                                   jlong handle) {
  return TakeOwnedCString(env,
                          kelpie_history_store_to_json(
                              HandleFromJLong<HistoryStoreRef>(handle)));
}

JNIEXPORT jstring JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_historyStoreBestUrlCompletion(JNIEnv* env,
                                                                              jobject,
                                                                              jlong handle,
                                                                              jstring query) {
  const std::string native_query = JStringToUtf8(env, query);
  return TakeOwnedCString(
      env,
      kelpie_history_store_best_url_completion(
          HandleFromJLong<HistoryStoreRef>(handle),
          native_query.c_str()));
}

JNIEXPORT jint JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_historyStoreCount(JNIEnv*,
                                                                  jobject,
                                                                  jlong handle) {
  return kelpie_history_store_count(HandleFromJLong<HistoryStoreRef>(handle));
}

JNIEXPORT void JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_historyStoreLoadJson(JNIEnv* env,
                                                                     jobject,
                                                                     jlong handle,
                                                                     jstring json) {
  const std::string native_json = JStringToUtf8(env, json);
  kelpie_history_store_load_json(HandleFromJLong<HistoryStoreRef>(handle),
                                   native_json.c_str());
}

JNIEXPORT jlong JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_networkTrafficStoreCreateNative(JNIEnv*, jobject) {
  return JLongFromHandle(kelpie_network_traffic_store_create());
}

JNIEXPORT void JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_networkTrafficStoreDestroyNative(JNIEnv*,
                                                                                 jobject,
                                                                                 jlong handle) {
  kelpie_network_traffic_store_destroy(HandleFromJLong<NetworkTrafficStoreRef>(handle));
}

JNIEXPORT jboolean JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_networkTrafficStoreAppendJson(JNIEnv* env,
                                                                              jobject,
                                                                              jlong handle,
                                                                              jstring entryJson) {
  const std::string native_json = JStringToUtf8(env, entryJson);
  return kelpie_network_traffic_store_append_json(
             HandleFromJLong<NetworkTrafficStoreRef>(handle), native_json.c_str()) != 0;
}

JNIEXPORT void JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_networkTrafficStoreAppendDocumentNavigation(
    JNIEnv* env,
    jobject,
    jlong handle,
    jstring url,
    jint statusCode,
    jstring contentType,
    jstring responseHeadersJson,
    jlong size,
    jstring startTime,
    jint duration) {
  const std::string native_url = JStringToUtf8(env, url);
  const std::string native_content_type = JStringToUtf8(env, contentType);
  const std::string native_response_headers = JStringToUtf8(env, responseHeadersJson);
  const std::string native_start_time = JStringToUtf8(env, startTime);
  kelpie_network_traffic_store_append_document_navigation(
      HandleFromJLong<NetworkTrafficStoreRef>(handle),
      native_url.c_str(),
      statusCode,
      native_content_type.c_str(),
      native_response_headers.c_str(),
      size,
      native_start_time.c_str(),
      duration);
}

JNIEXPORT void JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_networkTrafficStoreClear(JNIEnv*,
                                                                         jobject,
                                                                         jlong handle) {
  kelpie_network_traffic_store_clear(HandleFromJLong<NetworkTrafficStoreRef>(handle));
}

JNIEXPORT jboolean JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_networkTrafficStoreSelect(JNIEnv*,
                                                                          jobject,
                                                                          jlong handle,
                                                                          jint index) {
  return kelpie_network_traffic_store_select(
             HandleFromJLong<NetworkTrafficStoreRef>(handle), index) != 0;
}

JNIEXPORT jint JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_networkTrafficStoreSelectedIndex(JNIEnv*,
                                                                                 jobject,
                                                                                 jlong handle) {
  return kelpie_network_traffic_store_selected_index(
      HandleFromJLong<NetworkTrafficStoreRef>(handle));
}

JNIEXPORT jstring JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_networkTrafficStoreGetSelectedJson(JNIEnv* env,
                                                                                   jobject,
                                                                                   jlong handle) {
  return TakeOwnedCString(env,
                          kelpie_network_traffic_store_get_selected_json(
                              HandleFromJLong<NetworkTrafficStoreRef>(handle)));
}

JNIEXPORT jstring JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_networkTrafficStoreToJson(JNIEnv* env,
                                                                          jobject,
                                                                          jlong handle) {
  return TakeOwnedCString(env,
                          kelpie_network_traffic_store_to_json(
                              HandleFromJLong<NetworkTrafficStoreRef>(handle)));
}

JNIEXPORT jstring JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_networkTrafficStoreToSummaryJson(
    JNIEnv* env,
    jobject,
    jlong handle,
    jstring method,
    jstring category,
    jstring statusRange,
    jstring urlPattern) {
  const std::string native_method = JStringToUtf8(env, method);
  const std::string native_category = JStringToUtf8(env, category);
  const std::string native_status_range = JStringToUtf8(env, statusRange);
  const std::string native_url_pattern = JStringToUtf8(env, urlPattern);
  return TakeOwnedCString(
      env,
      kelpie_network_traffic_store_to_summary_json(
          HandleFromJLong<NetworkTrafficStoreRef>(handle),
          native_method.c_str(),
          native_category.c_str(),
          native_status_range.c_str(),
          native_url_pattern.c_str()));
}

JNIEXPORT jint JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_networkTrafficStoreCount(JNIEnv*,
                                                                         jobject,
                                                                         jlong handle) {
  return kelpie_network_traffic_store_count(HandleFromJLong<NetworkTrafficStoreRef>(handle));
}

JNIEXPORT void JNICALL
Java_com_kelpie_browser_nativecore_NativeCore_networkTrafficStoreLoadJson(JNIEnv* env,
                                                                            jobject,
                                                                            jlong handle,
                                                                            jstring json) {
  const std::string native_json = JStringToUtf8(env, json);
  kelpie_network_traffic_store_load_json(HandleFromJLong<NetworkTrafficStoreRef>(handle),
                                           native_json.c_str());
}

// ---- AI Manager ----

using AiManagerRef = KelpieAiManagerRef;

JNIEXPORT jlong JNICALL
Java_com_kelpie_browser_nativecore_AiManager_aiManagerCreateNative(JNIEnv* env,
                                                                     jobject,
                                                                     jstring modelsDir) {
  const std::string native_dir = JStringToUtf8(env, modelsDir);
  return JLongFromHandle(kelpie_ai_create(native_dir.c_str()));
}

JNIEXPORT void JNICALL
Java_com_kelpie_browser_nativecore_AiManager_aiManagerDestroyNative(JNIEnv*,
                                                                      jobject,
                                                                      jlong handle) {
  kelpie_ai_destroy(HandleFromJLong<AiManagerRef>(handle));
}

JNIEXPORT void JNICALL
Java_com_kelpie_browser_nativecore_AiManager_aiSetHfToken(JNIEnv* env,
                                                            jobject,
                                                            jlong handle,
                                                            jstring token) {
  const std::string native_token = JStringToUtf8(env, token);
  kelpie_ai_set_hf_token(HandleFromJLong<AiManagerRef>(handle), native_token.c_str());
}

JNIEXPORT jstring JNICALL
Java_com_kelpie_browser_nativecore_AiManager_aiGetHfToken(JNIEnv* env,
                                                            jobject,
                                                            jlong handle) {
  return TakeOwnedAiString(env,
                           kelpie_ai_get_hf_token(HandleFromJLong<AiManagerRef>(handle)));
}

JNIEXPORT jstring JNICALL
Java_com_kelpie_browser_nativecore_AiManager_aiListApprovedModels(JNIEnv* env,
                                                                    jobject,
                                                                    jlong handle) {
  return TakeOwnedAiString(env,
                           kelpie_ai_list_approved_models(HandleFromJLong<AiManagerRef>(handle)));
}

JNIEXPORT jstring JNICALL
Java_com_kelpie_browser_nativecore_AiManager_aiModelFitness(JNIEnv* env,
                                                              jobject,
                                                              jlong handle,
                                                              jstring modelId,
                                                              jdouble ramGB,
                                                              jdouble diskGB) {
  const std::string native_model_id = JStringToUtf8(env, modelId);
  return TakeOwnedAiString(env,
                           kelpie_ai_model_fitness(HandleFromJLong<AiManagerRef>(handle),
                                                     native_model_id.c_str(),
                                                     ramGB, diskGB));
}

JNIEXPORT jboolean JNICALL
Java_com_kelpie_browser_nativecore_AiManager_aiIsModelDownloaded(JNIEnv* env,
                                                                    jobject,
                                                                    jlong handle,
                                                                    jstring modelId) {
  const std::string native_model_id = JStringToUtf8(env, modelId);
  return kelpie_ai_is_model_downloaded(HandleFromJLong<AiManagerRef>(handle),
                                          native_model_id.c_str());
}

JNIEXPORT jstring JNICALL
Java_com_kelpie_browser_nativecore_AiManager_aiModelPath(JNIEnv* env,
                                                           jobject,
                                                           jlong handle,
                                                           jstring modelId) {
  const std::string native_model_id = JStringToUtf8(env, modelId);
  return TakeOwnedAiString(env,
                           kelpie_ai_model_path(HandleFromJLong<AiManagerRef>(handle),
                                                   native_model_id.c_str()));
}

JNIEXPORT jboolean JNICALL
Java_com_kelpie_browser_nativecore_AiManager_aiRemoveModel(JNIEnv* env,
                                                              jobject,
                                                              jlong handle,
                                                              jstring modelId) {
  const std::string native_model_id = JStringToUtf8(env, modelId);
  return kelpie_ai_remove_model(HandleFromJLong<AiManagerRef>(handle),
                                   native_model_id.c_str());
}

JNIEXPORT void JNICALL
Java_com_kelpie_browser_nativecore_AiManager_aiSetOllamaEndpoint(JNIEnv* env,
                                                                    jobject,
                                                                    jlong handle,
                                                                    jstring endpoint) {
  const std::string native_endpoint = JStringToUtf8(env, endpoint);
  kelpie_ai_set_ollama_endpoint(HandleFromJLong<AiManagerRef>(handle),
                                   native_endpoint.c_str());
}

JNIEXPORT jboolean JNICALL
Java_com_kelpie_browser_nativecore_AiManager_aiOllamaReachable(JNIEnv*,
                                                                  jobject,
                                                                  jlong handle) {
  return kelpie_ai_ollama_reachable(HandleFromJLong<AiManagerRef>(handle));
}

JNIEXPORT jstring JNICALL
Java_com_kelpie_browser_nativecore_AiManager_aiOllamaListModels(JNIEnv* env,
                                                                   jobject,
                                                                   jlong handle) {
  return TakeOwnedAiString(env,
                           kelpie_ai_ollama_list_models(HandleFromJLong<AiManagerRef>(handle)));
}

JNIEXPORT jstring JNICALL
Java_com_kelpie_browser_nativecore_AiManager_aiOllamaInfer(JNIEnv* env,
                                                              jobject,
                                                              jlong handle,
                                                              jstring model,
                                                              jstring requestJson) {
  const std::string native_model = JStringToUtf8(env, model);
  const std::string native_request = JStringToUtf8(env, requestJson);
  return TakeOwnedAiString(env,
                           kelpie_ai_ollama_infer(HandleFromJLong<AiManagerRef>(handle),
                                                     native_model.c_str(),
                                                     native_request.c_str()));
}

}  // extern "C"
