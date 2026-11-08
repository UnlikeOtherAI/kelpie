#pragma once

#include <sstream>
#include <string>

namespace kelpie {

inline std::string JsStringLiteral(const std::string& value) {
  std::ostringstream escaped;
  escaped << '"';
  for (const char ch : value) {
    switch (ch) {
      case '\\':
        escaped << "\\\\";
        break;
      case '"':
        escaped << "\\\"";
        break;
      case '\n':
        escaped << "\\n";
        break;
      case '\r':
        escaped << "\\r";
        break;
      case '\t':
        escaped << "\\t";
        break;
      default:
        escaped << ch;
        break;
    }
  }
  escaped << '"';
  return escaped.str();
}

}  // namespace kelpie
