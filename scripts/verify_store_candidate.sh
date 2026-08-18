#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_dir="$(mktemp -d /tmp/quickdict-store-derived.XXXXXX)"
archive_root="$(mktemp -d /tmp/quickdict-store-archive.XXXXXX)"
signed_root="$(mktemp -d /tmp/quickdict-store-signed.XXXXXX)"
archive_path="$archive_root/QuickDict.xcarchive"

cd "$root_dir"

scripts/generate_xcode_project.sh
swift test
xcodebuild -quiet \
  -project QuickDict.xcodeproj \
  -scheme QuickDict \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_dir" \
  test \
  CODE_SIGNING_ALLOWED=NO \
  CLANG_MODULE_CACHE_PATH="$derived_dir/ModuleCache.noindex" \
  MODULE_CACHE_DIR="$derived_dir/ModuleCache.noindex"

xcodebuild -quiet \
  -project QuickDict.xcodeproj \
  -scheme QuickDict \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_dir" \
  -archivePath "$archive_path" \
  archive \
  CODE_SIGNING_ALLOWED=NO \
  CLANG_MODULE_CACHE_PATH="$derived_dir/ModuleCache.noindex" \
  MODULE_CACHE_DIR="$derived_dir/ModuleCache.noindex"

app_path="$archive_path/Products/Applications/QuickDict.app"
info_path="$app_path/Contents/Info.plist"
privacy_path="$app_path/Contents/Resources/PrivacyInfo.xcprivacy"
assets_path="$app_path/Contents/Resources/Assets.car"

test -d "$app_path"
test -f "$privacy_path"
test -f "$assets_path"
plutil -lint "$info_path" "$privacy_path" Resources/QuickDictStore.entitlements >/dev/null

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_path")"
display_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$info_path")"
icon_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$info_path")"
marketing_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_path")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_path")"
if [[ "$bundle_id" != "com.kexin.quickdict" || "$display_name" != "快捷查词" || "$icon_name" != "AppIcon" ]]; then
  echo "Unexpected Store identity or icon: $bundle_id / $display_name / $icon_name" >&2
  exit 1
fi
if [[ "$marketing_version" != "1.0.0" || "$build_number" != "2" ]]; then
  echo "Unexpected Store version: $marketing_version ($build_number)" >&2
  exit 1
fi

service_message="$(/usr/libexec/PlistBuddy -c 'Print :NSServices:0:NSMessage' "$info_path")"
service_port="$(/usr/libexec/PlistBuddy -c 'Print :NSServices:0:NSPortName' "$info_path")"
service_send_type="$(/usr/libexec/PlistBuddy -c 'Print :NSServices:0:NSSendTypes:0' "$info_path")"
if [[ "$service_message" != "lookupSelection" || "$service_port" != "QuickDict" || "$service_send_type" != "public.utf8-plain-text" ]]; then
  echo "Unexpected Services registration: $service_message / $service_port / $service_send_type" >&2
  exit 1
fi

if /usr/libexec/PlistBuddy -c 'Print :NSAppTransportSecurity:NSAllowsArbitraryLoads' "$info_path" >/dev/null 2>&1; then
  echo "NSAllowsArbitraryLoads must not be present" >&2
  exit 1
fi

architectures="$(lipo -archs "$app_path/Contents/MacOS/QuickDict")"
if [[ "$architectures" != *arm64* || "$architectures" != *x86_64* ]]; then
  echo "Archive is not universal: $architectures" >&2
  exit 1
fi

restricted_symbols='CGPreflightListenEventAccess|CGRequestListenEventAccess|CGPreflightPostEventAccess|CGRequestPostEventAccess|CGEventTapCreate|CGEventCreateKeyboardEvent|AXIsProcessTrusted|AXUIElement'
if nm -u "$app_path/Contents/MacOS/QuickDict" | grep -E "$restricted_symbols" >/dev/null; then
  echo "Archived binary still references a restricted input-monitoring or accessibility API" >&2
  exit 1
fi

restricted_copy='输入监控|辅助功能权限|Control-L|Shift-Option-B'
if strings "$app_path/Contents/MacOS/QuickDict" | grep -E "$restricted_copy" >/dev/null; then
  echo "Archived binary still contains obsolete permission or global-shortcut copy" >&2
  exit 1
fi

if ! strings "$app_path/Contents/MacOS/QuickDict" | grep -F 'lookupSelection:userData:error:' >/dev/null; then
  echo "Archived binary is missing the Services provider selector" >&2
  exit 1
fi

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' Resources/QuickDictStore.entitlements)" != "true" ]]; then
  echo "App Sandbox entitlement is missing" >&2
  exit 1
fi

signed_app="$signed_root/QuickDict.app"
ditto --noextattr --noqtn "$app_path" "$signed_app"
codesign --force --deep --sign - --entitlements Resources/QuickDictStore.entitlements "$signed_app"
codesign --verify --deep --strict "$signed_app"

embedded_entitlements="$(codesign -d --entitlements :- --xml "$signed_app" 2>/dev/null)"
if [[ "$embedded_entitlements" != *'<key>com.apple.security.app-sandbox</key><true/>'* ]]; then
  echo "Signed candidate did not retain App Sandbox" >&2
  exit 1
fi

echo "QuickDict Store candidate verification passed"
echo "Archive: $archive_path"
echo "Ad-hoc sandbox candidate: $signed_app"
echo "Architectures: $architectures"
