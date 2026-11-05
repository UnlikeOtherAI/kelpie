#include "script_capture_service.h"
#include <cassert>
#include <fstream>
#include <iostream>

int main(int argc,char** argv) {
  assert(argc==2);
  const auto root=std::filesystem::path(argv[1]);
  assert(!std::filesystem::exists(root));
  assert(std::filesystem::create_directory(root));
  const auto owned=root/"owned.png",saved=root/"renamed-owned.png";
  {std::ofstream file(owned);file<<"owned";}
  const auto identity=kelpie::windows::CaptureFileIdentity(owned);
  std::filesystem::rename(owned,saved);
  {std::ofstream file(owned);file<<"replacement";}
  assert(kelpie::windows::RemoveCaptureFile(owned,identity));
  assert(std::filesystem::exists(owned));
  assert(std::filesystem::exists(saved));
  const auto replacement=kelpie::windows::CaptureFileIdentity(owned);
  assert(kelpie::windows::RemoveCaptureFile(saved,identity));
  assert(!std::filesystem::exists(saved));
  assert(kelpie::windows::RemoveCaptureFile(saved,identity));
  assert(kelpie::windows::RemoveCaptureFile(owned,replacement));
  assert(!std::filesystem::exists(owned));
  assert(std::filesystem::remove(root));
  std::cout<<"Exact file identity deletion and replacement preservation passed\n";
}
