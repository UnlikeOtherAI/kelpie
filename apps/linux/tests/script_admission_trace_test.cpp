#include "script_admission_trace.h"
#include <cassert>
#include <filesystem>
#include <fstream>

int main() {
  using namespace kelpie::linuxapp;
  const auto path=std::filesystem::temp_directory_path() / ("kelpie-admission-test-"+std::to_string(getpid()));
  setenv("KELPIE_LINUX_TEST_ADMISSION_TRACE",path.c_str(),1);
  bool refused=false;
  try { WriteAdmissionTrace({{"pageText",42}}); } catch (...) { refused=true; }
  assert(refused && !std::filesystem::exists(path));
  refused=false;
  try { WriteAdmissionTrace({{"phase","private-canary"}}); } catch (...) { refused=true; }
  assert(refused && !std::filesystem::exists(path));
  WriteAdmissionTrace({{"phase",0},{"elapsedMs",767.0},{"markerAgeMs",767.0},{"due",0},
    {"previousMovieMs",750.0},{"committedBefore",4},{"committedAfter",4}});
  std::ifstream stream(path); nlohmann::json row; stream >> row;
  assert(row.at("phase")==0 && row.at("markerAgeMs")==767.0 && row.at("due")==0);
  std::filesystem::remove(path);
}
