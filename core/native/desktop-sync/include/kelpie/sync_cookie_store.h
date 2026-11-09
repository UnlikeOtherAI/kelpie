#pragma once

#include <functional>

#include <nlohmann/json.hpp>

namespace kelpie {

// The browser's default (unpartitioned) cookie store as cookie sync sees it.
// Implemented by the Chromium desktop engine over the global CefCookieManager;
// tests use fakes. Partitioned stores are never visible here.
//
// Snapshot and Apply block and are called from sync worker threads, never from
// the browser UI thread. They return early, reporting failure, once
// `cancelled` returns true.
class SyncCookieStore {
 public:
  using Cancelled = std::function<bool()>;

  virtual ~SyncCookieStore() = default;

  // Every cookie in the store in the core-sync wire shape
  // {domain,path,name,value,expires,secure,httpOnly,sameSite} and its coverage:
  // {"all":true} only for a complete enumeration. Returns false when the store
  // could not be read; a failed read is never an empty success.
  virtual bool Snapshot(nlohmann::json* cookies, nlohmann::json* coverage, const Cancelled& cancelled) = 0;

  // Applies core-sync planned ops [{id, op:"set"|"delete", cookie}] and returns
  // one {id, ok, readback} per op. `readback` holds every cookie in the store
  // with the op's name whose domain, with or without a leading dot, equals the
  // op's domain without its dot, read after the op was applied. A failed
  // read-back is ok:false with whatever the engine still holds; it is never
  // an invented empty result.
  virtual nlohmann::json Apply(const nlohmann::json& ops, const Cancelled& cancelled) = 0;

  // `listener` runs (on any thread, without blocking) whenever the store may
  // have changed. nullptr removes it. Implementations must not call a removed
  // listener after this returns.
  virtual void SetChangeListener(std::function<void()> listener) = 0;
};

}  // namespace kelpie
