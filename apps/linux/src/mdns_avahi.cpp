#include "mdns_avahi.h"

#if KELPIE_LINUX_HAS_AVAHI
#include <avahi-client/client.h>
#include <avahi-client/publish.h>
#include <avahi-common/error.h>
#include <avahi-common/malloc.h>
#include <avahi-common/simple-watch.h>
#endif

#include <utility>

#include "kelpie/constants.h"

namespace kelpie::linuxapp {

#if KELPIE_LINUX_HAS_AVAHI
namespace {

AvahiStringList* BuildTxtList(const MdnsServiceConfig& config) {
  AvahiStringList* list = nullptr;
  list = avahi_string_list_add_pair(list, "id", config.device.id.c_str());
  list = avahi_string_list_add_pair(list, "name", config.device.name.c_str());
  list = avahi_string_list_add_pair(list, "model", config.device.model.c_str());
  list = avahi_string_list_add_pair(list, "platform", "linux");
  list = avahi_string_list_add_pair(list, "engine", "chromium");
  list = avahi_string_list_add_pair(list, "width", std::to_string(config.width).c_str());
  list = avahi_string_list_add_pair(list, "height", std::to_string(config.height).c_str());
  list = avahi_string_list_add_pair(list, "port", std::to_string(config.port).c_str());
  list = avahi_string_list_add_pair(list, "version", config.version.c_str());
  list = avahi_string_list_add_pair(list, "runtime_mode", config.runtime_mode.c_str());
  return list;
}

}  // namespace
#endif

MdnsAvahi::MdnsAvahi() = default;

MdnsAvahi::~MdnsAvahi() {
  Stop();
}

bool MdnsAvahi::Start(const MdnsServiceConfig& config) {
  Stop();
  service_name_ = config.device.name;

#if KELPIE_LINUX_HAS_AVAHI
  running_ = true;
  thread_ = std::thread([this, config]() { Run(config); });
  return true;
#else
  last_error_ = "Avahi support not available in this build";
  return false;
#endif
}

void MdnsAvahi::Stop() {
#if KELPIE_LINUX_HAS_AVAHI
  if (simple_poll_ != nullptr) {
    avahi_simple_poll_quit(static_cast<AvahiSimplePoll*>(simple_poll_));
  }
  if (thread_.joinable()) {
    thread_.join();
  }
#endif
  running_ = false;
}

bool MdnsAvahi::IsRunning() const {
  return running_;
}

std::string MdnsAvahi::ServiceName() const {
  if (service_name_.empty()) {
    return std::string();
  }
  return service_name_ + "." + std::string(kelpie::kMdnsServiceType) + ".local";
}

std::string MdnsAvahi::LastError() const {
  return last_error_;
}

#if KELPIE_LINUX_HAS_AVAHI
void MdnsAvahi::Run(const MdnsServiceConfig& config) {
  struct State {
    MdnsAvahi* owner;
    MdnsServiceConfig config;
  } state{this, config};

  simple_poll_ = avahi_simple_poll_new();
  if (simple_poll_ == nullptr) {
    last_error_ = "Failed to create Avahi simple poll";
    running_ = false;
    return;
  }

  auto client_callback = [](AvahiClient* client, AvahiClientState state_value, void* userdata) {
    auto* state_ptr = static_cast<State*>(userdata);
    switch (state_value) {
      case AVAHI_CLIENT_S_RUNNING: {
        if (state_ptr->owner->group_ == nullptr) {
          state_ptr->owner->group_ =
              avahi_entry_group_new(client, nullptr, nullptr);
        }
        if (state_ptr->owner->group_ == nullptr) {
          state_ptr->owner->last_error_ = "Failed to create Avahi entry group";
          state_ptr->owner->running_ = false;
          break;
        }
        if (!avahi_entry_group_is_empty(static_cast<AvahiEntryGroup*>(state_ptr->owner->group_))) {
          break;
        }
        AvahiStringList* txt = BuildTxtList(state_ptr->config);
        const int result = avahi_entry_group_add_service_strlst(
            static_cast<AvahiEntryGroup*>(state_ptr->owner->group_),
            AVAHI_IF_UNSPEC,
            AVAHI_PROTO_UNSPEC,
            static_cast<AvahiPublishFlags>(0),
            state_ptr->config.device.name.c_str(),
            std::string(kelpie::kMdnsServiceType).c_str(),
            nullptr,
            nullptr,
            static_cast<std::uint16_t>(state_ptr->config.port),
            txt);
        avahi_string_list_free(txt);
        if (result < 0) {
          state_ptr->owner->last_error_ = avahi_strerror(result);
          state_ptr->owner->running_ = false;
          break;
        }
        const int commit = avahi_entry_group_commit(static_cast<AvahiEntryGroup*>(state_ptr->owner->group_));
        if (commit < 0) {
          state_ptr->owner->last_error_ = avahi_strerror(commit);
          state_ptr->owner->running_ = false;
        }
        break;
      }
      case AVAHI_CLIENT_FAILURE:
        state_ptr->owner->last_error_ = avahi_strerror(avahi_client_errno(client));
        state_ptr->owner->running_ = false;
        avahi_simple_poll_quit(static_cast<AvahiSimplePoll*>(state_ptr->owner->simple_poll_));
        break;
      case AVAHI_CLIENT_S_COLLISION:
      case AVAHI_CLIENT_S_REGISTERING:
        if (state_ptr->owner->group_ != nullptr) {
          avahi_entry_group_reset(static_cast<AvahiEntryGroup*>(state_ptr->owner->group_));
        }
        break;
      case AVAHI_CLIENT_CONNECTING:
        break;
    }
  };

  int error = 0;
  client_ = avahi_client_new(avahi_simple_poll_get(static_cast<AvahiSimplePoll*>(simple_poll_)),
                             AVAHI_CLIENT_NO_FAIL,
                             client_callback,
                             &state,
                             &error);
  if (client_ == nullptr) {
    last_error_ = avahi_strerror(error);
    running_ = false;
    avahi_simple_poll_free(static_cast<AvahiSimplePoll*>(simple_poll_));
    simple_poll_ = nullptr;
    return;
  }

  avahi_simple_poll_loop(static_cast<AvahiSimplePoll*>(simple_poll_));

  if (group_ != nullptr) {
    avahi_entry_group_free(static_cast<AvahiEntryGroup*>(group_));
    group_ = nullptr;
  }
  if (client_ != nullptr) {
    avahi_client_free(static_cast<AvahiClient*>(client_));
    client_ = nullptr;
  }
  if (simple_poll_ != nullptr) {
    avahi_simple_poll_free(static_cast<AvahiSimplePoll*>(simple_poll_));
    simple_poll_ = nullptr;
  }
}
#endif

}  // namespace kelpie::linuxapp
