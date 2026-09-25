#include "kelpie/private_login_window.h"
namespace kelpie {
bool OpenPrivateLoginWindow(const std::string&,std::function<void()>) { return false; }
bool ClosePrivateLoginWindow() { return true; }
}
