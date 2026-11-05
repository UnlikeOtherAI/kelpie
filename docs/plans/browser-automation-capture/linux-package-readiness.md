# Ubuntu DEB and Fedora RPM pre-PR route audit

Read-only common audit,5 November2026. No build,package,install,dispatch or
workflow mutation was started.

## Registered CI route

GitHub Actions workflow API returned these registered paths:
android.yml,ios.yml,lint.yml,macos.yml,pages.yml,release-windows.yml,release.yml,
windows.yml,plus GitHub's dynamic Copilot entries. Primary main195eb90f has no
linux-native.yml. The new reusable Linux workflow therefore cannot currently
be manually dispatched before it exists on default. Registered release.yml
runs on release published,not workflow_dispatch.

There is no existing registered pre-PR Linux manual route proven by this audit.
Do not publish a release,open a premature PR or repurpose Mac/Windows workflows
to bypass that dependency. After normal integration to default,the Linux
workflow's documented dispatch/reusable route becomes available; it cannot
retroactively supply the required pre-PR package evidence.

## Approved permanent follow-up

Root approved a minimal opt-in Linux quality gate through existing default-
registered lint.yml,whose primary version already has workflow_dispatch.
linux_native_candidate is a boolean defaultfalse; only an explicit manual
dispatch calls the authoritative ./linux-native.yml at the SAME selected
ref/commit,with force_build:true,empty release_tag and candidate artifact prefix.
Normal lint/PR/main behavior is unchanged; contents:read,no secrets inheritance
and no publication. No build recipe is copied into lint.yml.

This is a Linux-specific candidate route,not a Mac/Windows workflow workaround.
It avoids waiting indefinitely for offline umac while respecting the dispatch
registration rule. Root reviews the pushed wrapper before any manual dispatch.
The Linux owner owns installed DEB/RPM ABI/sandbox smoke in the callee; existing
build/package/codec tests alone do not close installed runtime acceptance.

Official event and same-ref rules:
[manual dispatch](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
and [reusable workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows).
Focused static YAML/policy tests check defaultfalse,event guard,same-ref call,
read-only/no-secret/no-publish boundaries and unchanged lint. No YAML parser
was installed; GitHub's own parse/dispatch result remains part of the actual
candidate run gate. Static wrapper policy and existing Linux scope tests passed4/4
in8.70s under hard JobObject affinity1/Normal,2GiB,task D: TEMP/TMP; whole job
9.478s. Evidence: linux-candidate-checks.log and policy JSON in common artifacts.
No native/compiler/container/dispatch job was launched by these focused checks.

## Owned cache and host facts

Linux owner reports only the Fedora test worktree:
 /home/ondre/Projects/kelpie-worktrees/capture-linux-20261104,
testHEAD198252bb,native compiled3001,incremental .native-build-gtk.
Toolchain: Ninja Release,GCC16.2.1,GTK3.24.52,Cairo1.18.6,GStreamer1.28.8,
giflib6.1.3 (libgif.so.7). Existing pinned CEF cache:
 /home/ondre/.cache/kelpie/cef/cef_binary_120.2.7+g4bc6a59+chromium-120.0.6099.234_linux64_minimal.
Owner confirmed no app/compiler/LP/media unit remained active at this checkpoint.

No owned umac checkout/cache/reservation and no Ubuntu DEB build/install
evidence were reported. Independent bounded access probes now failed:
umac.local could not resolve;192.168.1.192:22 timed out at5 seconds.
No host key bypass,credential copy or machine change was attempted.

Existing evidence is native Fedora build/media/artifact/OSR/CLI execution,
not RPM/DEB/AppImage packaging or installed runtime verification.

## Minimal legitimate remaining route

- Fedora RPM: the Linux owner can reuse the owned native cache and current
  source for a bounded Linux-specific package/install verification after root
  grants the resource slot. Build a runtime bundle,run package-linux-rpm.sh,
  inspect declared dependencies/ELF GIF SONAME,install via the supported package
  manager and run the installed sandboxed native GTK/OSR/protocol/codec gates.
  The package/install result needs exact source,package/binary hashes and removal/
  supported cleanup evidence. No-CEF refusal is a separate negative case.
- Ubuntu DEB: restore approved SSH access first. Assign an isolated Linux-owner
  test worktree and inspect/reuse any existing compatible toolchain/cache before
  a Linux-specific ABI build. Ubuntu is justified for actual ELF/package runtime
  verification,not general portable compilation. Build/package on the supported
  Ubuntu ABI (or verified matching Ubuntu container on an approved Linux host),
  inspect dependencies,install the actual DEB and execute its installed runtime.
  A Fedora binary cannot substitute merely because a DEB wrapper can be made;
  ELF/library compatibility and runtime codecs must actually be proven.
- Both scripts use the native runtime bundle,CEF/sandbox and media dependencies.
  RPM disables automatic private-CEF dependency generation and binds GIF to the
  actual app ELF SONAME. DEB declares libgif7 and GStreamer>=1.20. Inspect the
  actual package/runtime,not filename or build-only status.
- Keep portable builds on Maxis. Fedora remains a bounded Linux-specific test
  target;do not move generic build/service workloads there. No new owner/agent,
  parallel allocator,token-state edits or user UI are needed.

Ubuntu access/build/install and Fedora package/install gates are open. Root and
the Linux owner schedule those actual phases; this map neither authorizes a
heavy job now nor treats native cache availability as installed-package parity.
