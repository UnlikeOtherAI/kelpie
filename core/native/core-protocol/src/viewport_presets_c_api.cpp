#include "kelpie/viewport_presets_c_api.h"

// clang-format off
static const KelpieViewportPreset kPresets[] = {
    // ── Phones ───────────────────────────────────────────────────────────────
    // portraitSize = CSS viewport pixels (portrait_width x portrait_height)
    // pixelResolutionLabel = CSS viewport dimensions shown in UI
    { "flip-fold-cover",    "Flip Fold (Cover)",     "Flip C",   "3.4\" Flip Cover",  KELPIE_DEVICE_KIND_PHONE,  "3.4\"", "360 x 380",   360,  380  },
    { "book-fold-cover",    "Book Fold (Cover)",     "Book C",   "6.3\" Book Cover",  KELPIE_DEVICE_KIND_PHONE,  "6.3\"", "360 x 800",   360,  800  },
    { "compact-base",       "Compact / Base",        "Compact",  "6.1\" Compact",     KELPIE_DEVICE_KIND_PHONE,  "6.1\"", "393 x 852",   393,  852  },
    { "standard-pro",       "Standard / Pro",        "Standard", "6.2\" Standard",    KELPIE_DEVICE_KIND_PHONE,  "6.2\"", "402 x 874",   402,  874  },
    { "flip-fold-internal", "Flip Fold (Internal)",  "Flip In",  "6.7\" Flip Fold",   KELPIE_DEVICE_KIND_PHONE,  "6.7\"", "412 x 914",   412,  914  },
    { "large-plus",         "Large / Plus",          "Large",    "6.7\" Large",       KELPIE_DEVICE_KIND_PHONE,  "6.7\"", "430 x 932",   430,  932  },
    { "ultra-pro-max",      "Ultra / Pro Max",       "Ultra",    "6.8\" Ultra",       KELPIE_DEVICE_KIND_PHONE,  "6.8\"", "440 x 956",   440,  956  },
    { "book-fold-internal", "Book Fold (Internal)",  "Book In",  "7.6\" Book Fold",   KELPIE_DEVICE_KIND_PHONE,  "7.6\"", "904 x 1136",  904, 1136  },
    { "tri-fold-internal",  "Tri-Fold (Internal)",   "Tri",      "10\" Tri-Fold",     KELPIE_DEVICE_KIND_PHONE, "~10.0\"", "980 x 1120",  980, 1120  },
    // ── Tablets ──────────────────────────────────────────────────────────────
    { "ipad-mini",          "iPad mini",             "mini",     "8.3\" iPad mini",   KELPIE_DEVICE_KIND_TABLET,  "8.3\"",  "744 x 1133",   744, 1133  },
    { "tab-s-11",           "Galaxy Tab S 11\"",     "Tab 11",   "11\" Galaxy Tab S", KELPIE_DEVICE_KIND_TABLET, "11\"",   "800 x 1280",   800, 1280  },
    { "ipad-10",            "iPad 10.9\"",           "iPad",     "10.9\" iPad",       KELPIE_DEVICE_KIND_TABLET, "10.9\"", "820 x 1180",   820, 1180  },
    { "ipad-pro-11",        "iPad Pro 11\"",         "Pro 11",   "11\" iPad Pro",     KELPIE_DEVICE_KIND_TABLET, "11\"",   "834 x 1194",   834, 1194  },
    { "tab-s-12",           "Galaxy Tab S 12.4\"",   "Tab 12",   "12.4\" Galaxy Tab", KELPIE_DEVICE_KIND_TABLET, "12.4\"", "840 x 1344",   840, 1344  },
    { "ipad-air-13",        "iPad Air 13\"",         "Air 13",   "13\" iPad Air",     KELPIE_DEVICE_KIND_TABLET, "13\"",   "1024 x 1366", 1024, 1366  },
    { "ipad-pro-13",        "iPad Pro 13\"",         "Pro 13",   "13\" iPad Pro",     KELPIE_DEVICE_KIND_TABLET, "13\"",   "1032 x 1376", 1032, 1376  },
    // ── Laptops ──────────────────────────────────────────────────────────────
    // portraitSize stores (short, long) — landscape flips to (long, short)
    { "laptop-13", "13\" Laptop", "13\"",  "13\" Laptop", KELPIE_DEVICE_KIND_LAPTOP, "13\"", "1280 x 800",   800, 1280 },
    { "laptop-15", "15\" Laptop", "15\"",  "15\" Laptop", KELPIE_DEVICE_KIND_LAPTOP, "15\"", "1440 x 900",   900, 1440 },
    { "laptop-16", "16\" Laptop", "16\"",  "16\" Laptop", KELPIE_DEVICE_KIND_LAPTOP, "16\"", "1728 x 1117", 1117, 1728 },
};
// clang-format on

static const int32_t kPresetCount =
    static_cast<int32_t>(sizeof(kPresets) / sizeof(kPresets[0]));

int32_t kelpie_viewport_preset_count(void) {
    return kPresetCount;
}

const KelpieViewportPreset* kelpie_viewport_preset_get(int32_t index) {
    if (index < 0 || index >= kPresetCount) return nullptr;
    return &kPresets[index];
}
