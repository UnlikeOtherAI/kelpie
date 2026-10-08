#include "http_server.h"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#include <algorithm>
#include <cctype>
#include <cerrno>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string_view>
#include <vector>

namespace kelpie::linuxapp {
namespace {

using json = nlohmann::json;

std::string HttpStatusText(int status) {
  switch (status) {
    case 200:
      return "OK";
    case 204:
      return "No Content";
    case 400:
      return "Bad Request";
    case 401:
      return "Unauthorized";
    case 404:
      return "Not Found";
    case 405:
      return "Method Not Allowed";
    case 500:
      return "Internal Server Error";
    case 501:
      return "Not Implemented";
    case 503:
      return "Service Unavailable";
    default:
      return "Error";
  }
}

std::string TextResponse(int status, std::string_view body, std::string_view content_type) {
  std::ostringstream stream;
  stream << "HTTP/1.1 " << status << ' ' << HttpStatusText(status) << "\r\n"
         << "Content-Type: " << content_type << "\r\n"
         << "Content-Length: " << body.size() << "\r\n"
         << "Connection: close\r\n\r\n"
         << body;
  return stream.str();
}

std::string JsonResponse(int status, const json& payload) {
  const std::string body = payload.dump();
  return TextResponse(status, body, "application/json");
}

std::filesystem::path CurrentExecutablePath() {
  std::error_code error;
  const std::filesystem::path path = std::filesystem::read_symlink("/proc/self/exe", error);
  return error ? std::filesystem::path() : path;
}

std::filesystem::path CoordinateCalibrationPagePath() {
  return CurrentExecutablePath().parent_path() / "diagnostics" / "coordinate-calibration.html";
}

std::string ReadFile(const std::filesystem::path& path) {
  std::ifstream stream(path);
  if (!stream.good()) {
    return std::string();
  }
  std::ostringstream buffer;
  buffer << stream.rdbuf();
  return buffer.str();
}

std::string ReadRequest(int fd) {
  std::string request;
  char buffer[4096];
  std::size_t expected_total = 0;
  while (true) {
    const ssize_t read_bytes = recv(fd, buffer, sizeof(buffer), 0);
    if (read_bytes <= 0) {
      break;
    }
    request.append(buffer, static_cast<std::size_t>(read_bytes));

    const std::size_t header_end = request.find("\r\n\r\n");
    if (header_end == std::string::npos) {
      continue;
    }
    if (expected_total == 0) {
      const std::string_view headers(request.data(), header_end);
      const std::string marker = "Content-Length:";
      const std::size_t pos = headers.find(marker);
      std::size_t body_size = 0;
      if (pos != std::string::npos) {
        const std::size_t value_start = headers.find_first_not_of(' ', pos + marker.size());
        const std::size_t value_end = headers.find("\r\n", value_start);
        body_size = static_cast<std::size_t>(
            std::max(0, std::atoi(request.substr(value_start, value_end - value_start).c_str())));
      }
      expected_total = header_end + 4 + body_size;
    }
    if (expected_total != 0 && request.size() >= expected_total) {
      break;
    }
  }
  return request;
}

json ParseJsonBody(const std::string& request) {
  const std::size_t header_end = request.find("\r\n\r\n");
  if (header_end == std::string::npos) {
    return json::object();
  }
  const std::string body = request.substr(header_end + 4);
  if (body.empty()) {
    return json::object();
  }
  try {
    return json::parse(body);
  } catch (const json::parse_error&) {
    return json::object();
  }
}

/** Every `Authorization` header value in the request head (case-insensitive name). */
std::vector<std::string> AuthorizationValues(const std::string& request) {
  std::vector<std::string> values;
  const std::size_t header_end = request.find("\r\n\r\n");
  std::istringstream lines(request.substr(0, header_end));
  std::string line;
  std::getline(lines, line);  // request line
  while (std::getline(lines, line)) {
    if (!line.empty() && line.back() == '\r') line.pop_back();
    const std::size_t colon = line.find(':');
    if (colon == std::string::npos) continue;
    std::string name = line.substr(0, colon);
    std::transform(name.begin(), name.end(), name.begin(), [](unsigned char c) { return std::tolower(c); });
    if (name != "authorization") continue;
    const std::size_t start = line.find_first_not_of(' ', colon + 1);
    values.push_back(start == std::string::npos ? std::string() : line.substr(start));
  }
  return values;
}

bool ConstantTimeEqual(std::string_view lhs, std::string_view rhs) {
  if (lhs.size() != rhs.size()) return false;
  unsigned char diff = 0;
  for (std::size_t i = 0; i < lhs.size(); ++i) {
    diff |= static_cast<unsigned char>(lhs[i] ^ rhs[i]);
  }
  return diff == 0;
}

/** True when the request carries exactly one `Bearer <token>` header. */
bool HasControlToken(const std::string& request, const std::string& token) {
  const std::vector<std::string> values = AuthorizationValues(request);
  if (token.empty() || values.size() != 1) return false;
  constexpr std::string_view scheme = "bearer ";
  const std::string& value = values.front();
  if (value.size() <= scheme.size()) return false;
  for (std::size_t i = 0; i < scheme.size(); ++i) {
    if (std::tolower(static_cast<unsigned char>(value[i])) != scheme[i]) return false;
  }
  return ConstantTimeEqual(std::string_view(value).substr(scheme.size()), token);
}

}  // namespace

HttpServer::HttpServer() = default;

HttpServer::~HttpServer() {
  Stop();
}

bool HttpServer::Start(int preferred_port, std::string control_token, RequestHandler handler,
                       std::string* error) {
  if (running_) {
    return true;
  }
  if (control_token.empty()) {
    if (error != nullptr) {
      *error = "A control token is required";
    }
    return false;
  }
  control_token_ = std::move(control_token);
  handler_ = std::move(handler);
  if (!Bind(preferred_port, error)) {
    return false;
  }

  running_ = true;
  thread_ = std::thread([this]() { AcceptLoop(); });
  return true;
}

void HttpServer::Stop() {
  if (!running_) {
    return;
  }

  running_ = false;
  if (server_fd_ >= 0) {
    shutdown(server_fd_, SHUT_RDWR);
    close(server_fd_);
    server_fd_ = -1;
  }
  if (thread_.joinable()) {
    thread_.join();
  }
}

bool HttpServer::running() const {
  return running_;
}

int HttpServer::port() const {
  return port_;
}

bool HttpServer::Bind(int preferred_port, std::string* error) {
  server_fd_ = socket(AF_INET, SOCK_STREAM, 0);
  if (server_fd_ < 0) {
    if (error != nullptr) {
      *error = std::strerror(errno);
    }
    return false;
  }

  int option = 1;
  setsockopt(server_fd_, SOL_SOCKET, SO_REUSEADDR, &option, sizeof(option));

  sockaddr_in address{};
  address.sin_family = AF_INET;
  // Loopback only: the control API is never reachable from the network.
  address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

  for (int candidate = preferred_port; candidate < preferred_port + 50; ++candidate) {
    address.sin_port = htons(static_cast<std::uint16_t>(candidate));
    if (bind(server_fd_, reinterpret_cast<sockaddr*>(&address), sizeof(address)) == 0) {
      port_ = candidate;
      if (listen(server_fd_, 16) == 0) {
        return true;
      }
      break;
    }
  }

  if (error != nullptr) {
    *error = std::strerror(errno);
  }
  close(server_fd_);
  server_fd_ = -1;
  return false;
}

void HttpServer::AcceptLoop() {
  while (running_) {
    sockaddr_in client_address{};
    socklen_t client_length = sizeof(client_address);
    const int client_fd =
        accept(server_fd_, reinterpret_cast<sockaddr*>(&client_address), &client_length);
    if (client_fd < 0) {
      continue;
    }

    const std::string request = ReadRequest(client_fd);
    std::istringstream stream(request);
    std::string method;
    std::string path;
    stream >> method >> path;

    int status = 200;
    std::string response;
    if (method == "GET" && path == "/health") {
      response = JsonResponse(200, {{"status", "ok"}});
    } else if (method == "GET" && path == "/debug/coordinate-calibration") {
      const std::string page = ReadFile(CoordinateCalibrationPagePath());
      if (page.empty()) {
        status = 500;
        response = JsonResponse(
            status,
            {
                {"success", false},
                {"error", {{"code", "INTERNAL_ERROR"},
                           {"message", "Coordinate calibration page missing from build output"}}},
            });
      } else {
        response = TextResponse(200, page, "text/html; charset=utf-8");
      }
    } else if (method == "POST" && path.rfind("/v1/", 0) == 0 && !HasControlToken(request, control_token_)) {
      status = 401;
      response = JsonResponse(status, {
          {"success", false},
          {"error", {{"code", "UNAUTHORIZED"}, {"message", "Authentication required"}}},
      });
    } else if (method == "POST" && path.rfind("/v1/", 0) == 0) {
      const json body = ParseJsonBody(request);
      const json payload = handler_ != nullptr ? handler_(path.substr(4), body, &status) : json::object();
      response = JsonResponse(status, payload);
    } else if (method == "GET" && path == "/mcp") {
      status = 501;
      response = JsonResponse(status, {
          {"success", false},
          {"error", {{"code", "PLATFORM_NOT_SUPPORTED"}, {"message", "MCP HTTP is not implemented yet"}}},
      });
    } else {
      status = method == "GET" || method == "POST" ? 404 : 405;
      response = JsonResponse(status, {
          {"success", false},
          {"error", {{"code", "NOT_FOUND"}, {"message", "Unknown route"}}},
      });
    }

    send(client_fd, response.data(), response.size(), 0);
    shutdown(client_fd, SHUT_RDWR);
    close(client_fd);
  }
}

}  // namespace kelpie::linuxapp
