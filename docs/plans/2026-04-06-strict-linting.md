# Strict Linting Across All Components

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Every `make` / `pnpm build` / `./gradlew build` command must fail if lint violations exist — no component can ship unlinted code.

**Architecture:** Add ESLint (TypeScript), SwiftLint (Swift), and ktlint (Kotlin) with strict rulesets. Each tool hooks into the existing build command so there is zero friction — developers don't run a separate step; the build itself gates on lint.

**Tech Stack:** ESLint 9 + @typescript-eslint (TS), SwiftLint (Swift via Homebrew), ktlint via jlleitschuh Gradle plugin (Kotlin)

---

### Task 1: TypeScript — ESLint strict setup

**Files:**
- Create: `eslint.config.mjs` (repo root)
- Modify: `package.json` (root — add devDependencies)
- Modify: `packages/cli/package.json` (change `lint` script)
- Modify: `packages/shared/package.json` (change `lint` script)

**Step 1: Install ESLint + typescript-eslint**

```bash
pnpm add -D -w eslint @eslint/js typescript-eslint
```

**Step 2: Create `eslint.config.mjs` at repo root**

```js
import eslint from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  eslint.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  ...tseslint.configs.stylisticTypeChecked,
  {
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
  },
  {
    // Test files: relax a few rules that conflict with vitest patterns
    files: ["**/tests/**/*.ts"],
    rules: {
      "@typescript-eslint/no-unsafe-assignment": "off",
      "@typescript-eslint/no-unsafe-member-access": "off",
      "@typescript-eslint/no-unsafe-call": "off",
      "@typescript-eslint/no-unsafe-argument": "off",
      "@typescript-eslint/no-floating-promises": "off",
      "@typescript-eslint/unbound-method": "off",
    },
  },
  {
    ignores: ["**/dist/", "**/node_modules/", "**/*.js", "**/*.mjs"],
  },
);
```

**Step 3: Update lint scripts in both packages**

In `packages/cli/package.json`, change:
```json
"lint": "eslint src/ tests/"
```

In `packages/shared/package.json`, change:
```json
"lint": "eslint src/ tests/"
```

**Step 4: Run lint and fix all violations**

```bash
pnpm lint
```

Fix every violation. The codebase already has zero `any` types and strict TS, so violations should be minimal — mostly stylistic (prefer `interface` over `type`, etc.).

**Step 5: Verify build pipeline gates on lint**

```bash
pnpm lint && pnpm build && pnpm test
```

All three must pass. Introduce a deliberate violation (e.g., add `let x: any = 1;` to a file), run `pnpm lint`, confirm it fails, then remove the violation.

**Step 6: Commit**

```bash
git add eslint.config.mjs package.json packages/cli/package.json packages/shared/package.json
# plus any source files that needed fixes
git commit -m "feat: add ESLint strict type-checked linting for TypeScript"
```

---

### Task 2: Swift — SwiftLint strict setup

SwiftLint is already installed at `/opt/homebrew/bin/swiftlint`.

**Files:**
- Create: `.swiftlint.yml` (repo root)
- Modify: `Makefile` (add lint gates to `ios-build` and `macos-build`)

**Step 1: Create `.swiftlint.yml` at repo root**

```yaml
# Kelpie SwiftLint — strict rules, build must fail on violations.

included:
  - apps/ios/Kelpie
  - apps/macos/Kelpie

excluded:
  - apps/ios/.build
  - apps/macos/.build
  - apps/macos/Frameworks

# Promote all warnings to errors so the build fails.
strict: true

# ── Enabled opt-in rules ────────────────────────────────────────────────────
opt_in_rules:
  - closure_end_indentation
  - closure_spacing
  - collection_alignment
  - contains_over_filter_count
  - contains_over_first_not_nil
  - contains_over_range_nil_comparison
  - convenience_type
  - discouraged_object_literal
  - empty_collection_literal
  - empty_count
  - empty_string
  - enum_case_associated_values_count
  - explicit_init
  - fallthrough
  - fatal_error_message
  - file_name_no_space
  - first_where
  - flatmap_over_map_reduce
  - identical_operands
  - implicit_return
  - joined_default_parameter
  - last_where
  - legacy_multiple
  - literal_expression_end_indentation
  - lower_acl_than_parent
  - modifier_order
  - multiline_arguments
  - multiline_parameters
  - operator_usage_whitespace
  - overridden_super_call
  - pattern_matching_keywords
  - prefer_self_in_static_references
  - prefer_self_type_over_type_of_self
  - prefer_zero_over_explicit_init
  - private_action
  - private_outlet
  - redundant_nil_coalescing
  - redundant_type_annotation
  - return_value_from_void_function
  - sorted_first_last
  - static_operator
  - toggle_bool
  - unavailable_function
  - unneeded_parentheses_in_closure_argument
  - unowned_variable_capture
  - vertical_parameter_alignment_on_call
  - yoda_condition

# ── Rule configuration ──────────────────────────────────────────────────────
line_length:
  warning: 200
  error: 300

file_length:
  warning: 500
  error: 600

type_body_length:
  warning: 400
  error: 500

function_body_length:
  warning: 60
  error: 100

function_parameter_count:
  warning: 6
  error: 8

cyclomatic_complexity:
  warning: 15
  error: 25

# Force-unwrap: warn. Many are legitimate (WKNavigation!, string literals).
# Each should be evaluated; truly dangerous ones should be fixed.
force_unwrapping:
  severity: warning

# Force-cast is already at zero in the codebase — keep it an error.
force_cast: error

# Allow large enums (MCP tool lists, route registrations).
large_tuple:
  warning: 4

identifier_name:
  min_length:
    warning: 2
    error: 1
  max_length:
    warning: 60
    error: 80
  excluded:
    - id
    - x
    - y
    - ip
    - js
    - i
    - w
    - h

type_name:
  max_length:
    warning: 60
    error: 80

nesting:
  type_level: 3
  function_level: 3
```

**Step 2: Add SwiftLint gates to Makefile**

Add a new `lint-swift` target and wire it into `ios-build` and `macos-build`:

```makefile
lint-swift:
	@echo "→ Linting Swift (iOS)..."
	/opt/homebrew/bin/swiftlint lint --strict --path apps/ios/Kelpie
	@echo "→ Linting Swift (macOS)..."
	/opt/homebrew/bin/swiftlint lint --strict --path apps/macos/Kelpie
```

Then change `ios-build` to depend on `lint-swift` and `macos-build` to depend on `lint-swift`:

```makefile
ios-build: lint-swift
macos-build: lint-swift
```

This means `make ios` and `make macos` will fail if SwiftLint finds any violations.

**Step 3: Run SwiftLint and fix violations**

```bash
/opt/homebrew/bin/swiftlint lint --strict --path apps/ios/Kelpie 2>&1 | head -50
/opt/homebrew/bin/swiftlint lint --strict --path apps/macos/Kelpie 2>&1 | head -50
```

Fix all errors. Common patterns to expect:
- Trailing whitespace
- Vertical whitespace
- Line length (200 char warning threshold is generous)
- `force_unwrapping` warnings — evaluate each; keep if safe (string literals, system APIs), fix if risky
- Identifier name length

Use `swiftlint --fix` for auto-fixable violations:
```bash
/opt/homebrew/bin/swiftlint --fix --path apps/ios/Kelpie
/opt/homebrew/bin/swiftlint --fix --path apps/macos/Kelpie
```

**Step 4: Verify the build gates**

```bash
make macos-build
```

Must succeed with zero lint errors. Introduce a deliberate violation (e.g., add `let x = foo as! Bar` to a file), run `make macos-build`, confirm it fails, then remove the violation.

**Step 5: Commit**

```bash
git add .swiftlint.yml Makefile
# plus any Swift source files that needed fixes
git commit -m "feat: add SwiftLint strict linting for iOS and macOS"
```

---

### Task 3: Kotlin — ktlint strict setup

**Files:**
- Modify: `apps/android/build.gradle.kts` (add ktlint plugin)
- Modify: `apps/android/app/build.gradle.kts` (apply plugin, configure)
- Create: `apps/android/.editorconfig` (ktlint reads this for style rules)

**Step 1: Add ktlint Gradle plugin to root build.gradle.kts**

In `apps/android/build.gradle.kts`, add to the `plugins` block:

```kotlin
plugins {
    id("com.android.application") version "8.3.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "1.9.22" apply false
    id("org.jlleitschuh.gradle.ktlint") version "12.1.2"
}
```

**Step 2: Apply plugin in app build.gradle.kts**

Add to the `plugins` block in `apps/android/app/build.gradle.kts`:

```kotlin
id("org.jlleitschuh.gradle.ktlint")
```

Add configuration block:

```kotlin
ktlint {
    version.set("1.5.0")
    android.set(true)
    verbose.set(true)
    outputToConsole.set(true)
    // The check task runs automatically as part of `./gradlew build`
    // because the plugin hooks into the check lifecycle.
}
```

**Step 3: Create `apps/android/.editorconfig`**

```ini
[*.{kt,kts}]
# ktlint reads EditorConfig for style rules.
indent_size = 4
indent_style = space
max_line_length = 200
insert_final_newline = true
# Official Kotlin style (matches gradle.properties kotlin.code.style=official)
ktlint_code_style = ktlint_official
```

**Step 4: Run ktlint and fix violations**

```bash
cd apps/android && ./gradlew ktlintCheck 2>&1 | tail -50
```

Auto-format what can be fixed:
```bash
cd apps/android && ./gradlew ktlintFormat
```

Fix remaining violations manually. Common patterns:
- Trailing commas
- Import ordering
- Wildcard imports
- Spacing around operators
- Multi-line expression indentation

**Step 5: Verify the build gates**

```bash
cd apps/android && ./gradlew build
```

The ktlint plugin hooks into the `check` lifecycle, which `build` depends on. Build must fail on violations. Introduce a deliberate violation, confirm failure, remove it.

**Step 6: Commit**

```bash
git add apps/android/build.gradle.kts apps/android/app/build.gradle.kts apps/android/.editorconfig
# plus any Kotlin source files that needed fixes
git commit -m "feat: add ktlint strict linting for Android"
```

---

### Task 4: Documentation and CI alignment

**Files:**
- Modify: `AGENTS.md` (update verification section)

**Step 1: Update AGENTS.md verification section**

Change the Verification section to include lint:

```markdown
## Verification

- CLI: `pnpm lint && pnpm build && pnpm test` must pass before committing
- iOS: `make lint-swift` then Xcode build succeeds, no warnings
- Android: `cd apps/android && ./gradlew build` succeeds (includes ktlint)
- macOS: `make lint-swift` then rebuild and launch. Kill stale instance first.
```

**Step 2: Commit**

```bash
git add AGENTS.md
git commit -m "docs: update verification section with lint requirements"
```

---

### Task 5: Final verification

**Step 1: Run everything from scratch**

```bash
# TypeScript
pnpm lint && pnpm build && pnpm test

# Swift
/opt/homebrew/bin/swiftlint lint --strict --path apps/ios/Kelpie
/opt/homebrew/bin/swiftlint lint --strict --path apps/macos/Kelpie

# Kotlin (if Android SDK available)
cd apps/android && ./gradlew ktlintCheck
```

All must pass with zero violations.

**Step 2: Push all commits**

```bash
git push
```
