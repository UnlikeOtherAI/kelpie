#pragma once
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <stdexcept>
#include <string>
#include <nlohmann/json.hpp>

namespace kelpie::connect {
struct JournalClock {
  static constexpr std::int64_t grace = 60 * 1000;
  static constexpr std::int64_t maxDeadline = 15 * 60 * 1000;
  static std::int64_t Now() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();
  }
  // Strict UTC ISO instant; arithmetic does not depend on process timezone or normalize invalid dates.
  static std::int64_t Deadline(const std::string& value) {
    if (value.size() < 20 || value.size() > 30 || value.back() != 'Z') throw std::invalid_argument("Invalid deadline");
    int year, month, day, hour, minute, second;
    if (std::sscanf(value.c_str(), "%4d-%2d-%2dT%2d:%2d:%2d", &year, &month, &day, &hour, &minute, &second) != 6)
      throw std::invalid_argument("Invalid deadline");
    for (std::size_t i = 0; i < 19; ++i) {
      const char expected = i == 4 || i == 7 ? '-' : i == 10 ? 'T' : i == 13 || i == 16 ? ':' : 0;
      if (expected ? value[i] != expected : value[i] < '0' || value[i] > '9') throw std::invalid_argument("Invalid deadline");
    }
    const bool leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    const int days[] = {31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    if (year < 1970 || month < 1 || month > 12 || day < 1 || day > days[month - 1] || hour > 23 || minute > 59 || second > 59)
      throw std::invalid_argument("Invalid deadline");
    int millis = 0;
    if (value.size() > 20) {
      if (value[19] != '.' || value.size() == 21) throw std::invalid_argument("Invalid deadline");
      for (std::size_t i = 20; i + 1 < value.size(); ++i) {
        if (value[i] < '0' || value[i] > '9') throw std::invalid_argument("Invalid deadline");
        if (i < 23) millis += (value[i] - '0') * (i == 20 ? 100 : i == 21 ? 10 : 1);
      }
    }
    // Proleptic Gregorian days since Unix epoch.
    const int adjusted = year - (month <= 2);
    const int era = adjusted / 400;
    const unsigned within = adjusted - era * 400;
    const unsigned doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1;
    const unsigned doe = within * 365 + within / 4 - within / 100 + doy;
    const auto epochDays = static_cast<std::int64_t>(era) * 146097 + doe - 719468;
    return ((epochDays * 24 + hour) * 60 * 60 + minute * 60 + second) * 1000 + millis;
  }
  static void Maintain(nlohmann::json& journal, std::int64_t wallClock) {
    if (wallClock < 0) throw std::invalid_argument("Invalid local time");
    const auto floor = std::max(wallClock, journal.value("retirementTime", std::int64_t{0}));
    journal["retirementTime"] = floor;
    auto& jobs = journal["jobs"];
    for (auto it = jobs.begin(); it != jobs.end();) {
      auto& job = it.value();
      if (!job.contains("retireAfter")) {
        const auto& command = job.at("command");
        job["retireAfter"] = command.contains("deadline") ? Deadline(command.at("deadline").get<std::string>()) + grace : floor + maxDeadline + grace;
      }
      if (job.value("acked", false) && job.value("terminal", false) && job["retireAfter"].get<std::int64_t>() <= floor) it = jobs.erase(it);
      else ++it;
    }
  }
};
}
