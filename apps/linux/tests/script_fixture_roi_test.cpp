#include "script_fixture_roi.h"
#include <algorithm>
#include <cassert>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <unistd.h>

using namespace kelpie::linuxapp;
int main() {
  char path[] = "/tmp/kelpie-fixture-roi-XXXXXX";
  assert(mkdtemp(path));
  assert(setenv("KELPIE_LINUX_TEST_ROI_DIR", path, 1) == 0);
  ScriptFrame frame;
  frame.width=120; frame.height=140; frame.stride=480;
  frame.bgra.resize(frame.stride*frame.height);
  for (std::size_t i=0; i<frame.bgra.size(); ++i) frame.bgra[i]=i%251;
  const auto before=FixtureRoi(frame);
  assert(before.size()==8100 && before[0]==frame.bgra[85*480+70*4]);
  assert(before.back()==frame.bgra[(85+44)*480+(70+45)*4-1]);
  auto after=before; after[400]=99;
  WriteFixtureRoi(0,before,after);
  std::ifstream file(std::string(path)+"/sample-0000.bgra",std::ios::binary);
  const std::vector<std::uint8_t> contents((std::istreambuf_iterator<char>(file)),{});
  assert(contents.size()==16200 && std::equal(before.begin(),before.end(),contents.begin()));
  assert(std::equal(after.begin(),after.end(),contents.begin()+8100));
  bool refused=false;
  try { WriteFixtureRoi(0,before,after); } catch (const std::runtime_error&) { refused=true; }
  assert(refused);
  frame.width=1; refused=false;
  try { FixtureRoi(frame); } catch (const std::runtime_error&) { refused=true; }
  assert(refused);
  std::filesystem::remove(std::string(path)+"/sample-0000.bgra");
  std::filesystem::remove(path);
}
