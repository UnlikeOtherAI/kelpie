#pragma once

#include "script_media_internal.h"
#include <atomic>
#include <mutex>

namespace kelpie::windows::media {

struct MediaFileOps {
  decltype(&::DuplicateHandle) duplicate = &::DuplicateHandle;
  decltype(&::FlushFileBuffers) flush = &::FlushFileBuffers;
  decltype(&::CloseHandle) close = &::CloseHandle;
};

// MF wraps this stream without ever opening its path. The exact CREATE_NEW
// object stays held with DELETE access until completion or rollback; failures
// never reopen/delete a filename or depend on obtaining a filesystem ID.
class OwnedMediaStream final : public IStream {
 public:
  explicit OwnedMediaStream(const std::filesystem::path& path, MediaFileOps io = {}) : io_(io) {
    file_ = CreateFileW(path.c_str(), GENERIC_READ | GENERIC_WRITE | DELETE,
        FILE_SHARE_READ, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file_ == INVALID_HANDLE_VALUE) {
      const auto error = GetLastError();
      if (error == ERROR_FILE_EXISTS || error == ERROR_ALREADY_EXISTS)
        throw std::runtime_error("CAPTURE_OUTPUT_EXISTS");
      throw std::runtime_error("CAPTURE_OUTPUT_UNAVAILABLE");
    }
    if (!io_.duplicate(GetCurrentProcess(), file_, GetCurrentProcess(), &guard_,
                       0, FALSE, DUPLICATE_SAME_ACCESS)) {
      FILE_DISPOSITION_INFO discard{TRUE};
      SetFileInformationByHandle(file_, FileDispositionInfo, &discard, sizeof(discard));
      CloseHandle(file_);
      file_ = INVALID_HANDLE_VALUE;
      throw std::runtime_error("CAPTURE_OUTPUT_UNAVAILABLE");
    }
  }

  HRESULT Complete() noexcept {
    std::lock_guard<std::mutex> lock(mutex_);
    if (terminal_) return S_OK;
    if (!io_.flush(file_)) return LastError();
    if (!io_.close(file_)) return LastError();
    file_ = INVALID_HANDLE_VALUE;
    if (!io_.close(guard_)) return LastError();
    guard_ = INVALID_HANDLE_VALUE;
    terminal_ = true;
    return S_OK;
  }

  void Abort() noexcept {
    std::lock_guard<std::mutex> lock(mutex_);
    if (terminal_) return;
    const auto owned = guard_ != INVALID_HANDLE_VALUE ? guard_ : file_;
    FILE_DISPOSITION_INFO discard{TRUE};
    if (owned != INVALID_HANDLE_VALUE)
      SetFileInformationByHandle(owned, FileDispositionInfo, &discard, sizeof(discard));
    if (file_ != INVALID_HANDLE_VALUE) CloseHandle(file_);
    if (guard_ != INVALID_HANDLE_VALUE) CloseHandle(guard_);
    file_ = guard_ = INVALID_HANDLE_VALUE;
    terminal_ = true;
  }

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id, void** result) override {
    if (!result) return E_POINTER;
    *result = nullptr;
    if (id != IID_IUnknown && id != IID_ISequentialStream && id != IID_IStream)
      return E_NOINTERFACE;
    *result = static_cast<IStream*>(this);
    AddRef();
    return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
  ULONG STDMETHODCALLTYPE Release() override {
    const auto count = --references_;
    if (!count) delete this;
    return count;
  }
  HRESULT STDMETHODCALLTYPE Read(void* bytes, ULONG count, ULONG* read) override {
    std::lock_guard<std::mutex> lock(mutex_);
    if (read) *read = 0;
    DWORD actual = 0;
    if (!ReadFile(file_, bytes, count, &actual, nullptr)) return LastError();
    if (read) *read = actual;
    return actual == count ? S_OK : S_FALSE;
  }
  HRESULT STDMETHODCALLTYPE Write(const void* bytes, ULONG count, ULONG* written) override {
    std::lock_guard<std::mutex> lock(mutex_);
    if (written) *written = 0;
    DWORD actual = 0;
    if (!WriteFile(file_, bytes, count, &actual, nullptr)) return LastError();
    if (written) *written = actual;
    return actual == count ? S_OK : STG_E_WRITEFAULT;
  }
  HRESULT STDMETHODCALLTYPE Seek(LARGE_INTEGER distance, DWORD origin,
                                  ULARGE_INTEGER* position) override {
    std::lock_guard<std::mutex> lock(mutex_);
    if (origin > STREAM_SEEK_END) return STG_E_INVALIDFUNCTION;
    LARGE_INTEGER value{};
    if (!SetFilePointerEx(file_, distance, &value, origin)) return LastError();
    if (position) position->QuadPart = static_cast<ULONGLONG>(value.QuadPart);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE SetSize(ULARGE_INTEGER size) override {
    std::lock_guard<std::mutex> lock(mutex_);
    if (size.QuadPart > static_cast<ULONGLONG>(MAXLONGLONG)) return STG_E_INVALIDFUNCTION;
    LARGE_INTEGER zero{}, previous{}, target{};
    target.QuadPart = static_cast<LONGLONG>(size.QuadPart);
    if (!SetFilePointerEx(file_, zero, &previous, FILE_CURRENT) ||
        !SetFilePointerEx(file_, target, nullptr, FILE_BEGIN)) return LastError();
    const auto resized = SetEndOfFile(file_);
    const auto error = GetLastError();
    if (!SetFilePointerEx(file_, previous, nullptr, FILE_BEGIN)) return LastError();
    return resized ? S_OK : HRESULT_FROM_WIN32(error);
  }
  HRESULT STDMETHODCALLTYPE Commit(DWORD) override {
    std::lock_guard<std::mutex> lock(mutex_);
    return io_.flush(file_) ? S_OK : LastError();
  }
  HRESULT STDMETHODCALLTYPE Stat(STATSTG* stats, DWORD) override {
    if (!stats) return E_POINTER;
    std::lock_guard<std::mutex> lock(mutex_);
    *stats = {};
    LARGE_INTEGER size{};
    if (!GetFileSizeEx(file_, &size)) return LastError();
    stats->type = STGTY_STREAM;
    stats->grfMode = STGM_READWRITE;
    stats->cbSize.QuadPart = static_cast<ULONGLONG>(size.QuadPart);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE CopyTo(IStream*, ULARGE_INTEGER, ULARGE_INTEGER*,
                                    ULARGE_INTEGER*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE Revert() override { return STG_E_INVALIDFUNCTION; }
  HRESULT STDMETHODCALLTYPE LockRegion(ULARGE_INTEGER, ULARGE_INTEGER, DWORD) override {
    return STG_E_INVALIDFUNCTION;
  }
  HRESULT STDMETHODCALLTYPE UnlockRegion(ULARGE_INTEGER, ULARGE_INTEGER, DWORD) override {
    return STG_E_INVALIDFUNCTION;
  }
  HRESULT STDMETHODCALLTYPE Clone(IStream** result) override {
    if (result) *result = nullptr;
    return E_NOTIMPL;
  }

 private:
  ~OwnedMediaStream() { Abort(); }
  static HRESULT LastError() noexcept {
    const auto error = GetLastError();
    return HRESULT_FROM_WIN32(error == ERROR_SUCCESS ? ERROR_WRITE_FAULT : error);
  }
  MediaFileOps io_;
  HANDLE file_ = INVALID_HANDLE_VALUE;
  HANDLE guard_ = INVALID_HANDLE_VALUE;
  std::atomic<ULONG> references_{1};
  std::mutex mutex_;
  bool terminal_ = false;
};
}  // namespace kelpie::windows::media