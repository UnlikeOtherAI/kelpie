#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KelpieBookmarkStore* KelpieBookmarkStoreRef;
typedef struct KelpieHistoryStore* KelpieHistoryStoreRef;
typedef struct KelpieNetworkTrafficStore* KelpieNetworkTrafficStoreRef;
typedef struct KelpieConsoleStore* KelpieConsoleStoreRef;

void kelpie_free_string(char* str);

KelpieBookmarkStoreRef kelpie_bookmark_store_create(void);
void kelpie_bookmark_store_destroy(KelpieBookmarkStoreRef store);
void kelpie_bookmark_store_add(KelpieBookmarkStoreRef store, const char* title, const char* url);
void kelpie_bookmark_store_remove(KelpieBookmarkStoreRef store, const char* id);
void kelpie_bookmark_store_remove_all(KelpieBookmarkStoreRef store);
char* kelpie_bookmark_store_to_json(KelpieBookmarkStoreRef store);
int32_t kelpie_bookmark_store_count(KelpieBookmarkStoreRef store);
void kelpie_bookmark_store_load_json(KelpieBookmarkStoreRef store, const char* json);

KelpieHistoryStoreRef kelpie_history_store_create(void);
void kelpie_history_store_destroy(KelpieHistoryStoreRef store);
void kelpie_history_store_record(KelpieHistoryStoreRef store, const char* url, const char* title);
void kelpie_history_store_clear(KelpieHistoryStoreRef store);
int32_t kelpie_history_store_remove_by_id(KelpieHistoryStoreRef store, const char* id);
void kelpie_history_store_update_latest_title(KelpieHistoryStoreRef store,
                                                const char* url,
                                                const char* title);
char* kelpie_history_store_to_json(KelpieHistoryStoreRef store);
int32_t kelpie_history_store_count(KelpieHistoryStoreRef store);
void kelpie_history_store_load_json(KelpieHistoryStoreRef store, const char* json);

KelpieNetworkTrafficStoreRef kelpie_network_traffic_store_create(void);
void kelpie_network_traffic_store_destroy(KelpieNetworkTrafficStoreRef store);
int32_t kelpie_network_traffic_store_append_json(KelpieNetworkTrafficStoreRef store,
                                                   const char* entry_json);
void kelpie_network_traffic_store_append_document_navigation(
    KelpieNetworkTrafficStoreRef store,
    const char* url,
    int32_t status_code,
    const char* content_type,
    const char* response_headers_json,
    int64_t size,
    const char* start_time,
    int32_t duration);
void kelpie_network_traffic_store_clear(KelpieNetworkTrafficStoreRef store);
int32_t kelpie_network_traffic_store_select(KelpieNetworkTrafficStoreRef store, int32_t index);
int32_t kelpie_network_traffic_store_selected_index(KelpieNetworkTrafficStoreRef store);
char* kelpie_network_traffic_store_get_selected_json(KelpieNetworkTrafficStoreRef store);
char* kelpie_network_traffic_store_to_json(KelpieNetworkTrafficStoreRef store);
char* kelpie_network_traffic_store_to_summary_json(KelpieNetworkTrafficStoreRef store,
                                                     const char* method,
                                                     const char* category,
                                                     const char* status_range,
                                                     const char* url_pattern);
int32_t kelpie_network_traffic_store_count(KelpieNetworkTrafficStoreRef store);
void kelpie_network_traffic_store_load_json(KelpieNetworkTrafficStoreRef store, const char* json);

KelpieConsoleStoreRef kelpie_console_store_create(void);
void kelpie_console_store_destroy(KelpieConsoleStoreRef store);
int32_t kelpie_console_store_append_json(KelpieConsoleStoreRef store, const char* entry_json);
void kelpie_console_store_clear(KelpieConsoleStoreRef store);
char* kelpie_console_store_to_json(KelpieConsoleStoreRef store, const char* level_filter);
char* kelpie_console_store_get_errors_only(KelpieConsoleStoreRef store);
int32_t kelpie_console_store_count(KelpieConsoleStoreRef store);
void kelpie_console_store_load_json(KelpieConsoleStoreRef store, const char* json);

#ifdef __cplusplus
}
#endif
