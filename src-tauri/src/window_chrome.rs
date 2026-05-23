//! Window chrome tuning for the Tauri main window.
//!
//! Two responsibilities, both done once at app startup on the main thread:
//!   1. Lock the content area to a 16:10 aspect ratio so windowed-mode
//!      resizes (via the OS drag handle, F11 toggle, traffic-light
//!      maximize, etc.) keep the eDEX layout square. macOS enforces this
//!      live during the user's drag, not after release.
//!   2. Make the title bar transparent and let the content view extend
//!      under it. With `tauri.conf.json` `decorations: true`, macOS
//!      auto-hides the title bar entirely in fullscreen but gives us
//!      the standard traffic-light controls in windowed mode — the
//!      best of both worlds.

#![allow(deprecated)]
#![allow(unexpected_cfgs)]

use cocoa::base::{id, YES};
use cocoa::foundation::{NSPoint, NSRect, NSSize};
use objc::{class, msg_send, sel, sel_impl};
use tauri::{AppHandle, Manager};

/// Locked aspect ratio for windowed mode. 16:10 matches the post-1080p
/// MacBook screens and pre-empts the awkward 16:9 letterboxing the
/// original eDEX assumed.
pub const ASPECT_W: f64 = 16.0;
pub const ASPECT_H: f64 = 10.0;

/// NSWindowStyleMask::FullSizeContentView.
const NS_FULLSIZE_CONTENT: u64 = 1 << 15;
/// NSWindowTitleVisibility::Hidden.
const NS_TITLE_HIDDEN: isize = 1;

pub fn configure(app: &AppHandle, keep_geometry: bool) -> Result<(), Box<dyn std::error::Error>> {
    debug_assert!(
        is_main_thread(),
        "window_chrome::configure must run on the main thread"
    );

    let window = app
        .get_webview_window("main")
        .ok_or("window_chrome: main webview window not found")?;
    let ns_window = window
        .ns_window()
        .map_err(|e| format!("window_chrome: ns_window() failed: {e}"))? as id;
    if ns_window.is_null() {
        return Err("window_chrome: ns_window() returned null".into());
    }

    unsafe {
        // 1. Optionally lock content area to 16:10 based on persisted
        //    keepGeometry. When disabled, use NSZeroSize to clear the ratio
        //    lock and keep freeform windowed resizing behavior.
        let aspect = if keep_geometry {
            NSSize::new(ASPECT_W, ASPECT_H)
        } else {
            NSSize::new(0.0, 0.0)
        };
        let _: () = msg_send![ns_window, setContentAspectRatio: aspect];

        // 2. Borderless aesthetic via transparent titlebar + full-size
        //    content view. With decorations enabled we keep the
        //    traffic-light controls (close/min/max) for windowed mode
        //    and macOS hides them automatically in fullscreen.
        let _: () = msg_send![ns_window, setTitlebarAppearsTransparent: YES];
        let _: () = msg_send![ns_window, setTitleVisibility: NS_TITLE_HIDDEN];

        let current_mask: u64 = msg_send![ns_window, styleMask];
        let _: () = msg_send![ns_window, setStyleMask: current_mask | NS_FULLSIZE_CONTENT];

        // Touch NSPoint and NSRect so the imports don't go unused if a
        // future edit removes their direct callers.
        let _ = NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(0.0, 0.0));
    }

    Ok(())
}

fn is_main_thread() -> bool {
    unsafe {
        let nsthread: id = msg_send![class!(NSThread), currentThread];
        let is_main: bool = msg_send![nsthread, isMainThread];
        is_main
    }
}
