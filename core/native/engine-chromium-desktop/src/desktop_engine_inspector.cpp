#include "desktop_engine_impl.h"

#include "desktop_inspector_resources.h"
#include "include/cef_task.h"

namespace kelpie {
namespace {

using Tab = DesktopEngine::Impl::Tab;
using Json = nlohmann::json;

bool CanInspect(const Tab& tab) {
  return tab.browser && tab.devtools && !tab.closing && !tab.loading &&
         tab.url != "about:blank" && !tab.url.starts_with("kelpie://");
}

std::string EnterScript(const DesktopDevToolsSession::Result& capture) {
  using namespace desktop_inspector;
  std::string script;
  for (const auto phase : {kSetup, kCollect, kApply, kScene, kTree, kTools, kInput}) {
    script.append(phase).append("\n");
  }
  const auto preview = DesktopDevToolsSession::ParseScreenshotResult(capture, "png");
  if (preview.ok) {
    const auto image = "data:image/png;base64," + preview.value.at("data").get<std::string>();
    script += "window.__m3d?.setPreview(" + Json(image).dump() + ");";
  }
  script += "\n!!window.__m3d";
  return script;
}

void EvaluateInspector(Tab& tab, const std::string& script) {
  tab.inspector.pending = tab.devtools->Begin(
      tab.browser, "Runtime.evaluate", DesktopDevToolsSession::EvaluateParams(script));
}

}  // namespace

DesktopEngine::Inspector3DState DesktopEngine::Active3DInspector() const {
  if (!impl_->initialized || !CefCurrentlyOn(TID_UI)) return {};
  const auto* tab = impl_->ActiveTab();
  if (!tab) return {};
  return {CanInspect(*tab), tab->inspector.active};
}

void DesktopEngine::Toggle3DInspector() {
  if (!Active3DInspector().enabled) return;
  auto& tab = *impl_->ActiveTab();
  if (tab.inspector.pending) return;
  if (tab.inspector.active) {
    impl_->Exit3DInspector(tab);
    return;
  }
  tab.inspector.capturing = true;
  tab.inspector.pending = tab.devtools->Begin(
      tab.browser, "Page.captureScreenshot", {{"format", "png"}}, false);
}

void DesktopEngine::Impl::Exit3DInspector(Tab& tab) {
  if (tab.inspector.pending) return;
  EvaluateInspector(tab, std::string(desktop_inspector::kExit) + "\n!!window.__m3d");
}

void DesktopEngine::Impl::Update3DInspectors() {
  if (!initialized || !CefCurrentlyOn(TID_UI)) return;
  for (auto& tab : tabs) {
    auto& inspector = tab.inspector;
    if (!inspector.pending) continue;
    const auto reply = DesktopDevToolsSession::ReadCompleted(inspector.pending);
    if (!reply) continue;
    inspector.pending.reset();
    if (inspector.capturing) {
      inspector.capturing = false;
      if (&tab == ActiveTab() && CanInspect(tab)) EvaluateInspector(tab, EnterScript(*reply));
    } else {
      const auto result = DesktopDevToolsSession::ParseEvaluateResult(*reply);
      if (result.ok && result.value.is_boolean()) inspector.active = result.value.get<bool>();
    }
  }
}

}  // namespace kelpie
