#pragma once

#include "kelpie/types.h"

namespace kelpie {

class DesktopMdns {
 public:
  using TxtRecord = StringMap;

  virtual ~DesktopMdns() = default;

  virtual bool Start(int port, const TxtRecord& txt_record) = 0;
  virtual void Stop() = 0;
  virtual void UpdateTxtRecord(const TxtRecord& txt_record) = 0;
};

}  // namespace kelpie
