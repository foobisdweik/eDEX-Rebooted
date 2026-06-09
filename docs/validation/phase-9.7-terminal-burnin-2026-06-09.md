# Phase 9.7 Terminal Burn-In

Date: 2026-06-09
Branch: `codex/native-terminal-burnin-webview-retirement`

## Result

SwiftTerm burn-in passed for the locally available scenarios:

- shell command execution
- interactive vim write/quit
- interactive nano write/quit
- top one-shot output
- ssh client invocation (`ssh -V`)
- ANSI SGR color output
- Unicode output
- resize propagation (`stty size` changed from `18 69` to `22 87`)
- scrollback output (`seq 1 220`)

Local skips:

- `htop` was not installed.
- `tmux` was not installed.

## Evidence

The burn-in ran in the native app's SwiftTerm surface via a temporary local
`.app` wrapper after terminating stale `eDEXNative` processes. Marker files were
written under `/tmp/edex-native-burnin/`:

- `shell.txt`: `shell-pass`
- `vim.txt`: interactive vim wrote the expected text
- `nano.txt`: interactive nano wrote the expected text
- `top.txt`: contained macOS process/CPU/load output
- `ssh.txt`: contained the OpenSSH version line
- `ansi.txt`: contained 16-color and 256-color SGR escapes
- `unicode.txt`: contained the Unicode sample
- `scrollback.txt`: contained 220 lines
- `size-before.txt` / `size-after.txt`: PTY dimensions changed after window resize
