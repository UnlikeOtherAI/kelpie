# Linux native acceptance

Run on a Linux desktop with a built CEF app:

```sh
GDK_BACKEND=x11 DISPLAY=:2 node tests/linux/run-release-acceptance.mjs /absolute/path/kelpie-linux
```

The harness owns a temporary profile, checks restrictive permissions and profile
locking, exercises shared Windows/Linux HTTP and direct MCP acceptance, then
checks persistent/transient tab restoration and graceful readiness cleanup.
It does not alter the normal user profile. GTK input and visual checks still
require the desktop: verify typing, IME, tab focus, select popups, conditional
favorites, and active-only animated page colors.

Use the CLI alias lifecycle separately to verify its local stdio bridge.
