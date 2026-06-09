#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/native-phase"

fail() {
  printf 'native-phase test failed: %s\n' "$1" >&2
  exit 1
}

[[ -x "$script" ]] || fail "scripts/native-phase is missing or not executable"

start_output="$("$script" --dry-run start 6.2 modal-manager)"
grep -q "git fetch --prune" <<<"$start_output" || fail "start dry-run does not fetch/prune"
grep -q "git switch post-web-runtime" <<<"$start_output" || fail "start dry-run does not switch to post-web-runtime"
grep -q "git merge --ff-only origin/post-web-runtime" <<<"$start_output" || fail "start dry-run does not fast-forward post-web-runtime"
grep -q "git switch -c codex/native-modal-manager" <<<"$start_output" || fail "start dry-run does not create expected branch"
grep -q "macos/eDEXNative/Package.swift" <<<"$start_output" || fail "start dry-run does not print native Package.swift"
grep -q "macos/eDEXNative/Sources/Stores/ShellState.swift" <<<"$start_output" || fail "start dry-run does not print ShellState reference"

precheck_output="$("$script" --dry-run precheck)"
grep -q "cargo build --release" <<<"$precheck_output" || fail "precheck dry-run does not build the release FFI dylib"
grep -q "swift build --build-tests" <<<"$precheck_output" || fail "precheck dry-run does not include swift build --build-tests"
grep -q "cargo check --tests" <<<"$precheck_output" || fail "precheck dry-run does not include cargo check --tests"

verify_output="$("$script" --dry-run verify)"
grep -q "~/.swiftly/bin/swift test" <<<"$verify_output" || fail "verify dry-run does not include swift test"
grep -q "cargo clippy -- -D warnings" <<<"$verify_output" || fail "verify dry-run does not include clippy gate"
grep -q "smoke-window" <<<"$verify_output" && fail "verify must NOT run the smoke-window (CI-safe gate)"

smoke_output="$("$script" --dry-run smoke)"
grep -q "~/.swiftly/bin/swift run eDEXNative --smoke-window" <<<"$smoke_output" || fail "smoke dry-run does not include smoke-window"

pr_output="$("$script" --dry-run pr "feat(native): add native modal manager" "feat(native): add native modal manager" "Modal manager summary")"
grep -q "compile floor" <<<"$pr_output" || fail "pr dry-run does not run the compile floor (precheck)"
grep -q "git commit -m" <<<"$pr_output" || fail "pr dry-run does not include commit"
grep -q "git push -u origin" <<<"$pr_output" || fail "pr dry-run does not include push"
grep -q "gh pr create --base post-web-runtime" <<<"$pr_output" || fail "pr dry-run does not create PR against post-web-runtime"

detached_repo="$(mktemp -d)"
trap 'rm -rf "$detached_repo"' EXIT
cp "$script" "$detached_repo/native-phase"
(
  cd "$detached_repo"
  git init -q
  git config user.email "native-phase@example.invalid"
  git config user.name "native-phase test"
  touch README.md
  git add README.md
  git commit -q -m "init"
  git switch --detach -q HEAD
  detached_output="$(./native-phase --dry-run pr "feat(native): dry run" "feat(native): dry run" "Detached dry-run summary")"
  grep -q "codex/native-dry-run-placeholder" <<<"$detached_output" || fail "pr dry-run does not use placeholder branch on detached HEAD"
  grep -q "gh pr create --base post-web-runtime" <<<"$detached_output" || fail "pr dry-run detached HEAD does not print PR command"
)

printf 'native-phase tests passed\n'
