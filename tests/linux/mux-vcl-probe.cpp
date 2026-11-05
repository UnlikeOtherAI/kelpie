// Test-only remux of retained synthetic AVC packets; never a public API.
#include <gst/gst.h>
#include <gst/app/gstappsrc.h>
#include <gst/app/gstappsink.h>
#include <nlohmann/json.hpp>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <vector>
namespace fs=std::filesystem;
using Json=nlohmann::json;
static std::vector<unsigned char> Read(const fs::path& path) {
 std::ifstream file(path,std::ios::binary);if(!file)throw std::runtime_error("INPUT_MISSING");
 return {std::istreambuf_iterator<char>(file),{}};
}
int main(int argc,char** argv) try {
 if(argc!=4)throw std::runtime_error("ARGUMENTS");
 const fs::path dir=argv[1],output=argv[3];const std::string mode=argv[2];
 if(mode!="fragmented"&&mode!="faststart")throw std::runtime_error("MODE");
 gst_init(nullptr,nullptr);
 GError* error=nullptr;
 auto* pipeline=gst_parse_launch("appsrc name=input format=time is-live=false block=false max-bytes=268435456 ! video/x-h264,stream-format=avc,alignment=au ! mp4mux name=mux ! appsink name=output sync=false async=false max-buffers=2",&error);
 if(error||!pipeline)throw std::runtime_error("PIPELINE");
 auto* source=gst_bin_get_by_name(GST_BIN(pipeline),"input"),*sink=gst_bin_get_by_name(GST_BIN(pipeline),"output"),*mux=gst_bin_get_by_name(GST_BIN(pipeline),"mux");
 if(mode=="fragmented")g_object_set(mux,"fragment-duration",1u,"streamable",FALSE,"trak-timescale",1000000u,nullptr);
 else {const auto scratch=(dir/"faststart-temp").string();g_object_set(mux,"fragment-duration",0u,"faststart",TRUE,"faststart-file",scratch.c_str(),"trak-timescale",1000000u,nullptr);}
 const auto codec=Read(dir/"codec.bin");auto* codecbuf=gst_buffer_new_allocate(nullptr,codec.size(),nullptr);gst_buffer_fill(codecbuf,0,codec.data(),codec.size());
 auto* caps=gst_caps_new_simple("video/x-h264","stream-format",G_TYPE_STRING,"avc","alignment",G_TYPE_STRING,"au","codec_data",GST_TYPE_BUFFER,codecbuf,nullptr);
 gst_app_src_set_caps(GST_APP_SRC(source),caps);gst_caps_unref(caps);gst_buffer_unref(codecbuf);
 std::vector<unsigned char> bytes;
 GstAppSinkCallbacks callbacks{};callbacks.new_sample=[](GstAppSink* sink,gpointer raw)->GstFlowReturn {
  auto* sample=gst_app_sink_pull_sample(sink);if(!sample)return GST_FLOW_ERROR;
  auto* buffer=gst_sample_get_buffer(sample);GstMapInfo map{};
  if(!buffer||!gst_buffer_map(buffer,&map,GST_MAP_READ)){gst_sample_unref(sample);return GST_FLOW_ERROR;}
  auto& out=*static_cast<std::vector<unsigned char>*>(raw);
  if(out.size()+map.size>16777216){gst_buffer_unmap(buffer,&map);gst_sample_unref(sample);return GST_FLOW_ERROR;}
  out.insert(out.end(),map.data,map.data+map.size);gst_buffer_unmap(buffer,&map);gst_sample_unref(sample);return GST_FLOW_OK;
 };
 gst_app_sink_set_callbacks(GST_APP_SINK(sink),&callbacks,&bytes,nullptr);
 if(gst_element_set_state(pipeline,GST_STATE_PLAYING)==GST_STATE_CHANGE_FAILURE)throw std::runtime_error("START");
 std::ifstream file(dir/"manifest.json");const auto manifest=Json::parse(file);if(manifest.at("packets").size()!=15)throw std::runtime_error("PACKETS");
 for(std::size_t i=0;i<15;i++) {
  const auto data=Read(dir/("packet-"+std::to_string(i)+".bin"));auto* buf=gst_buffer_new_allocate(nullptr,data.size(),nullptr);gst_buffer_fill(buf,0,data.data(),data.size());
  GST_BUFFER_PTS(buf)=manifest["packets"][i]["ptsNs"].get<std::uint64_t>();GST_BUFFER_DTS(buf)=GST_BUFFER_PTS(buf);
  GST_BUFFER_DURATION(buf)=manifest["packets"][i]["durationNs"].get<std::uint64_t>();
  if(i)GST_BUFFER_FLAG_SET(buf,GST_BUFFER_FLAG_DELTA_UNIT);
  if(gst_app_src_push_buffer(GST_APP_SRC(source),buf)!=GST_FLOW_OK)throw std::runtime_error("PUSH");
 }
 if(gst_app_src_end_of_stream(GST_APP_SRC(source))!=GST_FLOW_OK)throw std::runtime_error("EOS");
 auto* bus=gst_element_get_bus(pipeline);auto* msg=gst_bus_timed_pop_filtered(bus,10*GST_SECOND,static_cast<GstMessageType>(GST_MESSAGE_EOS|GST_MESSAGE_ERROR));
 if(!msg||GST_MESSAGE_TYPE(msg)!=GST_MESSAGE_EOS)throw std::runtime_error("MUX_FAILED");
 gst_message_unref(msg);gst_object_unref(bus);gst_element_set_state(pipeline,GST_STATE_NULL);
 std::ofstream out(output,std::ios::binary|std::ios::trunc);out.write(reinterpret_cast<const char*>(bytes.data()),bytes.size());if(!out)throw std::runtime_error("OUTPUT");
 gst_object_unref(mux);gst_object_unref(source);gst_object_unref(sink);gst_object_unref(pipeline);
 std::cout<<"{\"mode\":\""<<mode<<"\",\"packets\":15,\"bytes\":"<<bytes.size()<<"}\n";
 return 0;
} catch(const std::exception& e) {std::cerr<<e.what()<<"\n";return 1;}
