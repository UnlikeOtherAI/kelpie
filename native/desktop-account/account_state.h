#pragma once
#include <string>
namespace kelpie::account {
struct AccountState {
  bool signed_in=false, signing_in=false, busy=false;
  std::string name, email, avatar, error;
};
}
