# Swift/Rust Migration Intake Notes

This file captures the staged intake scope and token sizing used to start the JS/TS/CSS to Swift/Rust conversion effort.

## Intake Scope

The repository now uses `/.cursorignore` to exclude heavy/non-runtime content:

- Build/cache and local state: `.git/`, `.cursor/`, `.claude/`, `.gemini/`, `.codex/`, `.remember/`, `src-tauri/target/`, `node_modules/`, `dist/`
- Heavy non-runtime assets: `media/`, `src/assets/audio/`, `src/assets/icons/`, `src/assets/fonts/`, `src/assets/vendor/`
- Non-runtime content: `docs/`, `file-icons/`, `src/assets/misc/file-icons-match.js`, `LICENSE`

Build-critical components intentionally remain included:

- `src-tauri/gen/`
- `src-tauri/build.rs`
- `.github/workflows/`

## Token Cost Estimate

Token estimates are based on byte counts of staged runtime paths and a rough text-token conversion of `bytes/4` to `bytes/3.5`.

- Minimal with build-critical files:
  - files: 64
  - bytes: 723,676
  - estimated input tokens: 180,919 to 206,764
- Broader with themes/kb/misc:
  - files: 107
  - bytes: 2,068,621
  - estimated input tokens: 517,155 to 591,034

For first-pass analysis, target the minimal set and load subsystem files incrementally.

## `/find-docs` Workflow (Context7)

Use targeted API lookups instead of loading large docs into session context.

1. Resolve library ID first:
   - `npx -y ctx7@latest library tauri "Tauri 2 Channel IPC raw bytes onmessage ArrayBuffer behavior"`
   - `npx -y ctx7@latest library swiftui "macOS app architecture scene lifecycle window management"`
2. Query specific docs:
   - `npx -y ctx7@latest docs /tauri-apps/tauri-docs "JavaScript Channel onmessage payload and Rust Channel<Vec<u8>> behavior"`
   - `npx -y ctx7@latest docs /websites/developer_apple_swiftui "macOS app scene lifecycle window management commands and settings scene"`

Resolved IDs used:

- Tauri: `/tauri-apps/tauri-docs`
- SwiftUI: `/websites/developer_apple_swiftui`

## `/find-skills` Workflow

Use skill discovery for focused migration sub-workflows before broad custom analysis:

- `npx -y skills find "rust tauri ipc"`
- `npx -y skills find "swiftui macos migration"`
- `npx -y skills find "codebase refactor planning"`

Current search results for this niche are low-install; prefer existing trusted local skills first, then adopt external skills selectively.
