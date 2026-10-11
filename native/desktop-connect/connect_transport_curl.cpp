#include "connect_transport.h"
#include "websocket_codec.h"
#include <curl/curl.h>
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <poll.h>
#include <algorithm>
#include <array>
#include <cctype>
#include <thread>
namespace kelpie::connect {
namespace {
std::string Base64(const unsigned char* data,int size) {
  std::string result(4*((size+2)/3),'\0');
  EVP_EncodeBlock(reinterpret_cast<unsigned char*>(result.data()),data,size); return result;
}
class CurlTransport final:public Transport {
 public:
  ~CurlTransport() override { Close(); }
  void Open() override {
    Close(); curl_=curl_easy_init(); if (!curl_)throw std::runtime_error("Gateway unavailable");
    curl_easy_setopt(curl_,CURLOPT_URL,"https://api.nessie.works/api/kelpie/connect");
    curl_easy_setopt(curl_,CURLOPT_CONNECT_ONLY,1L);
    curl_easy_setopt(curl_,CURLOPT_CONNECTTIMEOUT,5L);
    curl_easy_setopt(curl_,CURLOPT_TIMEOUT,8L);
    curl_easy_setopt(curl_,CURLOPT_SSL_VERIFYPEER,1L);
    curl_easy_setopt(curl_,CURLOPT_SSL_VERIFYHOST,2L);
    curl_easy_setopt(curl_,CURLOPT_NOSIGNAL,1L);
    curl_easy_setopt(curl_,CURLOPT_HTTP_VERSION,CURL_HTTP_VERSION_1_1);
    if (curl_easy_perform(curl_)!=CURLE_OK || curl_easy_getinfo(curl_,CURLINFO_ACTIVESOCKET,&socket_)!=CURLE_OK)
      throw std::runtime_error("Gateway unavailable");
    unsigned char nonce[16]; if(RAND_bytes(nonce,16)!=1)throw std::runtime_error("Random source unavailable");
    const auto key=Base64(nonce,16);
    Write("GET /api/kelpie/connect HTTP/1.1\r\nHost: api.nessie.works\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: "+key+"\r\n\r\n");
    const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(5);
    while(buffer_.find("\r\n\r\n")==std::string::npos && std::chrono::steady_clock::now()<deadline) {
      Read(std::chrono::milliseconds(250)); if(buffer_.size()>16384)throw std::runtime_error("Invalid gateway upgrade");
    }
    const auto end=buffer_.find("\r\n\r\n");
    if(end==std::string::npos)throw std::runtime_error("Gateway upgrade timeout");
    auto original=buffer_.substr(0,end+2); auto header=original; buffer_.erase(0,end+4);
    std::transform(header.begin(),header.end(),header.begin(),[](unsigned char c){return static_cast<char>(std::tolower(c));});
    const auto challenge=key+"258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    unsigned char digest[EVP_MAX_MD_SIZE]; unsigned length=0;
    if(EVP_Digest(challenge.data(),challenge.size(),digest,&length,EVP_sha1(),nullptr)!=1)throw std::runtime_error("Invalid gateway upgrade");
    auto accept=Base64(digest,static_cast<int>(length));

    if(!header.starts_with("http/1.1 101 ") || header.find("\r\nupgrade: websocket\r\n")==std::string::npos ||
        ([&] { const auto pos=header.find("\r\nsec-websocket-accept: "); return pos==std::string::npos || original.substr(pos+24,accept.size())!=accept || original.substr(pos+24+accept.size(),2)!="\r\n"; })())throw std::runtime_error("Invalid gateway upgrade");
  }
  void Send(const std::string& frame) override { SendControl(frame,1); }
  std::optional<std::string> Receive(std::chrono::milliseconds wait) override {
    const auto deadline=std::chrono::steady_clock::now()+wait;
    do {
      while(auto frame=DecodeFrame(buffer_)) {
        if(frame->opcode==8)throw std::runtime_error("Gateway disconnected");
        if(frame->opcode==9) { SendControl(frame->payload,10); continue; }
        if(frame->opcode==10)continue;
        if(frame->opcode!=0 && frame->opcode!=1)throw std::runtime_error("Unsupported gateway frame");
        if((frame->opcode==0 && !fragmented_) || (frame->opcode==1 && fragmented_))throw std::runtime_error("Invalid gateway fragments");
        message_+=frame->payload;
        if(message_.size()>1024*1024)throw std::runtime_error("Gateway frame too large");
        fragmented_=!frame->final;
        if(frame->final) { auto text=std::move(message_); message_.clear(); return text; }
      }
      Read(std::chrono::milliseconds(20));
    }while(std::chrono::steady_clock::now()<deadline);
    return {};
  }
  void Close() override { if(curl_)curl_easy_cleanup(curl_); curl_=nullptr; buffer_.clear(); message_.clear(); fragmented_=false; }
 private:
  void SendControl(const std::string& text,unsigned opcode) {
    std::array<unsigned char,4> mask{}; if(RAND_bytes(mask.data(),4)!=1)throw std::runtime_error("Random source unavailable");
    Write(EncodeFrame(text,opcode,mask));
  }
  void Write(const std::string& text) {
    std::size_t offset=0; const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(5);
    while(offset<text.size()) {
      std::size_t sent=0; const auto code=curl_easy_send(curl_,text.data()+offset,text.size()-offset,&sent);
      if(code!=CURLE_OK && code!=CURLE_AGAIN)throw std::runtime_error("Gateway disconnected");
      offset+=sent; if(std::chrono::steady_clock::now()>deadline)throw std::runtime_error("Gateway send timeout");
      if(!sent)std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
  }
  void Read(std::chrono::milliseconds wait) {
    char bytes[16384]; std::size_t size=0;
    auto code=curl_easy_recv(curl_,bytes,sizeof(bytes),&size);
    if(code==CURLE_AGAIN) {
      pollfd event{socket_,POLLIN,0}; poll(&event,1,static_cast<int>(wait.count()));
      code=curl_easy_recv(curl_,bytes,sizeof(bytes),&size);
    }
    if(code==CURLE_AGAIN)return;
    if(code!=CURLE_OK || !size)throw std::runtime_error("Gateway disconnected");
    buffer_.append(bytes,size);
    if(buffer_.size()>1024*1024+16384)throw std::runtime_error("Gateway buffer exceeded");
  }
  CURL* curl_=nullptr; curl_socket_t socket_=CURL_SOCKET_BAD;
  std::string buffer_,message_; bool fragmented_=false;
};
}
std::unique_ptr<Transport> MakeTransport() { return std::make_unique<CurlTransport>(); }
}
