#pragma once

#include <cstddef>

#include <nlohmann/json.hpp>

// The ceiling `kelpie_get_page_text` has on the app's own /mcp, matching the
// CLI's MCP server (packages/cli/src/mcp/page-text-limit.ts) so the two MCP
// surfaces return the same result. A real article's readable text runs to tens
// of kilobytes, which an agent rarely needs in one piece and which an
// integrator's result cap may refuse outright. The HTTP API stays unbounded.
namespace kelpie::desktop_mcp {

inline constexpr std::size_t kDefaultPageTextMaxChars = 20000;

// Cuts a successful get-page-text body's `text` to at most `max_chars`
// characters and adds `truncated`, plus `totalChars` and a `note` when it cut.
// Characters are UTF-16 code units, as JavaScript counts them, so the CLI and
// this server agree on every length; a character outside the Basic
// Multilingual Plane is two, and is never split.
nlohmann::json LimitPageText(nlohmann::json body, std::size_t max_chars);

}  // namespace kelpie::desktop_mcp
