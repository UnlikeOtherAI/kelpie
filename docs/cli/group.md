# Group Commands

Back to the [CLI reference](../cli.md).

All group commands target every discovered device unless filtered.

### `kelpie group <command> [args]`

```bash
kelpie group navigate "https://example.com"
kelpie group screenshot --output ./screenshots/
kelpie group fill "#email" "test@example.com"
kelpie group click "#submit"
kelpie group scroll2 "#footer"
```

### `kelpie group find-button <text>`
Find a button on all devices. Returns which devices found it and which didn't.

```bash
kelpie group find-button "Submit"
```

**Output:**
```json
{
  "found": [
    {"device": "My iPhone", "element": {"tag": "button", "text": "Submit"}},
    {"device": "Pixel 8", "element": {"tag": "button", "text": "Submit"}}
  ],
  "notFound": [
    {"device": "iPad Air", "reason": "Element not found"}
  ]
}
```

### `kelpie group find-element <text>`

```bash
kelpie group find-element "Sign Up" --role link
```

### `kelpie group find-link <text>`

```bash
kelpie group find-link "Sign Up"
```

### `kelpie group find-input <label>`

```bash
kelpie group find-input "Email"
```

### Diagnostic group commands

These mirror the per-device diagnostic and keyboard commands and apply them to every (filtered) device in one shot.

```bash
kelpie group a11y                          # accessibility tree from every device
kelpie group dom                           # full DOM from every device
kelpie group console                       # console messages from every device
kelpie group errors                        # JS errors from every device
kelpie group form-state                    # form state from every device
kelpie group visible                       # visible elements from every device
kelpie group eval "document.title"         # evaluate JS on every device
kelpie group keyboard-show --platform ios  # show keyboard on iOS devices
kelpie group keyboard-hide --platform ios  # hide keyboard on iOS devices
```

`kelpie group eval` is useful for sanity-checking environment differences across browsers. `kelpie group keyboard-show` and `kelpie group keyboard-hide` are mobile-only — combine with `--platform ios` or `--platform android` to avoid hitting unsupported desktop devices.

### Group Filtering

```bash
kelpie group navigate "https://example.com" --platform ios       # only iOS devices
kelpie group navigate "https://example.com" --platform android   # only Android
kelpie group navigate "https://example.com" --exclude "iPad Air" # exclude specific device
kelpie group navigate "https://example.com" --include "a1b2c3d4,My iPhone" # only these devices (by ID or name)
```

`--include` accepts a comma-separated list of device IDs or names. When both `--include` and `--platform` are specified, only devices matching both filters are targeted.

### Per-device failures and exit codes

Every group command runs against the filtered set of devices in parallel and returns a structured result:

```json
{
  "command": "navigate",
  "deviceCount": 3,
  "succeeded": 2,
  "failed": 1,
  "results": [
    { "device": {"name": "iPhone", "platform": "ios", "resolution": "390x844"}, "success": true,  "data": {"success": true} },
    { "device": {"name": "Pixel",  "platform": "android", "resolution": "412x915"}, "success": false, "error": {"code": "NAVIGATION_ERROR", "message": "DNS failed"} },
    { "device": {"name": "iPad",   "platform": "ios", "resolution": "1024x1366"}, "success": true,  "data": {"success": true} }
  ]
}
```

- Per-device failures appear in `results[]` as entries with `success: false` and a populated `error` envelope. They are **never** silently dropped.
- By default, the CLI exits with status code `1` if **any** device fails — even when the rest succeeded. Use this for scripts that must treat any device failure as fatal.
- Pass `--allow-partial` to suppress the non-zero exit and treat the run as successful as long as the orchestrator itself completed. The output payload is identical with or without the flag.

```bash
kelpie group navigate "https://example.com"                   # exit 1 if any device fails
kelpie group navigate "https://example.com" --allow-partial   # exit 0 even if some devices fail
```

For smart queries (`find-button`, `find-element`, `find-link`, `find-input`), only **device-level errors** (transport/protocol failures) flip the exit code. A genuine "element absent" result is reported in `notFound[]` but does not set a non-zero exit, because it is the expected answer when the element is not present on that page.

---
