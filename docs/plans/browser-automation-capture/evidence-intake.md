# Pending native evidence intake

Common owner ingests raw owner/client reports after the actual run. A chat
summary, compiled test, metadata ACK or codec-only vector never becomes a native
semantic/UI pass. Use differential-evidence.md and tests/capture/native-coverage.mjs.

| Runtime | Exercised source / state | Intake needed |
|---|---|---|
| Windows CEF windowed, including hidden normal app | Actual reported missing-marker failure at c852787f344f61dcc3b3ab798ba6a4c979c4fcd3; corrected pixel replay pending | Failure report/media paths and target binary/version/hash; next corrected full source SHA; exact HTTP/direct MCP/generic MCP/CLI records; all-frame GIF/MP4 marker+document observations. |
| Android Chromium phone, windowed | Candidate compiled source ca498e21eb1897918d1bf7a5b0b167bdecb1fc8b; actual installed/exercised identity not yet supplied | APK/native target hashes/version, actual runtime/device identity, raw instrumentation/report paths, public protocol calls, full-decode marker/readiness/extraction/security outcomes. |
| Android Chromium tablet, windowed | Separate cell; never inherited from phone | Same identity/report set independently; matching fixture/viewport conditions for differential comparison. |
| Native UI/Stop on each applicable runtime | No automatic promotion from machine/media tests | Separately authorized and observed local UI evidence; current user hold/handoff limits remain explicit. |

Each accepted input record identifies requirement,host,platform,renderer,
deviceClass,runtimeMode,full exercised revision,reviewer,UTC observation time,
status,kind and result. Actual machine records additionally identify protocol,
target installed version,target binary SHA-256,public entry point,source paths,
steps and independently hashed artifacts. Report client/CLI version separately
from target version; it cannot substitute for native binary identity.

Record only the protocols actually exercised. HTTP does not imply direct MCP,
generic MCP or CLI forwarding. Group multiple same-build cases into the record's
steps/artifacts; failures remain visible alongside successful protocol evidence.
Phone/tablet,GTK/OSR and different native binaries remain distinct.

Decoded-media evidence must retain the raw GIF/MP4,decoder report and frame
artifacts/hashes plus actual marker/document observation. A frame-count prefix
test does not prove marker pixels. Manual-media evidence is separate from native
UI evidence; exported frames cannot establish local Stop/live overlay behavior.
Never overwrite earlier failed-run artifacts with a later replay.

Prepare version1 records in an ignored per-run directory. Artifact ingestion
checks bytes under the chosen root and emits all432 native requirement cells as
acceptance:unreviewed. Unavailable binary/source/protocol identity keeps intake
pending; do not invent hashes or infer executed cases from compiled test names.

No actual phone/tablet or corrected Windows replay report has been ingested by
this reviewer as of this checkpoint. All pending rows above require owner/client
artifact paths before source-linked semantic review and matrix updates.
