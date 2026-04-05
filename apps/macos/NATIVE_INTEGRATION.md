# macOS Native Core Integration

This app now expects the shared C++ state C API to be visible to Swift through
`Kelpie/Kelpie-Bridging-Header.h`.

Do not hand-edit `apps/macos/Kelpie.xcodeproj/project.pbxproj`. This repo uses
XcodeGen, so make the equivalent build-setting changes in `apps/macos/project.yml`
and regenerate the project with `xcodegen generate`.

## 1. Build the native static libraries

Build the native targets so Xcode has these static libraries available:

- `libkelpie_core_state.a`
- `libkelpie_core_protocol.a`

`kelpie_core_state` links against `kelpie_core_protocol`, so both need to be
linked into the macOS app target.

## 2. Link the libraries into the `Kelpie` target

Add both `.a` files to the macOS app target's link phase. In Xcode this is the
equivalent of adding them to `Link Binary With Libraries`.

If you are expressing this through `apps/macos/project.yml`, add the libraries to
the `Kelpie` target instead of editing the generated `.xcodeproj` directly, then
run:

```sh
xcodegen generate
```

## 3. Add the native header search path

Append the core-state public headers to `HEADER_SEARCH_PATHS` for the `Kelpie`
target:

```text
$(PROJECT_DIR)/../native/core-state/include
```

Keep the existing CEF include path. The final setting should append the new path,
not replace the current one.

If your static libraries live outside the default linker search locations, also add
their output directory to `LIBRARY_SEARCH_PATHS`.

## 4. Keep the existing Swift bridging header

The macOS target already points at:

```text
Kelpie/Kelpie-Bridging-Header.h
```

That file now imports both headers:

```objc
#import "CEFBridge.h"
#import "kelpie/state_c_api.h"
```

Do not replace the bridging header with a new file. Keep the existing CEF import
and append the native state C API import.

## 5. Regenerate and build

After updating `apps/macos/project.yml`, regenerate the project and build the app:

```sh
xcodegen generate
xcodebuild -project apps/macos/Kelpie.xcodeproj -scheme Kelpie -configuration Debug build
```

If the bridging header import fails, the usual cause is a missing
`../native/core-state/include` entry in `HEADER_SEARCH_PATHS`.
