# core-ai Shared C++ Library — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move all AI model management, HF token auth, Ollama integration, and HF cloud inference into a shared C++ library (`native/core-ai`) so every platform (macOS, iOS, Android) uses the same logic, with only the UI and local inference engines remaining platform-specific.

**Architecture:** A new `native/core-ai` static library following the exact patterns of `core-state`. Exposes a C ABI via opaque `MollotovAiManagerRef` handle. Manages the model catalog, HF token, model downloads with auth, Ollama HTTP client, and HF Inference API cloud calls. Platforms call the C API from Swift (bridging header) or Kotlin (JNI). Local inference engines (llama.cpp, Apple Foundation Models, Google AI Edge) stay platform-specific and are plugged in via a callback the platform registers.

**Tech Stack:** C++17, nlohmann_json, cpp-httplib (for Ollama + HF cloud HTTP), CMake, C ABI

**Supersedes:** `docs/plans/2026-04-03-hf-token-flow.md` (Swift-only approach)

---

## Scope — what moves to C++, what stays

| Moves to `core-ai` | Stays platform-specific |
|---|---|
| Model catalog (approved models, HF repos, sizes, capabilities) | llama.cpp + Metal inference (macOS) |
| Device fitness evaluation (RAM/disk checks) | Apple Foundation Models (iOS) |
| HF token storage & retrieval | Google AI Edge SDK (Android) |
| Model download with `Authorization: Bearer` header | Audio recording (AVFoundation / MediaRecorder) |
| Download file validation (reject HTML error bodies) | Screenshot capture |
| Model store (exists / path / remove) | SwiftUI / Compose / XML UI |
| Ollama HTTP: reachable, list models, load, infer | Platform-specific inference dispatch |
| HF cloud inference via Inference API | |
| System prompt & tool definitions (text constants) | |

---

### Task 1: Scaffold `native/core-ai` with CMake and empty C API header

**Files:**
- Create: `native/core-ai/CMakeLists.txt`
- Create: `native/core-ai/include/mollotov/ai_c_api.h`
- Create: `native/core-ai/src/ai_c_api.cpp`
- Create: `native/core-ai/src/ai_c_api_internal.h`
- Modify: `native/CMakeLists.txt:36` — add `add_subdirectory(core-ai)`

**Step 1: Create CMakeLists.txt**

```cmake
add_library(mollotov_core_ai STATIC
  src/ai_c_api.cpp
)

target_include_directories(mollotov_core_ai
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(mollotov_core_ai
  PUBLIC
    mollotov_core_protocol
    nlohmann_json::nlohmann_json
)

if(BUILD_TESTING)
  add_subdirectory(tests)
endif()
```

**Step 2: Create the C API header**

```c
// native/core-ai/include/mollotov/ai_c_api.h
#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MollotovAiManager* MollotovAiManagerRef;

// Lifecycle
MollotovAiManagerRef mollotov_ai_create(const char* models_dir);
void mollotov_ai_destroy(MollotovAiManagerRef mgr);

// String ownership — caller must free returned strings
void mollotov_ai_free_string(char* str);

// HF token
void mollotov_ai_set_hf_token(MollotovAiManagerRef mgr, const char* token);
char* mollotov_ai_get_hf_token(MollotovAiManagerRef mgr);

// Model catalog
char* mollotov_ai_list_approved_models(MollotovAiManagerRef mgr);
char* mollotov_ai_model_fitness(MollotovAiManagerRef mgr,
                                const char* model_id,
                                double total_ram_gb,
                                double disk_free_gb);

// Model store
bool mollotov_ai_is_model_downloaded(MollotovAiManagerRef mgr, const char* model_id);
char* mollotov_ai_model_path(MollotovAiManagerRef mgr, const char* model_id);
bool mollotov_ai_remove_model(MollotovAiManagerRef mgr, const char* model_id);

// Model download (blocking — platform wraps in async)
// Returns NULL on success, error JSON string on failure.
// progress_cb receives (bytes_downloaded, total_bytes, user_data).
typedef void (*MollotovAiDownloadProgressCb)(int64_t downloaded, int64_t total, void* user_data);
char* mollotov_ai_download_model(MollotovAiManagerRef mgr,
                                 const char* model_id,
                                 MollotovAiDownloadProgressCb progress_cb,
                                 void* user_data);

// Ollama
void mollotov_ai_set_ollama_endpoint(MollotovAiManagerRef mgr, const char* endpoint);
bool mollotov_ai_ollama_reachable(MollotovAiManagerRef mgr);
char* mollotov_ai_ollama_list_models(MollotovAiManagerRef mgr);
char* mollotov_ai_ollama_infer(MollotovAiManagerRef mgr,
                               const char* model_name,
                               const char* request_json);

// HF cloud inference
char* mollotov_ai_hf_infer(MollotovAiManagerRef mgr,
                            const char* model_id,
                            const char* request_json);

#ifdef __cplusplus
}
#endif
```

**Step 3: Create stub implementation**

```cpp
// native/core-ai/src/ai_c_api.cpp
#include "mollotov/ai_c_api.h"
#include "ai_c_api_internal.h"

extern "C" {

MollotovAiManagerRef mollotov_ai_create(const char* models_dir) {
  try {
    return new MollotovAiManager(
        mollotov::ai_internal::SafeCString(models_dir));
  } catch (...) {
    return nullptr;
  }
}

void mollotov_ai_destroy(MollotovAiManagerRef mgr) {
  delete mgr;
}

void mollotov_ai_free_string(char* str) {
  delete[] str;
}

// --- stubs (filled in by later tasks) ---

void mollotov_ai_set_hf_token(MollotovAiManagerRef, const char*) {}
char* mollotov_ai_get_hf_token(MollotovAiManagerRef) { return nullptr; }
char* mollotov_ai_list_approved_models(MollotovAiManagerRef) { return nullptr; }
char* mollotov_ai_model_fitness(MollotovAiManagerRef, const char*, double, double) { return nullptr; }
bool mollotov_ai_is_model_downloaded(MollotovAiManagerRef, const char*) { return false; }
char* mollotov_ai_model_path(MollotovAiManagerRef, const char*) { return nullptr; }
bool mollotov_ai_remove_model(MollotovAiManagerRef, const char*) { return false; }
char* mollotov_ai_download_model(MollotovAiManagerRef, const char*, MollotovAiDownloadProgressCb, void*) { return nullptr; }
void mollotov_ai_set_ollama_endpoint(MollotovAiManagerRef, const char*) {}
bool mollotov_ai_ollama_reachable(MollotovAiManagerRef) { return false; }
char* mollotov_ai_ollama_list_models(MollotovAiManagerRef) { return nullptr; }
char* mollotov_ai_ollama_infer(MollotovAiManagerRef, const char*, const char*) { return nullptr; }
char* mollotov_ai_hf_infer(MollotovAiManagerRef, const char*, const char*) { return nullptr; }

}  // extern "C"
```

**Step 4: Create internal header**

```cpp
// native/core-ai/src/ai_c_api_internal.h
#pragma once

#include <cstring>
#include <new>
#include <string>

#include <nlohmann/json.hpp>

namespace mollotov::ai_internal {

using json = nlohmann::json;

inline const char* SafeCString(const char* value) {
  return value == nullptr ? "" : value;
}

inline char* CopyString(const std::string& value) {
  char* buffer = new (std::nothrow) char[value.size() + 1];
  if (buffer == nullptr) return nullptr;
  std::memcpy(buffer, value.c_str(), value.size() + 1);
  return buffer;
}

}  // namespace mollotov::ai_internal

struct MollotovAiManager {
  std::string models_dir;
  std::string hf_token;
  std::string ollama_endpoint = "http://localhost:11434";

  explicit MollotovAiManager(std::string dir) : models_dir(std::move(dir)) {}
};
```

**Step 5: Add to root CMakeLists**

In `native/CMakeLists.txt`, add before `engine-chromium-desktop`:

```cmake
add_subdirectory(core-ai)
```

**Step 6: Create empty test scaffold**

Create `native/core-ai/tests/CMakeLists.txt`:

```cmake
function(add_ai_test name)
  add_executable(${name} ${ARGN})
  target_link_libraries(${name} PRIVATE mollotov_core_ai)
  add_test(NAME ${name} COMMAND ${name})
endfunction()

add_ai_test(test_ai_catalog test_ai_catalog.cpp)
```

Create `native/core-ai/tests/test_ai_catalog.cpp`:

```cpp
#include "mollotov/ai_c_api.h"
#include <cassert>
#include <iostream>

void TestCreateDestroy() {
  auto* mgr = mollotov_ai_create("/tmp/test_models");
  assert(mgr != nullptr);
  mollotov_ai_destroy(mgr);
}

int main() {
  TestCreateDestroy();
  std::cout << "PASS: test_ai_catalog" << std::endl;
  return 0;
}
```

**Step 7: Build and verify**

```bash
cd native && mkdir -p .build && cd .build
cmake .. -DBUILD_TESTING=ON && cmake --build . --target mollotov_core_ai
ctest -R test_ai_catalog --output-on-failure
```

**Step 8: Commit**

```bash
git add native/core-ai/ native/CMakeLists.txt
git commit -m "feat(native): scaffold core-ai shared library with C API"
```

---

### Task 2: Model catalog and fitness evaluation

**Files:**
- Create: `native/core-ai/src/model_catalog.h`
- Create: `native/core-ai/src/model_catalog.cpp`
- Modify: `native/core-ai/src/ai_c_api_internal.h`
- Modify: `native/core-ai/src/ai_c_api.cpp`
- Modify: `native/core-ai/CMakeLists.txt`
- Modify: `native/core-ai/tests/test_ai_catalog.cpp`

**Step 1: Write tests**

Add to `test_ai_catalog.cpp`:

```cpp
#include <nlohmann/json.hpp>
using json = nlohmann::json;

void TestListApprovedModels() {
  auto* mgr = mollotov_ai_create("/tmp/test_models");
  char* result = mollotov_ai_list_approved_models(mgr);
  assert(result != nullptr);
  json models = json::parse(result);
  assert(models.is_array());
  assert(models.size() >= 2);  // gemma-4-e2b-q4, gemma-4-e2b-q8
  assert(models[0].contains("id"));
  assert(models[0].contains("name"));
  assert(models[0].contains("hugging_face_repo"));
  assert(models[0].contains("size_bytes"));
  assert(models[0].contains("capabilities"));
  mollotov_ai_free_string(result);
  mollotov_ai_destroy(mgr);
}

void TestModelFitnessRecommended() {
  auto* mgr = mollotov_ai_create("/tmp/test_models");
  char* result = mollotov_ai_model_fitness(mgr, "gemma-4-e2b-q4", 32.0, 50.0);
  json fitness = json::parse(result);
  assert(fitness["fitness"] == "recommended");
  mollotov_ai_free_string(result);
  mollotov_ai_destroy(mgr);
}

void TestModelFitnessNoStorage() {
  auto* mgr = mollotov_ai_create("/tmp/test_models");
  char* result = mollotov_ai_model_fitness(mgr, "gemma-4-e2b-q4", 32.0, 0.1);
  json fitness = json::parse(result);
  assert(fitness["fitness"] == "no_storage");
  assert(fitness.contains("message"));
  mollotov_ai_free_string(result);
  mollotov_ai_destroy(mgr);
}
```

**Step 2: Build, verify tests fail**

```bash
cd native/.build && cmake --build . && ctest -R test_ai_catalog --output-on-failure
```

**Step 3: Implement model_catalog.h/cpp**

`native/core-ai/src/model_catalog.h`:

```cpp
#pragma once
#include <string>
#include <vector>
#include <nlohmann/json.hpp>

namespace mollotov {

struct ApprovedModel {
  std::string id;
  std::string name;
  std::string hugging_face_repo;
  std::string hugging_face_file;
  int64_t size_bytes;
  double ram_when_loaded_gb;
  std::vector<std::string> capabilities;
  double min_ram_gb;
  double recommended_ram_gb;
  std::string quantization;
  int context_window;
  std::string summary;

  std::string download_url() const;
  nlohmann::json to_json() const;
};

struct ModelFitness {
  enum Level { kRecommended, kPossible, kNotRecommended, kNoStorage };
  Level level;
  std::string message;

  nlohmann::json to_json() const;
};

class ModelCatalog {
 public:
  static const std::vector<ApprovedModel>& approved_models();
  static const ApprovedModel* find(const std::string& id);
  static ModelFitness fitness(const ApprovedModel& model,
                              double total_ram_gb,
                              double disk_free_gb);
};

}  // namespace mollotov
```

`native/core-ai/src/model_catalog.cpp` — implement with the two Gemma models (same data as `AIModelCatalog.swift`), `download_url()` returns `https://huggingface.co/{repo}/resolve/main/{file}`, `fitness()` checks disk/RAM thresholds.

**Step 4: Wire into C API**

Implement `mollotov_ai_list_approved_models` and `mollotov_ai_model_fitness` in `ai_c_api.cpp` by delegating to `ModelCatalog`.

**Step 5: Build, run tests**

```bash
cmake --build . && ctest -R test_ai_catalog --output-on-failure
```

**Step 6: Commit**

```bash
git add native/core-ai/
git commit -m "feat(native): model catalog and fitness evaluation in core-ai"
```

---

### Task 3: HF token and model store (download, validate, remove)

**Files:**
- Create: `native/core-ai/src/model_store.h`
- Create: `native/core-ai/src/model_store.cpp`
- Modify: `native/core-ai/src/ai_c_api.cpp`
- Modify: `native/core-ai/CMakeLists.txt`
- Create: `native/core-ai/tests/test_ai_store.cpp`

**Step 1: Write tests**

`test_ai_store.cpp`:

```cpp
#include "mollotov/ai_c_api.h"
#include <cassert>
#include <cstdio>
#include <filesystem>
#include <iostream>
#include <nlohmann/json.hpp>

namespace fs = std::filesystem;
using json = nlohmann::json;

void TestHfToken() {
  auto* mgr = mollotov_ai_create("/tmp/test_ai_store");
  mollotov_ai_set_hf_token(mgr, "hf_test_123");
  char* token = mollotov_ai_get_hf_token(mgr);
  assert(std::string(token) == "hf_test_123");
  mollotov_ai_free_string(token);
  mollotov_ai_destroy(mgr);
}

void TestModelNotDownloaded() {
  auto* mgr = mollotov_ai_create("/tmp/test_ai_store_empty");
  assert(!mollotov_ai_is_model_downloaded(mgr, "gemma-4-e2b-q4"));
  char* path = mollotov_ai_model_path(mgr, "gemma-4-e2b-q4");
  // Path returned even if not downloaded (for resolution)
  assert(path != nullptr);
  mollotov_ai_free_string(path);
  mollotov_ai_destroy(mgr);
}

void TestRemoveModel() {
  std::string dir = "/tmp/test_ai_store_rm";
  fs::create_directories(dir + "/gemma-4-e2b-q4");
  // Write a fake model file
  std::ofstream(dir + "/gemma-4-e2b-q4/model.gguf") << "fake";
  std::ofstream(dir + "/gemma-4-e2b-q4/metadata.json") << "{}";

  auto* mgr = mollotov_ai_create(dir.c_str());
  assert(mollotov_ai_is_model_downloaded(mgr, "gemma-4-e2b-q4"));
  assert(mollotov_ai_remove_model(mgr, "gemma-4-e2b-q4"));
  assert(!mollotov_ai_is_model_downloaded(mgr, "gemma-4-e2b-q4"));
  mollotov_ai_destroy(mgr);
  fs::remove_all(dir);
}

int main() {
  TestHfToken();
  TestModelNotDownloaded();
  TestRemoveModel();
  std::cout << "PASS: test_ai_store" << std::endl;
  return 0;
}
```

**Step 2: Implement model_store.h/cpp**

Key methods:
- `is_downloaded(id)` — checks `{models_dir}/{id}/model.gguf` exists and > 1 MB
- `model_path(id)` — returns `{models_dir}/{id}/model.gguf`
- `remove(id)` — deletes `{models_dir}/{id}/` directory
- `download(id, token, progress_cb)` — constructs `URLRequest` with `Authorization: Bearer {token}` header, downloads to `.download` temp file, validates size, atomically moves to final location, writes `metadata.json`. Returns error string or empty on success. **Uses cpp-httplib** for the HTTP download.

**Step 3: Add cpp-httplib dependency**

In `native/core-ai/CMakeLists.txt`, fetch httplib:

```cmake
FetchContent_Declare(
  cpp_httplib
  GIT_REPOSITORY https://github.com/yhirose/cpp-httplib.git
  GIT_TAG v0.18.3
  GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(cpp_httplib)

target_link_libraries(mollotov_core_ai
  PUBLIC mollotov_core_protocol nlohmann_json::nlohmann_json
  PRIVATE httplib::httplib
)
```

**Note:** cpp-httplib supports HTTPS via system OpenSSL/SecureTransport. On macOS it uses SecureTransport by default. On Android the platform layer should handle HTTPS downloads instead (see Task 7).

**Step 4: Implement download with auth and validation**

In `model_store.cpp`, the download function:
1. Looks up the model in the catalog
2. Parses the HF download URL into host + path
3. Creates an `httplib::SSLClient` to `huggingface.co`
4. Sets `Authorization: Bearer {token}` if token is non-empty
5. Follows redirects (HF uses 302 to CDN)
6. Streams response body to `{models_dir}/{id}/model.gguf.download`
7. Calls `progress_cb` with bytes/total during download
8. On HTTP 401/403: returns `{"error":"auth_required","message":"..."}`
9. On completion: validates file size > 1 MB (reject HTML error pages)
10. Atomically renames `.download` to `model.gguf`
11. Writes `metadata.json`

**Step 5: Wire C API implementations**

Replace stubs in `ai_c_api.cpp` for `set_hf_token`, `get_hf_token`, `is_model_downloaded`, `model_path`, `remove_model`, `download_model`.

**Step 6: Build, run tests**

```bash
cmake --build . && ctest -R test_ai_store --output-on-failure
```

**Step 7: Commit**

```bash
git add native/core-ai/
git commit -m "feat(native): HF token, model store, and authenticated downloads"
```

---

### Task 4: Ollama HTTP client

**Files:**
- Create: `native/core-ai/src/ollama_client.h`
- Create: `native/core-ai/src/ollama_client.cpp`
- Modify: `native/core-ai/src/ai_c_api.cpp`
- Modify: `native/core-ai/CMakeLists.txt`
- Create: `native/core-ai/tests/test_ai_ollama.cpp`

**Step 1: Write tests**

`test_ai_ollama.cpp` — tests for endpoint setting, JSON parsing of model list responses, and inference request construction. Mock the HTTP layer by testing the parsing logic directly (not a live Ollama server).

```cpp
void TestOllamaEndpoint() {
  auto* mgr = mollotov_ai_create("/tmp/test_ollama");
  mollotov_ai_set_ollama_endpoint(mgr, "http://localhost:11434");
  // Reachability depends on live server — just verify no crash
  mollotov_ai_ollama_reachable(mgr);
  mollotov_ai_destroy(mgr);
}
```

**Step 2: Implement ollama_client.h/cpp**

- `is_reachable()` — GET `{endpoint}/api/tags`, return true on 2xx within 2s timeout
- `list_models()` — GET `{endpoint}/api/tags`, parse JSON `{"models":[...]}`, detect vision capabilities (llava, bakllava, moondream), return JSON array
- `infer(model, request_json)` — POST `{endpoint}/api/chat` or `/api/generate` depending on whether `messages` array is present. Parse Ollama response format (token counts, duration in nanoseconds → ms).

Uses cpp-httplib (plain HTTP, Ollama is local).

**Step 3: Wire C API, build, test, commit**

```bash
git commit -m "feat(native): Ollama HTTP client in core-ai"
```

---

### Task 5: HF cloud inference

**Files:**
- Create: `native/core-ai/src/hf_cloud_client.h`
- Create: `native/core-ai/src/hf_cloud_client.cpp`
- Modify: `native/core-ai/src/ai_c_api.cpp`
- Create: `native/core-ai/tests/test_ai_hf_cloud.cpp`

**Step 1: Write tests**

Test request construction and response parsing (no live API calls).

**Step 2: Implement hf_cloud_client.h/cpp**

HF Inference API:
- Endpoint: `https://api-inference.huggingface.co/models/{model_id}`
- Method: POST
- Headers: `Authorization: Bearer {token}`, `Content-Type: application/json`
- Body: `{"inputs": "prompt text", "parameters": {"max_new_tokens": N, "temperature": T}}`
- Response: `[{"generated_text": "..."}]`

The client:
- Takes a model ID (from HF, e.g. `google/gemma-2-2b-it` or the same repo as native models)
- Sends the prompt to the Inference API
- Returns JSON: `{"response": "...", "inferenceTimeMs": N, "backend": "hf_cloud"}`
- On 401/403: returns `{"error":"auth_required"}`
- On 503 (model loading): returns `{"error":"model_loading","message":"Model is loading, try again"}`

**Step 3: Wire C API, build, test, commit**

```bash
git commit -m "feat(native): HF cloud inference client in core-ai"
```

---

### Task 6: Wire core-ai into macOS app

**Files:**
- Modify: `apps/macos/project.yml` — add header/library search paths and linker flag
- Modify: `apps/macos/Mollotov/Mollotov-Bridging-Header.h` — import `ai_c_api.h`
- Create: `apps/macos/Mollotov/AI/AIManager.swift` — Swift wrapper around C API
- Modify: `apps/macos/Mollotov/AI/AIState.swift` — delegate to AIManager instead of inline logic
- Modify: `apps/macos/Mollotov/Views/AIChatPanel.swift` — add HF token button + popover
- Modify: `apps/macos/Mollotov/Views/BrowserView.swift` — wire auth-failure navigation

**Step 1: Update project.yml**

Add to `HEADER_SEARCH_PATHS`:
```yaml
- "$(PROJECT_DIR)/../../native/core-ai/include"
```

Add to `LIBRARY_SEARCH_PATHS`:
```yaml
- "$(PROJECT_DIR)/../../native/.build/core-ai"
```

Add to `OTHER_LDFLAGS`:
```yaml
- "-lmollotov_core_ai"
```

**Step 2: Update bridging header**

```objc
#import "mollotov/ai_c_api.h"
```

**Step 3: Create AIManager.swift**

Thin Swift wrapper that creates the `MollotovAiManagerRef` on init, calls C functions, and converts between `char*` and `String`. All methods are synchronous — `AIState` wraps them in `Task {}` for async.

```swift
final class AIManager {
    private let ref: MollotovAiManagerRef

    init(modelsDir: String) {
        ref = mollotov_ai_create(modelsDir)!
    }

    deinit { mollotov_ai_destroy(ref) }

    var hfToken: String {
        get { string(mollotov_ai_get_hf_token(ref)) }
        set { mollotov_ai_set_hf_token(ref, newValue) }
    }

    func listApprovedModels() -> [[String: Any]] { ... }
    func modelFitness(id: String, ramGB: Double, diskGB: Double) -> [String: Any] { ... }
    func isModelDownloaded(id: String) -> Bool { ... }
    func modelPath(id: String) -> String { ... }
    func removeModel(id: String) -> Bool { ... }
    func downloadModel(id: String, progress: ((Int64, Int64) -> Void)?) -> String? { ... }
    func ollamaReachable() -> Bool { ... }
    func ollamaListModels() -> [[String: Any]] { ... }
    func ollamaInfer(model: String, requestJSON: String) -> [String: Any] { ... }
    func hfCloudInfer(modelId: String, requestJSON: String) -> [String: Any] { ... }

    private func string(_ ptr: UnsafeMutablePointer<CChar>?) -> String {
        guard let ptr else { return "" }
        defer { mollotov_ai_free_string(ptr) }
        return String(cString: ptr)
    }
}
```

**Step 4: Refactor AIState to use AIManager**

Replace inline HTTP calls, model catalog data, and download logic with calls to `AIManager`. Keep the `@Published` properties and `@MainActor` scheduling — only the business logic moves.

**Step 5: Add HF token button + popover to AIChatPanel**

Same UI as described in the superseded `2026-04-03-hf-token-flow.md` plan (Task 4) — "Set HF Token" button in NATIVE header, SecureField popover.

**Step 6: Wire auth-failure navigation in BrowserView**

When a download returns `auth_required`, navigate the browser to `https://huggingface.co/settings/tokens`.

**Step 7: Build the native library for macOS**

```bash
cd native/.build && cmake .. && cmake --build . --target mollotov_core_ai
```

**Step 8: Build and launch the macOS app**

```bash
cd apps/macos && xcodebuild -project Mollotov.xcodeproj -scheme Mollotov -configuration Debug build
```

**Step 9: Commit**

```bash
git add apps/macos/ native/core-ai/
git commit -m "feat(macos): wire core-ai shared library into macOS app"
```

---

### Task 7: Wire core-ai into Android app

**Files:**
- Modify: `apps/android/app/src/main/cpp/CMakeLists.txt` — link `mollotov_core_ai`
- Modify: `apps/android/app/src/main/cpp/mollotov_jni.cpp` — add JNI wrappers for ai C API
- Create: `apps/android/app/src/main/java/com/mollotov/browser/nativecore/AiManager.kt` — Kotlin wrapper
- Modify: `apps/android/app/src/main/java/com/mollotov/browser/ai/AIHandler.kt` — delegate to AiManager

**Step 1: Update Android CMakeLists**

```cmake
target_link_libraries(mollotov_jni
  PRIVATE
    mollotov_core_state
    mollotov_core_protocol
    mollotov_core_ai
)
```

**Step 2: Add JNI wrappers**

Follow existing pattern in `mollotov_jni.cpp`:

```cpp
extern "C" JNIEXPORT jlong JNICALL
Java_com_mollotov_browser_nativecore_NativeCore_aiManagerCreateNative(
    JNIEnv* env, jobject, jstring models_dir) {
  auto dir = JStringToUtf8(env, models_dir);
  return reinterpret_cast<jlong>(mollotov_ai_create(dir.c_str()));
}
// ... wrappers for each C API function
```

**Step 3: Create Kotlin AiManager wrapper**

**Step 4: Refactor AIHandler.kt to delegate to native core-ai**

**Step 5: Build and verify**

```bash
cd apps/android && ./gradlew build
```

**Step 6: Commit**

```bash
git commit -m "feat(android): wire core-ai shared library into Android app"
```

---

### Task 8: Wire core-ai into iOS app

**Files:**
- Modify: iOS Xcode project settings — add header/library paths
- Modify: iOS bridging header — import `ai_c_api.h`
- Create: `apps/ios/Mollotov/AI/AIManager.swift` — same wrapper as macOS
- Modify: `apps/ios/Mollotov/AI/AIState.swift` — delegate to AIManager

Same approach as Task 6 but for iOS target. iOS won't use `download_model` for local GGUF files (no llama.cpp on iOS), but will use HF cloud inference and Ollama.

**Commit:**

```bash
git commit -m "feat(ios): wire core-ai shared library into iOS app"
```

---

### Task 9: Remove duplicated Swift/Kotlin AI logic

**Files:**
- Modify: `apps/macos/Mollotov/AI/AIState.swift` — remove inline model catalog, download logic, Ollama HTTP calls
- Modify: `apps/android/app/src/main/java/com/mollotov/browser/ai/AIHandler.kt` — remove Ollama HTTP duplication
- Delete: model catalog data from platform code (single source of truth is now `model_catalog.cpp`)

**Step 1: Audit remaining duplication**

Grep for any inline HF URLs, Ollama HTTP calls, or model catalog definitions in platform code. Remove anything that's now handled by core-ai.

**Step 2: Verify builds on all platforms**

```bash
# macOS
cd apps/macos && xcodebuild -scheme Mollotov -configuration Debug build

# Android
cd apps/android && ./gradlew build
```

**Step 3: Commit**

```bash
git commit -m "refactor: remove platform-duplicated AI logic, single source in core-ai"
```

---

### Task 10: Update docs

**Files:**
- Modify: `docs/functionality.md` — add HF token flow, HF cloud inference backend
- Modify: `docs/architecture.md` — document core-ai library in native layer
- Create: `native/core-ai/README.md` — module overview, C API reference

**Commit:**

```bash
git commit -m "docs: document core-ai shared library and HF token/cloud inference"
```

---

## Summary

| Task | What | Tests |
|------|------|-------|
| 1 | Scaffold `native/core-ai` + CMake + stubs | create/destroy |
| 2 | Model catalog + fitness | catalog listing, fitness levels |
| 3 | HF token + model store + authenticated downloads | token get/set, download validation |
| 4 | Ollama HTTP client | endpoint, list, infer |
| 5 | HF cloud inference | request/response parsing |
| 6 | macOS integration + HF token UI | Xcode build + manual test |
| 7 | Android integration | Gradle build |
| 8 | iOS integration | Xcode build |
| 9 | Remove duplication | All platforms build |
| 10 | Documentation | — |
