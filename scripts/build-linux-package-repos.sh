#!/bin/bash
set -euo pipefail

SITE_DIR="site"
REPOSITORY="${GITHUB_REPOSITORY:-}"
OWNER="${GITHUB_REPOSITORY_OWNER:-}"

usage() {
  cat <<'EOF'
Usage: scripts/build-linux-package-repos.sh [--site-dir <dir>]
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --site-dir)
      SITE_DIR="$2"
      shift 2
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "${REPOSITORY}" ]; then
  echo "GITHUB_REPOSITORY must be set" >&2
  exit 1
fi

if [ -z "${OWNER}" ]; then
  OWNER="${REPOSITORY%%/*}"
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

ASSET_DIR="${WORK_DIR}/assets"
APT_ROOT="${SITE_DIR}/packages/apt"
RPM_ROOT="${SITE_DIR}/packages/rpm"
mkdir -p "${ASSET_DIR}"
rm -rf "${SITE_DIR}/packages"
mkdir -p "${APT_ROOT}" "${RPM_ROOT}"

mapfile -t TAGS < <(gh api --paginate "repos/${REPOSITORY}/releases" --jq '.[] | select(.draft == false) | .tag_name')

for tag in "${TAGS[@]}"; do
  gh release download "${tag}" \
    --repo "${REPOSITORY}" \
    --dir "${ASSET_DIR}" \
    --pattern '*.deb' \
    --pattern '*.rpm' \
    --skip-existing
done

APT_POOL="${APT_ROOT}/pool/main/m/kelpie"
APT_DIST="${APT_ROOT}/dists/stable/main/binary-amd64"
mkdir -p "${APT_POOL}" "${APT_DIST}"

find "${ASSET_DIR}" -maxdepth 1 -name '*.deb' -exec cp -a {} "${APT_POOL}/" \;

pushd "${APT_ROOT}" >/dev/null
apt-ftparchive \
  -o APT::FTPArchive::Release::Origin="UnlikeOtherAI" \
  -o APT::FTPArchive::Release::Label="Kelpie" \
  -o APT::FTPArchive::Release::Suite="stable" \
  -o APT::FTPArchive::Release::Codename="stable" \
  packages pool/main > dists/stable/main/binary-amd64/Packages
gzip -kf dists/stable/main/binary-amd64/Packages
apt-ftparchive \
  -o APT::FTPArchive::Release::Origin="UnlikeOtherAI" \
  -o APT::FTPArchive::Release::Label="Kelpie" \
  -o APT::FTPArchive::Release::Suite="stable" \
  -o APT::FTPArchive::Release::Codename="stable" \
  release dists/stable > dists/stable/Release

if [ -n "${APT_GPG_KEY_ID:-}" ]; then
  gpg --batch --yes --armor --export "${APT_GPG_KEY_ID}" > "${APT_ROOT}/kelpie-archive-keyring.asc"
  gpg --batch --yes --pinentry-mode loopback --default-key "${APT_GPG_KEY_ID}" \
    --clearsign -o dists/stable/InRelease dists/stable/Release
  gpg --batch --yes --pinentry-mode loopback --default-key "${APT_GPG_KEY_ID}" \
    --detach-sign -o dists/stable/Release.gpg dists/stable/Release
fi
popd >/dev/null

mkdir -p "${RPM_ROOT}/x86_64"
find "${ASSET_DIR}" -maxdepth 1 -name '*.rpm' -exec cp -a {} "${RPM_ROOT}/x86_64/" \;
createrepo_c "${RPM_ROOT}/x86_64"

BASE_URL="https://${OWNER}.github.io/${REPOSITORY#*/}/packages"
if [ -n "${APT_GPG_KEY_ID:-}" ]; then
  APT_INSTALL_COMMANDS=$(cat <<EOF
curl -fsSL ${BASE_URL}/apt/kelpie-archive-keyring.asc | sudo gpg --dearmor -o /usr/share/keyrings/kelpie-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/kelpie-archive-keyring.gpg] ${BASE_URL}/apt stable main" | sudo tee /etc/apt/sources.list.d/kelpie.list
sudo apt update
sudo apt install kelpie
EOF
)
else
  APT_INSTALL_COMMANDS=$(cat <<EOF
echo "deb [trusted=yes] ${BASE_URL}/apt stable main" | sudo tee /etc/apt/sources.list.d/kelpie.list
sudo apt update
sudo apt install kelpie
EOF
)
fi

cat > "${SITE_DIR}/packages/index.html" <<EOF
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Kelpie Linux Packages</title>
    <style>
      body { font-family: sans-serif; margin: 2rem auto; max-width: 50rem; line-height: 1.5; }
      code, pre { background: #f5f5f5; padding: 0.15rem 0.3rem; border-radius: 4px; }
      pre { padding: 1rem; overflow-x: auto; }
    </style>
  </head>
  <body>
    <h1>Kelpie Linux Packages</h1>
    <p>Release automation publishes Linux packages here for manual download, APT, and DNF-compatible package managers.</p>
    <h2>APT (Debian and Ubuntu)</h2>
    <pre><code>${APT_INSTALL_COMMANDS}</code></pre>
    <h2>DNF / Yum (Fedora and compatible distros)</h2>
    <pre><code>sudo tee /etc/yum.repos.d/kelpie.repo &lt;&lt;'REPO'
[kelpie]
name=Kelpie
baseurl=${BASE_URL}/rpm/x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
REPO
sudo dnf install kelpie</code></pre>
    <p>Manual downloads remain available on the GitHub release page for <code>.tar.gz</code>, <code>.deb</code>, <code>.rpm</code>, and <code>.AppImage</code>.</p>
  </body>
</html>
EOF
