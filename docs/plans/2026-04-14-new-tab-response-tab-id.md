# New Tab Response Tab ID

## Problem

`new-tab` already returns a nested `tab` object with an `id`, but follow-up requests use a top-level `tabId` parameter. That creates unnecessary naming drift for CLI and MCP consumers:

- create tab -> read `response.tab.id`
- switch/close/target tab -> send `tabId`

The current contract is technically usable but awkward for agents and easy to misread as two different identifiers.

## Proposed Change

Keep the existing `tab` payload for compatibility and add a top-level `tabId` field to `new-tab` responses on every platform.

New response shape:

```json
{
  "success": true,
  "tabId": "550e8400-e29b-41d4-a716-446655440000",
  "tab": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "url": "https://example.com/page",
    "title": "",
    "active": true
  },
  "tabCount": 3
}
```

## Why This Shape

- Non-breaking: existing consumers that read `tab.id` continue to work.
- Direct: new consumers can pass `tabId` from `new-tab` straight into `switch-tab`, `close-tab`, or macOS webview-targeting requests.
- Minimal: avoids renaming `TabInfo.id` everywhere and avoids widening all tab payloads with duplicate fields.

## Scope

- macOS `new-tab` handler
- iOS `new-tab` handler
- Android `new-tab` handler
- shared API types
- CLI help metadata
- API and CLI docs
- targeted tests covering the new field

## Non-Goals

- Renaming `TabInfo.id` to `tabId`
- Changing `get-tabs` or `switch-tab` response payload shapes beyond doc clarification
- Addressing missing CLI `--tabId` flags for webview commands

## Cross-Provider Review

Pending.
