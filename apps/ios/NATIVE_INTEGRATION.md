# iOS Native Core Integration

The iOS store wrappers in `apps/ios/Kelpie/Browser/` now call the shared C API from `native/core-state/include/kelpie/state_c_api.h`.

The Xcode project is not updated automatically. Do not edit `project.pbxproj` by hand unless you have to. Configure the target in Xcode instead.

## 1. Set the bridging header

For the `Kelpie` target, set:

- `Objective-C Bridging Header` = `$(PROJECT_DIR)/Kelpie/Kelpie-Bridging-Header.h`

The header itself is already in the repo at:

- `apps/ios/Kelpie/Kelpie-Bridging-Header.h`

## 2. Add header search paths

For the `Kelpie` target, add these to `Header Search Paths`:

- `$(SRCROOT)/../native/core-state/include`
- `$(SRCROOT)/../native/core-protocol/include`

Mark them `recursive = No`.

Notes:

- `$(SRCROOT)` here is `apps/ios`.
- The bridging header imports `kelpie/state_c_api.h`, so `native/core-state/include` must be visible to Clang.
- `libkelpie_core_state.a` depends on `libkelpie_core_protocol.a`, so both headers and both libraries must be configured together.

## 3. Add the static libraries

Add these files to the `Kelpie` target and ensure they are linked in `Link Binary With Libraries`:

- `/tmp/kelpie-build/core-protocol/libkelpie_core_protocol.a`
- `/tmp/kelpie-build/core-state/libkelpie_core_state.a`

If you prefer search paths instead of direct file references, add these to `Library Search Paths`:

- `/tmp/kelpie-build/core-protocol`
- `/tmp/kelpie-build/core-state`

Then add:

- `libkelpie_core_protocol.a`
- `libkelpie_core_state.a`

## 4. Keep the wrapper expectations in mind

The Swift stores assume:

- `kelpie/state_c_api.h` is visible through the bridging header
- both static libraries are linked into the app target
- bookmark and history continue using the existing UserDefaults keys
- network traffic persists under `kelpie_network_traffic` because there was no previous iOS persistence key for that store

## 5. Rebuild after wiring

After the target settings are updated, rebuild the iOS app in Xcode. The store files will not compile until the bridging header and static libraries are configured.
