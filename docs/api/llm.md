# Kelpie API — LLM-Optimized Methods

Accessibility tree, annotated screenshots, visible elements, page text extraction, form state, smart queries.

These methods are specifically designed for LLM consumption — compact, semantic, and token-efficient compared to raw DOM.

For protocol details, errors, and MCP tool names, see [README.md](README.md).

---

## AI

These methods expose the local AI backend used by Kelpie. On Android, supported devices default to the `platform` backend (Gemini Nano once the AI Edge SDK is wired), and `ollama:` model IDs switch inference to a configured Ollama endpoint.

### `ai-status`

Report the active AI backend, model, and capabilities.

```json
POST /v1/ai-status
{}

Response:
{
  "success": true,
  "loaded": true,
  "backend": "platform",
  "model": "platform",
  "capabilities": ["text"]
}
```

### `ai-load`

Switch to the platform backend or load an Ollama-managed model.

```json
POST /v1/ai-load
{
  "model": "ollama:llava:7b",
  "ollamaEndpoint": "http://192.168.1.50:11434"
}

Response:
{
  "success": true,
  "backend": "ollama",
  "model": "llava:7b",
  "loadTimeMs": 12
}
```

Pass `{ "model": "platform" }` to return to the default on-device backend.

### `ai-unload`

Clear the active non-platform model and fall back to the platform backend when available.

```json
POST /v1/ai-unload
{}

Response:
{
  "success": true,
  "backend": "platform",
  "model": "platform"
}
```

### `ai-infer`

Run inference against the active backend. Platform inference is text-only. Ollama requests may use single-shot prompts or multi-turn `messages`.

```json
POST /v1/ai-infer
{
  "prompt": "Summarise this page in 3 bullet points",
  "maxTokens": 256
}

Response:
{
  "success": true,
  "response": "The page highlights three pricing tiers...",
  "tokensUsed": 46,
  "inferenceTimeMs": 1450
}
```

If the platform backend is selected before the AI Edge SDK is wired, Android currently returns `PLATFORM_AI_NOT_WIRED`. If Ollama becomes unreachable mid-request, Kelpie returns `OLLAMA_DISCONNECTED`.

### `ai-record`

Reserved for chat audio capture. Android currently exposes the route as a stub.

```json
POST /v1/ai-record
{
  "action": "start"
}

Response:
{
  "success": false,
  "error": {
    "code": "NOT_IMPLEMENTED",
    "message": "ai-record start is not yet implemented on Android"
  }
}
```

---

## Smart Queries (Group Context)

These methods are designed for multi-device scenarios. On a single device they work normally; via the CLI's group commands, they enable LLM decision-making.

### `findElement`
Search for an element and return detailed info about whether and where it was found.

```json
POST /v1/find-element
{
  "text": "Submit",           // search by visible text
  "role": "button",           // optional, ARIA role filter
  "selector": null            // alternative: CSS selector
}

Response:
{
  "found": true,
  "element": {
    "tag": "button",
    "text": "Submit",
    "selector": "#form > button.submit",
    "rect": {"x": 120, "y": 580, "width": 200, "height": 44},
    "visible": true,
    "interactable": true
  }
}
```

### `findButton`
Shorthand for `findElement` with `role: "button"`.

```json
POST /v1/find-button
{
  "text": "Submit"
}

Response:
{
  "found": true,
  "element": {
    "tag": "button",
    "text": "Submit",
    "selector": "#submit-btn",
    "rect": {"x": 120, "y": 580, "width": 200, "height": 44},
    "visible": true
  }
}
```

### `findLink`
Shorthand for `findElement` with `role: "link"`.

```json
POST /v1/find-link
{
  "text": "Sign Up"
}
```

### `findInput`
Find an input field by label, placeholder, or name.

```json
POST /v1/find-input
{
  "label": "Email",          // search by associated label
  "placeholder": null,        // or by placeholder text
  "name": null                // or by name attribute
}

Response:
{
  "found": true,
  "element": {
    "tag": "input",
    "type": "email",
    "name": "email",
    "selector": "#email-input",
    "rect": {"x": 20, "y": 320, "width": 350, "height": 44},
    "visible": true
  }
}
```

---

## Accessibility

### `getAccessibilityTree`
Get the accessibility tree snapshot — the single most useful endpoint for LLMs. Returns a semantic, structured tree of ARIA roles, names, states, and values. Far more compact and meaningful than raw HTML.

```json
POST /v1/get-accessibility-tree
{
  "root": null,               // optional, CSS selector to scope the tree
  "interactableOnly": false,  // optional, only return interactive elements
  "maxDepth": null             // optional, limit tree depth
}

Response:
{
  "success": true,
  "tree": {
    "role": "WebArea",
    "name": "Example Domain",
    "children": [
      {
        "role": "banner",
        "children": [
          {"role": "link", "name": "Home", "focused": false},
          {"role": "link", "name": "About", "focused": false},
          {"role": "link", "name": "Contact", "focused": false}
        ]
      },
      {
        "role": "main",
        "children": [
          {"role": "heading", "name": "Welcome", "level": 1},
          {"role": "paragraph", "name": "This is an example page."},
          {
            "role": "form",
            "name": "Sign Up",
            "children": [
              {"role": "textbox", "name": "Email", "value": "", "required": true, "focused": false},
              {"role": "textbox", "name": "Password", "value": "", "required": true, "focused": false},
              {"role": "checkbox", "name": "I agree to the terms", "checked": false},
              {"role": "button", "name": "Submit", "disabled": false}
            ]
          }
        ]
      },
      {
        "role": "contentinfo",
        "children": [
          {"role": "link", "name": "Privacy Policy"},
          {"role": "link", "name": "Terms of Service"}
        ]
      }
    ]
  },
  "nodeCount": 14
}
```

---

## Annotated Screenshots

### `screenshotAnnotated`
Capture a screenshot with numbered labels overlaid on all interactive elements. The LLM can reference elements by index number instead of generating CSS selectors — dramatically more reliable for visual grounding.

> **CLI note:** Like `screenshot`, the CLI auto-saves annotated screenshots to file and returns the path. See [cli.md](../cli.md).

```json
POST /v1/screenshot-annotated
{
  "fullPage": false,          // optional
  "format": "png",            // optional
  "interactableOnly": true,   // optional, default true — only label clickable/fillable elements
  "labelStyle": "numbered"    // optional, "numbered" | "badge"
}

Response:
{
  "success": true,
  "image": "base64-encoded-image-with-overlays",
  "width": 390,
  "height": 844,
  "format": "png",
  "annotations": [
    {"index": 0, "role": "link", "name": "Home", "selector": "nav a:nth-child(1)", "rect": {"x": 20, "y": 60, "width": 50, "height": 24}},
    {"index": 1, "role": "link", "name": "About", "selector": "nav a:nth-child(2)", "rect": {"x": 80, "y": 60, "width": 50, "height": 24}},
    {"index": 2, "role": "textbox", "name": "Email", "selector": "#email", "rect": {"x": 20, "y": 320, "width": 350, "height": 44}},
    {"index": 3, "role": "textbox", "name": "Password", "selector": "#password", "rect": {"x": 20, "y": 380, "width": 350, "height": 44}},
    {"index": 4, "role": "checkbox", "name": "I agree", "selector": "#terms", "rect": {"x": 20, "y": 440, "width": 24, "height": 24}},
    {"index": 5, "role": "button", "name": "Submit", "selector": "#submit", "rect": {"x": 120, "y": 490, "width": 150, "height": 44}}
  ]
}
```

### `clickAnnotation`
Click an element by its annotation index from the last `screenshotAnnotated` call.

```json
POST /v1/click-annotation
{
  "index": 5
}

Response:
{
  "success": true,
  "element": {"role": "button", "name": "Submit", "selector": "#submit"}
}
```

### `fillAnnotation`
Fill an element by its annotation index.

```json
POST /v1/fill-annotation
{
  "index": 2,
  "value": "user@example.com"
}

Response:
{
  "success": true,
  "element": {"role": "textbox", "name": "Email", "selector": "#email"},
  "value": "user@example.com"
}
```

---

## Visible Elements

### `getVisibleElements`
Get only the elements currently visible in the viewport. Returns a compact list instead of the full DOM — typically 20-50 elements instead of thousands of nodes.

```json
POST /v1/get-visible-elements
{
  "interactableOnly": false,  // optional, only return interactive elements
  "includeText": true         // optional, include text content nodes
}

Response:
{
  "success": true,
  "viewport": {"width": 390, "height": 844, "scrollX": 0, "scrollY": 0},
  "elements": [
    {"tag": "h1", "text": "Welcome", "rect": {"x": 20, "y": 100, "width": 350, "height": 36}, "role": "heading"},
    {"tag": "p", "text": "This is an example page.", "rect": {"x": 20, "y": 150, "width": 350, "height": 48}, "role": "paragraph"},
    {"tag": "input", "type": "email", "name": "email", "placeholder": "Email", "value": "", "rect": {"x": 20, "y": 320, "width": 350, "height": 44}, "role": "textbox", "interactable": true},
    {"tag": "button", "text": "Submit", "rect": {"x": 120, "y": 490, "width": 150, "height": 44}, "role": "button", "interactable": true}
  ],
  "count": 4
}
```
## Page Text Extraction

### `getPageText`
Extract the main readable content from the page, stripping navigation, ads, footers, and boilerplate. Uses a Readability-style algorithm to identify the primary content area. Returns clean text that's far more token-efficient than HTML.

```json
POST /v1/get-page-text
{
  "mode": "readable",         // "readable" (main content only) | "full" (all visible text) | "markdown" (structured markdown)
  "selector": null             // optional, extract from specific element
}

Response:
{
  "success": true,
  "title": "Example Article",
  "byline": "By John Doe",
  "content": "This is the main article text, cleaned of navigation, ads, and other boilerplate...",
  "wordCount": 842,
  "language": "en",
  "excerpt": "This is the main article text..."
}
```
## Form State

### `getFormState`
Get the complete state of all forms on the page — every field, its current value, validation state, and whether it's required. One call instead of querying each field individually.

```json
POST /v1/get-form-state
{
  "selector": null             // optional, scope to specific form
}

Response:
{
  "success": true,
  "forms": [
    {
      "selector": "#signup-form",
      "action": "/api/signup",
      "method": "POST",
      "fields": [
        {
          "name": "email",
          "type": "email",
          "selector": "#email",
          "label": "Email Address",
          "value": "",
          "placeholder": "Enter your email",
          "required": true,
          "valid": false,
          "validationMessage": "Please fill out this field.",
          "disabled": false,
          "readonly": false
        },
        {
          "name": "password",
          "type": "password",
          "selector": "#password",
          "label": "Password",
          "value": "",
          "required": true,
          "valid": false,
          "validationMessage": "Please fill out this field.",
          "disabled": false,
          "readonly": false
        },
        {
          "name": "terms",
          "type": "checkbox",
          "selector": "#terms",
          "label": "I agree to the terms",
          "checked": false,
          "required": true,
          "valid": false,
          "disabled": false
        }
      ],
      "isValid": false,
      "emptyRequired": ["email", "password", "terms"],
      "submitButton": {"selector": "#submit", "text": "Submit", "disabled": false}
    }
  ],
  "formCount": 1
}
```

---
