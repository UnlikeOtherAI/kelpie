#include <cassert>
#include <string>

#include "kelpie/error_codes.h"
#include "kelpie/partition.h"

namespace {

using kelpie::PartitionInvalidReason;

void AcceptsOrdinaryIdentifiers() {
  assert(kelpie::IsValidPartition("sam.eng-lead"));
  assert(kelpie::IsValidPartition("a"));
  assert(kelpie::IsValidPartition("A_1"));
  assert(kelpie::IsValidPartition("work-2"));
  assert(kelpie::IsValidPartition(std::string(kelpie::kMaxPartitionLength, 'x')));
}

void RejectsCharsetAndLength() {
  const auto empty = kelpie::ValidatePartition("");
  assert(!empty.ok && empty.reason == PartitionInvalidReason::kCharsetOrLength);
  const auto too_long = kelpie::ValidatePartition(std::string(kelpie::kMaxPartitionLength + 1, 'x'));
  assert(!too_long.ok && too_long.reason == PartitionInvalidReason::kCharsetOrLength);
  // Path separators are the reason a directory name can be derived safely.
  assert(!kelpie::IsValidPartition("a/b"));
  assert(!kelpie::IsValidPartition("a\b"));
  assert(!kelpie::IsValidPartition("a b"));
  assert(!kelpie::IsValidPartition("caf\xc3\xa9"));
}

void RejectsPunctuationOnly() {
  const auto dots = kelpie::ValidatePartition("...");
  assert(!dots.ok && dots.reason == PartitionInvalidReason::kNoAlnum);
  const auto dashes = kelpie::ValidatePartition("-_-");
  assert(!dashes.ok && dashes.reason == PartitionInvalidReason::kNoAlnum);
}

void RejectsReservedWords() {
  for (const char* value : {".", "..", "default", "DEFAULT", "Default"}) {
    const auto result = kelpie::ValidatePartition(value);
    assert(!result.ok);
    // "." and ".." have no alphanumeric at all, so they are rejected earlier.
    assert(result.reason == PartitionInvalidReason::kReserved ||
           result.reason == PartitionInvalidReason::kNoAlnum);
  }
  const auto named = kelpie::ValidatePartition("default");
  assert(!named.ok && named.reason == PartitionInvalidReason::kReserved);
}

void RejectsReservedPrefix() {
  const auto result = kelpie::ValidatePartition("ephemeral-42");
  assert(!result.ok && result.reason == PartitionInvalidReason::kReservedPrefix);
  // The prefix is case-sensitive, matching the TypeScript validator.
  assert(kelpie::IsValidPartition("Ephemeral-42"));
}

void ReportsReasonsAndMessages() {
  assert(std::string(kelpie::PartitionInvalidReasonName(PartitionInvalidReason::kNoAlnum)) ==
         "no-alnum");
  assert(std::string(kelpie::PartitionInvalidReasonName(PartitionInvalidReason::kReservedPrefix)) ==
         "reserved-prefix");
  assert(!kelpie::PartitionErrorMessage(PartitionInvalidReason::kReserved).empty());
}

void MapsPartitionErrorCodes() {
  assert(std::string(kelpie::ErrorCodeToString(kelpie::ErrorCode::kInvalidPartition)) ==
         "INVALID_PARTITION");
  assert(kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kInvalidPartition) == 400);
  assert(kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kPartitionUnsupported) == 501);
  assert(kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kPartitionDeleting) == 409);
  assert(kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kPartitionInUse) == 409);
  assert(kelpie::ErrorCodeFromString("PARTITION_DELETING") == kelpie::ErrorCode::kPartitionDeleting);
}

}  // namespace

int main() {
  AcceptsOrdinaryIdentifiers();
  RejectsCharsetAndLength();
  RejectsPunctuationOnly();
  RejectsReservedWords();
  RejectsReservedPrefix();
  ReportsReasonsAndMessages();
  MapsPartitionErrorCodes();
  return 0;
}
