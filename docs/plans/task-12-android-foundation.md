# Task 12: Android App Foundation — Project + UI + WebView + CDP + Network

**Component:** Android
**Depends on:** Task 01
**Estimated size:** ~800 lines

## Goal

Create the complete Android app foundation: Android Studio project, Jetpack Compose browser UI, WebView with CDP enabled, Ktor embedded HTTP server, NsdManager mDNS advertisement, and AppReveal debug integration.

## Files to Create

```
apps/android/
  build.gradle.kts                          # Project-level
  settings.gradle.kts
  gradle.properties
  app/
    build.gradle.kts                        # App-level (dependencies, AppReveal debug/noop)
    src/
      main/
        AndroidManifest.xml                 # Permissions, network config
        java/com/kelpie/browser/
          KelpieApp.kt                    # Application class
          MainActivity.kt                   # Single activity host

          ui/
            BrowserScreen.kt               # Main Compose screen (URL bar + WebView)
            SettingsScreen.kt              # Settings panel (IP, port, mDNS, QR code)
            URLBar.kt                      # URL bar composable
            theme/
              Theme.kt                     # Material 3 theme

          browser/
            WebViewContainer.kt            # WebView + CDP wrapper
            BrowserState.kt               # StateFlow: URL, title, loading, history

          network/
            HTTPServer.kt                  # Ktor embedded server
            Router.kt                      # Route registration and dispatch
            MDNSAdvertiser.kt              # NsdManager service registration

          device/
            DeviceIdentity.kt              # Stable UUID (SharedPreferences + fallback)
            DeviceInfo.kt                  # Collect device metadata

      debug/
        java/com/kelpie/browser/debug/
          AppRevealSetup.kt               # AppReveal.start() in debug
```

## Steps

### 1. Android Studio Project

- Min SDK: 28 (Android 9)
- Target SDK: 34
- Kotlin 1.9+, Java 17
- Jetpack Compose with Material 3

### 2. Dependencies (`app/build.gradle.kts`)

```kotlin
dependencies {
    // Compose
    implementation(platform("androidx.compose:compose-bom:2024.02.00"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.8.2")

    // HTTP Server
    implementation("io.ktor:ktor-server-netty:2.3.8")
    implementation("io.ktor:ktor-server-content-negotiation:2.3.8")
    implementation("io.ktor:ktor-serialization-kotlinx-json:2.3.8")

    // Serialization
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")

    // AppReveal (debug only)
    debugImplementation("com.appreveal:appreveal")
    releaseImplementation("com.appreveal:appreveal-noop")
}
```

AppReveal via composite build:
```kotlin
// settings.gradle.kts
includeBuild("path/to/AppReveal/Android") {
    dependencySubstitution {
        substitute(module("com.appreveal:appreveal")).using(project(":appreveal"))
        substitute(module("com.appreveal:appreveal-noop")).using(project(":appreveal-noop"))
    }
}
```

### 3. AndroidManifest.xml

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
```

### 4. Application Class (`KelpieApp.kt`)

```kotlin
class KelpieApp : Application() {
    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG) {
            AppReveal.start(this)
        }
    }
}
```

### 5. Browser UI (Compose)

**BrowserScreen** — Scaffold with URL bar at top, WebView filling content area, settings FAB.

**URLBar** — TextField for URL input, navigate on submit, loading progress indicator.

**SettingsScreen** — Bottom sheet showing: device name, IP, port, mDNS status, device ID, app version, QR code.

### 6. WebView + CDP (`WebViewContainer.kt`)

```kotlin
WebView(context).apply {
    settings.javaScriptEnabled = true
    settings.domStorageEnabled = true
    WebView.setWebContentsDebuggingEnabled(true) // Enables CDP
    webViewClient = KelpieWebViewClient()
    webChromeClient = KelpieChromeClient()
}
```

CDP connection via local Unix socket — the app connects to its own WebView's CDP endpoint for DOM operations, screenshots, console, network, etc.

**BrowserState** — `StateFlow` with: currentUrl, pageTitle, isLoading, canGoBack, canGoForward, progress.

### 7. Ktor HTTP Server (`HTTPServer.kt`)

```kotlin
embeddedServer(Netty, port = 8420) {
    install(ContentNegotiation) { json() }
    routing {
        router.registerRoutes(this)
    }
}.start(wait = false)
```

**Router** — Maps `POST /v1/{method}` to handler functions. JSON request/response. Standard error format. Start with stub handlers returning `NOT_IMPLEMENTED`.

### 8. NsdManager mDNS (`MDNSAdvertiser.kt`)

```kotlin
val serviceInfo = NsdServiceInfo().apply {
    serviceName = deviceName
    serviceType = "_kelpie._tcp"
    port = 8420
    setAttribute("id", deviceId)
    setAttribute("name", deviceName)
    setAttribute("model", Build.MODEL)
    setAttribute("platform", "android")
    setAttribute("width", displayWidth.toString())
    setAttribute("height", displayHeight.toString())
    setAttribute("port", "8420")
    setAttribute("version", BuildConfig.VERSION_NAME)
}
nsdManager.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, registrationListener)
```

### 9. Device Identity (`DeviceIdentity.kt`)

Primary: UUIDv4 stored in SharedPreferences on first launch. Fallback: `Settings.Secure.ANDROID_ID`. Stable across restarts, changes only on reinstall.

### 10. AppReveal (Debug Only)

In `debug/` source set:
```kotlin
object AppRevealSetup {
    fun configure(app: Application) {
        AppReveal.start(app)
    }
}
```

Only compiled into debug builds via source set separation.

### 11. Commit

```bash
git add apps/android/ && git commit -m "feat: Android app foundation — Compose UI, WebView+CDP, Ktor, NsdManager"
```

## Acceptance Criteria

- [ ] `./gradlew assembleDebug` succeeds without errors
- [ ] App launches in Emulator showing URL bar and WebView
- [ ] Typing a URL and pressing Go navigates the WebView
- [ ] Back/forward navigation works
- [ ] Settings panel shows device IP, port, mDNS status
- [ ] Ktor HTTP server starts on port 8420
- [ ] `curl http://10.0.2.2:8420/v1/get-device-info` returns JSON (via adb forward)
- [ ] NsdManager advertises `_kelpie._tcp` — discoverable on local network
- [ ] TXT records include: id, name, model, platform, width, height, port, version
- [ ] `WebView.setWebContentsDebuggingEnabled(true)` is called — CDP is available
- [ ] Device ID persists across app restarts
- [ ] AppReveal is active in debug builds — discoverable via `_appreveal._tcp`
- [ ] AppReveal is NOT present in release builds (`./gradlew assembleRelease` excludes it)
- [ ] App icon uses the kawaii fire character
- [ ] Min SDK is 28, Kotlin 1.9+, Java 17

---

- [ ] **Have you run an adversarial review with Codex?**
