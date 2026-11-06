# Hosted Windows PNG encoding experiment

The single [hosted Windows run 42147031897](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42147031897) used source `c382deb13d5c1447afc493f16aa5c7d38bf74f17` and one test-enabled binary for both serial dense-C arms. The control ran first with ordinary PNG encoding; the candidate enabled Chromium's `optimizeForSpeed` on script movie screenshots. Both used DLL SHA-256 `69e50cda40f2f9aa9ec7579399cb65b0b320983c7a3fffa9e65e2c4ca7b1e91d` and bootstrap SHA-256 `54c8be31e003853947182c9461755bf4e7be5f91a2c64fcfb97ed5da1a32d755`. The strict per-artifact oracle was unchanged. Both apps closed through the public interface, and the owned process, readiness file and listener were absent afterward.

| Result | Control | Candidate |
| --- | --- | --- |
| Encoded GIF / MP4 frames | 225 / 225 | 293 / 293 |
| Reported dropped frames per format | 315 | 88 |
| Strict GIF oracle | Insufficient dense motion | Passed |
| Strict MP4 oracle | Insufficient dense motion | Insufficient: tail differs from calibrated pointer-only baseline |
| Screenshot stage median / p90 | 32.195 / 68.006 ms | 23.693 / 35.235 ms |
| Post-fence median / p90 | 35.413 / 49.669 ms | 1.673 / 1.904 ms |
| Encoder stage median / p90 | 12.844 / 13.373 ms | 12.734 / 13.525 ms |
| GIF decoded PTS gap median / p90 | 100 / 150 ms | 100 / 100 ms |
| MP4 decoded PTS gap median / p90 | 103.35 / 155.4 ms | 98.625 / 102.65 ms |
| Maximum screenshot base64 length | 4,444 characters | 17,000 characters |
| App PID peak working set | 133,517,312 bytes | 134,926,336 bytes |

Medians average the two middle values when needed; p90 uses the nearest-rank observation. The 226 control and 421 candidate stage records represent completed sampler `AddFrame` calls after document and viewport checks, including milestone-triggered acquisitions. The Windows movie cadence gate may decline early arrivals before encoder admission: a timing-record count exceeding committed media frames is not, by itself, encoder loss. Each artifact's dropped count combines sampler missed cadence slots and document drops with that format's writer drops. The retained receipt does not separate those components. The arms used the same formula, but the serial order and cache/load differences are not controlled; in particular, the post-fence distribution also changed sharply. These observations do not isolate PNG encoding as the cause of the cadence difference.

The hosted workflow completed its comparison, but the candidate's MP4 did not pass the oracle. This is not a pixel/alpha-equivalence, native WGC, installed release or production-enablement result. Process peaks cover the owned app PID only; CEF process-tree and job peaks were unavailable. No whole-tree memory claim is made.

## Synthetic writer-only tail control

The retained candidate media was independently decoded at calibration frame 87 and final clear-tail frame 292. In the canonical 85×85 marker region, the GIF frames were identical; the MP4 differed in 1,458 of 7,225 pixels, with a maximum channel difference of 7. The original per-frame source BGRA was not retained, so this comparison alone cannot tell whether the captured input changed.

A separate, local Windows writer-only control used the existing production GIF and MP4 writers, without CEF or a browser. It fed 40 frames at 20 fps to each of two cases: clean frames throughout, and clean frames with an intervening synthetic red marker. Each case reused the exact same clean BGRA buffer for baseline and tail. Both GIF comparisons were identical. The clean-only MP4 differed at 94 of 7,225 ROI pixels, maximum channel delta 3; the marker-then-clean MP4 differed at 204 pixels, maximum delta 5. All four files decoded to 40 frames with the expected 50 ms PTS. This demonstrates that the production video encode/decode path can produce strict decoded baseline/tail inequality with identical source pixels; it does not establish why the historical candidate's source or MP4 tail differed, or justify changing the oracle.

The standalone diagnostic executable was compiled from `78f5f7e27ad52eff3c347c2a7ee0ec49766bf3ba` using `/W4 /WX /MT`; its SHA-256 was `8ed2e166fe633cb067f5555046b07124944701891178a9d12e217f9bf1c97b35`. Analyzer source `472d5f199db7ce590d3950d461e9abb605e379f9` differed only in the analyzer; the compiled project sources and headers were checked unchanged and hashed. The corrected analysis receipt SHA-256 is `649475a958a88053573c2e87e5686fdd53a415560abd555a79d86838c12bb4a6`. The first analysis used an incorrect supplied revision and remains preserved but ineligible as provenance evidence; the corrected analysis verifies the revision and does not overwrite it. These synthetic artifacts and receipts remain private; the diagnostic source is isolated research, not an integrated product or build-default change.

The original public artifact `13471995287` included synthetic task-owned profiles and raw logs beyond the intended evidence. It was removed after its byte-exact ZIP was privately retained and its SHA-256 `c786d30418b86b2f871bc2a8e5b663bcf085258e78398b89ddabbeae343e749d` matched GitHub's digest; the workflow run remains. Only the explicit safe receipts and four synthetic media files were selectively extracted into private local storage, with each media length and SHA-256 checked against its oracle input. The private profiles and logs were not inspected to establish whether ephemeral credentials were present. No replay was performed.
