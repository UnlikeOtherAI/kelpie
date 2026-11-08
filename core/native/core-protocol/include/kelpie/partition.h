#pragma once

#include <cstddef>
#include <string>
#include <string_view>

namespace kelpie {

// The native mirror of `packages/shared/src/partition.ts`. Every consumer of a
// partition identifier — HTTP handlers, the session snapshot parser, the native
// shell — validates through this one function, so a string the CLI accepts is a
// string the device accepts.
//
// Keep this file and the TypeScript original in lockstep. A validator that
// drifts lets a caller create a partition on one platform that another rejects.

/** Maximum length of a partition identifier, in ASCII characters. */
inline constexpr std::size_t kMaxPartitionLength = 128;

/** Maximum length of the free-form per-tab display `name`. */
inline constexpr std::size_t kMaxTabNameLength = 200;

/**
 * Reserved internal prefix. Android's non-persistent emulation creates
 * profiles named `ephemeral-<partition>-<uuid>`; a user-supplied string
 * starting with the same prefix could collide with one of those.
 */
inline constexpr std::string_view kReservedPartitionPrefix = "ephemeral-";

/** Machine-actionable discriminator for why a partition string was rejected. */
enum class PartitionInvalidReason {
  kCharsetOrLength,
  kNoAlnum,
  kReserved,
  kReservedPrefix,
};

struct PartitionValidation {
  bool ok = false;
  PartitionInvalidReason reason = PartitionInvalidReason::kCharsetOrLength;
};

/**
 * Validate a partition identifier.
 *
 * Accepts 1-128 ASCII characters drawn from `[A-Za-z0-9._-]`, containing at
 * least one alphanumeric, that is neither a reserved word (`.`, `..`,
 * `default` — case-insensitive) nor prefixed with `ephemeral-`.
 */
PartitionValidation ValidatePartition(std::string_view value);

/** Convenience predicate for callers that do not need the failure reason. */
bool IsValidPartition(std::string_view value);

/** Wire name of a rejection reason, matching the TypeScript union members. */
const char* PartitionInvalidReasonName(PartitionInvalidReason reason);

/** Human-readable explanation for a rejection, reused by HTTP error bodies. */
std::string PartitionErrorMessage(PartitionInvalidReason reason);

}  // namespace kelpie
