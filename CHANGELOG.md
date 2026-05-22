# Changelog

All notable changes to this fork will be documented in this file.

## [3.0.0] - 2026-05-22

### Changed
- Replaced the Electron + Node runtime with a Tauri 2 + Rust native macOS app.
- Retargeted the release to Apple Silicon macOS only (`aarch64-apple-darwin`).
- Replaced the localhost WebSocket terminal channel with in-process Tauri IPC.
- Replaced `node-pty` with Rust `portable-pty` for terminal process management.
- Replaced the `systeminformation` worker model with Rust `sysinfo`/`battery` command handlers.
- Replaced direct Node filesystem access in the renderer with Rust filesystem commands.
- Vendored the frontend runtime assets under `src/assets/vendor/` so the shipped app does not include `node_modules/`.

### Added
- Tauri bundle configuration for `.app` and `.dmg` output.
- Tauri command allow-list in `src-tauri/capabilities/default.json`.
- Native settings/user-data initialization in Rust.
- Production build verification for `cargo +stable tauri build --target aarch64-apple-darwin`.

### Fixed
- Removed the original terminal-control WebSocket attack surface entirely.
- Reduced UI stalls by moving blocking sysinfo, filesystem, and PTY polling work onto Tauri/Tokio blocking tasks.
- Fixed terminal font measurement races by loading bundled fonts before xterm starts and disabling ligature joining for non-ligature terminal themes.

### Deferred
- Network globe, connection list, PDF reader, and update checker are out of the v3.0.0 scope and remain v0.2 backlog items.
- Code signing and notarization are not yet implemented.
- Windows and Linux Tauri targets are not part of this release.

## [Unreleased] - 2025-10-05

### Updated Dependencies

#### Major Updates
- **Electron**: v12.1.0 → v37.6.0 (latest stable)
  - Includes all security patches and performance improvements from 25 major versions
  - Updated Chrome rendering engine to v138
  - Updated Node.js to v22.19.0
- **electron-builder**: v22.14.5 → v26.0.12
  - Better support for modern packaging formats
  - Improved build performance
- **@electron/rebuild**: v3.7.4 (added as recommended package)
  - Replaces deprecated electron-rebuild for native module compilation

#### Frontend Dependencies
- **@xterm/xterm**: v5.5.0 (migrated from deprecated xterm package)
- **@xterm/addon-attach**: v0.11.0 (from xterm-addon-attach v0.6.0)
- **@xterm/addon-fit**: v0.10.0 (from xterm-addon-fit v0.5.0)
- **@xterm/addon-ligatures**: v0.9.0 (from xterm-addon-ligatures v0.5.1)
- **@xterm/addon-webgl**: v0.18.0 (from xterm-addon-webgl v0.11.2)
- **@electron/remote**: v2.1.3 (from v1.2.2)
- **systeminformation**: v5.27.11 (from v5.23.8)
- **ws**: v8.18.3 (from v7.5.10)
- **node-pty**: v1.0.0 (from v0.10.1)
- **pdfjs-dist**: v4.9.296 (from v4.2.67)
- **augmented-ui**: v2.0.0 (from v1.1.2)
- **color**: v4.2.3 (from v3.2.1)
- **geolite2-redist**: v3.0.3 (from v2.0.4)
- **howler**: v2.2.4 (from v2.2.3)
- **maxmind**: v4.3.29 (from v4.3.2)
- **smoothie**: v1.36.1 (from v1.35.0)
- **tail**: v2.2.6 (from v2.2.4)
- **which**: v5.0.0 (from v2.0.2)

#### Build Tool Updates
- **clean-css**: v5.3.3 (from v5.2.1)
- **terser**: v5.44.0 (from v5.9.0)
- **node-abi**: v3.77.0 (from v2.30.1)
- **node-json-minify**: v3.0.0 (from v1.0.0)

### Changed

#### API Compatibility
- Removed deprecated `enableRemoteModule` webPreference (deprecated in Electron 14+)
- Added proper `@electron/remote` initialization with `enable()` call for window
- Updated to use modern Electron IPC patterns

#### Build Requirements
- **Node.js**: Now requires v20.x LTS (previously v16)
- **Python**: Now requires Python 3.8+ (previously locked to 3.10)
- Build scripts no longer require specific Python version path

#### Code Changes
- Migrated all xterm imports to use @xterm/* namespace
- Fixed CommonJS/ESM compatibility issues in dependencies
- Updated import statements in `src/classes/terminal.class.js`

### Fixed
- Zero security vulnerabilities in all dependencies (previously had multiple)
- Electron ASAR integrity bypass vulnerability (CVE in Electron <35.7.5)
- Deprecated package warnings for xterm ecosystem
- Network request vulnerabilities in outdated ws package
- Compatibility with modern Node.js and build tools

### Security
- **Critical**: Updated from Electron 12 (May 2021, end-of-life) to Electron 37 (October 2025)
- **High**: Updated ws from 7.5.10 to 8.18.3 (multiple security fixes)
- **Moderate**: Various dependency security patches

### Documentation
- Updated README with new Node.js v20.x requirement
- Updated README with simplified Python installation (any modern version)
- Added troubleshooting section for build issues
- Added changelog section documenting recent updates
- Simplified installation instructions (removed Python version pinning)

### Developer Experience
- Faster dependency installation (removed legacy version constraints)
- Better compatibility with modern development environments
- Clearer error messages from updated dependencies
- Updated to use @electron/rebuild (recommended by Electron team)

## [2.2.8] - Previous Release

### Security
- Fixed critical WebSocket hijacking vulnerability
- Added origin validation for WebSocket connections
- Rejected unauthorized connection attempts are now logged

---

**Note**: This fork maintains compatibility with the original eDEX-UI while incorporating critical security fixes and modernizing the dependency stack. All changes are designed to be minimal and focused on security, stability, and maintainability.
