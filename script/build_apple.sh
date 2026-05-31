#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/xcode"
PROJECT="$ROOT_DIR/Apple/PaxHistoriaApple.xcodeproj"

cd "$ROOT_DIR"
npm run build

xcodebuild \
  -project "$PROJECT" \
  -scheme PaxHistoriaMac \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build

xcodebuild \
  -project "$PROJECT" \
  -scheme PaxHistoriaiOS \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -sdk iphonesimulator26.5 \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build
