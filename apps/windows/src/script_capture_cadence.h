#pragma once
namespace kelpie::windows {
// Milestone PNG requests must not increase the configured movie frame rate.
inline bool ScriptMovieFrameDue(double previous,double elapsed,int fps) {
  return previous<0 || elapsed-previous+0.000001>=1000.0/fps;
}
}
