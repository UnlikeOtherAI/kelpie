#include "kelpie/state_c_api.h"

#include <optional>
#include <string>

#include "state_c_api_internal.h"

extern "C" {

void kelpie_free_string(char* str) {
  delete[] str;
}

KelpieBookmarkStoreRef kelpie_bookmark_store_create(void) {
  try {
    return new KelpieBookmarkStore();
  } catch (...) {
    return nullptr;
  }
}

void kelpie_bookmark_store_destroy(KelpieBookmarkStoreRef store) {
  delete store;
}

void kelpie_bookmark_store_add(KelpieBookmarkStoreRef store, const char* title, const char* url) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.Add(kelpie::state_c_api_internal::SafeCString(title),
                     kelpie::state_c_api_internal::SafeCString(url));
  } catch (...) {
  }
}

void kelpie_bookmark_store_remove(KelpieBookmarkStoreRef store, const char* id) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.Remove(kelpie::state_c_api_internal::SafeCString(id));
  } catch (...) {
  }
}

void kelpie_bookmark_store_remove_all(KelpieBookmarkStoreRef store) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.RemoveAll();
  } catch (...) {
  }
}

char* kelpie_bookmark_store_to_json(KelpieBookmarkStoreRef store) {
  if (store == nullptr) {
    return nullptr;
  }
  try {
    return kelpie::state_c_api_internal::CopyString(store->store.ToJson());
  } catch (...) {
    return nullptr;
  }
}

int32_t kelpie_bookmark_store_count(KelpieBookmarkStoreRef store) {
  if (store == nullptr) {
    return 0;
  }
  try {
    return store->store.Count();
  } catch (...) {
    return 0;
  }
}

void kelpie_bookmark_store_load_json(KelpieBookmarkStoreRef store, const char* json_text) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.LoadJson(kelpie::state_c_api_internal::SafeCString(json_text));
  } catch (...) {
  }
}

KelpieHistoryStoreRef kelpie_history_store_create(void) {
  try {
    return new KelpieHistoryStore();
  } catch (...) {
    return nullptr;
  }
}

void kelpie_history_store_destroy(KelpieHistoryStoreRef store) {
  delete store;
}

void kelpie_history_store_record(KelpieHistoryStoreRef store, const char* url, const char* title) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.Record(kelpie::state_c_api_internal::SafeCString(url),
                        kelpie::state_c_api_internal::SafeCString(title));
  } catch (...) {
  }
}

void kelpie_history_store_clear(KelpieHistoryStoreRef store) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.Clear();
  } catch (...) {
  }
}

void kelpie_history_store_update_latest_title(KelpieHistoryStoreRef store,
                                                const char* url,
                                                const char* title) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.UpdateLatestTitle(kelpie::state_c_api_internal::SafeCString(url),
                                   kelpie::state_c_api_internal::SafeCString(title));
  } catch (...) {
  }
}

char* kelpie_history_store_to_json(KelpieHistoryStoreRef store) {
  if (store == nullptr) {
    return nullptr;
  }
  try {
    return kelpie::state_c_api_internal::CopyString(store->store.ToJson());
  } catch (...) {
    return nullptr;
  }
}

int32_t kelpie_history_store_count(KelpieHistoryStoreRef store) {
  if (store == nullptr) {
    return 0;
  }
  try {
    return store->store.Count();
  } catch (...) {
    return 0;
  }
}

void kelpie_history_store_load_json(KelpieHistoryStoreRef store, const char* json_text) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.LoadJson(kelpie::state_c_api_internal::SafeCString(json_text));
  } catch (...) {
  }
}

KelpieNetworkTrafficStoreRef kelpie_network_traffic_store_create(void) {
  try {
    return new KelpieNetworkTrafficStore();
  } catch (...) {
    return nullptr;
  }
}

void kelpie_network_traffic_store_destroy(KelpieNetworkTrafficStoreRef store) {
  delete store;
}

int32_t kelpie_network_traffic_store_append_json(KelpieNetworkTrafficStoreRef store,
                                                   const char* entry_json) {
  if (store == nullptr) {
    return 0;
  }
  try {
    const std::optional<kelpie::TrafficEntry> entry =
        kelpie::state_c_api_internal::ParseTrafficEntry(entry_json);
    if (!entry.has_value()) {
      return 0;
    }
    store->store.Append(*entry);
    return 1;
  } catch (...) {
    return 0;
  }
}

void kelpie_network_traffic_store_append_document_navigation(
    KelpieNetworkTrafficStoreRef store,
    const char* url,
    int32_t status_code,
    const char* content_type,
    const char* response_headers_json,
    int64_t size,
    const char* start_time,
    int32_t duration) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.AppendDocumentNavigation(
        kelpie::state_c_api_internal::SafeCString(url), status_code,
        kelpie::state_c_api_internal::SafeCString(content_type),
        kelpie::state_c_api_internal::ParseHeadersJson(response_headers_json), size,
        kelpie::state_c_api_internal::SafeCString(start_time), duration);
  } catch (...) {
  }
}

void kelpie_network_traffic_store_clear(KelpieNetworkTrafficStoreRef store) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.Clear();
  } catch (...) {
  }
}

int32_t kelpie_network_traffic_store_select(KelpieNetworkTrafficStoreRef store, int32_t index) {
  if (store == nullptr || index < 0) {
    return 0;
  }
  try {
    return store->store.Select(static_cast<std::size_t>(index)) ? 1 : 0;
  } catch (...) {
    return 0;
  }
}

int32_t kelpie_network_traffic_store_selected_index(KelpieNetworkTrafficStoreRef store) {
  if (store == nullptr) {
    return -1;
  }
  try {
    const std::optional<std::size_t> index = store->store.SelectedIndex();
    return index.has_value() ? static_cast<int32_t>(*index) : -1;
  } catch (...) {
    return -1;
  }
}

char* kelpie_network_traffic_store_get_selected_json(KelpieNetworkTrafficStoreRef store) {
  if (store == nullptr) {
    return nullptr;
  }
  try {
    const std::string payload = store->store.GetSelectedJson();
    return payload.empty() ? nullptr : kelpie::state_c_api_internal::CopyString(payload);
  } catch (...) {
    return nullptr;
  }
}

char* kelpie_network_traffic_store_to_json(KelpieNetworkTrafficStoreRef store) {
  if (store == nullptr) {
    return nullptr;
  }
  try {
    return kelpie::state_c_api_internal::CopyString(store->store.ToJson());
  } catch (...) {
    return nullptr;
  }
}

char* kelpie_network_traffic_store_to_summary_json(KelpieNetworkTrafficStoreRef store,
                                                     const char* method,
                                                     const char* category,
                                                     const char* status_range,
                                                     const char* url_pattern) {
  if (store == nullptr) {
    return nullptr;
  }
  try {
    const auto to_optional = [](const char* value) -> std::optional<std::string> {
      if (value == nullptr || value[0] == '\0') {
        return std::nullopt;
      }
      return std::string(value);
    };
    return kelpie::state_c_api_internal::CopyString(
        store->store.ToSummaryJson(to_optional(method), to_optional(category),
                                   to_optional(status_range), to_optional(url_pattern)));
  } catch (...) {
    return nullptr;
  }
}

int32_t kelpie_network_traffic_store_count(KelpieNetworkTrafficStoreRef store) {
  if (store == nullptr) {
    return 0;
  }
  try {
    return store->store.Count();
  } catch (...) {
    return 0;
  }
}

void kelpie_network_traffic_store_load_json(KelpieNetworkTrafficStoreRef store, const char* json_text) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.LoadJson(kelpie::state_c_api_internal::SafeCString(json_text));
  } catch (...) {
  }
}

KelpieConsoleStoreRef kelpie_console_store_create(void) {
  try {
    return new KelpieConsoleStore();
  } catch (...) {
    return nullptr;
  }
}

void kelpie_console_store_destroy(KelpieConsoleStoreRef store) {
  delete store;
}

int32_t kelpie_console_store_append_json(KelpieConsoleStoreRef store, const char* entry_json) {
  if (store == nullptr) {
    return 0;
  }
  try {
    const std::optional<kelpie::ConsoleEntry> entry =
        kelpie::state_c_api_internal::ParseConsoleEntry(entry_json);
    if (!entry.has_value()) {
      return 0;
    }
    store->store.Append(*entry);
    return 1;
  } catch (...) {
    return 0;
  }
}

void kelpie_console_store_clear(KelpieConsoleStoreRef store) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.Clear();
  } catch (...) {
  }
}

char* kelpie_console_store_to_json(KelpieConsoleStoreRef store, const char* level_filter) {
  if (store == nullptr) {
    return nullptr;
  }
  try {
    if (level_filter == nullptr || level_filter[0] == '\0') {
      return kelpie::state_c_api_internal::CopyString(store->store.ToJson());
    }
    return kelpie::state_c_api_internal::CopyString(store->store.ToJson(std::string(level_filter)));
  } catch (...) {
    return nullptr;
  }
}

char* kelpie_console_store_get_errors_only(KelpieConsoleStoreRef store) {
  if (store == nullptr) {
    return nullptr;
  }
  try {
    return kelpie::state_c_api_internal::CopyString(store->store.GetErrorsOnly());
  } catch (...) {
    return nullptr;
  }
}

int32_t kelpie_console_store_count(KelpieConsoleStoreRef store) {
  if (store == nullptr) {
    return 0;
  }
  try {
    return store->store.Count();
  } catch (...) {
    return 0;
  }
}

void kelpie_console_store_load_json(KelpieConsoleStoreRef store, const char* json_text) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.LoadJson(kelpie::state_c_api_internal::SafeCString(json_text));
  } catch (...) {
  }
}

}  // extern "C"
