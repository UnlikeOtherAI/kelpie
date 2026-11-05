#pragma once
namespace kelpie::linuxapp {
// Step screenshots share the sampler but never exceed the movie FPS ceiling.
inline bool ScriptMovieFrameDue(double previous_ms,double elapsed_ms,int fps) {
  return previous_ms < 0 || elapsed_ms - previous_ms + .000001 >= 1000.0 / fps;
}
}
