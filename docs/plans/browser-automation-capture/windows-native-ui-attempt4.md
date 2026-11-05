# Windows native spatial and Stop evidence: f188 attempt4

Root independently reviewed the actual native Canvas and Stop PNGs and accepted this exact spatial/Stop/partial/recovery case. It does not establish native fade/wobble animation, physical pointer clicking, foreground/minimize/modal behavior, browser zoom, or final G07 source acceptance.

## Revision and identities

- Native source: f188883fbbbf16703b3154d81ed609d187a4e4fa; version0.1.15, unsigned private candidate.
- EXE SHA256:54c8be31e003853947182c9461755bf4e7be5f91a2c64fcfb97ed5da1a32d755.
- DLL SHA256:421e4162fca5ab484ce2901b087800e435e9272a48fd6e161d9cffc5f9fdf60f.
- Test source:b7c8d471; SDK helper source:3b886d7798d2154fd686de6fe4ccd81d4e5d4446.
- WGC executable SHA256:0cd9b736a2a2ed170b92750c917fc73665f07630c34bdbaddde37514c407b774.
- UIA executable SHA256:c3c6da4306fcf618b4deca2550a215ff24042e966162c3e7dcee2d793a14d034.
- Validator SHA256:0245ab3b5b76bcc780a208a000abf87e30b0b09d493f990702e45197a6a6cf31.
- Exact Session1 PID56076, start2026-11-05T04:39:57.9273422Z, launch7fe0741edfd44b9cbf604fe965411cc3f49825f92924ff6f7fe75845150c4514, private port28420.
- The immutable build manifest, source/binary hashes and fourteen evidence-file hashes are retained in the receipt below.

## Actual native result

The normal public CLI launched the private candidate. Existing authenticated APIs prepared a synthetic button and semantic click. The observed viewport was959x415 CSS pixels, DPR2, visual scale1. The actual trusted click landed at230,180, the button center.

The spatial fixture used red radius24, duration5000ms (strict schema maximum), fade=false and wobble=false. Pointer endpoint presentation was enabled; this one native still is not trajectory or animation evidence. Separate exported timelines cover those features.

Windows Graphics Capture targeted only exact own KelpieScriptPresentation HWND54069320. Cursor inclusion was off, secondary windows excluded, default border retained, frame pool2, no picker/access request/desktop item. Session closed before encoding. No desktop DC, CUA, SetFocus, SendInput or global cursor movement ran.

The actual1918x830 BGRA surface reported straight alpha:1,584,554 zero-alpha pixels,6,780 partial-alpha pixels,606 opaque pixels. Every PNG alpha byte matched raw BGRA. Nothing was composited behind the transparent surface. The connected red component contained7305 pixels (minimum1810), centered460.06,360.12 against expected460,360, radius48. Root's independent file view confirmed the red circle and pointer on this native Canvas.

The separate88x32 PrintWindow capture shows the real native Stop script button. Exact own UIA InvokePattern invoked it once. The run became aborted, returned four valid partial artifacts and recovered on the next run. Legacy evaluate correctly returned BUSY during playback; click-event evaluation and spatial validation occurred only after Stop and terminal status.

Capture requested2026-11-05T04:40:04.432Z and completed04:40:05.074Z,642ms, at workflow elapsed3349.97ms. The terminal run was febefe0daf14bcd2d88c215712d82b3bd9e9f6c5f5b4f4ad. Two PNGs and both21-frame GIF/MP4 partial outputs passed hash checks and complete independent decoding on Minis.

## Evidence and cleanup

Maxis receipt:
D:/BuildArtifacts/kelpie/capture-windows-20261104/windows-native-ui-attempt4-receipt.json

Receipt SHA256:
f89278a0e0167ed73019cee01e43aa2808d1d44051145d77cc8f389a7e577d14

Raw report:
D:/BuildArtifacts/kelpie/capture-windows-20261104/uia-wgc-f188-attempt4/report.json

Local native Canvas:
C:/Users/ondre/.codex/worktrees/capture-windows-client-20261104/.cache/capture-evidence/uia-wgc-f188-attempt4/wgc-native-window/frame.png

Canvas PNG SHA256:
1a74b88fada0e8941811bbab5a1a4081f66efff3b02805accff13ff9c2b09e98

Local native Stop:
C:/Users/ondre/.codex/worktrees/capture-windows-client-20261104/.cache/capture-evidence/uia-wgc-f188-attempt4/native-stop-window/KelpieScriptStop-6358152.png

Stop SHA256:
fa6854ba2b4e8e32254d69bc78f13e35cb872dd60f9fc256713c46f73784055b

Local copied-media-report.json/full-decode-report.json in that same attempt4 directory verify the four partials. These are SCP copies of prior authenticated artifact downloads, not new cross-host opaque-ID retrieval evidence.

The exact Interactive/Limited on-demand task had no triggers. The hard Job enforced one CPU/Normal/2GiB,170s; task cap180s. Public CLI stop plus exact-process wait completed43ms before the Job parent exited. Task definition/result/cleanup and Job policy remain alongside the raw report. Task/process/socket/readiness/running alias were absent after cleanup; other-owner52960 remained. No own app, capture session or Job remains.

All earlier failures remain separate and immutable: PrintWindow red-text false positive; first opaque-origin fixture failure; second active-legacy-read/scope failure; third incorrect COM IID failure. None was relabeled as native success.

## Changed-state screenshot scope

This is a new capture-presentation and Stop state with no prior equivalent on primary main195eb. The final PR can state that in the Before cell and show the actual native Canvas and Stop images in After. Do not substitute renderer exports or unrelated unchanged chrome. The final candidate must still consume and verify later shared target fixes.
