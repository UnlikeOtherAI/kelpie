#!/bin/bash
# The native library test runner has no need for developer credentials.
set -euo pipefail
if [ "$#" -ne 2 ]; then echo "Usage: $0 <absolute-test-bundle.xctest> <class-or-test-selectors>" >&2; exit 2; fi
bundle="$1"
selectors="$2"
case "$bundle" in /*.xctest) ;; *) echo "Expected an absolute XCTest bundle path" >&2; exit 2 ;; esac
if [ ! -d "$bundle" ]; then echo "Test bundle does not exist" >&2; exit 2; fi
case "$selectors" in ''|*[!A-Za-z0-9_.,/]*) echo "Invalid XCTest selectors" >&2; exit 2 ;; esac
# Xcode's hosted Debug bundles reference the host's adjacent debug dylib.
host_libraries="$(dirname "$(dirname "$bundle")")/MacOS"
if [ ! -d "$host_libraries" ]; then host_libraries=''; fi
exec env -i DYLD_LIBRARY_PATH="$host_libraries" HOME="$HOME" USER="$(id -un)" LOGNAME="$(id -un)"     PATH=/usr/bin:/bin:/usr/sbin:/sbin     /usr/bin/xcrun xctest -XCTest "$selectors" "$bundle"
