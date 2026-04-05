# Task 04: CLI Interaction, Scroll, Wait, and Device Info Commands

**Component:** CLI
**Depends on:** Task 02
**Estimated size:** ~400 lines

## Goal

Implement interaction commands (click, fill, type, etc.), scrolling, wait/sync, device info, and JS evaluation.

## Files to Create

```
packages/cli/src/commands/
  interaction.ts              # click, tap, fill, type, select, check, uncheck
  scroll.ts                   # scroll, scroll2, scroll-top, scroll-bottom
  wait.ts                     # wait, wait-nav
  device-info.ts              # info, viewport
  eval.ts                     # eval
```

```
packages/cli/tests/commands/
  interaction.test.ts
  scroll.test.ts
  wait.test.ts
```

## Commands

### Interaction (`interaction.ts`)

| Command | API Method | Args |
|---------|-----------|------|
| `kelpie click <selector>` | `click` | selector, `--timeout` |
| `kelpie tap <x> <y>` | `tap` | x, y (positional) |
| `kelpie fill <selector> <value>` | `fill` | selector, value, `--timeout` |
| `kelpie type <text>` | `type` | text, `--selector`, `--delay` |
| `kelpie select <selector> <value>` | `select-option` | selector, value |
| `kelpie check <selector>` | `check` | selector |
| `kelpie uncheck <selector>` | `uncheck` | selector |

### Scrolling (`scroll.ts`)

| Command | API Method | Args |
|---------|-----------|------|
| `kelpie scroll` | `scroll` | `--x`, `--y` |
| `kelpie scroll2 <selector>` | `scroll2` | selector, `--position`, `--max-scrolls` |
| `kelpie scroll-top` | `scroll-to-top` | — |
| `kelpie scroll-bottom` | `scroll-to-bottom` | — |

### Wait (`wait.ts`)

| Command | API Method | Args |
|---------|-----------|------|
| `kelpie wait <selector>` | `wait-for-element` | selector, `--timeout`, `--state` |
| `kelpie wait-nav` | `wait-for-navigation` | `--timeout` |

### Device Info (`device-info.ts`)

| Command | API Method | Args |
|---------|-----------|------|
| `kelpie info` | `get-device-info` | `--device` (optional, all if omitted) |
| `kelpie viewport` | `get-viewport` | `--device` |

### Evaluate (`eval.ts`)

| Command | API Method | Args |
|---------|-----------|------|
| `kelpie eval <expression>` | `evaluate` | expression (positional) |

## Tests

- Interaction: verify each command sends correct API method and params
- Scroll: verify `scroll2` sends selector, position, maxScrolls
- Wait: verify timeout and state params passed correctly
- Eval: verify expression passed as-is

## Acceptance Criteria

- [ ] `click <selector>` sends POST to `/v1/click` with correct body
- [ ] `tap <x> <y>` parses numeric coordinates correctly
- [ ] `fill <selector> <value>` sends both selector and value
- [ ] `type <text> --selector "#box" --delay 50` sends all params
- [ ] `scroll --x 0 --y 500` sends deltaX/deltaY
- [ ] `scroll2 <selector> --position center` sends position param
- [ ] `wait <selector> --state hidden --timeout 15000` sends all params
- [ ] `eval "document.title"` sends expression and returns result
- [ ] `info` without `--device` queries all known devices
- [ ] All tests pass

---

- [ ] **Have you run an adversarial review with Codex?**
