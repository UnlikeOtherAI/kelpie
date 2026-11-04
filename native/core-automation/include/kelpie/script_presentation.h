#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KelpieScriptPoint {
  double x;
  double y;
} KelpieScriptPoint;

typedef struct KelpieScriptTapState {
  double scale;
  double alpha;
} KelpieScriptTapState;

/* Pure presentation only. These functions never generate input or hover events.
 * Progress clamps to [0,1]; NaN means 0. Non-positive duration means immediate end.
 * curve_s = 0 selects C; any other value selects S. */
double kelpie_script_progress(double elapsed_ms, double duration_ms);
KelpieScriptPoint kelpie_script_pointer_position(
    KelpieScriptPoint from, KelpieScriptPoint to, int curve_s, double progress);
KelpieScriptTapState kelpie_script_tap_presentation(
    double progress, int wobble, int fade);

#ifdef __cplusplus
}
#endif
