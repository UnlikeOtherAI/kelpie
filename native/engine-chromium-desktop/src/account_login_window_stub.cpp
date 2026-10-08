#include "kelpie/account_login_window.h"
namespace kelpie {
bool OpenAccountLoginWindow(const std::string&,std::function<void()>) { return false; }
bool CloseAccountLoginWindow() { return true; }
}
