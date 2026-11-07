#include "inference_store.h"
#include "inference_transport.h"
#include "windows_utf.h"
#include <windows.h>
#include <wincrypt.h>
#include <objbase.h>
#include <fstream>
#include <iterator>

namespace kelpie::windows {
namespace {
constexpr char entropy_value[] = "com.unlikeotherai.kelpie/inference.v1";
DATA_BLOB Blob(const std::string& text) {
  return {static_cast<DWORD>(text.size()), reinterpret_cast<BYTE*>(const_cast<char*>(text.data()))};
}
DATA_BLOB Entropy() { return {sizeof(entropy_value) - 1, reinterpret_cast<BYTE*>(const_cast<char*>(entropy_value))}; }
void Fail() { throw InferenceError("AI_STORAGE_FAILED", "Could not read or save encrypted inference settings"); }
}
std::string NewInferenceId() {
  GUID id{}; wchar_t buffer[40]{};
  if (FAILED(CoCreateGuid(&id)) || !StringFromGUID2(id, buffer, 40)) Fail();
  return utf::WideToUtf8(buffer).value();
}
nlohmann::json ReadInferenceStore(const std::filesystem::path& file) {
  if (!std::filesystem::exists(file)) return {{"endpoints", nlohmann::json::array()}, {"backend", "none"}};
  if (std::filesystem::file_size(file) > 2 * 1024 * 1024) Fail();
  std::ifstream stream(file, std::ios::binary);
  if (!stream) Fail();
  std::string sealed{std::istreambuf_iterator<char>(stream), {}};
  auto input = Blob(sealed); auto entropy = Entropy(); DATA_BLOB output{};
  if (!CryptUnprotectData(&input, nullptr, &entropy, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output)) Fail();
  auto data = nlohmann::json::parse(output.pbData, output.pbData + output.cbData, nullptr, false);
  SecureZeroMemory(output.pbData, output.cbData); LocalFree(output.pbData);
  if (!data.is_object() || !data.value("endpoints", nlohmann::json()).is_array()) Fail();
  return data;
}
void WriteInferenceStore(const std::filesystem::path& file, const nlohmann::json& data) {
  auto plain = data.dump(); auto input = Blob(plain); auto entropy = Entropy(); DATA_BLOB output{};
  const BOOL ok = CryptProtectData(&input, L"Kelpie inference", &entropy, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output);
  SecureZeroMemory(plain.data(), plain.size());
  if (!ok) Fail();
  const auto temporary = file.wstring() + L".tmp";
  std::filesystem::create_directories(file.parent_path());
  HANDLE handle = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  DWORD written = 0;
  bool saved = handle != INVALID_HANDLE_VALUE && WriteFile(handle, output.pbData, output.cbData, &written, nullptr)
      && written == output.cbData && FlushFileBuffers(handle);
  SecureZeroMemory(output.pbData, output.cbData); LocalFree(output.pbData);
  if (handle != INVALID_HANDLE_VALUE) CloseHandle(handle);
  saved = saved && MoveFileExW(temporary.c_str(), file.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
  if (!saved) { DeleteFileW(temporary.c_str()); Fail(); }
}
}
