#pragma once

#include <stddef.h>

#ifdef __cplusplus
#include <string>
#include <string_view>

namespace kelpie {
// Resolves user-entered address-bar text only. Automation URLs bypass this policy.
std::string ResolveAddressInput(std::string_view input);
}
extern "C" {
#endif

// Returns the required UTF-8 buffer size, including NUL. Writes only when it fits.
size_t kelpie_resolve_address_input(const char* input, char* output, size_t capacity);

#ifdef __cplusplus
}
#endif
