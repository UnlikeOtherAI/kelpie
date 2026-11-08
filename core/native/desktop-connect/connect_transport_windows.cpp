#include "connect_transport.h"
#include <windows.h>
#include <winhttp.h>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <stdexcept>
#include <thread>
namespace kelpie::connect {
namespace {
class WindowsTransport final:public Transport {
 public:
  ~WindowsTransport() override { Close(); }
  void Open() override {
    Close(); failed_=false;
    session_=WinHttpOpen(L"Kelpie/1",WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,nullptr,nullptr,0);
    if (!session_) throw std::runtime_error("Gateway unavailable");
    WinHttpSetTimeouts(session_,5000,5000,5000,5000);
    connection_=WinHttpConnect(session_,L"api.nessie.works",443,0);
    auto request=WinHttpOpenRequest(connection_,L"GET",L"/api/kelpie/connect",nullptr,
        WINHTTP_NO_REFERER,WINHTTP_DEFAULT_ACCEPT_TYPES,WINHTTP_FLAG_SECURE);
    DWORD redirects=WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
    const bool ready=request && WinHttpSetOption(request,WINHTTP_OPTION_REDIRECT_POLICY,&redirects,sizeof(redirects)) &&
        WinHttpSetOption(request,WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET,nullptr,0) &&
        WinHttpSendRequest(request,WINHTTP_NO_ADDITIONAL_HEADERS,0,nullptr,0,0,0) && WinHttpReceiveResponse(request,nullptr);
    DWORD status=0,size=sizeof(status);
    if (ready) WinHttpQueryHeaders(request,WINHTTP_QUERY_STATUS_CODE|WINHTTP_QUERY_FLAG_NUMBER,nullptr,&status,&size,nullptr);
    if (status==101) socket_=WinHttpWebSocketCompleteUpgrade(request,0);
    if (request) WinHttpCloseHandle(request);
    if (!socket_) { Close(); throw std::runtime_error("Gateway unavailable"); }
    const auto socket=socket_;
    reader_=std::thread([this,socket] {
      char bytes[16384]; std::string text;
      for (;;) {
        DWORD count=0; WINHTTP_WEB_SOCKET_BUFFER_TYPE type;
        const auto error=WinHttpWebSocketReceive(socket,bytes,sizeof(bytes),&count,&type);
        if (error || type==WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE ||
            (type!=WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE && type!=WINHTTP_WEB_SOCKET_UTF8_FRAGMENT_BUFFER_TYPE)) break;
        text.append(bytes,count);
        if (text.size()>1024*1024) break;
        if (type==WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE) {
          std::lock_guard lock(mutex_);
          if (frames_.size()>=16) break;
          frames_.push_back(std::move(text)); text.clear(); changed_.notify_all();
        }
      }
      std::lock_guard lock(mutex_); failed_=true; changed_.notify_all();
    });
  }
  void Send(const std::string& frame) override {
    if (frame.size()>1024*1024 || !socket_ || WinHttpWebSocketSend(socket_,WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE,
        const_cast<char*>(frame.data()),static_cast<DWORD>(frame.size()))) throw std::runtime_error("Gateway disconnected");
  }
  std::optional<std::string> Receive(std::chrono::milliseconds wait) override {
    std::unique_lock lock(mutex_); changed_.wait_for(lock,wait,[this] { return failed_ || !frames_.empty(); });
    if (!frames_.empty()) { auto result=std::move(frames_.front()); frames_.pop_front(); return result; }
    if (failed_) throw std::runtime_error("Gateway disconnected");
    return std::nullopt;
  }
  void Close() override {
    if (socket_) { WinHttpCloseHandle(socket_); socket_=nullptr; }
    if (reader_.joinable()) reader_.join();
    if (connection_) { WinHttpCloseHandle(connection_); connection_=nullptr; }
    if (session_) { WinHttpCloseHandle(session_); session_=nullptr; }
    std::lock_guard lock(mutex_); frames_.clear();
  }
 private:
  HINTERNET session_=nullptr,connection_=nullptr,socket_=nullptr;
  std::thread reader_; std::mutex mutex_; std::condition_variable changed_;
  std::deque<std::string> frames_; bool failed_=false;
};
}
std::unique_ptr<Transport> MakeTransport() { return std::make_unique<WindowsTransport>(); }
}
