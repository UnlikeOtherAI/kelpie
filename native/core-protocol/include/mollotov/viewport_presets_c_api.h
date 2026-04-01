#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    MOLLOTOV_DEVICE_KIND_PHONE  = 0,
    MOLLOTOV_DEVICE_KIND_TABLET = 1
} MollotovDeviceKind;

typedef struct {
    const char*       id;
    const char*       name;
    const char*       label;
    const char*       menu_label;
    MollotovDeviceKind kind;
    const char*       display_size_label;
    const char*       pixel_resolution_label;
    float             portrait_width;
    float             portrait_height;
} MollotovViewportPreset;

/** Total number of built-in viewport presets (phones + tablets). */
int32_t mollotov_viewport_preset_count(void);

/**
 * Returns a pointer to the preset at @p index, or NULL if out of range.
 * The returned pointer is valid for the lifetime of the process — do not free it.
 */
const MollotovViewportPreset* mollotov_viewport_preset_get(int32_t index);

#ifdef __cplusplus
}
#endif
