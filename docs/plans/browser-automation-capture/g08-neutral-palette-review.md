# G08 neutral GIF palette review

Source checkpoint: `be969792b58ced6e67a84e2f624a151851c11ac6`.
This is a test-oracle investigation, not an accepted native timeline.
No shared oracle criterion was changed. Earlier G08 insufficient and
marker-tail failures remain in their original reports.

## Actual controls and bounded study

The Linux owner produced controls using its actual pointer compositor and
3/3/2 GIF encoder, with a 640×450 output, 1280×900 viewport, 0.5 scale,
white scene and pointer at (480,225). The marker is painted over the pointer.
Four final frames from each hashed control were decoded:

| Control | Container SHA-256 | Marker |
| --- | --- | --- |
| Pointer only | `024bb04fd5948aee17fa07508099279e7742ecc112a356bc1e76dc8aa5fa6a8a` | None |
| Small retained | `32688764ba0e7857c34d2bfceec17e041e4d1e32ad4fdfc960c231ca1100040e` | Radius 4 CSS px, 2 output px, alpha 178/255 |
| Faint retained | `eb249c4092fc44b19f3bbfaeb3b012e98dc3c844857995d83226d5596ab10827` | Radius 48 CSS px, 24 output px, alpha approximately 0.0499 |
| Full retained | `b584ddf0599c74535b75fdadc47c2c46d9e128a74ea0902a9879a5842ae7e325` | Radius 48 CSS px, alpha 178/255 |

A research-only decoder examined the scaled Cairo pointer polygon plus a
one-output-pixel antialias margin and required white outside that footprint.
It recognized only exact quantized neutral-pointer triplets inside. All four
tail frames had the same counts within each control:

| Control | Nonwhite outside footprint | Non-neutral inside footprint |
| --- | ---: | ---: |
| Pointer only | 0 | 0 |
| Small retained | 8 | 8 |
| Faint retained | 0 | 12 |
| Full retained | 1780 | 64 |

The study used the verified FFmpeg binary under a one-CPU, 2-GiB, 120-second
JobObject and exited successfully in 12.016 s. Its ignored output and receipt
are `tmp/g08-controls/neutral-job.log` (SHA-256
`20844164729cfcae30746aa5f2cae2c19f23e59b4847d3809ce055797aa0b8a6`)
and `tmp/g08-controls/neutral-job.json` (SHA-256
`3b83107d69dbdb80b781f950c768236b1940d5af388891b5d804ce81aeb83ea7`)
in the owner's Maxis worktree. These are sampled controls, not a proof for
all colors, opacities, transforms or renderers.

## Why the shortcut is not an acceptance rule

The production palette maps neutral grays to eight exact RGB triplets. That
set is not exclusive to neutral pointer pixels. For example, blue at alpha
0.13 over white gives approximately (222,222,255) before encoding and
(218,218,255) after 3/3/2 quantization: the latter is also a neutral-gray
pointer triplet. A rule that accepts every neutral triplet within a coarse
pointer footprint can therefore overlook a real pixel change. The four
observed controls do not disprove this collision. Pixels that encode
identically are not distinguishable from video evidence alone.

The Linux owner separately verified that the actual S/GIF final ROI matched
its independently rendered pointer-only control byte-for-byte under the
stated matched geometry, and that the retained controls differed. That is
useful comparison evidence, not a same-run baseline or a timeline pass.
A model-based oracle would need review of the exact source primitive,
transform, background, quantizer and ambiguity limits, including adversarial
overlap; it must not turn a second recording into runtime ground truth.

The independent MP4 19-red-pixel tail and pointer-control three-pixel residue
remain separate lossy-codec cases. Existing real-encoder controls include an
eight-pixel retained marker and a faint marker below the old threshold, so a
generic 19-pixel allowance is unsound. The present calibrated oracle remains
insufficient when it cannot obtain a stable pre-marker same-position reference;
no result has been promoted to pass.
