# Storage and device controls

Back to the [CLI reference](../cli.md).

## Cookie & Storage Commands

### Authentication / session state

To drive an app that sits behind a login, put the browser into an authenticated state **before** navigating. Kelpie owns the browser's cookie store directly, so no external proxy is needed:

- **httpOnly session cookies are fully supported.** Set them with `kelpie cookies set <name> <value> --http-only` (MCP: `kelpie_set_cookie`). They are written to the native cookie store (`WKHTTPCookieStore` on iOS/macOS, `CookieManager` on Android), not via JavaScript, so the `--http-only`, `--secure`, `--same-site`, and `--expires` attributes all take effect.
- **Do not use `eval` / `document.cookie` to set a session cookie.** JavaScript cannot create an httpOnly cookie, and reading `document.cookie` returns an empty string for httpOnly cookies — so it looks like the cookie is missing even when it is set. Use `kelpie cookies list` (which reads the native store, including httpOnly cookies) to verify instead.
- **Non-httpOnly token schemes** that live in web storage can be primed with `kelpie storage set <key> <value>`.
- **Interactive login** is also available: sign in once in a browser tab, and the resulting session cookies persist in the same store.

```bash
# inject an httpOnly session cookie, then navigate authenticated
kelpie cookies set "hw_session" "$TOKEN" --domain "app.example.com" --path "/" --http-only --secure --device admin
kelpie navigate "https://app.example.com/dashboard" --device admin
```

### `kelpie cookies list`
Get cookies for the current page. Reads the native cookie store, so httpOnly cookies are included (unlike `document.cookie`).

```bash
kelpie cookies list --device "My iPhone"
kelpie cookies list --device "My iPhone" --name "session_id"
```

### `kelpie cookies set <name> <value>`
Set a cookie. Supports `--domain`, `--path`, `--secure`, `--http-only`, `--same-site <Strict|Lax|None>`, and `--expires`.

```bash
kelpie cookies set "session_id" "abc123" --device "My iPhone"
kelpie cookies set "theme" "dark" --device "My iPhone" --domain "example.com" --path "/" --secure
kelpie cookies set "hw_session" "abc123" --device "My iPhone" --domain "example.com" --path "/" --http-only --secure
```

### `kelpie cookies delete`
Delete cookies.

```bash
kelpie cookies delete --name "session_id" --device "My iPhone"
kelpie cookies delete --domain "example.com" --device "My iPhone"
kelpie cookies delete --all --device "My iPhone"
```

### `kelpie storage get`
Read localStorage or sessionStorage.

```bash
kelpie storage get --device "My iPhone"                          # localStorage (default)
kelpie storage get --device "My iPhone" --type session
kelpie storage get --device "My iPhone" --key "auth_token"
```

### `kelpie storage set <key> <value>`
Write to storage.

```bash
kelpie storage set "theme" "dark" --device "My iPhone"
kelpie storage set "theme" "dark" --device "My iPhone" --type session
```

### `kelpie storage clear`
Clear storage.

```bash
kelpie storage clear --device "My iPhone"
kelpie storage clear --device "My iPhone" --type session
kelpie storage clear --device "My iPhone" --type both
```

---

## Clipboard Commands

### `kelpie clipboard get`
Read clipboard contents.

```bash
kelpie clipboard get --device "My iPhone"
```

### `kelpie clipboard set <text>`
Write to clipboard.

```bash
kelpie clipboard set "text to copy" --device "My iPhone"
```

---

## Geolocation Commands

### `kelpie geo set <lat> <lng>`
Override geolocation.

```bash
kelpie geo set 37.7749 -122.4194 --device "My iPhone"
kelpie geo set 37.7749 -122.4194 --device "My iPhone" --accuracy 10
```

### `kelpie geo clear`
Remove geolocation override.

```bash
kelpie geo clear --device "My iPhone"
```

---

## Shadow DOM Commands

### `kelpie shadow-roots`
List all shadow DOM hosts on the page.

```bash
kelpie shadow-roots --device "My iPhone"
```

### `kelpie shadow-query <host> <selector>`
Query elements inside a shadow root.

```bash
kelpie shadow-query "my-component" ".inner-button" --device "My iPhone"
kelpie shadow-query "my-component" ".inner-button" --device "My iPhone" --pierce
```

---

## Keyboard & Viewport Commands

### `kelpie keyboard show`
Show the soft keyboard by focusing an element.

```bash
kelpie keyboard show --device "My iPhone"
kelpie keyboard show --device "My iPhone" --selector "#email"
kelpie keyboard show --device "My iPhone" --type number
```

### `kelpie keyboard hide`
Dismiss the soft keyboard.

```bash
kelpie keyboard hide --device "My iPhone"
```

### `kelpie keyboard state`
Check keyboard visibility and viewport impact.

```bash
kelpie keyboard state --device "My iPhone"
```

### `kelpie resize <width> <height>`
Simulate a reduced viewport (e.g., keyboard present, toolbar visible).

```bash
kelpie resize 390 500 --device "My iPhone"
```

### `kelpie resize-reset`
Restore full-screen viewport. Note: this is a top-level command (`resize-reset`), not a `resize reset` subcommand.

```bash
kelpie resize-reset --device "My iPhone"
```

### `kelpie obscured <selector>`
Check if an element is hidden by the keyboard or outside the visible viewport.

```bash
kelpie obscured "#password-input" --device "My iPhone"
```

---

## Viewport Presets

Named viewport presets simulate specific device sizes (e.g. iPhone 15 Pro, iPad Air, foldable open/closed). Supported on iOS, Android, and macOS; not supported on Linux or Windows.

### `kelpie viewport-preset list`
List available viewport presets for the current device or window geometry.

```bash
kelpie viewport-preset list --device "Mac mini"
```

### `kelpie viewport-preset set <name>`
Activate a named viewport preset. Pass the preset `id` returned by `viewport-preset list`.

```bash
kelpie viewport-preset set iphone-15-pro --device "Mac mini"
```

---
