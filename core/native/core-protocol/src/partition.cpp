#include "kelpie/partition.h"

#include <algorithm>
#include <cctype>

namespace kelpie {
namespace {

bool IsAllowedCharacter(char value) {
  const auto ch = static_cast<unsigned char>(value);
  return (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') ||
      ch == '.' || ch == '_' || ch == '-';
}

bool IsAlphanumeric(char value) {
  const auto ch = static_cast<unsigned char>(value);
  return (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9');
}

std::string ToLowerAscii(std::string_view value) {
  std::string lowered(value);
  std::transform(lowered.begin(), lowered.end(), lowered.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return lowered;
}

bool IsReserved(std::string_view value) {
  const std::string lowered = ToLowerAscii(value);
  return lowered == "." || lowered == ".." || lowered == "default";
}

}  // namespace

PartitionValidation ValidatePartition(std::string_view value) {
  if (value.empty() || value.size() > kMaxPartitionLength ||
      !std::all_of(value.begin(), value.end(), IsAllowedCharacter)) {
    return {false, PartitionInvalidReason::kCharsetOrLength};
  }
  if (std::none_of(value.begin(), value.end(), IsAlphanumeric)) {
    return {false, PartitionInvalidReason::kNoAlnum};
  }
  if (IsReserved(value)) return {false, PartitionInvalidReason::kReserved};
  if (value.rfind(kReservedPartitionPrefix, 0) == 0) {
    return {false, PartitionInvalidReason::kReservedPrefix};
  }
  return {true, PartitionInvalidReason::kCharsetOrLength};
}

bool IsValidPartition(std::string_view value) {
  return ValidatePartition(value).ok;
}

const char* PartitionInvalidReasonName(PartitionInvalidReason reason) {
  switch (reason) {
    case PartitionInvalidReason::kCharsetOrLength:
      return "charset-or-length";
    case PartitionInvalidReason::kNoAlnum:
      return "no-alnum";
    case PartitionInvalidReason::kReserved:
      return "reserved";
    case PartitionInvalidReason::kReservedPrefix:
      return "reserved-prefix";
  }
  return "charset-or-length";
}

std::string PartitionErrorMessage(PartitionInvalidReason reason) {
  switch (reason) {
    case PartitionInvalidReason::kCharsetOrLength:
      return "partition must be 1-128 characters from [A-Za-z0-9._-]";
    case PartitionInvalidReason::kNoAlnum:
      return "partition must contain at least one letter or digit";
    case PartitionInvalidReason::kReserved:
      return "partition must not be \".\", \"..\" or \"default\" (case-insensitive)";
    case PartitionInvalidReason::kReservedPrefix:
      return "partition must not start with \"ephemeral-\" (reserved internal prefix)";
  }
  return "partition is invalid";
}

}  // namespace kelpie
