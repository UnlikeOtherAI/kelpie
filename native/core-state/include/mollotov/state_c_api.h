#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MollotovBookmarkStore* MollotovBookmarkStoreRef;
typedef struct MollotovHistoryStore* MollotovHistoryStoreRef;
typedef struct MollotovNetworkTrafficStore* MollotovNetworkTrafficStoreRef;
typedef struct MollotovConsoleStore* MollotovConsoleStoreRef;

void mollotov_free_string(char* str);

MollotovBookmarkStoreRef mollotov_bookmark_store_create(void);
void mollotov_bookmark_store_destroy(MollotovBookmarkStoreRef store);
void mollotov_bookmark_store_add(MollotovBookmarkStoreRef store, const char* title, const char* url);
void mollotov_bookmark_store_remove(MollotovBookmarkStoreRef store, const char* id);
void mollotov_bookmark_store_remove_all(MollotovBookmarkStoreRef store);
char* mollotov_bookmark_store_to_json(MollotovBookmarkStoreRef store);
int32_t mollotov_bookmark_store_count(MollotovBookmarkStoreRef store);
void mollotov_bookmark_store_load_json(MollotovBookmarkStoreRef store, const char* json);

MollotovHistoryStoreRef mollotov_history_store_create(void);
void mollotov_history_store_destroy(MollotovHistoryStoreRef store);
void mollotov_history_store_record(MollotovHistoryStoreRef store, const char* url, const char* title);
void mollotov_history_store_clear(MollotovHistoryStoreRef store);
void mollotov_history_store_update_latest_title(MollotovHistoryStoreRef store,
                                                const char* url,
                                                const char* title);
char* mollotov_history_store_to_json(MollotovHistoryStoreRef store);
int32_t mollotov_history_store_count(MollotovHistoryStoreRef store);
void mollotov_history_store_load_json(MollotovHistoryStoreRef store, const char* json);

MollotovNetworkTrafficStoreRef mollotov_network_traffic_store_create(void);
void mollotov_network_traffic_store_destroy(MollotovNetworkTrafficStoreRef store);
int32_t mollotov_network_traffic_store_append_json(MollotovNetworkTrafficStoreRef store,
                                                   const char* entry_json);
void mollotov_network_traffic_store_append_document_navigation(
    MollotovNetworkTrafficStoreRef store,
    const char* url,
    int32_t status_code,
    const char* content_type,
    const char* response_headers_json,
    int64_t size,
    const char* start_time,
    int32_t duration);
void mollotov_network_traffic_store_clear(MollotovNetworkTrafficStoreRef store);
int32_t mollotov_network_traffic_store_select(MollotovNetworkTrafficStoreRef store, int32_t index);
int32_t mollotov_network_traffic_store_selected_index(MollotovNetworkTrafficStoreRef store);
char* mollotov_network_traffic_store_get_selected_json(MollotovNetworkTrafficStoreRef store);
char* mollotov_network_traffic_store_to_json(MollotovNetworkTrafficStoreRef store);
char* mollotov_network_traffic_store_to_summary_json(MollotovNetworkTrafficStoreRef store,
                                                     const char* method,
                                                     const char* category,
                                                     const char* status_range,
                                                     const char* url_pattern);
int32_t mollotov_network_traffic_store_count(MollotovNetworkTrafficStoreRef store);
void mollotov_network_traffic_store_load_json(MollotovNetworkTrafficStoreRef store, const char* json);

MollotovConsoleStoreRef mollotov_console_store_create(void);
void mollotov_console_store_destroy(MollotovConsoleStoreRef store);
int32_t mollotov_console_store_append_json(MollotovConsoleStoreRef store, const char* entry_json);
void mollotov_console_store_clear(MollotovConsoleStoreRef store);
char* mollotov_console_store_to_json(MollotovConsoleStoreRef store, const char* level_filter);
char* mollotov_console_store_get_errors_only(MollotovConsoleStoreRef store);
int32_t mollotov_console_store_count(MollotovConsoleStoreRef store);
void mollotov_console_store_load_json(MollotovConsoleStoreRef store, const char* json);

#ifdef __cplusplus
}
#endif
