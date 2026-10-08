#include "http_server.h"
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#include <atomic>
#include <cassert>
#include <string>

// The fallback (non-CEF) Linux server must follow the desktop control
// contract: loopback only, bearer token on every /v1/* call, no CORS grant.
namespace {
std::string Send(int port, const std::string& request) {
  const int fd=socket(AF_INET,SOCK_STREAM,0); assert(fd>=0);
  sockaddr_in address{}; address.sin_family=AF_INET; address.sin_port=htons(static_cast<uint16_t>(port));
  address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
  assert(connect(fd,reinterpret_cast<sockaddr*>(&address),sizeof(address))==0);
  assert(send(fd,request.data(),request.size(),0)==static_cast<ssize_t>(request.size()));
  std::string response; char buffer[4096]; ssize_t read_bytes=0;
  while((read_bytes=recv(fd,buffer,sizeof(buffer),0))>0) response.append(buffer,static_cast<std::size_t>(read_bytes));
  close(fd); return response;
}
std::string Post(int port, const std::string& extra_headers) {
  const std::string body="{}";
  return Send(port,"POST /v1/get-url HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\n"+
      extra_headers+"Content-Length: "+std::to_string(body.size())+"\r\n\r\n"+body);
}
bool StatusIs(const std::string& response, int status) {
  return response.rfind("HTTP/1.1 "+std::to_string(status)+" ",0)==0;
}
}  // namespace

int main() {
  std::atomic<int> handled{0};
  kelpie::linuxapp::HttpServer server;
  std::string error;
  assert(!server.Start(18420,"",[](std::string_view,const nlohmann::json&,int*) { return nlohmann::json::object(); },&error));
  assert(server.Start(18420,"secret-token",[&handled](std::string_view endpoint,const nlohmann::json&,int*) {
    ++handled; return nlohmann::json{{"success",true},{"endpoint",std::string(endpoint)}};
  },&error));
  const int port=server.port();

  // Bound to loopback only: the host's own LAN addresses refuse the port.
  ifaddrs* interfaces=nullptr;
  assert(getifaddrs(&interfaces)==0);
  for(const ifaddrs* entry=interfaces;entry!=nullptr;entry=entry->ifa_next) {
    if(entry->ifa_addr==nullptr || entry->ifa_addr->sa_family!=AF_INET) continue;
    sockaddr_in address=*reinterpret_cast<const sockaddr_in*>(entry->ifa_addr);
    if(ntohl(address.sin_addr.s_addr)>>24==127) continue;
    address.sin_port=htons(static_cast<uint16_t>(port));
    const int fd=socket(AF_INET,SOCK_STREAM,0);
    assert(connect(fd,reinterpret_cast<sockaddr*>(&address),sizeof(address))!=0);
    close(fd);
  }
  freeifaddrs(interfaces);

  assert(StatusIs(Post(port,""),401));
  assert(StatusIs(Post(port,"Authorization: Bearer wrong-token\r\n"),401));
  assert(StatusIs(Post(port,"Authorization: Bearer secret-token\r\nAuthorization: Bearer secret-token\r\n"),401));
  assert(handled==0);

  const std::string accepted=Post(port,"authorization: bearer secret-token\r\n");
  assert(StatusIs(accepted,200));
  assert(accepted.find("\"endpoint\":\"get-url\"")!=std::string::npos);
  assert(handled==1);

  assert(StatusIs(Send(port,"GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"),200));
  assert(accepted.find("Access-Control-Allow-Origin")==std::string::npos);
  assert(StatusIs(Send(port,"OPTIONS /v1/get-url HTTP/1.1\r\nHost: 127.0.0.1\r\nOrigin: http://evil.test\r\n\r\n"),405));
  server.Stop();
  return 0;
}
