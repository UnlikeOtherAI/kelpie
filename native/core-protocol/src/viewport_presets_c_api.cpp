#include "mollotov/viewport_presets_c_api.h"

// clang-format off
static const MollotovViewportPreset kPresets[] = {
    // ── Phones ───────────────────────────────────────────────────────────────
    { "compact-base",       "Compact / Base",        "Compact",  "6.1\" Compact",     MOLLOTOV_DEVICE_KIND_PHONE,  "6.1\" - 6.3\"", "1170 x 2532 - 1206 x 2622",  393,  852  },
    { "standard-pro",       "Standard / Pro",        "Standard", "6.2\" Standard",    MOLLOTOV_DEVICE_KIND_PHONE,  "6.2\" - 6.4\"", "1080 x 2340 - 1280 x 2856",  402,  874  },
    { "large-plus",         "Large / Plus",          "Large",    "6.7\" Large",       MOLLOTOV_DEVICE_KIND_PHONE,  "6.5\" - 6.7\"", "1260 x 2736 - 1440 x 3120",  430,  932  },
    { "ultra-pro-max",      "Ultra / Pro Max",       "Ultra",    "6.8\" Ultra",       MOLLOTOV_DEVICE_KIND_PHONE,  "6.8\" - 6.9\"", "1320 x 2868 - 1440 x 3120",  440,  956  },
    { "book-fold-internal", "Book Fold (Internal)",  "Book In",  "7.6\" Book Fold",   MOLLOTOV_DEVICE_KIND_PHONE,  "7.6\" - 8.0\"", "2076 x 2152 - 2160 x 2440",  904, 1136  },
    { "book-fold-cover",    "Book Fold (Cover)",     "Book C",   "6.3\" Book Cover",  MOLLOTOV_DEVICE_KIND_PHONE,  "6.3\" - 6.5\"", "1080 x 2364 - 1116 x 2484",  360,  800  },
    { "flip-fold-internal", "Flip Fold (Internal)",  "Flip In",  "6.7\" Flip Fold",   MOLLOTOV_DEVICE_KIND_PHONE,  "6.7\" - 6.9\"", "1080 x 2640 - 1200 x 2844",  412,  914  },
    { "flip-fold-cover",    "Flip Fold (Cover)",     "Flip C",   "3.4\" Flip Cover",  MOLLOTOV_DEVICE_KIND_PHONE,  "3.4\" - 4.1\"", "720 x 748 - 1056 x 1066",    360,  380  },
    { "tri-fold-internal",  "Tri-Fold (Internal)",   "Tri",      "10\" Tri-Fold",     MOLLOTOV_DEVICE_KIND_PHONE,  "~10.0\"",       "2800 x 3200",                 980, 1120  },
    // ── Tablets ──────────────────────────────────────────────────────────────
    { "ipad-mini",          "iPad mini",             "mini",     "8.3\" iPad mini",   MOLLOTOV_DEVICE_KIND_TABLET, "8.3\"",         "1488 x 2266",                 744, 1133  },
    { "ipad-10",            "iPad 10.9\"",           "iPad",     "10.9\" iPad",       MOLLOTOV_DEVICE_KIND_TABLET, "10.9\"",        "1640 x 2360",                 820, 1180  },
    { "ipad-pro-11",        "iPad Pro 11\"",         "Pro 11",   "11\" iPad Pro",     MOLLOTOV_DEVICE_KIND_TABLET, "11\"",          "1668 x 2388",                 834, 1194  },
    { "ipad-air-13",        "iPad Air 13\"",         "Air 13",   "13\" iPad Air",     MOLLOTOV_DEVICE_KIND_TABLET, "13\"",          "2048 x 2732",                1024, 1366  },
    { "ipad-pro-13",        "iPad Pro 13\"",         "Pro 13",   "13\" iPad Pro",     MOLLOTOV_DEVICE_KIND_TABLET, "13\"",          "2064 x 2752",                1032, 1376  },
    { "tab-s-11",           "Galaxy Tab S 11\"",     "Tab 11",   "11\" Galaxy Tab S", MOLLOTOV_DEVICE_KIND_TABLET, "11\"",          "1600 x 2560",                 800, 1280  },
    { "tab-s-12",           "Galaxy Tab S 12.4\"",   "Tab 12",   "12.4\" Galaxy Tab", MOLLOTOV_DEVICE_KIND_TABLET, "12.4\"",        "1752 x 2800",                 840, 1344  },
};
// clang-format on

static const int32_t kPresetCount =
    static_cast<int32_t>(sizeof(kPresets) / sizeof(kPresets[0]));

int32_t mollotov_viewport_preset_count(void) {
    return kPresetCount;
}

const MollotovViewportPreset* mollotov_viewport_preset_get(int32_t index) {
    if (index < 0 || index >= kPresetCount) return nullptr;
    return &kPresets[index];
}
