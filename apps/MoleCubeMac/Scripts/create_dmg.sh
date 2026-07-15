#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
PROJECT="$ROOT_DIR/apps/MoleCubeMac/MoleCubeMac.xcodeproj"
SCHEME="MoleCubeMac"
CONFIGURATION="Release"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
ARCHIVE_PATH="$OUTPUT_DIR/MoleCubeMac.xcarchive"
STAGING_DIR="$OUTPUT_DIR/MoleCube-dmg"
DMG_PATH="$OUTPUT_DIR/MoleCube.dmg"
SOURCE_URL="${SOURCE_URL:-https://github.com/crayhuang/MoleCube}"

if ! git -C "$ROOT_DIR" diff --quiet || ! git -C "$ROOT_DIR" diff --cached --quiet; then
    echo "Refusing to build a release from a dirty checkout. Commit the exact corresponding source first." >&2
    exit 1
fi

COMMIT=$(git -C "$ROOT_DIR" rev-parse HEAD)
TAG=$(git -C "$ROOT_DIR" describe --tags --exact-match "$COMMIT" 2>/dev/null || true)

if [[ -z "$TAG" ]]; then
    echo "Refusing to build a release from an untagged commit. Tag the corresponding source first." >&2
    exit 1
fi

if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    echo "Set DEVELOPER_ID_APPLICATION to a Developer ID Application identity before creating a distributable DMG." >&2
    exit 1
fi

if [[ -e "$ARCHIVE_PATH" || -e "$STAGING_DIR" || -e "$DMG_PATH" ]]; then
    echo "Release output already exists. Choose an empty OUTPUT_DIR to avoid overwriting a prior artifact." >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    ARCHS="arm64 x86_64" \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
    DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"

APP_PATH="$ARCHIVE_PATH/Products/Applications/MoleCubeMac.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "Archive did not contain MoleCubeMac.app." >&2
    exit 1
fi

ARCHS=$(lipo -archs "$APP_PATH/Contents/MacOS/MoleCubeMac")
if [[ "$ARCHS" != *"arm64"* || "$ARCHS" != *"x86_64"* ]]; then
    echo "Expected a universal app, found: $ARCHS" >&2
    exit 1
fi

mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/MoleCube.app"
cp "$ROOT_DIR/LICENSE" "$STAGING_DIR/LICENSE.txt"
cp "$ROOT_DIR/NOTICE" "$STAGING_DIR/NOTICE.txt"

printf '%s\n' \
    "MoleCube source for this DMG: $SOURCE_URL/tree/$COMMIT" \
    "Release tag: $TAG" \
    "This source includes the bundled Mole CLI and all MoleCube modifications." \
    > "$STAGING_DIR/SOURCE-CODE.txt"

hdiutil create \
    -volname "MoleCube" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -ov \
    "$DMG_PATH"

echo "Created $DMG_PATH"
