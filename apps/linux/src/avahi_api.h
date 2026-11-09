#pragma once

// libavahi-client and libavahi-common loaded with dlopen, plus the small
// conversions cookie-sync discovery needs. Only the functions are resolved at
// runtime; types and constants come from the Avahi headers, whose ABI
// (soname .3) has been stable since 2006.

#include <avahi-client/client.h>
#include <avahi-client/lookup.h>
#include <avahi-client/publish.h>
#include <avahi-common/address.h>
#include <avahi-common/alternative.h>
#include <avahi-common/error.h>
#include <avahi-common/malloc.h>
#include <avahi-common/strlst.h>
#include <avahi-common/thread-watch.h>

#include <string>
#include <vector>

#include "kelpie/sync_peer_events.h"

namespace kelpie::linuxapp::avahi {

// Only the functions are resolved at runtime; the types and constants come
// from the Avahi headers, whose ABI (soname .3) has been stable since 2006.
struct AvahiApi {
  decltype(&avahi_threaded_poll_new) poll_new = nullptr;
  decltype(&avahi_threaded_poll_free) poll_free = nullptr;
  decltype(&avahi_threaded_poll_get) poll_get = nullptr;
  decltype(&avahi_threaded_poll_start) poll_start = nullptr;
  decltype(&avahi_threaded_poll_stop) poll_stop = nullptr;
  decltype(&avahi_threaded_poll_lock) poll_lock = nullptr;
  decltype(&avahi_threaded_poll_unlock) poll_unlock = nullptr;
  decltype(&avahi_string_list_add) string_list_add = nullptr;
  decltype(&avahi_string_list_free) string_list_free = nullptr;
  decltype(&avahi_address_snprint) address_snprint = nullptr;
  decltype(&avahi_alternative_service_name) alternative_service_name = nullptr;
  decltype(&avahi_free) free = nullptr;
  decltype(&avahi_client_new) client_new = nullptr;
  decltype(&avahi_client_free) client_free = nullptr;
  decltype(&avahi_client_get_state) client_get_state = nullptr;
  decltype(&avahi_client_errno) client_errno = nullptr;
  decltype(&avahi_entry_group_new) group_new = nullptr;
  decltype(&avahi_entry_group_free) group_free = nullptr;
  decltype(&avahi_entry_group_commit) group_commit = nullptr;
  decltype(&avahi_entry_group_reset) group_reset = nullptr;
  decltype(&avahi_entry_group_is_empty) group_is_empty = nullptr;
  decltype(&avahi_entry_group_add_service_strlst) group_add_service = nullptr;
  decltype(&avahi_entry_group_update_service_txt_strlst) group_update_txt = nullptr;
  decltype(&avahi_service_browser_new) browser_new = nullptr;
  decltype(&avahi_service_browser_free) browser_free = nullptr;
  decltype(&avahi_service_resolver_new) resolver_new = nullptr;
  decltype(&avahi_service_resolver_free) resolver_free = nullptr;
  bool available = false;
};

// Loaded once and never unloaded; `available` is false when either library
// or any function is missing.
const AvahiApi& Api();

// Codes only: names, TXT values and addresses never reach the log.
void Log(const char* event, int code);

bool Connected(AvahiClientState state);
// One browse result source: interface and protocol.
std::string Source(AvahiIfIndex interface, AvahiProtocol protocol);
// Link-local IPv6 carries its interface as a numeric scope, as on Windows.
std::string AddressText(const AvahiAddress* address, AvahiIfIndex interface);
std::vector<std::string> TxtEntries(AvahiStringList* list);
// Caller frees with Api().string_list_free.
AvahiStringList* TxtList(const SyncTxt& txt);

}  // namespace kelpie::linuxapp::avahi
