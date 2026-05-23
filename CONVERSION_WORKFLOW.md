# JS/CSS to Swift/Rust Conversion Workflow

This is the execution workflow for migrating the remaining web runtime to native Rust/Swift components in controlled slices.

## Scope

- Replace runtime usage of JS/HTML/CSS with native Rust (gpui path) and Swift where macOS-specific APIs are a better fit.
- Keep visual parity and behavior parity at each step.
- Keep the app shippable after every merge.

## Operating Rules

1. One slice per PR.
2. Each slice has explicit acceptance criteria and rollback path.
3. Never remove compatibility bridges in the same PR that introduces a native replacement.
4. Remove legacy web code only after at least one green validation pass using the native path.

## Slice Pipeline

### Slice 0 - Baseline + Observability

- Lock intake scope (`.cursorignore`) and keep migration metadata current.
- Record before/after measurements for:
  - startup time to interactive shell
  - idle CPU/memory
  - PTY throughput behavior
- Validation:
  - `cargo check`
  - `cargo clippy -- -D warnings`
  - `cargo tauri build --target aarch64-apple-darwin`

### Slice 1 - Low-Risk Panel Pilots

Target panels:
- `clock.class.js`
- `modal.class.js`
- `audiofx.class.js`

Plan:
- Add native implementations behind feature flags or runtime toggles.
- Keep current JS path as fallback.
- Validate visual parity and interaction parity.

Exit criteria:
- Panel behavior matches current output.
- No regressions in terminal tabs, filesystem panel, or settings modal.

### Slice 2 - Telemetry Panel Migration

Target panels:
- `sysinfo.class.js`
- `hardwareInspector.class.js`
- `cpuinfo.class.js`
- `ramwatcher.class.js`
- `toplist.class.js`

Plan:
- Use existing Rust-side snapshot contracts as source of truth.
- Move rendering logic natively; keep bridge payload compatibility until full cutover.

Exit criteria:
- Left column updates remain stable under load.
- Polling frequency and CPU footprint improve or remain neutral.

### Slice 3 - Filesystem + Keyboard + Finder

Target:
- `filesystem.class.js`
- `keyboard.class.js`
- `fuzzyFinder.class.js`

Plan:
- Migrate input, focus, and navigation behavior with strict shortcut parity.
- Keep existing command contracts (`fs_*`) while native surfaces replace DOM views.

Exit criteria:
- Same navigation semantics and shortcuts as current runtime.
- No focus regressions with multi-tab terminal usage.

### Slice 4 - Terminal Renderer Replacement

Target:
- `terminal.class.js`
- `terminalTabs.class.js`
- xterm vendor removal path

Plan:
- Replace xterm rendering with native terminal renderer.
- Keep PTY manager and channel semantics stable while swapping renderer.

Exit criteria:
- Shell interactivity and scrollback parity.
- Tab lifecycle, title updates, cwd tracking, and exit behavior preserved.

### Slice 5 - Web Runtime Decommission

Target:
- `renderer.js`, `ui.html`, remaining CSS and JS classes, vendored frontend libs.

Plan:
- Remove compatibility layers only after all slices are green.
- Retain migration changelog with old->new mapping.

Exit criteria:
- No runtime dependence on web frontend stack.
- Native startup path is default and only path.

## PR Template For Each Slice

Each migration PR should include:

1. **Slice id and module set**
2. **Old -> new ownership mapping**
3. **Compatibility retained in this PR**
4. **Validation evidence**:
   - `cargo check`
   - `cargo clippy -- -D warnings`
   - `cargo tauri build --target aarch64-apple-darwin`
5. **Rollback notes**

## Command Checklist

Run for each slice:

```bash
cargo fmt --all
cargo check
cargo clippy -- -D warnings
cargo tauri build --target aarch64-apple-darwin
```

Optional during incremental frontend coexistence:

```bash
node --check src/renderer.js
node --test src/classes/*.test.js
```

