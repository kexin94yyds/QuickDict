#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required to regenerate QuickDict.xcodeproj" >&2
  exit 1
fi

cd "$root_dir"
xcodegen generate --spec project.yml
xcodebuild -project QuickDict.xcodeproj -scheme QuickDict -showBuildSettings >/dev/null
echo "Generated and validated QuickDict.xcodeproj"
