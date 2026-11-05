#include "../../apps/macos/Kelpie/Renderer/ScriptCaptureSourceLimits.h"
#include <cassert>
#include <limits>

int main() {
    using namespace kelpie_mac_capture;
    assert(AdmitsSource(3840, 2160));
    assert(AdmitsSource(8192, 1024));
    assert(!AdmitsSource(8192, 1025));
    assert(!AdmitsSource(8192.01, 100));
    assert(!AdmitsSource(1, 200));
    assert(!AdmitsSource(0, 200));
    assert(!AdmitsSource(std::numeric_limits<double>::infinity(), 200));
    assert(!AdmitsSource(std::numeric_limits<double>::quiet_NaN(), 200));
    assert(kMaximumPngBytes >= kMaximumSourcePixels * 8 + 4 * 1024 * 1024);
    assert(kMaximumBase64Characters == ((kMaximumPngBytes + 2) / 3) * 4);
}
