#pragma once

namespace kelpie::linuxapp {

class LinuxApp;

class GUIShell {
 public:
  explicit GUIShell(LinuxApp& app);

  int Run();

 private:
  LinuxApp& app_;
};

}  // namespace kelpie::linuxapp
