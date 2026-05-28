# eDEX-UI v3 — Ultrareview (Security Audit & Fixes)

**Scope:** full front-to-back snapshot audit of the JS↔Rust migration.
**Baseline:** branch `master` @ `06ec245` · 2026-05-28 · target `aarch64-apple-darwin` (only supported platform).
**Outcome:** all findings below fixed on branch `security/xss-ipc-hardening` → **PR #10**.

---

## Core framing

The renderer holds **unscoped IPC primitives** — `pty_spawn` (arbitrary exec), `fs_writefile`/`fs_readfile` (arbitrary write/read) — behind `withGlobalTauri: true` and a permissive CSP. So any DOM-injection sink fed external data is **arbitrary code execution on the host**, not merely XSS. The audit therefore prioritized eliminating reachable injection sinks.

---

## Findings (by severity)

### HIGH — reachable XSS → RCE

| # | Location | Issue | Fix (brief) |
|---|----------|-------|-------------|
| H1 | `filesystem.class.js:391` (+317/327/337/338) | Raw filename `${e.name}` in `innerHTML`; fired on directory render with no click (`<img onerror>`). Raw `e.name`/`e.path` also interpolated into inline `onclick`. | Escape name+type via `_escapeHtml`; route disk/theme/kblayout `onclick` through runtime `fsDisp.cwd[i]` lookups so names never enter the handler string. |
| H2 | `fuzzyFinder.class.js:110` | Raw match name `${file.name}` in `innerHTML`. | Wrap in `_escapeHtml`. |
| H3 | `toplist.class.js:34, 159` | Raw process name `${proc.name}` (auto-refreshing panel, no user action needed). | Escape name/user/state/started. |

### MEDIUM

| # | Location | Issue | Fix (brief) |
|---|----------|-------|-------------|
| M1 | `pty.rs` reader thread | Cleanup was 100% frontend-driven; a WKWebView reload/theme-change orphaned the shell + leaked the map entry & master fd. | Reader thread now reaps the handle + kills the child when its read loop ends. |
| M2 | `settings.rs:226,236` (`get_theme`/`get_keyboard_layout`) | Renderer-supplied `name` joined onto a trusted dir unvalidated → `name="../../etc/hosts"` reads arbitrary `*.json`. | `validate_basename()` rejects separators/`..`/NUL; unit-tested. |
| M3 | `keyboard.class.js:76–83` | Keyboard-layout label fields in `innerHTML` unescaped → malicious layout = XSS. | Escape every label field. |

### LOW / hardening

| # | Location | Issue | Fix (brief) |
|---|----------|-------|-------------|
| L1 | `tauri.conf.json:28` | CSP allowed `'unsafe-eval'` (no loaded lib needs it; JS eval already hard-disabled). | Removed `'unsafe-eval'`. (`'unsafe-inline'` retained — inline handlers still depend on it.) |
| L2 | renderer-wide | Inline `onclick=` handlers force `'unsafe-inline'` and amplify attribute-injection. | **Deferred** — migrate to `addEventListener` (larger refactor) to later drop `unsafe-inline`. |
| L3 | `renderer.js:637, 648` | Shortcuts-help reflects `shortcuts.json` trigger/action into `value=""` unescaped. | Escape both. |
| L4 | `native_mount.rs:164–185` | Transient `NSString`s in `build_view` never released (one-time leak). | Release after use (matches `native_modal`/`set_clock_text` pattern). |
| L5 | `native_mount.rs` | `native_mount_set_*` reachable regardless of `experimentalNative*` (client-side gating only). | Documented at the trust boundary; safe today (view hidden/text-only). |

**Also hardened:** `_escapeHtml` (`renderer.js:5`) now coerces `undefined`/non-string input instead of throwing.

---

## Verification

`node --check` (5 files) ✓ · `node --test` 30/30 ✓ · `cargo check` ✓ · `cargo clippy --all-targets -- -D warnings` ✓ · `cargo fmt --check` ✓ · `cargo test` 18/18 ✓ (incl. 2 new `validate_basename` tests).

**Not runtime-verified** (reviewer `cargo tauri dev` smoke test recommended): L1 CSP change (terminal/WebGL render) and L4 AppKit releases (native panel draw). Both independently revertable.

---

## Out of scope / accepted

- The unscoped `fs_*`/`pty_spawn` commands are inherent to a terminal + file manager; defense is sink hygiene (above) + CSP, not command scoping.
- **Dependabot (3 alerts: `nix`, `glib`)** — confirmed Linux/BSD-gated transitive deps **not compiled into the macOS binary** (`cargo tree --target aarch64-apple-darwin` shows both absent). Left open as accepted risk; only relevant if a Linux build is added.
