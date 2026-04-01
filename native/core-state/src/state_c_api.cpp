#include "mollotov/state_c_api.h"

#include <optional>
#include <string>

#include "state_c_api_internal.h"

extern "C" {

void mollotov_free_string(char* str) {
  delete[] str;
}

MollotovBookmarkStoreRef mollotov_bookmark_store_create(void) {
  try {
    return new MollotovBookmarkStore();
  } catch (...) {
    return nullptr;
  }
}

void mollotov_bookmark_store_destroy(MollotovBookmarkStoreRef store) {
  delete store;
}

void mollotov_bookmark_store_add(MollotovBookmarkStoreRef store, const char* title, const char* url) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.Add(mollotov::state_c_api_internal::SafeCString(title),
                     mollotov::state_c_api_internal::SafeCString(url));
  } catch (...) {
  }
}

void mollotov_bookmark_store_remove(MollotovBookmarkStoreRef store, const char* id) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.Remove(mollotov::state_c_api_internal::SafeCString(id));
  } catch (...) {
  }
}

void mollotov_bookmark_store_remove_all(MollotovBookmarkStoreRef store) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.RemoveAll();
  } catch (...) {
  }
}

char* mollotov_bookmark_store_to_json(MollotovBookmarkStoreRef store) {
  if (store == nullptr) {
    return nullptr;
  }
  try {
    return mollotov::state_c_api_internal::CopyString(store->store.ToJson());
  } catch (...) {
    return nullptr;
  }
}

int32_t mollotov_bookmark_store_count(MollotovBookmarkStoreRef store) {
  if (store == nullptr) {
    return 0;
  }
  try {
    return store->store.Count();
  } catch (...) {
    return 0;
  }
}

void mollotov_bookmark_store_load_json(MollotovBookmarkStoreRef store, const char* json_text) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.LoadJson(mollotov::state_c_api_internal::SafeCString(json_text));
  } catch (...) {
  }
}

MollotovHistoryStoreRef mollotov_history_store_create(void) {
  try {
    return new MollotovHistoryStore();
  } catch (...) {
    return nullptr;
  }
}

void mollotov_history_store_destroy(MollotovHistoryStoreRef store) {
  delete store;
}

void mollotov_history_store_record(MollotovHistoryStoreRef store, const char* url, const char* title) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.Record(mollotov::state_c_api_internal::SafeCString(url),
                        mollotov::state_c_api_internal::SafeCString(title));
  } catch (...) {
  }
}

void mollotov_history_store_clear(MollotovHistoryStoreRef store) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.Clear();
  } catch (...) {
  }
}

void mollotov_history_store_update_latest_title(MollotovHistoryStoreRef store,
                                                const char* url,
                                                const char* title) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.UpdateLatestTitle(mollotov::state_c_api_internal::SafeCString(url),
                                   mollotov::state_c_api_internal::SafeCString(title));
  } catch (...) {
  }
}

char* mollotov_history_store_to_json(MollotovHistoryStoreRef store) {
  if (store == nullptr) {
    return nullptr;
  }
  try {
    return mollotov::state_c_api_internal::CopyString(store->store.ToJson());
  } catch (...) {
    return nullptr;
  }
}

int32_t mollotov_history_store_count(MollotovHistoryStoreRef store) {
  if (store == nullptr) {
    return 0;
  }
  try {
    return store->store.Count();
  } catch (...) {
    return 0;
  }
}

void mollotov_history_store_load_json(MollotovHistoryStoreRef store, const char* json_text) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.LoadJson(mollotov::state_c_api_internal::SafeCString(json_text));
  } catch (...) {
  }
}

MollotovNetworkTrafficStoreRef mollotov_network_traffic_store_create(void) {
  try {
    return new MollotovNetworkTrafficStore();
  } catch (...) {
    return nullptr;
  }
}

void mollotov_network_traffic_store_destroy(MollotovNetworkTrafficStoreRef store) {
  delete store;
}

int32_t mollotov_network_traffic_store_append_json(MollotovNetworkTrafficStoreRef store,
                                                   const char* entry_json) {
  if (store == nullptr) {
    return 0;
  }
  try {
    const std::optional<mollotov::TrafficEntry> entry =
        mollotov::state_c_api_internal::ParseTrafficEntry(entry_json);
    if (!entry.has_value()) {
      return 0;
    }
    store->store.Append(*entry);
    return 1;
  } catch (...) {
    return 0;
  }
}

void mollotov_network_traffic_store_append_document_navigation(
    MollotovNetworkTrafficStoreRef store,
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
        mollotov::state_c_api_internal::SafeCString(url), status_code,
        mollotov::state_c_api_internal::SafeCString(content_type),
        mollotov::state_c_api_internal::ParseHeadersJson(response_headers_json), size,
        mollotov::state_c_api_internal::SafeCString(start_time), duration);
  } catch (...) {
  }
}

void mollotov_network_traffic_store_clear(MollotovNetworkTrafficStoreRef store) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.Clear();
  } catch (...) {
  }
}

int32_t mollotov_network_traffic_store_select(MollotovNetworkTrafficStoreRef store, int32_t index) {
  if (store == nullptr || index < 0) {
    return 0;
  }
  try {
    return store->store.Select(static_cast<std::size_t>(index)) ? 1 : 0;
  } catch (...) {
    return 0;
  }
}

int32_t mollotov_network_traffic_store_selected_index(MollotovNetworkTrafficStoreRef store) {
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

char* mollotov_network_traffic_store_get_selected_json(MollotovNetworkTrafficStoreRef store) {
  if (store == nullptr) {
    return nullptr;
  }
  try {
    const std::string payload = store->store.GetSelectedJson();
    return payload.empty() ? nullptr : mollotov::state_c_api_internal::CopyString(payload);
  } catch (...) {
    return nullptr;
  }
}

char* mollotov_network_traffic_store_to_json(MollotovNetworkTrafficStoreRef store) {
  if (store == nullptr) {
    return nullptr;
  }
  try {
    return mollotov::state_c_api_internal::CopyString(store->store.ToJson());
  } catch (...) {
    return nullptr;
  }
}

char* mollotov_network_traffic_store_to_summary_json(MollotovNetworkTrafficStoreRef store,
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
    return mollotov::state_c_api_internal::CopyString(
        store->store.ToSummaryJson(to_optional(method), to_optional(category),
                                   to_optional(status_range), to_optional(url_pattern)));
  } catch (...) {
    return nullptr;
  }
}

int32_t mollotov_network_traffic_store_count(MollotovNetworkTrafficStoreRef store) {
  if (store == nullptr) {
    return 0;
  }
  try {
    return store->store.Count();
  } catch (...) {
    return 0;
  }
}

void mollotov_network_traffic_store_load_json(MollotovNetworkTrafficStoreRef store, const char* json_text) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.LoadJson(mollotov::state_c_api_internal::SafeCString(json_text));
  } catch (...) {
  }
}

MollotovConsoleStoreRef mollotov_console_store_create(void) {
  try {
    return new MollotovConsoleStore();
  } catch (...) {
    return nullptr;
  }
}

void mollotov_console_store_destroy(MollotovConsoleStoreRef store) {
  delete store;
}

int32_t mollotov_console_store_append_json(MollotovConsoleStoreRef store, const char* entry_json) {
  if (store == nullptr) {
    return 0;
  }
  try {
    const std::optional<mollotov::ConsoleEntry> entry =
        mollotov::state_c_api_internal::ParseConsoleEntry(entry_json);
    if (!entry.has_value()) {
      return 0;
    }
    store->store.Append(*entry);
    return 1;
  } catch (...) {
    return 0;
  }
}

void mollotov_console_store_clear(MollotovConsoleStoreRef store) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.Clear();
  } catch (...) {
  }
}

char* mollotov_console_store_to_json(MollotovConsoleStoreRef store, const char* level_filter) {
  if (store == nullptr) {
    return nullptr;
  }
  try {
    if (level_filter == nullptr || level_filter[0] == '\0') {
      return mollotov::state_c_api_internal::CopyString(store->store.ToJson());
    }
    return mollotov::state_c_api_internal::CopyString(store->store.ToJson(std::string(level_filter)));
  } catch (...) {
    return nullptr;
  }
}

char* mollotov_console_store_get_errors_only(MollotovConsoleStoreRef store) {
  if (store == nullptr) {
    return nullptr;
  }
  try {
    return mollotov::state_c_api_internal::CopyString(store->store.GetErrorsOnly());
  } catch (...) {
    return nullptr;
  }
}

int32_t mollotov_console_store_count(MollotovConsoleStoreRef store) {
  if (store == nullptr) {
    return 0;
  }
  try {
    return store->store.Count();
  } catch (...) {
    return 0;
  }
}

void mollotov_console_store_load_json(MollotovConsoleStoreRef store, const char* json_text) {
  if (store == nullptr) {
    return;
  }
  try {
    store->store.LoadJson(mollotov::state_c_api_internal::SafeCString(json_text));
  } catch (...) {
  }
}

}  // extern "C"
