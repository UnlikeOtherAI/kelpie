# Task 06: CLI LLM-Optimized + Smart Query Commands

**Component:** CLI
**Depends on:** Task 02
**Estimated size:** ~350 lines

## Goal

Implement the LLM-optimized commands that provide semantic, token-efficient page representations, and the smart query commands designed for multi-device scenarios.

## Files to Create

```
packages/cli/src/commands/
  a11y.ts                     # accessibility tree
  annotate.ts                 # annotated screenshot + click-index + fill-index
  visible.ts                  # visible elements
  page-text.ts                # page text extraction
  form-state.ts               # form state
  find.ts                     # find-element, find-button, find-link, find-input (shared)
```

```
packages/cli/tests/commands/
  llm-commands.test.ts
  find-commands.test.ts
```

## Commands

### Accessibility (`a11y.ts`)

| Command | API Method | Flags |
|---------|-----------|-------|
| `kelpie a11y` | `get-accessibility-tree` | `--interactable-only`, `--selector`, `--max-depth` |

### Annotated Screenshots (`annotate.ts`)

| Command | API Method | Flags |
|---------|-----------|-------|
| `kelpie annotate` | `screenshot-annotated` | `--output`, `--full-page`, `--base64`, `--interactable-only` |
| `kelpie click-index <index>` | `click-annotation` | index (positional) |
| `kelpie fill-index <index> <value>` | `fill-annotation` | index, value (positional) |

`annotate` follows the same file-save behavior as `screenshot` (Task 03). The JSON response also includes the `annotations` array with element metadata.

### Visible Elements (`visible.ts`)

| Command | API Method | Flags |
|---------|-----------|-------|
| `kelpie visible` | `get-visible-elements` | `--interactable-only` |

### Page Text (`page-text.ts`)

| Command | API Method | Flags |
|---------|-----------|-------|
| `kelpie page-text` | `get-page-text` | `--mode <readable\|full\|markdown>`, `--selector` |

### Form State (`form-state.ts`)

| Command | API Method | Flags |
|---------|-----------|-------|
| `kelpie form-state` | `get-form-state` | `--selector` |

### Smart Queries (`find.ts`)

These are single-device commands here. Group variants are in Task 07.

| Command | API Method | Args |
|---------|-----------|------|
| `kelpie find-element <text>` | `find-element` | text, `--role` |
| `kelpie find-button <text>` | `find-button` | text |
| `kelpie find-link <text>` | `find-link` | text |
| `kelpie find-input <label>` | `find-input` | label, `--placeholder`, `--name` |

## Tests

- a11y: verify `--interactable-only` and `--selector` passed correctly
- annotate: verify file-save behavior (same as screenshot), annotations included in response
- click-index/fill-index: verify index passed to correct endpoint
- find commands: verify text/role/label params sent correctly

## Acceptance Criteria

- [ ] `a11y --interactable-only --selector "main"` sends both params
- [ ] `annotate` saves file to disk by default (same behavior as `screenshot`)
- [ ] `annotate` response includes `annotations` array alongside file path
- [ ] `click-index 5` sends `{"index": 5}` to `click-annotation`
- [ ] `fill-index 2 "user@example.com"` sends index and value
- [ ] `visible --interactable-only` sends param
- [ ] `page-text --mode markdown` sends mode param
- [ ] `form-state --selector "#signup-form"` scopes to form
- [ ] `find-element "Submit" --role button` sends text and role
- [ ] `find-button`, `find-link`, `find-input` each call correct endpoint
- [ ] All tests pass

---

- [ ] **Have you run an adversarial review with Codex?**
