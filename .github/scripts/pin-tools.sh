#!/bin/bash
# Pin the Xcode and XcodeGen used by Test and UI Walk. No network secret, no content pack.
set -euo pipefail
sudo xcode-select -s /Applications/Xcode_26.6.app
xcodebuild -version
XCODEGEN_VERSION=2.46.0
if ! command -v xcodegen >/dev/null 2>&1 || [[ "$(xcodegen --version 2>/dev/null || true)" != *"$XCODEGEN_VERSION"* ]]; then
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/xcodegen.zip" "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"
  unzip -q "$tmp/xcodegen.zip" -d "$tmp/xcodegen"
  bin=$(find "$tmp/xcodegen" -type f -name xcodegen -perm -111 | head -1)
  if [ -z "$bin" ]; then
    bin=$(find "$tmp/xcodegen" -type f -name xcodegen | head -1)
  fi
  if [ -z "$bin" ]; then
    echo "XcodeGen ${XCODEGEN_VERSION} 的压缩包里没有 xcodegen"
    exit 1
  fi
  sudo mkdir -p /usr/local/bin
  sudo cp "$bin" /usr/local/bin/xcodegen
  sudo chmod +x /usr/local/bin/xcodegen
  hash -r
fi
xcodegen --version
