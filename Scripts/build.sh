#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0}"
BUILD_NUMBER="${2:-1}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "ERROR: XcodeGen is not installed."
  echo "Install it with:  brew install xcodegen"
  exit 1
fi

xcodegen

xcodebuild \
  -project Beam.xcodeproj \
  -scheme Beam \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build

rm -rf Beam.app
cp -R "build/Build/Products/Release/Beam.app" Beam.app
echo ""
echo "Built: $(pwd)/Beam.app  (version $VERSION, build $BUILD_NUMBER)"
