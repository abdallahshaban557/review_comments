#!/usr/bin/env bash
# Publishes the 3 review_comments packages to pub.dev in dependency order:
#   1. review_comments         (internal shared runtime + server + CLI)
#   2. review_comments_jaspr   (single-package Jaspr plugin + CLI)
#   3. review_comments_flutter (single-package Flutter Web plugin + CLI)
#
# Prerequisites:
#   1. Authenticate with your PERSONAL Google account (not @google.com):
#        dart pub login
#   2. Push this repo to https://github.com/abdallahshaban557/review_comments
#      so pub.dev's repository URL check passes for full pub points.
#   3. After initial upload, visit each package's Admin tab on pub.dev to
#      transfer it to your personal verified publisher:
#        https://pub.dev/packages/review_comments/admin
#        https://pub.dev/packages/review_comments_jaspr/admin
#        https://pub.dev/packages/review_comments_flutter/admin

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CredsA="${HOME}/.config/dart/pub-credentials.json"
CredsB="${HOME}/.pub-cache/credentials.json"
if [[ ! -f "${CredsA}" && ! -f "${CredsB}" ]]; then
  echo "Error: No pub.dev credentials found." >&2
  echo "Run 'dart pub login' first and sign in with your PERSONAL Google account." >&2
  exit 1
fi

echo "==> [1/3] Publishing review_comments..."
(cd "${REPO_ROOT}/packages/review_comments" && dart pub publish --force)

echo "==> Waiting for review_comments 0.1.0 to become visible on pub.dev..."
for i in {1..30}; do
  if curl -fsS https://pub.dev/api/packages/review_comments >/dev/null 2>&1; then
    echo "    review_comments is live on pub.dev!"
    break
  fi
  sleep 3
done

strip_overrides() {
  local file="$1"
  python3 - "$file" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
lines = p.read_text().splitlines(keepends=True)
out = []
skip = False
for line in lines:
    if line.startswith('dependency_overrides:'):
        skip = True
        continue
    if skip:
        if line.startswith(' ') or line.startswith('\t') or line.strip() == '':
            continue
        skip = False
    out.append(line)
p.write_text(''.join(out))
PY
}

JASPR_PUBSPEC="${REPO_ROOT}/packages/review_comments_jaspr/pubspec.yaml"
FLUTTER_PUBSPEC="${REPO_ROOT}/packages/review_comments_flutter/pubspec.yaml"
cp "${JASPR_PUBSPEC}" "${JASPR_PUBSPEC}.bak"
cp "${FLUTTER_PUBSPEC}" "${FLUTTER_PUBSPEC}.bak"
restore_pubspecs() {
  [[ -f "${JASPR_PUBSPEC}.bak" ]] && mv "${JASPR_PUBSPEC}.bak" "${JASPR_PUBSPEC}"
  [[ -f "${FLUTTER_PUBSPEC}.bak" ]] && mv "${FLUTTER_PUBSPEC}.bak" "${FLUTTER_PUBSPEC}"
}
trap restore_pubspecs EXIT

strip_overrides "${JASPR_PUBSPEC}"
strip_overrides "${FLUTTER_PUBSPEC}"

echo "==> [2/3] Publishing review_comments_jaspr..."
(cd "${REPO_ROOT}/packages/review_comments_jaspr" && dart pub get && dart pub publish --force)

echo "==> [3/3] Publishing review_comments_flutter..."
(cd "${REPO_ROOT}/packages/review_comments_flutter" && flutter pub get && flutter pub publish --force)

echo ""
echo "All 3 packages published! Assign them to your personal verified publisher at:"
echo "  - https://pub.dev/packages/review_comments/admin"
echo "  - https://pub.dev/packages/review_comments_jaspr/admin"
echo "  - https://pub.dev/packages/review_comments_flutter/admin"
