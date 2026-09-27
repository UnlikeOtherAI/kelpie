#pragma once
#include <string>
namespace kelpie::account {
struct AccountState {
  bool signed_in=false, signing_in=false, busy=false;
  std::string name, email, avatar, error;
};
// Account control text shared by the desktop shells: identity, sign-in progress
// (including launch restore), favourites sync and the latest error.
inline std::string AccountLabel(const AccountState& state) {
  std::string label=state.signed_in ? state.email : state.signing_in ? "Signing in\xE2\x80\xA6" : "Login/register";
  if (state.signed_in && state.busy) label+=" \xE2\x80\x94 syncing";
  if (!state.error.empty()) label+=" \xE2\x80\x94 "+state.error;
  return label;
}
}
