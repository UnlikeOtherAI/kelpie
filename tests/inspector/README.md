# 3D inspector interaction checks

Run after `pnpm install --frozen-lockfile`:

```sh
node --test tests/inspector/navigation.test.mjs
```

The runner uses the existing `playwright-core` dependency of `packages/shared`.
Install its matching Chromium browser first, or set `KELPIE_TEST_EXECUTABLE` to an
installed Chromium/Edge executable. Set `KELPIE_TEST_ENGINE=webkit` to exercise
Playwright WebKit with its matching browser installation.

The fixture runs the exact bundled scripts and uses visible controls to check
camera movement, orientation, zoom, keyboard separation, tree reveal in both
directions, shadow roots, phone touch input, exit and stale-state re-entry. It also
checks source equality between Apple and Android. Native snapshot capture and
native entry/exit still require the platform app journeys.

Set `KELPIE_SCREENSHOTS` to an ignored output directory to capture matching desktop
and phone scenes before and after, plus the new toolbox state. The Before scene
loads the scripts from `KELPIE_BASE_REVISION` (default `ae744915`); both revisions
use the same fixture, viewport and initial state. Images are evidence artifacts,
not repository sources.
