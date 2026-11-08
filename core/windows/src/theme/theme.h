#pragma once

// The shell's visual system: colours, DPI-aware metrics, fonts, icon glyphs,
// and the antialiased drawing primitives every native surface paints with.
// Including this header gives a view or control everything it needs to look
// like the rest of the app, so no file reaches for a raw RGB value or a
// hardcoded pixel size.

#include "theme/icons.h"
#include "theme/metrics.h"
#include "theme/paint.h"
#include "theme/palette.h"
#include "theme/panels.h"
