#pragma once

#include <functional>
#include <string>
#include <vector>

#include "network_rows.h"
#include "panel_window.h"

#include <commctrl.h>

namespace kelpie::windows {

// The Network panel, laid out like Chrome DevTools' Network tool: Clear, a
// text filter and request-type buttons above a striped request table, and a
// summary line below it. It follows new traffic while it is open.
class NetworkInspector final : public PanelWindow {
 public:
  // `supplier` returns the network store's JSON; `clear` empties the store.
  void SetSource(std::function<std::string()> supplier, std::function<void()> clear) {
    supplier_ = std::move(supplier);
    clear_ = std::move(clear);
  }
  // Re-reads the store and redraws when it changed.
  void Refresh();

 private:
  Spec Describe() const override;
  void CreateControls() override;
  void Layout(const RECT& client) override;
  void ApplyTheme() override;
  void OnShown() override;
  bool HandlePanelMessage(UINT message, WPARAM wparam, LPARAM lparam, LRESULT* result) override;

  static LRESULT CALLBACK ButtonProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam,
                                     UINT_PTR subclass_id, DWORD_PTR reference_data);
  // Re-filters the table, keeping the request with `selected_id` selected.
  void ApplyFilter(const std::string& selected_id);
  std::string SelectedId() const;
  void Paint(HDC dc) const;
  bool DrawButton(const DRAWITEMSTRUCT& item) const;
  LRESULT CustomDrawList(NMLVCUSTOMDRAW* draw) const;
  std::wstring Summary() const;
  int ToolbarHeight() const;
  int StatusHeight() const;

  std::function<std::string()> supplier_;
  std::function<void()> clear_;
  std::string json_;
  std::vector<NetworkRow> rows_;
  std::vector<std::size_t> visible_;
  RequestType type_ = RequestType::kAll;
  HWND clear_button_ = nullptr;
  HWND filter_ = nullptr;
  std::vector<HWND> type_buttons_;
  HWND list_ = nullptr;
  HWND tooltip_ = nullptr;
  HWND hovered_ = nullptr;
  HBRUSH field_brush_ = nullptr;
  RECT filter_frame_{};
  int separator_x_ = 0;
};

}  // namespace kelpie::windows
