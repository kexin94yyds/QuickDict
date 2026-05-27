#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="快捷查词.app"
BUILD_APP="$ROOT_DIR/build/QuickDict.app"
RELEASE_BIN="$ROOT_DIR/.build/release/QuickDict"
APPLICATIONS_APP="/Applications/$APP_NAME"
USER_APP="${QUICKDICT_USER_APP:-/Users/apple/查找单词/$APP_NAME}"
BACKUP_DIR="$ROOT_DIR/build/backups"
RUN_TESTS="${RUN_TESTS:-1}"
stamp="$(date +%Y%m%d-%H%M%S)"
STAGING_ROOT="/tmp/quickdict-install-$stamp"
STAGING_APP="$STAGING_ROOT/$APP_NAME"

cleanup() {
  if [[ -n "${STAGING_ROOT:-}" && "$STAGING_ROOT" == /tmp/quickdict-install-* ]]; then
    rm -rf "$STAGING_ROOT"
  fi
}
trap cleanup EXIT

cd "$ROOT_DIR"

if [[ "$RUN_TESTS" == "1" ]]; then
  swift test
fi

swift build -c release

if [[ ! -d "$BUILD_APP" ]]; then
  echo "Missing app template: $BUILD_APP" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"
cp "$RELEASE_BIN" "$BUILD_APP/Contents/MacOS/QuickDict"
xattr -cr "$BUILD_APP"
codesign --force --deep --sign - "$BUILD_APP"
codesign --verify --deep --strict "$BUILD_APP"

mkdir -p "$STAGING_ROOT"
ditto --noextattr --noqtn "$BUILD_APP" "$STAGING_APP"
xattr -cr "$STAGING_APP"
codesign --force --deep --sign - "$STAGING_APP"
codesign --verify --deep --strict "$STAGING_APP"

pkill -x QuickDict 2>/dev/null || true
sleep 1

if [[ -d "$APPLICATIONS_APP" ]]; then
  mv "$APPLICATIONS_APP" "$BACKUP_DIR/Applications-$APP_NAME.pre-install-$stamp"
fi
if [[ -d "$USER_APP" ]]; then
  mv "$USER_APP" "$BACKUP_DIR/UserDir-$APP_NAME.pre-install-$stamp"
fi

mkdir -p "$(dirname "$USER_APP")"
ditto --noextattr --noqtn "$STAGING_APP" "$APPLICATIONS_APP"
ditto --noextattr --noqtn "$STAGING_APP" "$USER_APP"

xattr -cr "$APPLICATIONS_APP" "$USER_APP"
codesign --force --deep --sign - "$APPLICATIONS_APP"
codesign --force --deep --sign - "$USER_APP"
codesign --verify --deep --strict "$APPLICATIONS_APP"
codesign --verify --deep --strict "$USER_APP"

build_hash="$(shasum -a 256 "$BUILD_APP/Contents/MacOS/QuickDict" | awk '{print $1}')"
staging_hash="$(shasum -a 256 "$STAGING_APP/Contents/MacOS/QuickDict" | awk '{print $1}')"
applications_hash="$(shasum -a 256 "$APPLICATIONS_APP/Contents/MacOS/QuickDict" | awk '{print $1}')"
user_hash="$(shasum -a 256 "$USER_APP/Contents/MacOS/QuickDict" | awk '{print $1}')"

if [[ "$build_hash" != "$staging_hash" || "$build_hash" != "$applications_hash" || "$build_hash" != "$user_hash" ]]; then
  echo "Installed binary hashes do not match staging bundle" >&2
  exit 1
fi

open "$APPLICATIONS_APP"
sleep 1

if ! pgrep -x QuickDict >/dev/null; then
  echo "QuickDict did not start" >&2
  exit 1
fi

pgrep -fl QuickDict
echo "Installed $APP_NAME successfully"
