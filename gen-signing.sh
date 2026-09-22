#!/usr/bin/env bash
#
# Generate Local.xcconfig from .env so every build (Xcode IDE and xcodebuild) signs with
# the same identity. The identity lives only in .env (gitignored); this script copies the
# values into Local.xcconfig (also gitignored), which Build.xcconfig already ends with
# `#include? "Local.xcconfig"`. Never prints the values. See .env.example.
#
# Upstream leaves DEVELOPMENT_TEAM empty and CODE_SIGN_IDENTITY = "-" in Build.xcconfig,
# and the project sets both to $(inherited) at target level — so this file is the whole
# signing seam and no tracked file ever carries an identity.
#
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "error: .env not found — copy .env.example to .env and set your signing identity." >&2
  exit 1
fi

set -a; source .env; set +a
: "${SIGN_IDENTITY:?set SIGN_IDENTITY in .env (see .env.example)}"
: "${DEV_TEAM:?set DEV_TEAM in .env (see .env.example)}"

# ENTITLEMENTS_VARIANT selects MarkEditMac/Info$(ENTITLEMENTS_VARIANT).entitlements.
# Empty uses the tracked Info.entitlements; ".local" uses a gitignored variant, which is
# where capabilities needing portal registration (app groups) belong.
: "${ENTITLEMENTS_VARIANT:=}"

cat > Local.xcconfig <<EOF
// Generated from .env by gen-signing.sh — do NOT edit or commit (gitignored).
DEVELOPMENT_TEAM = ${DEV_TEAM}
CODE_SIGN_IDENTITY = ${SIGN_IDENTITY}
ENTITLEMENTS_VARIANT = ${ENTITLEMENTS_VARIANT}
EOF

echo "wrote Local.xcconfig"
