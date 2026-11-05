#!/bin/bash
set -euo pipefail
if [[ $# != 2 || ! "$1" =~ ^[0-9a-fA-F]{40}$ || ! "$2" =~ ^[0-9a-fA-F]{40}$ ]]; then
  echo "Expected exact base and head commit hashes" >&2
  exit 1
fi
changed_files="$(mktemp)"
trap 'rm -f -- "${changed_files}"' EXIT
# Fail closed on missing commits/diff failure; process-substitution status is
# deliberately not used because it can turn a failed diff into a false skip.
git diff --name-only -z "$1" "$2" -- > "${changed_files}"
changed=false
while IFS= read -r -d "" file; do
  case "${file}" in
    apps/linux/*|packaging/linux/*|packages/shared/*|native/core-*/*|native/desktop-account/*|native/desktop-connect/*|native/engine-chromium-desktop/*|native/CMakeLists.txt|native/cmake/*|scripts/native/*|scripts/*linux*|scripts/download-cef.sh|Makefile|package.json|pnpm-lock.yaml|pnpm-workspace.yaml|.github/workflows/linux-native.yml)
      changed=true ;;
  esac
done < "${changed_files}"
echo "build=${changed}"
