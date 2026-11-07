#pragma once
#include <chrono>
#include <memory>
#include <optional>
#include <string>
namespace kelpie::connect {
class Transport {
 public:
  virtual ~Transport()=default;
  virtual void Open()=0; // Exact TLS gateway; credentials travel only in hello/auth.
  virtual void Send(const std::string& frame)=0;
  virtual std::optional<std::string> Receive(std::chrono::milliseconds wait)=0;
  virtual void Close()=0;
};
std::unique_ptr<Transport> MakeTransport();
}
