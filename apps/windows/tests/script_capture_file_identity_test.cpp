#include "script_capture_service.h"
#include <stdexcept>
#define CHECK(value) do {if(!(value)) throw std::runtime_error(#value);} while(false)
#include <fstream>
#include <iostream>

namespace kelpie::windows {
struct WindowsScriptStoreTest {
  static void Age(WindowsScriptService& store,const std::string& id) {
    store.entries_.at(id).created-=std::chrono::hours(2);
  }
};
}
namespace {
using namespace kelpie::windows;
void Write(const std::filesystem::path& path,const char* text) {std::ofstream file(path);CHECK(file.good());file<<text;file.flush();CHECK(file.good());}
bool Exists(const std::filesystem::path& path) {return std::filesystem::exists(path);}
auto Publish(WindowsScriptService& store,const std::filesystem::path& path,const std::string& run="run",const std::string& owner="owner") {
  return store.Publish(path,"image/png",{{"width",1},{"height",1}},run,owner);
}
auto Read(WindowsScriptService& store,const std::string& id,const std::string& run="run",const std::string& owner="owner") {
  return store.Read({{"runId",run},{"artifactId",id},{"offset",0},{"length",5}},owner);
}
}
int main(int argc,char** argv) {
  try {
  std::cerr<<"Store identity regression started"<<std::endl;
  CHECK(argc==2);
  const auto base=std::filesystem::path(argv[1]);
  CHECK(!Exists(base));CHECK(std::filesystem::create_directory(base));
  std::filesystem::path root,owned,saved;
  const auto next_case=[&](const char* name) {
    root=base/name;CHECK(std::filesystem::create_directory(root));
    owned=root/"owned.png";saved=root/"renamed-owned.png";
    std::cerr<<"Store case: "<<name<<std::endl;
  };
  next_case("file-identity");
  Write(owned,"owned");
  const auto identity=CaptureFileIdentity(owned);
  CHECK(ReadCaptureFile(owned,identity,5,0,5).size()==5);
  std::filesystem::rename(owned,saved);Write(owned,"other"); // Same length, different object.
  bool refused=false;
  try {ReadCaptureFile(owned,identity,5,0,5);}catch(...){refused=true;}
  CHECK(refused);CHECK(RemoveCaptureFile(owned,identity));CHECK(Exists(owned)&&Exists(saved));
  CHECK(RemoveCaptureFile(saved,identity));CHECK(!Exists(saved));
  CHECK(RemoveCaptureFile(saved,identity));
  CHECK(RemoveCaptureFile(owned,CaptureFileIdentity(owned)));CHECK(!Exists(owned));
  CHECK(std::filesystem::remove(root));next_case("read-expiry");
  {
    WindowsScriptService store(nullptr,nullptr,{},{});
    Write(owned,"owned");const auto item=Publish(store,owned);
    CHECK(Read(store,item.at("id")).value("success",false));
    std::filesystem::rename(owned,saved);Write(owned,"other");
    const auto denied=Read(store,item.at("id"));
    CHECK(!denied.value("success",true));CHECK(denied["error"]["code"]=="ARTIFACT_READ_FAILED");
    WindowsScriptStoreTest::Age(store,item.at("id"));
    CHECK(Read(store,item.at("id"))["error"]["code"]=="ARTIFACT_NOT_FOUND"); // Real expiry path.
    CHECK(Exists(owned)&&Exists(saved));
  }
  std::filesystem::remove(owned);std::filesystem::remove(saved);
  CHECK(std::filesystem::remove(root));next_case("destructor");
  {
    WindowsScriptService store(nullptr,nullptr,{},{});
    Write(owned,"owned");Publish(store,owned);
    std::filesystem::rename(owned,saved);Write(owned,"other");
  } // Real destructor must preserve the replacement.
  CHECK(Exists(owned)&&Exists(saved));
  std::filesystem::remove(owned);std::filesystem::remove(saved);
  CHECK(std::filesystem::remove(root));next_case("owner-run");
  {
    WindowsScriptService store(nullptr,nullptr,{},{});
    const auto other=root/"other.png",foreign=root/"foreign.png";
    Write(owned,"owned");Write(other,"other");Write(foreign,"other");
    const auto a=Publish(store,owned),b=Publish(store,other,"other-run"),c=Publish(store,foreign,"run","foreign");
    store.Discard("run","owner");
    CHECK(!Exists(owned)&&Exists(other)&&Exists(foreign));
    CHECK(Read(store,a.at("id"))["error"]["code"]=="ARTIFACT_NOT_FOUND");
    CHECK(Read(store,b.at("id"),"other-run").value("success",false));
    CHECK(Read(store,c.at("id"),"run","foreign").value("success",false));
  }
  CHECK(!Exists(root));next_case("sharing-retry");
  {
    WindowsScriptService store(nullptr,nullptr,{},{});
    Write(owned,"owned");const auto item=Publish(store,owned);
    const HANDLE blocker=CreateFileW(owned.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,0,nullptr);
    CHECK(blocker!=INVALID_HANDLE_VALUE);
    bool deferred=false;try{store.Discard("run","owner");}catch(...){deferred=true;}
    CHECK(deferred&&Exists(owned));
    CHECK(Read(store,item.at("id"))["error"]["code"]=="ARTIFACT_NOT_FOUND");
    CloseHandle(blocker);
    const auto next=root/"next.png";Write(next,"other");
    const auto next_item=Publish(store,next,"next-run"); // Natural checkpoint retries, no state edits.
    CHECK(!Exists(owned));
    CHECK(Read(store,next_item.at("id"),"next-run").value("success",false));
  }
  CHECK(!Exists(root));CHECK(std::filesystem::remove(base));
  std::cout<<"Verified reads, same-length replacement, expiry, destructor and exact owner/run discard passed"<<std::endl;
  return 0;
  } catch(const std::exception& error) {std::cerr<<"Store identity regression: "<<error.what()<<std::endl;return 1;}
}
