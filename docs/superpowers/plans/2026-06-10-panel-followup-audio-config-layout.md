# Panel Follow-Up Audio Config Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the release-QA regressions where keyboard audio clips on rapid input, the config ribbon is not clickable, and the bottom filesystem/keyboard layout still wastes or clips space.

**Architecture:** Keep the existing native SwiftUI app and the current collision-managed layout branch. Add pure layout/audio policy tests first, then make the smallest changes in the layout engine, status ribbon geometry, and audio playback service.

**Tech Stack:** SwiftPM, SwiftUI, AVFoundation, XCTest, `scripts/native-phase`, packaged SwiftPM `.app` bundle.

---

### Task 1: Layout Follow-Up

**Files:**
- Modify: `macos/eDEXNative/Sources/EdexRenderingSupport/Layout/LayoutSupport.swift`
- Test: `macos/eDEXNative/Tests/EdexLayoutTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests asserting the status ribbon sits below the 42 pt drag strip, the left column starts below the ribbon, filesystem sits left of keyboard in the bottom band, filesystem absorbs leftover bottom-band width, and screenshot-like 16:10/tiled content sizes keep fixed surfaces separate.

- [ ] **Step 2: Run test to verify failure**

Run: `cd macos/eDEXNative && ~/.swiftly/bin/swift test --filter EdexLayoutTests`
Expected: FAIL before implementation because status ribbon starts at the top inset and keyboard is left of filesystem.

- [ ] **Step 3: Implement layout adjustment**

Move the status ribbon below the titlebar drag strip, set column top from the ribbon bottom, swap bottom order to filesystem then keyboard, keep keyboard width bounded to the preferred visual width, and let filesystem fill the remaining bottom corridor width.

- [ ] **Step 4: Run layout tests**

Run: `cd macos/eDEXNative && ~/.swiftly/bin/swift test --filter EdexLayoutTests`
Expected: PASS.

### Task 2: Rapid Keyboard Audio

**Files:**
- Modify: `macos/eDEXNative/Sources/EdexDomainSupport/Audio/AudioSupport.swift`
- Modify: `macos/eDEXNative/Sources/Services/EdexAudioService.swift`
- Test: `macos/eDEXNative/Tests/NativeAudioTests.swift`

- [ ] **Step 1: Write failing pure policy test**

Add a test that `EdexAudioVoicePolicy.voiceCount(for:)` returns multiple voices for rapid keyboard/input cues and one voice for long or modal cues.

- [ ] **Step 2: Run test to verify failure**

Run: `cd macos/eDEXNative && ~/.swiftly/bin/swift test --filter NativeAudioTests`
Expected: FAIL before implementation because the policy type does not exist.

- [ ] **Step 3: Implement policy and service pool**

Add `EdexAudioVoicePolicy` in the domain audio support module. Update `EdexAudioService` to store `[EdexAudioCue: [AVAudioPlayer]]` and round-robin through prepared voices in `play(_:)` without resetting another in-flight voice of the same cue.

- [ ] **Step 4: Run audio tests**

Run: `cd macos/eDEXNative && ~/.swiftly/bin/swift test --filter NativeAudioTests`
Expected: PASS.

### Task 3: Config Click Verification

**Files:**
- Modify: `macos/eDEXNative/Sources/EdexRenderingSupport/Layout/LayoutSupport.swift`
- Test: `macos/eDEXNative/Tests/EdexLayoutTests.swift`

- [ ] **Step 1: Cover the titlebar hit-test clearance**

The layout tests from Task 1 must assert `layout.statusRibbon.y >= 42` so the status ribbon is below the transparent drag overlay.

- [ ] **Step 2: Verify existing tap action remains wired**

Inspect `ContentView.statusRibbon` and confirm `.onTapGesture { state.openSettingsModal() }` remains on the ribbon after layout changes.

### Task 4: Verification And Release Launch

**Files:**
- No source edits expected.

- [ ] **Step 1: Run focused tests**

Run:
`cd macos/eDEXNative && ~/.swiftly/bin/swift test --filter EdexLayoutTests`
`cd macos/eDEXNative && ~/.swiftly/bin/swift test --filter NativeAudioTests`

- [ ] **Step 2: Run compile and smoke gates**

Run:
`bash scripts/native-phase precheck`
`pkill -x eDEXNative || true; pkill -x eDEX-UI || true; bash scripts/native-phase smoke`

- [ ] **Step 3: Package and launch release app**

Run:
`bash macos/eDEXNative/Scripts/package_app.sh`
If local hardened runtime signing rejects the bundled dylib, re-sign the local QA bundle ad-hoc without hardened runtime, then run:
`/usr/bin/open -n /Users/iphoobis/Projects/eDEX-UI-security-patched/dist/eDEXNative.app`

- [ ] **Step 4: Confirm launch process**

Run:
`ps -axo pid,comm,args | rg '/dist/eDEXNative.app/Contents/MacOS/eDEXNative|eDEXNative.app|eDEXNative' | rg -v 'rg|zsh -lc'`
Expected: one live `eDEXNative` process from `dist/eDEXNative.app`.
