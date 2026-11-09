#pragma once

#include <functional>
#include <string>
#include <vector>

#include "panel_window.h"

namespace kelpie::windows {

// One list of saved pages: Bookmarks or History. Each row opens its page, and
// the panel steps aside so the page is visible, as the macOS sheets do.
class LinkListPanel final : public PanelWindow {
 public:
  struct Column {
    const wchar_t* title;
    const char* field;  // JSON key printed in this column
    int width_dip;      // 0 = takes the width the other columns leave
  };
  struct Config {
    const wchar_t* class_name;
    const wchar_t* title;
    const wchar_t* empty_message;
    std::vector<Column> columns;  // one of them must carry "url"
  };

  static Config Bookmarks();
  static Config History();

  explicit LinkListPanel(Config config) : config_(std::move(config)) {}
  void SetNavigateCallback(std::function<void(const std::string&)> callback) {
    on_navigate_ = std::move(callback);
  }
  void UpdateFromJson(const std::string& json);

 private:
  struct Row {
    std::vector<std::wstring> cells;
    std::string url;
  };

  Spec Describe() const override;
  void CreateControls() override;
  void Layout(const RECT& client) override;
  void ApplyTheme() override;
  bool HandlePanelMessage(UINT message, WPARAM wparam, LPARAM lparam, LRESULT* result) override;
  void Populate();
  void OpenSelected();

  Config config_;
  HWND list_ = nullptr;
  std::vector<Row> rows_;
  std::function<void(const std::string&)> on_navigate_;
};

}  // namespace kelpie::windows
