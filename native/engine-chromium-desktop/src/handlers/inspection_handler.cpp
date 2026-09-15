#include "inspection_handler.h"
namespace kelpie {
void InspectionHandler::Register(DesktopRouter& router) const {
  router.Register("find-element", [this](const nlohmann::json& p) { return Find(p, "*", "element"); });
  router.Register("find-button", [this](const nlohmann::json& p) { return Find(p, "button,[role=button]", "button"); });
  router.Register("find-link", [this](const nlohmann::json& p) { return Find(p, "a,[role=link]", "link"); });
  router.Register("find-input", [this](const nlohmann::json& p) { return Find(p, "input,textarea,select,[contenteditable=true]", "input"); });
  router.Register("get-page-text", [this](const nlohmann::json& p) { return Evaluate(p, "(() => ({text:(document.body&&document.body.innerText)||'', length:((document.body&&document.body.innerText)||'').length}))()"); });
  router.Register("get-visible-elements", [this](const nlohmann::json& p) { return Evaluate(p, "(() => {const e=Array.from(document.querySelectorAll('*')).filter(n=>{const r=n.getBoundingClientRect();return !!(r.width&&r.height)}).map(n=>({tag:n.tagName.toLowerCase(),text:(n.innerText||'').trim(),selector:n.id?'#'+CSS.escape(n.id):n.tagName.toLowerCase()}).slice(0,200);return {elements:e,count:e.length};})()"); });
  router.Register("get-form-state", [this](const nlohmann::json& p) { return Evaluate(p, "(() => ({fields:Array.from(document.querySelectorAll('input,textarea,select')).map(e=>({name:e.name||'',id:e.id||'',type:e.type||e.tagName.toLowerCase(),value:e.value,checked:!!e.checked})),count:document.querySelectorAll('input,textarea,select').length}))()"); });
  router.Register("get-accessibility-tree", [this](const nlohmann::json& p) { return Evaluate(p, "(() => {const nodes=Array.from(document.querySelectorAll('body *')).slice(0,500).map(e=>({role:e.getAttribute('role')||e.tagName.toLowerCase(),name:e.getAttribute('aria-label')||(e.innerText||'').trim(),hidden:e.getAttribute('aria-hidden')==='true'}));return {nodes,count:nodes.length};})()"); });
}
nlohmann::json InspectionHandler::Find(const nlohmann::json& params, const char* selector, const char* label) const {
  try {
    const std::string text = RequireString(params, "text");
    const std::string script = "(() => {const text=" + JsStringLiteral(text) + ";const nodes=Array.from(document.querySelectorAll(" + JsStringLiteral(selector) + "));const e=nodes.find(n=>((n.innerText||n.value||'').includes(text)));return e?{found:true,tag:e.tagName.toLowerCase(),text:(e.innerText||e.value||'').trim()}: {found:false};})()";
    nlohmann::json value; const auto result = EvaluateForTab(runtime_, params, script, &value);
    return result.ok ? SuccessResponse({{"kind", label}, {"result", value}}) : ControlError(result);
  } catch (const std::invalid_argument& e) { return InvalidParams(e.what()); }
}
nlohmann::json InspectionHandler::Evaluate(const nlohmann::json& params, const std::string& script) const {
  try { nlohmann::json value; const auto result = EvaluateForTab(runtime_, params, script, &value); return result.ok ? SuccessResponse(value) : ControlError(result); }
  catch (const std::invalid_argument& e) { return InvalidParams(e.what()); }
}
}  // namespace kelpie
