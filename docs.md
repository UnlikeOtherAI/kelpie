# AppReveal In Kelpie

This document is the source of truth for how Kelpie uses AppReveal.

## Two separate things

AppReveal has two distinct pieces. Do not conflate them.

1. The AppReveal CLI is an external command-line helper.
   It helps an agent connect to and operate an AppReveal-enabled app.
   Updating the CLI does not update the in-app SDK.

2. The AppReveal library is the in-app runtime.
   On iOS this is a Swift package imported by the app in debug-only builds.
   On Android this is a debug-only app dependency.
   This runtime is what actually exposes the app to external automation.

## Release rule

The in-app AppReveal library must never ship in release builds.

Reason:
- It uses private API.
- Shipping it in production would risk App Store rejection.

That means:
- iOS: AppReveal is linked and started only in debug builds.
- Android: AppReveal belongs in `debugImplementation` only, with no release inclusion.
- Release builds must behave as if AppReveal does not exist.

## Kelpie integration model

Kelpie uses AppReveal for debug automation and verification, not for core product behavior.

AppReveal is used to:
- inspect visible windows and UI state
- inspect WebViews and DOM state
- drive taps and other debug interactions
- support local debug automation from an external agent

Kelpie does not depend on AppReveal for:
- browser control over the product HTTP API
- end-user features
- release functionality

## iOS

The iOS integration lives in:
- [AppRevealSetup.swift](/System/Volumes/Data/.internal/projects/Projects/kelpie/apps/ios/Kelpie/Debug/AppRevealSetup.swift)

Current model:
- import AppReveal only behind debug-only compilation conditions
- call `AppReveal.start()` only in debug
- use a no-op fallback when AppReveal is not linked

Operationally, there are two separate update surfaces:
- the AppReveal CLI helper on the machine
- the Swift package used by the iOS app

Updating one does not update the other.

## Android

The Android debug integration entry point lives in:
- [AppRevealSetup.kt](/System/Volumes/Data/.internal/projects/Projects/kelpie/apps/android/app/src/debug/java/com/kelpie/browser/debug/AppRevealSetup.kt)

The intended model is:
- include AppReveal only in debug dependencies
- start it only from debug code
- keep release builds free of the library

## Practical rule for future work

When AppReveal behavior is wrong, first identify which layer is wrong:
- CLI/helper problem
- in-app SDK/library problem
- Kelpie integration problem

Do not treat "update AppReveal" as a single action until that distinction is clear.

