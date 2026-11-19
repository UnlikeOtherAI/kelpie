#!/bin/bash
# Publish site/ to https://kelpie.rocks.
#
# kelpie.rocks is served by an nginx container that mounts
# /srv/kelpie-web/dist on the web host. This uploads the site, keeps the
# files it replaces in /srv/kelpie-web/previous, and syncs the upload into
# place. See docs/website.md.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/deploy-website.sh <ssh-target> [--rollback]

  <ssh-target>  SSH host or alias of the machine that serves kelpie.rocks
  --rollback    Put back the version the last deploy replaced
EOF
}

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  usage >&2
  exit 1
fi

TARGET="$1"
MODE="${2:-deploy}"
REMOTE_ROOT="/srv/kelpie-web"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE_DIR="${REPO_ROOT}/site"

rollback() {
  ssh "${TARGET}" "set -e
    test -f '${REMOTE_ROOT}/previous/index.html'
    rsync -a --delete '${REMOTE_ROOT}/previous/' '${REMOTE_ROOT}/dist/'"
  echo "restored the previous version on ${TARGET}"
}

deploy() {
  if [ ! -f "${SITE_DIR}/index.html" ]; then
    echo "site/index.html not found" >&2
    exit 1
  fi

  # Linux package repositories are built into site/packages by CI and
  # published through GitHub Pages only.
  tar -C "${SITE_DIR}" --exclude=./packages -czf - . | ssh "${TARGET}" "set -e
    rm -rf '${REMOTE_ROOT}/incoming'
    mkdir -p '${REMOTE_ROOT}/incoming' '${REMOTE_ROOT}/previous'
    tar -xzf - -C '${REMOTE_ROOT}/incoming'
    test -f '${REMOTE_ROOT}/incoming/index.html'
    chmod -R u=rwX,go=rX '${REMOTE_ROOT}/incoming'
    rsync -a --delete '${REMOTE_ROOT}/dist/' '${REMOTE_ROOT}/previous/'
    rsync -a --delete '${REMOTE_ROOT}/incoming/' '${REMOTE_ROOT}/dist/'
    rm -rf '${REMOTE_ROOT}/incoming'"
  echo "published site/ to ${TARGET}:${REMOTE_ROOT}/dist"
}

case "${MODE}" in
  deploy) deploy ;;
  --rollback) rollback ;;
  *) usage >&2; exit 1 ;;
esac
