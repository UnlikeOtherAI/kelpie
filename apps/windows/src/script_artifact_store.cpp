#include "script_capture_service.h"
#include "kelpie/desktop_script_owner.h"
#include "kelpie/response_helpers.h"
#include <sddl.h>
#include <wincrypt.h>
#include <algorithm>
#include <fstream>
#include <vector>
namespace kelpie::windows {
namespace {
struct CaptureHandle {
  HANDLE value=INVALID_HANDLE_VALUE;
  ~CaptureHandle(){if(value!=INVALID_HANDLE_VALUE)CloseHandle(value);}
};
bool SameIdentity(const BY_HANDLE_FILE_INFORMATION& actual,const BY_HANDLE_FILE_INFORMATION& expected) {
  return actual.dwVolumeSerialNumber==expected.dwVolumeSerialNumber&&
    actual.nFileIndexHigh==expected.nFileIndexHigh&&actual.nFileIndexLow==expected.nFileIndexLow&&
    actual.ftCreationTime.dwHighDateTime==expected.ftCreationTime.dwHighDateTime&&
    actual.ftCreationTime.dwLowDateTime==expected.ftCreationTime.dwLowDateTime&&
    !(actual.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT));
}
void OpenVerified(CaptureHandle& file,const std::filesystem::path& path,
                  const BY_HANDLE_FILE_INFORMATION& expected,std::uint64_t size) {
  file.value=CreateFileW(path.c_str(),GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_DELETE,
    nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
  BY_HANDLE_FILE_INFORMATION actual{};
  if(file.value==INVALID_HANDLE_VALUE||!GetFileInformationByHandle(file.value,&actual)||
     !SameIdentity(actual,expected)||((static_cast<std::uint64_t>(actual.nFileSizeHigh)<<32)|actual.nFileSizeLow)!=size)
    throw std::runtime_error("ARTIFACT_IDENTITY_CHANGED");
}
std::string HashFile(const std::filesystem::path& path,const BY_HANDLE_FILE_INFORMATION& expected,std::uint64_t size) {
  CaptureHandle file;OpenVerified(file,path,expected,size);
  HCRYPTPROV provider=0;HCRYPTHASH hash=0;
  if(!CryptAcquireContextW(&provider,nullptr,nullptr,PROV_RSA_AES,CRYPT_VERIFYCONTEXT)||!CryptCreateHash(provider,CALG_SHA_256,0,0,&hash)) {
    if(provider)CryptReleaseContext(provider,0);throw std::runtime_error("CAPTURE_HASH_FAILED");
  }
  std::vector<BYTE> bytes(65536);DWORD read=0;bool valid=true;std::uint64_t total=0;
  do {
    valid=ReadFile(file.value,bytes.data(),static_cast<DWORD>(bytes.size()),&read,nullptr)!=FALSE;
    if(!valid)break;
    total+=read;
    if(read&&!CryptHashData(hash,bytes.data(),read,0)){valid=false;break;}
  }while(read);
  BYTE digest[32];DWORD digest_size=sizeof(digest);
  valid=valid&&total==size&&CryptGetHashParam(hash,HP_HASHVAL,digest,&digest_size,0);
  CryptDestroyHash(hash);CryptReleaseContext(provider,0);
  if(!valid)throw std::runtime_error("CAPTURE_HASH_FAILED");
  constexpr char hex[]="0123456789abcdef";std::string result;
  for(BYTE value:digest){result.push_back(hex[value>>4]);result.push_back(hex[value&15]);}return result;
}
std::string Base64(const std::vector<BYTE>& bytes) {
  if(bytes.empty()) return ""; DWORD length=0;
  if(!CryptBinaryToStringA(bytes.data(),static_cast<DWORD>(bytes.size()),CRYPT_STRING_BASE64|CRYPT_STRING_NOCRLF,nullptr,&length))
    throw std::runtime_error("ARTIFACT_READ_FAILED");
  std::string result(length,'\0');
  if(!CryptBinaryToStringA(bytes.data(),static_cast<DWORD>(bytes.size()),CRYPT_STRING_BASE64|CRYPT_STRING_NOCRLF,result.data(),&length))
    throw std::runtime_error("ARTIFACT_READ_FAILED");
  result.resize(length&&result[length-1]=='\0'?length-1:length); return result;
}
void Remove(const std::filesystem::path& path,const BY_HANDLE_FILE_INFORMATION& identity) {
  RemoveCaptureFile(path,identity);
  std::error_code ignored; std::filesystem::remove(path.parent_path(),ignored);
}
}
BY_HANDLE_FILE_INFORMATION CaptureFileIdentity(const std::filesystem::path& path) {
  const HANDLE file=CreateFileW(path.c_str(),FILE_READ_ATTRIBUTES,
    FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
  if(file==INVALID_HANDLE_VALUE) throw std::runtime_error("CAPTURE_FILE_IDENTITY_FAILED");
  BY_HANDLE_FILE_INFORMATION identity{};const bool ok=GetFileInformationByHandle(file,&identity)!=FALSE;
  CloseHandle(file);
  if(!ok || (identity.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT)))
    throw std::runtime_error("CAPTURE_FILE_IDENTITY_FAILED");
  return identity;
}
bool RemoveCaptureFile(const std::filesystem::path& path,const BY_HANDLE_FILE_INFORMATION& expected) {
  const HANDLE file=CreateFileW(path.c_str(),DELETE|FILE_READ_ATTRIBUTES,
    FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
  if(file==INVALID_HANDLE_VALUE) return GetLastError()==ERROR_FILE_NOT_FOUND||GetLastError()==ERROR_PATH_NOT_FOUND;
  BY_HANDLE_FILE_INFORMATION actual{};bool ok=GetFileInformationByHandle(file,&actual)!=FALSE;
  const bool same=ok&&SameIdentity(actual,expected);
  if(same) {FILE_DISPOSITION_INFO disposition{TRUE};ok=SetFileInformationByHandle(file,FileDispositionInfo,&disposition,sizeof(disposition))!=FALSE;}
  CloseHandle(file);return ok; // A replacement is preserved and its capability is still revoked.
}
std::vector<BYTE> ReadCaptureFile(const std::filesystem::path& path,const BY_HANDLE_FILE_INFORMATION& expected,
  std::uint64_t size,std::uint64_t offset,std::uint64_t length) {
  if(offset>size||length>1048576)throw std::runtime_error("ARTIFACT_READ_RANGE");
  CaptureHandle file;OpenVerified(file,path,expected,size);
  LARGE_INTEGER position{};position.QuadPart=static_cast<LONGLONG>(offset);
  if(!SetFilePointerEx(file.value,position,nullptr,FILE_BEGIN))throw std::runtime_error("ARTIFACT_READ_FAILED");
  std::vector<BYTE> bytes(static_cast<std::size_t>(std::min(length,size-offset)));DWORD read=0;
  if(!bytes.empty()&&(!ReadFile(file.value,bytes.data(),static_cast<DWORD>(bytes.size()),&read,nullptr)||read!=bytes.size()))
    throw std::runtime_error("ARTIFACT_READ_FAILED");
  return bytes;
}
void WindowsScriptService::Discard(const std::string& run,const std::string& owner) {
  std::lock_guard lock(mutex_);bool cleaned=true;
  for(auto it=entries_.begin();it!=entries_.end();) {
    if(it->second.run!=run || it->second.owner!=owner) {++it;continue;}
    const auto entry=it->second;it=entries_.erase(it); // Revoke before attempting filesystem cleanup.
    cleaned=RemoveCaptureFile(entry.path,entry.identity)&&cleaned;
    std::error_code ignored;std::filesystem::remove(entry.path.parent_path(),ignored);
  }
  if(!cleaned) throw std::runtime_error("CAPTURE_PRIVACY_CLEANUP_FAILED");
}
std::filesystem::path CreatePrivateCaptureDirectory(const std::string& run) {
  HANDLE token=nullptr; DWORD size=0;
  if(!OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&token)) throw std::runtime_error("CAPTURE_STORAGE_FAILED");
  GetTokenInformation(token,TokenUser,nullptr,0,&size); std::vector<BYTE> info(size);
  if(!GetTokenInformation(token,TokenUser,info.data(),size,&size)) { CloseHandle(token); throw std::runtime_error("CAPTURE_STORAGE_FAILED"); }
  CloseHandle(token); LPWSTR sid=nullptr;
  if(!ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(info.data())->User.Sid,&sid)) throw std::runtime_error("CAPTURE_STORAGE_FAILED");
  const std::wstring sddl=L"D:P(A;;FA;;;SY)(A;;FA;;;"+std::wstring(sid)+L")"; LocalFree(sid);
  PSECURITY_DESCRIPTOR descriptor=nullptr;
  if(!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl.c_str(),SDDL_REVISION_1,&descriptor,nullptr)) throw std::runtime_error("CAPTURE_STORAGE_FAILED");
  SECURITY_ATTRIBUTES attributes{sizeof(SECURITY_ATTRIBUTES),descriptor,FALSE};
  const auto directory=std::filesystem::temp_directory_path()/("kelpie-capture-"+run);
  const bool created=CreateDirectoryW(directory.c_str(),&attributes)!=FALSE; LocalFree(descriptor);
  if(!created) throw std::runtime_error("CAPTURE_STORAGE_FAILED"); return directory;
}
WindowsScriptService::Json WindowsScriptService::Publish(const std::filesystem::path& path,const std::string& mime,Json metadata,const std::string& run,const std::string& owner) {
  const auto identity=CaptureFileIdentity(path);
  const auto bytes=(static_cast<std::uint64_t>(identity.nFileSizeHigh)<<32)|identity.nFileSizeLow; if(bytes>268435456) throw std::runtime_error("CAPTURE_BUDGET_EXCEEDED");
  metadata["id"]=NewDesktopScriptId(); metadata["mimeType"]=mime; metadata["byteLength"]=bytes;
  metadata["sha256"]=HashFile(path,identity,bytes); if(!metadata.contains("partial")) metadata["partial"]=false;
  std::lock_guard lock(mutex_); Expire();
  entries_.emplace(metadata["id"].get<std::string>(),Entry{path,run,owner,metadata,identity,std::chrono::steady_clock::now()});
  Expire();
  return metadata;
}
void WindowsScriptService::Expire() {
  const auto now=std::chrono::steady_clock::now();
  for(auto it=entries_.begin();it!=entries_.end();) {
    if(now-it->second.created>std::chrono::hours(1)) { Remove(it->second.path,it->second.identity); it=entries_.erase(it); } else ++it;
  }
  std::uintmax_t total=0; for(const auto& [id,entry]:entries_) total+=entry.manifest.value("byteLength",std::uintmax_t(0));
  while(total>268435456&&!entries_.empty()) {
    const auto oldest=std::min_element(entries_.begin(),entries_.end(),[](const auto& a,const auto& b){return a.second.created<b.second.created;});
    total-=oldest->second.manifest.value("byteLength",std::uintmax_t(0)); Remove(oldest->second.path,oldest->second.identity); entries_.erase(oldest);
  }
}
WindowsScriptService::Json WindowsScriptService::Read(const Json& body,const std::string& owner) {
  if(!body.is_object()||!body.contains("runId")||!body["runId"].is_string()||!body.contains("artifactId")||!body["artifactId"].is_string())
    return ErrorResponse("INVALID_PARAMS","Run and artifact IDs are required");
  if(body["runId"].get_ref<const std::string&>().empty() || body["artifactId"].get_ref<const std::string&>().empty() ||
     body["runId"].get_ref<const std::string&>().size()>128 || body["artifactId"].get_ref<const std::string&>().size()>128)
    return ErrorResponse("INVALID_PARAMS","Artifact IDs exceed the range limit");
  for(const auto& item:body.items()) if(item.key()!="runId"&&item.key()!="artifactId"&&item.key()!="offset"&&item.key()!="length")
    return ErrorResponse("INVALID_PARAMS","Unknown artifact range field");
  for(const char* field:{"offset","length"}) if(body.contains(field)&&!body[field].is_number_unsigned()&&!(body[field].is_number_integer()&&body[field].get<std::int64_t>()>=0))
    return ErrorResponse("INVALID_PARAMS","Artifact ranges must be nonnegative integers");
  const auto offset=body.value("offset",std::uint64_t(0)),length=body.value("length",std::uint64_t(262144));
  if(!length||length>1048576) return ErrorResponse("INVALID_PARAMS","Artifact chunk exceeds range limit");
  std::lock_guard lock(mutex_); Expire(); const auto found=entries_.find(body["artifactId"].get<std::string>());
  if(owner.empty()||found==entries_.end()||found->second.owner!=owner||found->second.run!=body["runId"].get_ref<const std::string&>())
    return ErrorResponse("ARTIFACT_NOT_FOUND","Artifact expired or is not owned by this grant");
  const auto& entry=found->second; const auto total=entry.manifest["byteLength"].get<std::uint64_t>();
  if(offset>total) return ErrorResponse("INVALID_PARAMS","Artifact offset is beyond end");
  try {
    const auto bytes=ReadCaptureFile(entry.path,entry.identity,total,offset,length);
    return SuccessResponse({{"runId",entry.run},{"artifactId",body["artifactId"]},{"data",Base64(bytes)},{"offset",offset},{"nextOffset",offset+bytes.size()},{"eof",offset+bytes.size()>=total},
      {"mimeType",entry.manifest["mimeType"]},{"byteLength",total},{"sha256",entry.manifest["sha256"]}});
  } catch(...) { return ErrorResponse("ARTIFACT_READ_FAILED","Artifact chunk could not be read"); }
}
}
