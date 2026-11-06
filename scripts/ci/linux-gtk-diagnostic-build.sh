#!/usr/bin/env bash
# Hosted test-only build; the caller provides the existing Fedora dependency recipe.
set -euo pipefail
test "${DISTRO_NAME:-}" = fedora-44
test -n "${DISTRO_INSTALL:-}"
[[ "${DIAGNOSTIC_SOURCE:-}" =~ ^[0-9a-f]{40}$ ]]
eval "${DISTRO_INSTALL}"
curl -fsSL https://nodejs.org/dist/v22.14.0/node-v22.14.0-linux-x64.tar.xz -o /tmp/kelpie-node.tar.xz
printf '%s  %s\n' 69b09dba5c8dcb05c4e4273a4340db1005abeafe3927efda2bc5b249e80437ec /tmp/kelpie-node.tar.xz | sha256sum -c -
tar -xJf /tmp/kelpie-node.tar.xz -C /opt
export PATH="/opt/node-v22.14.0-linux-x64/bin:${PATH}"
npm install --global pnpm@10.12.4
bash scripts/download-cef.sh linux
cef_root="${HOME}/.cache/kelpie/cef/linux64-current"
test -f "${cef_root}/Release/libcef.so"
cmake -S apps/linux -B apps/linux/build-gtk-diagnostic -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCEF_ROOT="${cef_root}" -DBUILD_TESTING=ON \
  -DKELPIE_LINUX_STARTUP_TEST_TRACE=ON -DKELPIE_LINUX_HEADLESS_ONLY=OFF -DKELPIE_LOCAL_LLM=OFF \
  -DKELPIE_LINUX_G08_TEST_OBSERVATION=OFF -DKELPIE_LINUX_ADMISSION_TEST_OBSERVATION=OFF
cache=apps/linux/build-gtk-diagnostic/CMakeCache.txt
for option in BUILD_TESTING KELPIE_LINUX_STARTUP_TEST_TRACE KELPIE_ENABLE_CHROMIUM_DESKTOP; do
  grep -Fx "${option}:BOOL=ON" "${cache}" >/dev/null
done
for option in KELPIE_LINUX_HEADLESS_ONLY KELPIE_LOCAL_LLM KELPIE_LINUX_G08_TEST_OBSERVATION KELPIE_LINUX_ADMISSION_TEST_OBSERVATION; do
  grep -Fx "${option}:BOOL=OFF" "${cache}" >/dev/null
done
cmake --build apps/linux/build-gtk-diagnostic --target kelpie-linux
source_revision="$(git -c safe.directory=/workspace rev-parse HEAD)"
[[ "${source_revision}" =~ ^[0-9a-f]{40}$ ]]
test "${source_revision}" = "${DIAGNOSTIC_SOURCE}"
out=dist/gtk-diagnostic
mkdir -p "${out}"
cp apps/linux/build-gtk-diagnostic/kelpie-linux "${out}/kelpie-linux"
binary_sha="$(sha256sum "${out}/kelpie-linux" | cut -d ' ' -f 1)"
readelf -d "${out}/kelpie-linux" > "${out}/elf-dependencies.txt"
awk '/^(BUILD_TESTING|CEF_ROOT|KELPIE_ENABLE_CHROMIUM_DESKTOP|KELPIE_LOCAL_LLM|KELPIE_LINUX_HEADLESS_ONLY|KELPIE_LINUX_G08_TEST_OBSERVATION|KELPIE_LINUX_ADMISSION_TEST_OBSERVATION|KELPIE_LINUX_STARTUP_TEST_TRACE):/ { print }' "${cache}" > "${out}/build-options.txt"
sha256sum pnpm-lock.yaml > "${out}/lock-sha256.txt"
printf "cef_sdk=%s\n" "$(basename "$(readlink -f "${cef_root}")")" > "${out}/cef-identity.txt"
sha256sum scripts/download-cef.sh >> "${out}/cef-identity.txt"
(
  cd apps/linux/build-gtk-diagnostic
  while IFS= read -r asset; do
    test -n "${asset}"
    test -e "${asset}"
    find -L "${asset}" -type f -print0
  done < /workspace/packaging/linux/runtime-files.txt | sort -z | xargs -0 sha256sum
) > "${out}/runtime-sha256.txt"
SOURCE_REVISION="${source_revision}" BINARY_SHA="${binary_sha}" node - > "${out}/manifest.json" <<'NODE'
const manifest = {
  historicalBase: "c42fc68d7fdfa01fae0cbe9cda82dc39bd8c4dc2",
  source: process.env.SOURCE_REVISION,
  target: "kelpie-linux",
  binarySHA256: process.env.BINARY_SHA,
  options: { BUILD_TESTING: true, CEF: true, GTK: true, STARTUP_TEST_TRACE: true },
};
process.stdout.write(JSON.stringify(manifest, null, 2) + "\n");
NODE
(
  cd "${out}"
  sha256sum manifest.json kelpie-linux build-options.txt runtime-sha256.txt elf-dependencies.txt lock-sha256.txt cef-identity.txt > checksums.txt
)
