#include "standalone_instance.h"

#include <cassert>
#include <csignal>
#include <sys/wait.h>

using kelpie::linuxapp::StandaloneInstance;

int main() {
  const std::string name = "Kelpie.Standalone.Test." + std::to_string(getpid());
  {
    StandaloneInstance first(name);
    assert(first.error() == 0);
    StandaloneInstance other_profile(name);
    assert(other_profile.error() == EADDRINUSE);
  }
  {
    StandaloneInstance next(name);
    assert(next.error() == 0);
  }

  int ready[2];
  assert(pipe(ready) == 0);
  const pid_t child = fork();
  assert(child >= 0);
  if (child == 0) {
    close(ready[0]);
    StandaloneInstance instance(name);
    const char result = instance.error() == 0 ? 'y' : 'n';
    assert(write(ready[1], &result, 1) == 1);
    pause();
    _exit(1);
  }
  close(ready[1]);
  char result = 0;
  assert(read(ready[0], &result, 1) == 1 && result == 'y');
  close(ready[0]);
  {
    StandaloneInstance contender(name);
    assert(contender.error() == EADDRINUSE);
  }
  assert(kill(child, SIGKILL) == 0);
  int status = 0;
  assert(waitpid(child, &status, 0) == child && WIFSIGNALED(status));
  StandaloneInstance recovered(name);
  assert(recovered.error() == 0);
}
