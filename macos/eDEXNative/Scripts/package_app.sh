#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${APP_DIR}/../.." && pwd)"
FFI_DIR="${REPO_ROOT}/crates/edex-ffi"
RUST_LIB="${FFI_DIR}/target/release/libedex_ffi.dylib"
DIST_DIR="${REPO_ROOT}/dist"
APP_BUNDLE="${DIST_DIR}/eDEXNative.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
EXECUTABLE="${MACOS_DIR}/eDEXNative"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

swift_bin() {
  if [[ -n "${SWIFT_BIN:-}" ]]; then
    printf '%s' "$SWIFT_BIN"
  elif [[ -x "$HOME/.swiftly/bin/swift" ]]; then
    printf '%s' "$HOME/.swiftly/bin/swift"
  else
    printf 'swift'
  fi
}

sign_item() {
  local item="$1"
  [[ "${SKIP_CODESIGN:-0}" == "1" ]] && return 0

  local args=(--force --sign "$SIGN_IDENTITY")
  if [[ "$SIGN_IDENTITY" != "-" ]]; then
    args+=(--options runtime --timestamp)
  fi
  codesign "${args[@]}" "$item"
}

printf '== build Rust FFI dylib ==\n'
(cd "$FFI_DIR" && cargo build --release)

printf '== build Swift release executable ==\n'
(cd "$APP_DIR" && "$(swift_bin)" build -c release --product eDEXNative)

printf '== assemble app bundle ==\n'
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
cp "$APP_DIR/.build/release/eDEXNative" "$EXECUTABLE"
cp "$RUST_LIB" "$FRAMEWORKS_DIR/libedex_ffi.dylib"
cp -R "$REPO_ROOT/assets" "$RESOURCES_DIR/assets"
cp "$REPO_ROOT/media/icon.icns" "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>eDEXNative</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.theelderemo.edex-ui.native</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>eDEX-UI</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>3.0.0-native</string>
  <key>CFBundleVersion</key>
  <string>3.0.0</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST

printf '== rewrite local dylib linkage ==\n'
chmod +w "$FRAMEWORKS_DIR/libedex_ffi.dylib" "$EXECUTABLE"
install_name_tool -id "@rpath/libedex_ffi.dylib" "$FRAMEWORKS_DIR/libedex_ffi.dylib"
linked_lib="$(otool -L "$EXECUTABLE" | awk '/libedex_ffi[.]dylib/{print $1; exit}')"
if [[ -n "$linked_lib" && "$linked_lib" != "@rpath/libedex_ffi.dylib" ]]; then
  install_name_tool -change "$linked_lib" "@rpath/libedex_ffi.dylib" "$EXECUTABLE"
fi
while IFS= read -r rpath; do
  if [[ "$rpath" == "$FFI_DIR/target/release"* ]]; then
    install_name_tool -delete_rpath "$rpath" "$EXECUTABLE"
  fi
done < <(otool -l "$EXECUTABLE" | awk '/cmd LC_RPATH/{in_rpath=1} in_rpath && /path /{print $2; in_rpath=0}')
if ! otool -l "$EXECUTABLE" | grep -q "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXECUTABLE"
fi

printf '== sign app bundle ==\n'
sign_item "$FRAMEWORKS_DIR/libedex_ffi.dylib"
sign_item "$EXECUTABLE"
sign_item "$APP_BUNDLE"

printf '== validate app bundle ==\n'
plutil -lint "$CONTENTS_DIR/Info.plist"
otool -L "$EXECUTABLE" | grep -q "@rpath/libedex_ffi.dylib"
! otool -l "$EXECUTABLE" | grep -q "$FFI_DIR/target/release"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

printf 'Packaged %s\n' "$APP_BUNDLE"
