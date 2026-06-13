# QoL improvements

Excluding Developer ID signing/notarization/Gatekeeper work until next month.

## Legend

- `~~~` means fix is in progress.
- `---` means task is complete.
- `???` means work has not started.

## Key findings

`???` **1. Phase 9-prime terminal renderer**
The original Rust terminal emulator + custom Swift cell renderer was explicitly carved out as a separate future project. Current SwiftTerm path is accepted and shippable; this only matters if you want full ownership over terminal rendering later.

`---` **2. Native PDFKit viewer**
PDFs currently show the intended deferred message. A real PDFKit modal is the clean optional enhancement. *(Done in PR #50: in-app PDFKit modal, off-main-thread load.)*

`???` **3. Netstat/network panel**
iface persists in settings, but network-interface monitoring is marked deferred to v0.2.

`~~~` **4. Remaining keyboard edge cases**
Detached text-field caret movement with arrows, press-and-hold repeat, and multi-touch behavior. Also need to make sure that the keyboard window size scales with the app window size. Right now it overlaps and bleeds into the other windows. *(PR #50: on-screen up/down arrows now do line-aware caret movement in detached fields, and the fuzzy finder routes them to its selection. Press-and-hold repeat already existed. Multi-touch and final scaling QA remain.)*

`---` **5. Keyboard layout file activation**
Clicking a keyboard layout file in the filesystem still opens externally "for now." Since native layout loading exists, making those files apply directly would be a small UX improvement. *(Done in PR #50: keyboard .json files in the keyboards dir apply to the on-screen keyboard for the session.)*

`???` **6. Custom CSS/theme compatibility note or migration**
injectCSS breakage was accepted once the web runtime died. Optional work would be a native theme-extension story, not resurrecting CSS.

`???` **7. Free/manual release QA**
Separate from paid Apple release ops: run the packaged app through a manual checklist, try clean user-data profiles, weird themes/keyboards, media files, PDFs, and long terminal sessions.

## Performance (added 2026-06-12)

`---` **WindowServer idle drain**: the CPU graph's continuous render-server pan kept WindowServer compositing at max display refresh whenever the app was visible (measured steady ~46% WindowServer CPU at idle vs ~25% baseline — the "whole Mac feels slow" symptom). Fixed in PR #50 with a 10 Hz timer-stepped transform that skips occluded windows; a `reducedMotion` settings toggle steps graphs at 1 Hz with zero inter-sample compositor work for battery use.

Remaining known idle costs (small, candidates for later passes): the prepared `AVAudioPlayer` voices keep the audio IO thread alive at idle; SwiftTerm cursor blink; 1 Hz telemetry SwiftUI passes. Note the dev session itself (browser + Terminal + agent) measures ~30-44% WindowServer with the app quit, so judge app perf with the dev tooling closed.

## Ranking

PDFKit and packaged-app manual QA are the most user-visible. Phase 9-prime is the biggest and least urgent. However, the keyboard edge cases cause issues for the actual development process — still highest priority fix. First step is to compile and launch the app, then wait for user's feedback.
