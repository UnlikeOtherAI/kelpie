#pragma once
// Test-only IStream wrapper which refuses writes before they exceed the limit.
class TimelineBoundedStream final : public IStream {
 public:
  TimelineBoundedStream(IStream* stream,std::uint64_t limit):stream_(stream),limit_(limit){}
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id,void** out) override {
    if(!out)return E_POINTER;*out=nullptr;
    if(id!=IID_IUnknown&&id!=IID_ISequentialStream&&id!=IID_IStream)return E_NOINTERFACE;
    *out=static_cast<IStream*>(this);AddRef();return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override{return ++refs_;}
  ULONG STDMETHODCALLTYPE Release() override{const auto n=--refs_;if(!n)delete this;return n;}
  HRESULT STDMETHODCALLTYPE Read(void* p,ULONG n,ULONG* done) override{std::lock_guard lock(mutex_);return stream_->Read(p,n,done);}
  HRESULT STDMETHODCALLTYPE Write(const void* p,ULONG n,ULONG* done) override{
    std::lock_guard lock(mutex_);if(done)*done=0;LARGE_INTEGER zero{};ULARGE_INTEGER at{};
    const auto hr=stream_->Seek(zero,STREAM_SEEK_CUR,&at);if(FAILED(hr))return hr;
    if(at.QuadPart>limit_||n>limit_-at.QuadPart)return STG_E_MEDIUMFULL;
    return stream_->Write(p,n,done);
  }
  HRESULT STDMETHODCALLTYPE Seek(LARGE_INTEGER n,DWORD origin,ULARGE_INTEGER* at) override{std::lock_guard lock(mutex_);return stream_->Seek(n,origin,at);}
  HRESULT STDMETHODCALLTYPE SetSize(ULARGE_INTEGER size) override{std::lock_guard lock(mutex_);return size.QuadPart>limit_?STG_E_MEDIUMFULL:stream_->SetSize(size);}
  HRESULT STDMETHODCALLTYPE CopyTo(IStream*,ULARGE_INTEGER,ULARGE_INTEGER*,ULARGE_INTEGER*) override{return E_NOTIMPL;}
  HRESULT STDMETHODCALLTYPE Commit(DWORD flags) override{std::lock_guard lock(mutex_);return stream_->Commit(flags);}
  HRESULT STDMETHODCALLTYPE Revert() override{return E_NOTIMPL;}
  HRESULT STDMETHODCALLTYPE LockRegion(ULARGE_INTEGER,ULARGE_INTEGER,DWORD) override{return E_NOTIMPL;}
  HRESULT STDMETHODCALLTYPE UnlockRegion(ULARGE_INTEGER,ULARGE_INTEGER,DWORD) override{return E_NOTIMPL;}
  HRESULT STDMETHODCALLTYPE Stat(STATSTG* stat,DWORD flags) override{std::lock_guard lock(mutex_);return stream_->Stat(stat,flags);}
  HRESULT STDMETHODCALLTYPE Clone(IStream** out) override{if(out)*out=nullptr;return E_NOTIMPL;}
 private:
  ~TimelineBoundedStream()=default;
  std::atomic<ULONG> refs_{1};std::mutex mutex_;Microsoft::WRL::ComPtr<IStream> stream_;std::uint64_t limit_;
};
inline Json TimelinePngFile(std::filesystem::path const& path,int width,int height,
    std::vector<BYTE> const& pixels,std::string const& alpha,std::function<void()> const& fence,std::uint64_t limit){
  fence();Microsoft::WRL::ComPtr<kelpie::windows::media::OwnedMediaStream> owned;
  owned.Attach(new kelpie::windows::media::OwnedMediaStream(path));
  Microsoft::WRL::ComPtr<TimelineBoundedStream> stream;stream.Attach(new TimelineBoundedStream(owned.Get(),limit));
  Microsoft::WRL::ComPtr<IWICImagingFactory> factory;
  Check(CoCreateInstance(CLSID_WICImagingFactory,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&factory)));
  Microsoft::WRL::ComPtr<IWICBitmap> bitmap;
  const auto format=alpha=="premultiplied"?GUID_WICPixelFormat32bppPBGRA:GUID_WICPixelFormat32bppBGRA;
  Check(factory->CreateBitmapFromMemory(static_cast<UINT>(width),static_cast<UINT>(height),format,
    static_cast<UINT>(width*4),static_cast<UINT>(pixels.size()),const_cast<BYTE*>(pixels.data()),&bitmap));
  Microsoft::WRL::ComPtr<IWICBitmapSource> source;Check(WICConvertBitmapSource(GUID_WICPixelFormat32bppBGRA,bitmap.Get(),&source));
  Microsoft::WRL::ComPtr<IWICBitmapEncoder> encoder;Check(factory->CreateEncoder(GUID_ContainerFormatPng,nullptr,&encoder));
  Check(encoder->Initialize(stream.Get(),WICBitmapEncoderNoCache));
  Microsoft::WRL::ComPtr<IWICBitmapFrameEncode> frame;Microsoft::WRL::ComPtr<IPropertyBag2> options;
  Check(encoder->CreateNewFrame(&frame,&options));Check(frame->Initialize(options.Get()));
  Check(frame->SetSize(static_cast<UINT>(width),static_cast<UINT>(height)));
  auto outputFormat=GUID_WICPixelFormat32bppBGRA;Check(frame->SetPixelFormat(&outputFormat));
  if(outputFormat!=GUID_WICPixelFormat32bppBGRA)throw std::runtime_error("WGC_PNG_FORMAT");
  Check(frame->WriteSource(source.Get(),nullptr));Check(frame->Commit());Check(encoder->Commit());
  frame.Reset();encoder.Reset();source.Reset();bitmap.Reset();factory.Reset();stream.Reset();
  fence();const auto hash=Hash(owned.Get());STATSTG stat{};Check(owned->Stat(&stat,STATFLAG_NONAME));
  if(stat.cbSize.QuadPart>limit)throw std::runtime_error("WGC_OUTPUT_BOUND");
  fence();Check(owned->Complete());
  return {{"path",Text(path)},{"sha256",hash},{"byteLength",stat.cbSize.QuadPart}};
}

inline Json TimelineStreamSelfTest(){
  Microsoft::WRL::ComPtr<IStream> memory;Check(CreateStreamOnHGlobal(nullptr,TRUE,&memory));
  Microsoft::WRL::ComPtr<TimelineBoundedStream> limited;limited.Attach(new TimelineBoundedStream(memory.Get(),4));
  const BYTE bytes[5]={1,2,3,4,5};ULONG written=0;
  Check(limited->Write(bytes,4,&written));if(written!=4)throw std::runtime_error("WGC_SELFTEST_WRITE");
  if(limited->Write(bytes,1,&written)!=STG_E_MEDIUMFULL||written!=0)throw std::runtime_error("WGC_SELFTEST_LIMIT");
  ULARGE_INTEGER size{};size.QuadPart=5;if(limited->SetSize(size)!=STG_E_MEDIUMFULL)throw std::runtime_error("WGC_SELFTEST_SIZE");
  STATSTG stat{};Check(memory->Stat(&stat,STATFLAG_NONAME));if(stat.cbSize.QuadPart!=4)throw std::runtime_error("WGC_SELFTEST_LENGTH");
  return {{"boundedStream",true},{"limitBytes",4}};
}
