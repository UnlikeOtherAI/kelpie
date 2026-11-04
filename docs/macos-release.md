# macOS-only releases

For a release containing only the macOS app, put this exact marker on the first
line of the GitHub release body:

```text
<!-- kelpie-release-components: macos -->
```

The release workflows skip unrelated Linux, Android, Windows and CLI builds when
this marker is present. Publish the Mac artifact yourself after its native build,
tests, signing checks and hands-on verification. Tag the committed, merged source
containing these workflow guards before publishing; editing release notes afterward
does not stop jobs already triggered. Releases without the marker retain their
existing multi-platform build behavior.

List the Mac component version, architecture, signing/notarization status and source
revision in the release notes. Keep a Mac-only release from replacing the global
latest release (`gh release create --latest=false`) so existing multi-platform
latest-asset links remain valid. Use `release/YYYY-MM-DD`, with a numeric suffix if
that date tag already exists. Download and verify the published artifact's SHA-256,
replace `/Applications/Kelpie.app`, then launch and verify that installed version.

Android and iOS CI are filtered to their app source, shared native/contract inputs
and relevant toolchain inputs. A Mac-only change or release-workflow edit does not
build those apps. Workflow-only changes can be checked with Actionlint; their
explicit `workflow_dispatch` entry points remain available for a platform build.
