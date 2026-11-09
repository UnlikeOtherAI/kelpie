#include "release_updates.h"
#if KELPIE_LINUX_HAS_GTK
#include "linux_app.h"
#include "update_dialogs.h"
#include "../../updates/release_monitor.h"
#include <curl/curl.h>
#include <cstdlib>
#include <sys/wait.h>
#include <unistd.h>

namespace kelpie::linuxapp {
namespace {
std::string Fetch() {
  static const auto initialized = curl_global_init(CURL_GLOBAL_DEFAULT);
  if (initialized != CURLE_OK) throw std::runtime_error("No TLS transport");
  std::unique_ptr<CURL, decltype(&curl_easy_cleanup)> curl(curl_easy_init(), curl_easy_cleanup);
  if (!curl) throw std::runtime_error("No TLS transport");
  std::string body;
  curl_easy_setopt(curl.get(), CURLOPT_URL, updates::kFeedURL);
  curl_easy_setopt(curl.get(), CURLOPT_USERAGENT, "Kelpie-update-check");
  curl_easy_setopt(curl.get(), CURLOPT_TIMEOUT, 15L);
  curl_easy_setopt(curl.get(), CURLOPT_CONNECTTIMEOUT, 5L);
  curl_easy_setopt(curl.get(), CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(curl.get(), CURLOPT_WRITEDATA, &body);
  curl_easy_setopt(curl.get(), CURLOPT_WRITEFUNCTION, +[](char* data, size_t size, size_t count, void* raw)->size_t {
    auto& output = *static_cast<std::string*>(raw);
    if (output.size() + size * count > 8 * 1024 * 1024) return 0;
    output.append(data, size * count); return size * count;
  });
  if (curl_easy_perform(curl.get()) != CURLE_OK) throw std::runtime_error("Update check failed");
  long status = 0; curl_easy_getinfo(curl.get(), CURLINFO_RESPONSE_CODE, &status);
  if (status != 200) throw std::runtime_error("Update check failed");
  return body;
}
std::filesystem::path Executable() { return std::filesystem::read_symlink("/proc/self/exe"); }
std::string Format() {
  if (const auto* image = std::getenv("APPIMAGE"); image && *image) return "appimage";
  if (Executable().parent_path() == "/opt/kelpie") {
    if (std::filesystem::exists("/var/lib/dpkg/info/kelpie.list")) return "deb";
    return "rpm";
  }
  return "tar";
}
std::vector<std::string> RestartArguments() {
  std::ifstream input("/proc/self/cmdline"); std::vector<std::string> args; std::string arg;
  std::getline(input, arg, '\0');
  while (std::getline(input, arg, '\0')) args.push_back(arg);
  return args;
}
}
struct StandaloneUpdates::Impl {
  LinuxApp& app; GtkWindow* window;
  std::string format = Format();
  updates::ReleaseMonitor monitor;
  std::filesystem::path operation;
  GPid helper = 0;
  GtkWidget* progress = nullptr;

  Impl(LinuxApp& browser, GtkWindow* owner) : app(browser), window(owner),
      monitor("linux-x64-" + format, KELPIE_LINUX_VERSION,
              std::filesystem::path(app.config().profile_dir) / "updates-skipped.json", Fetch) {}
  ~Impl() { if (helper) g_spawn_close_pid(helper); if (progress) gtk_widget_destroy(progress); }
  void Error(const char* message) {
    auto* dialog = gtk_message_dialog_new(window, GTK_DIALOG_DESTROY_WITH_PARENT,
        GTK_MESSAGE_ERROR, GTK_BUTTONS_CLOSE, "%s", message);
    g_signal_connect_swapped(dialog, "response", G_CALLBACK(gtk_widget_destroy), dialog);
    gtk_widget_show(dialog);
  }
  void Install(const updates::Release& release) {
    try {
      char* directory = g_dir_make_tmp("kelpie-update-XXXXXX", nullptr);
      if (!directory) throw std::runtime_error("No update directory");
      operation = directory; g_free(directory);
      const auto script = operation / "install.sh";
      std::filesystem::copy_file(Executable().parent_path() / "install-update.sh", script);
      const auto* image = std::getenv("APPIMAGE");
      const std::string install_path = format == "appimage" ? image : Executable().string();
      std::vector<std::string> values{"/bin/bash", script.string(), operation.string(), std::to_string(getpid()),
        release.url, release.sha256, release.version, install_path, format, app.config().profile_dir};
      for (auto& arg : RestartArguments()) values.push_back(arg);
      std::vector<char*> args; for (auto& value : values) args.push_back(value.data()); args.push_back(nullptr);
      if (!g_spawn_async(nullptr, args.data(), nullptr, G_SPAWN_DO_NOT_REAP_CHILD, nullptr, nullptr, &helper, nullptr))
        throw std::runtime_error("The updater could not start");
      progress = updates_ui::Progress(window);
      g_object_add_weak_pointer(G_OBJECT(progress), reinterpret_cast<gpointer*>(&progress));
      gtk_widget_show(progress);
    } catch (...) { Error("The updater could not start. Your installation is unchanged. Try again after restarting Kelpie."); }
  }
  void Tick() {
    if (helper) {
      std::ifstream input(operation / "status"); std::string status; std::getline(input, status);
      if (status == "ready") { app.RequestShutdown(); return; }
      int result = 0;
      if (waitpid(helper, &result, WNOHANG) == helper) {
        g_spawn_close_pid(helper); helper = 0;
        if (progress) { gtk_widget_destroy(progress); progress = nullptr; }
        Error("The update could not be downloaded or verified. Your installation is unchanged. Try again after restarting Kelpie.");
      }
      return;
    }
    if (!gtk_window_is_active(window)) return;
    const auto release = monitor.Tick();
    if (!release) return;
    auto* dialog = updates_ui::Prompt(window, release->version.c_str());
    struct Choice { Impl* self; updates::Release release; };
    auto* choice = new Choice{this, *release};
    g_signal_connect_data(dialog, "response", G_CALLBACK(+[](GtkDialog* dialog, int response, gpointer raw) {
      auto& value = *static_cast<Choice*>(raw);
      if (response == 100) value.self->Install(value.release);
      if (response == 101 && !value.self->monitor.Skip(value.release))
        value.self->Error("Kelpie could not save Skip version. Please try again after restarting the app.");
      gtk_widget_destroy(GTK_WIDGET(dialog));
    }), choice, +[](gpointer raw, GClosure*) { delete static_cast<Choice*>(raw); }, static_cast<GConnectFlags>(0));
    gtk_widget_show(dialog);
  }
};
StandaloneUpdates::StandaloneUpdates(LinuxApp& app, GtkWindow* window) : impl_(std::make_unique<Impl>(app, window)) {}
StandaloneUpdates::~StandaloneUpdates() = default;
void StandaloneUpdates::Tick() { impl_->Tick(); }
}
#endif
