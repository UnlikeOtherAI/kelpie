# Windows release readiness

This is a read-only readiness audit and release-policy repair, not a release. Root chooses the final integrated revision and component versions. Nothing has been signed, uploaded, installed or published by this worker.

## Source, build and package

All four Windows version declarations agree on the selected 0.1.16: apps/windows/CMakeLists.txt, resources/kelpie.rc, src/device_info_windows.h and src/windows_runtime.cpp. Keep them in step.

The tested unsigned private candidate is source 9333ff507ec91d06d86e338b1d2d9378daca2ac5. Its DLL hash is 27a474291206310a64e17cce27f6f9c50836af55b997b275d5f31e0fc71bca8c. This does not substitute for rebuilding the final integrated revision and rerunning the public app flow.

Use Maxis, task-owned D: source/build/TEMP paths, normal KELPIE_LOCAL_LLM=ON and the existing Windows CEF bootstrap path. Reuse the verified 152.0.6+g708dc14+chromium-152.0.7977.83 SDK and /MT sandbox wrapper. Final configure must retain USE_SANDBOX=ON, CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded and matching CEF runtime/locales. The verified SDK archive SHA-256 is db3e0751979c3cb3068f732ed4f0ef12ade69d183d98ceee120ad08c8d00f74c.

scripts/build-windows.ps1 supplies the documented bootstrap, static CRT and CTest path. Set resource-appropriate CMAKE_BUILD_PARALLEL_LEVEL explicitly. scripts/package-windows.ps1 validates original bootstrap hash/version, DLL x64/RunWinMain/version and required runtime assets, then stamps a copy of the bootstrap. Packaging output must remain under the dedicated worktree; an ignored .cache/release/windows directory on D: meets that constraint.

## CI is not a signing/publishing authority

The previous release-windows workflow attached unsigned ZIPs directly to public releases. The repaired workflow has contents: read, retains only windows-unsigned-candidate artifacts and has no release-upload job or signing trust. Packaging names the ZIP *-unsigned.zip and records signing_status=unsigned. No unsigned fallback is a release.

The agent preserves this candidate and provenance before signing copies on Maxis. Resource stamping occurs before signing. The existing ZIP stage is temporary, so extract a copy into a dedicated ignored signing directory; do not alter the preserved unsigned input or third-party runtime assets. After signing the first-party EXE/DLL, rebuild the final signed ZIP and fresh checksums/provenance. The old unsigned ZIP checksum cannot describe the signed archive.

## Existing signing authority and tool availability

The approved keyless Azure Artifact Signing Public Trust identity is the existing UnlikeOtherAI identity, not a new PFX or copied OIDC trust:

- Tenant ef7eb500-385d-4162-9239-0abb79887aa9, Subscription 1test.
- Resource group ArtifactGroup, account UOAartifactAccount, profile NessiePublicTrust.
- Endpoint https://neu.codesigning.azure.net/.
- Publisher CN=UnlikeOtherAI s.r.o., O=UnlikeOtherAI s.r.o., L=Mnichovice, S=Central Bohemia, C=CZ.
- Current profile-specific WINDOWS_SIGNER_EKU: 1.3.6.1.4.1.311.97.178939473.798312218.613811551.894157712. The generic Artifact Signing OID does not identify this publisher.

On 5 November 2026, Minis az account show reported the expected tenant and Subscription 1test. The SDK 10.0.26100.0 x64 SignTool is present. Both approved scripts exist at C:/Users/ondre/Projects/nessie/scripts/prepare-windows-signing.ps1 and sign-windows-artifact.ps1. GitHub exposes the configured WINDOWS_ARTIFACT_SIGNING_ENDPOINT/ACCOUNT/PROFILE and WINDOWS_SIGNER_EKU variables in UnlikeOtherAI/Nessie. No credential was read into output, copied or stored.

The coordinator reports that the existing UOA Artifact Signing account is now configured and verified on Maxis. Its durable %USERPROFILE%/.config/unlikeotherai/windows-signing/sign.ps1 takes an unsigned input, a fresh output path, the expected SHA-256 and source commit; it verifies the publisher, profile EKU, timestamp and SignTool result. Use Maxis for final signing, with Minis only as fallback. No task should weaken execution policy or copy tokens.

## Final release/install gates

1. Record the clean final source revision, native dependency versions and unsigned candidate size/SHA-256.
2. Sign verified copies on Maxis using the durable UOA signing script; use Minis only as fallback. Verify Authenticode Status=Valid, exact publisher, timestamp certificate and the profile-specific EKU; run SignTool verify /pa /all /tw for every signed EXE/installer and verify the first-party DLL.
3. Create immutable signed archive/checksum/provenance recording both unsigned input and signed output hashes. Root uploads only that signed result to the coordinated date release.
4. Install/extract the exact published Windows artifact into an owned test location and verify its public download hash, signatures, runtime version and source identity.
5. Run direct /mcp, public --browser alias mcp, semantic scripts, GIF/MP4/PNG export, native Stop accessibility invocation, cancellation/partial recovery and readiness cleanup on that installed artifact.
6. Complete changed-native-UI evidence with strictly owned-window capture. Do not use another task's process as a supposed base or relabel renderer/composited media as a native-window screenshot.

The published artifact and installed signed acceptance remain pending. This audit does not choose a version, publish a release or change the other task's installed app.

Root selected Windows0.1.16 for the final integrated candidate. Fresh origin/main195eb90fa5df47291a75e8d165c72fc2f825e3c9 inspection confirmed all four Windows mirrors0.1.15 before this bump. Only CMake project, RC numeric/string versions, device info and runtime Windows versions changed. Compilation/public replay remains pending; this is not a signed or published release. f1880.1.15 evidence and archived EXE/DLL are preserved. No signing, upload or install has occurred.


The coordinator prepared the existing pinned Microsoft ArtifactSigning.Client 1.0.146 on Minis under the release-tools cache. The archive SHA-256 is 7761e5d8f31e54b764da21d33cd8b0a2940e1b05526c7dfcb5e94b0431426f70; its x64 Azure.CodeSigning.Dlib.dll Authenticode signature is valid for Microsoft Corporation. This preparation did not sign or publish any Kelpie artifact.


On Maxis, the public CLI lifecycle probe at f0e7052b used the frozen 5877 Windows candidate and CLI JavaScript bundle SHA-256 6b47995a9fc6eba32081d2ad9d6784dae9b242afa42ce7e24867d4751fd98280. Its task-owned unready child was retired; the same alias then launched the candidate, reached the owned listener and stopped through the public CLI. The report SHA-256 is 8c24c0d89d7da9280132c8590ac0f773f0a70324adcb87484edc1187a63420bd; task, both PIDs, listener and running alias were independently absent afterward. This proves that bounded lifecycle flow only, not the final integrated candidate, signed package or dense animation gates.
