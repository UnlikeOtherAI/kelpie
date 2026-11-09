#include "avahi_api.h"

#include <dlfcn.h>

#include <iostream>

namespace kelpie::linuxapp::avahi {

void Log(const char* event, int code) {
  std::cerr << "kelpie sync discovery: " << event << " (" << code << ")\n";
}

namespace {

template <typename Function>
bool Bind(void* library, const char* name, Function* target) {
  *target = reinterpret_cast<Function>(dlsym(library, name));
  return *target != nullptr;
}

}  // namespace

const AvahiApi& Api() {
  static const AvahiApi api = [] {
    AvahiApi loaded;
    void* common = dlopen("libavahi-common.so.3", RTLD_NOW | RTLD_LOCAL);
    void* client = dlopen("libavahi-client.so.3", RTLD_NOW | RTLD_LOCAL);
    if (common == nullptr || client == nullptr) return loaded;
    loaded.available =
        Bind(common, "avahi_threaded_poll_new", &loaded.poll_new) &&
        Bind(common, "avahi_threaded_poll_free", &loaded.poll_free) &&
        Bind(common, "avahi_threaded_poll_get", &loaded.poll_get) &&
        Bind(common, "avahi_threaded_poll_start", &loaded.poll_start) &&
        Bind(common, "avahi_threaded_poll_stop", &loaded.poll_stop) &&
        Bind(common, "avahi_threaded_poll_lock", &loaded.poll_lock) &&
        Bind(common, "avahi_threaded_poll_unlock", &loaded.poll_unlock) &&
        Bind(common, "avahi_string_list_add", &loaded.string_list_add) &&
        Bind(common, "avahi_string_list_free", &loaded.string_list_free) &&
        Bind(common, "avahi_address_snprint", &loaded.address_snprint) &&
        Bind(common, "avahi_alternative_service_name", &loaded.alternative_service_name) &&
        Bind(common, "avahi_free", &loaded.free) &&
        Bind(client, "avahi_client_new", &loaded.client_new) &&
        Bind(client, "avahi_client_free", &loaded.client_free) &&
        Bind(client, "avahi_client_get_state", &loaded.client_get_state) &&
        Bind(client, "avahi_client_errno", &loaded.client_errno) &&
        Bind(client, "avahi_entry_group_new", &loaded.group_new) &&
        Bind(client, "avahi_entry_group_free", &loaded.group_free) &&
        Bind(client, "avahi_entry_group_commit", &loaded.group_commit) &&
        Bind(client, "avahi_entry_group_reset", &loaded.group_reset) &&
        Bind(client, "avahi_entry_group_is_empty", &loaded.group_is_empty) &&
        Bind(client, "avahi_entry_group_add_service_strlst", &loaded.group_add_service) &&
        Bind(client, "avahi_entry_group_update_service_txt_strlst", &loaded.group_update_txt) &&
        Bind(client, "avahi_service_browser_new", &loaded.browser_new) &&
        Bind(client, "avahi_service_browser_free", &loaded.browser_free) &&
        Bind(client, "avahi_service_resolver_new", &loaded.resolver_new) &&
        Bind(client, "avahi_service_resolver_free", &loaded.resolver_free);
    return loaded;
  }();
  return api;
}

bool Connected(AvahiClientState state) {
  return state == AVAHI_CLIENT_S_RUNNING || state == AVAHI_CLIENT_S_REGISTERING ||
         state == AVAHI_CLIENT_S_COLLISION;
}

std::string Source(AvahiIfIndex interface, AvahiProtocol protocol) {
  return std::to_string(interface) + "/" + std::to_string(protocol);
}

std::string AddressText(const AvahiAddress* address, AvahiIfIndex interface) {
  if (address == nullptr) return {};
  char text[AVAHI_ADDRESS_STR_MAX] = {};
  if (Api().address_snprint(text, sizeof(text), address) == nullptr) return {};
  std::string result = text;
  if (address->proto == AVAHI_PROTO_INET6) {
    const auto* bytes = address->data.ipv6.address;
    if (bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80) {
      if (interface < 0) return {};
      result += "%" + std::to_string(interface);
    }
  }
  return result;
}

std::vector<std::string> TxtEntries(AvahiStringList* list) {
  std::vector<std::string> entries;
  for (AvahiStringList* item = list; item != nullptr; item = item->next) {
    entries.emplace_back(reinterpret_cast<const char*>(item->text), item->size);
  }
  return entries;
}

AvahiStringList* TxtList(const SyncTxt& txt) {
  AvahiStringList* list = nullptr;
  for (const auto& entry : EncodeSyncTxt(txt)) list = Api().string_list_add(list, entry.c_str());
  return list;
}

}  // namespace kelpie::linuxapp::avahi
