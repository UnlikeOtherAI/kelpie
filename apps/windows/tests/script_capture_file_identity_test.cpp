#include "script_capture_service.h"
#include <cassert>
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
void Write(const std::filesystem::path& path,const char* text) {std::ofstream file(path);file<<text;}
bool Exists(const std::filesystem::path& path) {return std::filesystem::exists(path);}
auto Publish(WindowsScriptService& store,const std::filesystem::path& path,const std::string& run="run",const std::string& owner="owner") {
  return store.Publish(path,"image/png",{{"width",1},{"height",1}},run,owner);
}
auto Read(WindowsScriptService& store,const std::string& id,const std::string& run="run",const std::string& owner="owner") {
  return store.Read({{"runId",run},{"artifactId",id},{"offset",0},{"length",5}},owner);
}
}
int main(int argc,char** argv) {
  assert(argc==2);
  const auto root=std::filesystem::path(argv[1]);
  assert(!Exists(root));assert(std::filesystem::create_directory(root));
  const auto owned=root/"owned.png",saved=root/"renamed-owned.png";
  Write(owned,"owned");
  const auto identity=CaptureFileIdentity(owned);
  assert(ReadCaptureFile(owned,identity,5,0,5).size()==5);
  std::filesystem::rename(owned,saved);Write(owned,"other"); // Same length, different object.
  bool refused=false;
  try {ReadCaptureFile(owned,identity,5,0,5);}catch(...){refused=true;}
  assert(refused);assert(RemoveCaptureFile(owned,identity));assert(Exists(owned)&&Exists(saved));
  assert(RemoveCaptureFile(saved,identity));assert(!Exists(saved));
  assert(RemoveCaptureFile(saved,identity));
  assert(RemoveCaptureFile(owned,CaptureFileIdentity(owned)));assert(!Exists(owned));
  {
    WindowsScriptService store(nullptr,nullptr,{},{});
    Write(owned,"owned");const auto item=Publish(store,owned);
    assert(Read(store,item.at("id")).value("success",false));
    std::filesystem::rename(owned,saved);Write(owned,"other");
    const auto denied=Read(store,item.at("id"));
    assert(!denied.value("success",true));assert(denied["error"]["code"]=="ARTIFACT_READ_FAILED");
    WindowsScriptStoreTest::Age(store,item.at("id"));
    assert(Read(store,item.at("id"))["error"]["code"]=="ARTIFACT_NOT_FOUND"); // Real expiry path.
    assert(Exists(owned)&&Exists(saved));
  }
  std::filesystem::remove(owned);std::filesystem::remove(saved);
  {
    WindowsScriptService store(nullptr,nullptr,{},{});
    Write(owned,"owned");Publish(store,owned);
    std::filesystem::rename(owned,saved);Write(owned,"other");
  } // Real destructor must preserve the replacement.
  assert(Exists(owned)&&Exists(saved));
  std::filesystem::remove(owned);std::filesystem::remove(saved);
  {
    WindowsScriptService store(nullptr,nullptr,{},{});
    const auto other=root/"other.png",foreign=root/"foreign.png";
    Write(owned,"owned");Write(other,"other");Write(foreign,"other");
    const auto a=Publish(store,owned),b=Publish(store,other,"other-run"),c=Publish(store,foreign,"run","foreign");
    store.Discard("run","owner");
    assert(!Exists(owned)&&Exists(other)&&Exists(foreign));
    assert(Read(store,a.at("id"))["error"]["code"]=="ARTIFACT_NOT_FOUND");
    assert(Read(store,b.at("id"),"other-run").value("success",false));
    assert(Read(store,c.at("id"),"run","foreign").value("success",false));
  }
  assert(std::filesystem::remove(root));
  std::cout<<"Verified reads, same-length replacement, expiry, destructor and exact owner/run discard passed\n";
}
