# Conversion Board

This board tracks ownership and order for converting web runtime modules to native Rust/Swift surfaces.

Legend:
- **Status**: `pending`, `in_progress`, `migrated`, `removed`
- **Target Owner**: `rust`, `swift`, or `rust+swift`

## Runtime Modules

| Module | Current | Target Owner | Slice | Status | Notes |
|---|---|---|---|---|---|
| `src/classes/clock.class.js` | web | rust | 1 | in_progress | Native clock text pilot via `experimentalNativeClock` + native mount |
| `src/classes/modal.class.js` | web | rust | 1 | in_progress | Native simple-alert pilot via `experimentalNativeModal` (custom HTML modals still web) |
| `src/classes/audiofx.class.js` | web | swift | 1 | pending | AVFoundation candidate |
| `src/classes/sysinfo.class.js` | web | rust | 2 | pending | Snapshot-backed |
| `src/classes/hardwareInspector.class.js` | web | rust | 2 | pending | Snapshot-backed |
| `src/classes/cpuinfo.class.js` | web | rust | 2 | pending | Chart replacement needed |
| `src/classes/ramwatcher.class.js` | web | rust | 2 | pending | Grid visualization |
| `src/classes/toplist.class.js` | web | rust | 2 | pending | Process table parity |
| `src/classes/filesystem.class.js` | web | rust | 3 | pending | `fs_*` contract stays |
| `src/classes/keyboard.class.js` | web | rust | 3 | pending | Shortcut parity critical |
| `src/classes/fuzzyFinder.class.js` | web | rust | 3 | pending | Input/focus parity |
| `src/classes/terminal.class.js` | web+xterm | rust | 4 | pending | Renderer replacement |
| `src/classes/terminalTabs.class.js` | web | rust | 4 | pending | Tab lifecycle parity |
| `src/renderer.js` | web orchestrator | rust | 5 | pending | Remove after module cutover |
| `src/ui.html` | web shell | rust | 5 | pending | Remove after renderer cutover |

## CSS Decommission Map

| CSS Area | Slice | Status | Notes |
|---|---|---|---|
| `src/assets/css/mod_clock.css` | 1 | pending | Clock parity |
| `src/assets/css/modal.css` | 1 | pending | Modal parity |
| `src/assets/css/mod_sysinfo.css` | 2 | pending | Telemetry panel |
| `src/assets/css/mod_hardwareInspector.css` | 2 | pending | Telemetry panel |
| `src/assets/css/mod_cpuinfo.css` | 2 | pending | Chart replacement |
| `src/assets/css/mod_ramwatcher.css` | 2 | pending | Grid replacement |
| `src/assets/css/mod_toplist.css` | 2 | pending | Table replacement |
| `src/assets/css/mod_processlist.css` | 2 | pending | Modal process list |
| `src/assets/css/filesystem.css` | 3 | pending | Filesystem panel |
| `src/assets/css/keyboard.css` | 3 | pending | On-screen keyboard |
| `src/assets/css/mod_fuzzyFinder.css` | 3 | pending | Finder |
| `src/assets/css/main_shell.css` | 4 | pending | Terminal shell |
| `src/assets/css/main.css` | 5 | pending | Global shell cleanup |

## Current Active Slice

- **Active**: Slice 1 clock pilot
- **Immediate next move**: validate native clock pilot (`experimentalNativePanels=true` and `experimentalNativeClock=true`) then proceed to modal/audiofx.

