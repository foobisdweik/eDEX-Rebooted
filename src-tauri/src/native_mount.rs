//! Slice 1b: sibling NSView mounted into the Tauri window for the future
//! gpui-rendered panel column. Holds geometry only — no rendering content
//! here; that arrives in Slice 1c.
//!
//! Lifecycle:
//!   - `install()` runs once during Tauri's setup hook (main thread).
//!     It creates the NSView at NSZeroRect, installs it above the WKWebView
//!     in the window's contentView, and stashes raw pointers in
//!     `NativeMountState`. The view is created `hidden`.
//!   - JS calls `native_mount_set_rect` (sequence-numbered, latest-wins) on
//!     every #mod_column_left layout change. We dispatch to the main thread
//!     and update [view setFrame:] with the web→AppKit y-flip applied.
//!   - JS calls `native_mount_set_visible({visible:true})` once after the
//!     first rect has shipped, unhiding the view.
//!
//! Thread safety: `MountHandle` stores raw `*mut Object` as `usize` so the
//! struct is `Send + Sync` without lying about thread-safety of the AppKit
//! objects themselves — every dereference happens inside a
//! `dispatch::Queue::main().exec_async` block.

// cocoa 0.26 deprecates its own NSPoint/NSSize/NSRect helpers in favor of
// objc2-foundation. We use them deliberately here because the rest of the
// stack Tauri 2 pulls in is also cocoa-based; mixing objc2-foundation with
// cocoa NSView/NSWindow risks duplicate symbol churn. Slice 1c may migrate
// the whole module to objc2 when it adds CAMetalLayer support.
#![allow(deprecated)]
// `objc` 0.2's `sel_impl!` macro expands to `cfg(feature = "cargo-clippy")`,
// which the modern Rust lint treats as an unknown cfg. The macro is correct
// behavior for the version of objc we depend on; suppress here rather than
// pinning a different version.
#![allow(unexpected_cfgs)]

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

use cocoa::base::{id, nil, NO, YES};
use cocoa::foundation::{NSPoint, NSRect, NSSize, NSString};
use core_foundation::base::TCFType;
use core_graphics::color::CGColor;
use dispatch::Queue;
use objc::runtime::Object;
use objc::{class, msg_send, sel, sel_impl};
use serde::Deserialize;
use tauri::{AppHandle, Manager, State};

#[derive(Clone, Copy)]
struct MountHandle {
    view: usize,
    border_layer: usize,
    label_layer: usize,
    clock_layer: usize,
}

// Safety: every method on `*mut Object` is dispatched to the main thread
// before being touched. The struct itself carries no AppKit-owned mutable
// state — only opaque pointers.
unsafe impl Send for MountHandle {}
unsafe impl Sync for MountHandle {}

impl MountHandle {
    fn view(self) -> id {
        self.view as id
    }
    fn border_layer(self) -> id {
        self.border_layer as id
    }
    fn label_layer(self) -> id {
        self.label_layer as id
    }
    fn clock_layer(self) -> id {
        self.clock_layer as id
    }
}

#[derive(Default)]
pub struct NativeMountState {
    inner: Mutex<Option<MountHandle>>,
    last_seq: AtomicU64,
}

#[derive(Deserialize)]
pub struct WebRect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

/// CALayer autoresizing mask bits (kCALayerWidthSizable | kCALayerHeightSizable).
const CA_AUTORESIZE_W_H: std::os::raw::c_uint = 0x02 | 0x10;

/// NSWindowOrderingMode::Above.
const NS_WINDOW_ABOVE: isize = 1;

pub fn install(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    // Must run on the AppKit main thread because we are about to talk
    // to NSView / NSWindow. Tauri's setup() guarantees this; debug-assert.
    debug_assert!(
        is_main_thread(),
        "native_mount::install must run on the main thread"
    );

    let window = app
        .get_webview_window("main")
        .ok_or("native_mount: main webview window not found")?;
    let ns_window_ptr = window
        .ns_window()
        .map_err(|e| format!("native_mount: ns_window() failed: {e}"))?
        as id;
    if ns_window_ptr.is_null() {
        return Err("native_mount: ns_window() returned null".into());
    }

    let state = app.state::<NativeMountState>();
    let mut inner = state
        .inner
        .lock()
        .map_err(|_| "native_mount: install lock poisoned")?;
    if inner.is_some() {
        return Ok(()); // already installed
    }

    let handle = unsafe { build_view(ns_window_ptr) };
    *inner = Some(handle);
    Ok(())
}

fn is_main_thread() -> bool {
    unsafe {
        let nsthread: id = msg_send![class!(NSThread), currentThread];
        let is_main: bool = msg_send![nsthread, isMainThread];
        is_main
    }
}

unsafe fn build_view(ns_window_ptr: id) -> MountHandle {
    let zero_rect = NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(0.0, 0.0));

    // Root NSView, layer-backed, hidden until set_visible.
    let view: id = msg_send![class!(NSView), alloc];
    let view: id = msg_send![view, initWithFrame: zero_rect];
    let _: () = msg_send![view, setWantsLayer: YES];
    let _: () = msg_send![view, setHidden: YES];

    let root_layer: id = msg_send![view, layer];
    let black = CGColor::rgb(0.0, 0.0, 0.0, 1.0);
    let _: () = msg_send![root_layer, setBackgroundColor: black.as_concrete_TypeRef()];

    // 1px cyan border, full-bounds, follows view via autoresize mask.
    let border_layer: id = msg_send![class!(CALayer), layer];
    let cyan = CGColor::rgb(0.0, 1.0, 1.0, 1.0);
    let _: () = msg_send![border_layer, setBorderColor: cyan.as_concrete_TypeRef()];
    let _: () = msg_send![border_layer, setBorderWidth: 1.0_f64];
    let _: () = msg_send![border_layer, setFrame: zero_rect];
    let _: () = msg_send![border_layer, setAutoresizingMask: CA_AUTORESIZE_W_H];
    let _: () = msg_send![root_layer, addSublayer: border_layer];

    // "S1B native" label, cyan Menlo 11pt, top-left of the view.
    let label_layer: id = msg_send![class!(CATextLayer), layer];
    let ns_label = NSString::alloc(nil).init_str("S1B native");
    let _: () = msg_send![label_layer, setString: ns_label];
    let cyan2 = CGColor::rgb(0.0, 1.0, 1.0, 1.0);
    let _: () = msg_send![label_layer, setForegroundColor: cyan2.as_concrete_TypeRef()];
    let _: () = msg_send![label_layer, setFontSize: 11.0_f64];
    let menlo = NSString::alloc(nil).init_str("Menlo");
    let _: () = msg_send![label_layer, setFont: menlo];
    let label_rect = NSRect::new(NSPoint::new(8.0, 0.0), NSSize::new(100.0, 14.0));
    let _: () = msg_send![label_layer, setFrame: label_rect];
    let _: () = msg_send![root_layer, addSublayer: label_layer];

    // Clock text layer. Hidden by default; Slice 1 pilot toggles content from JS
    // via native_mount_set_clock_text when experimentalNativeClock is enabled.
    let clock_layer: id = msg_send![class!(CATextLayer), layer];
    let empty = NSString::alloc(nil).init_str("");
    let _: () = msg_send![clock_layer, setString: empty];
    let cyan3 = CGColor::rgb(0.0, 1.0, 1.0, 1.0);
    let _: () = msg_send![clock_layer, setForegroundColor: cyan3.as_concrete_TypeRef()];
    let _: () = msg_send![clock_layer, setFontSize: 28.0_f64];
    let menlo_bold = NSString::alloc(nil).init_str("Menlo-Bold");
    let _: () = msg_send![clock_layer, setFont: menlo_bold];
    let _: () = msg_send![clock_layer, setAlignmentMode: NSString::alloc(nil).init_str("right")];
    let clock_rect = NSRect::new(NSPoint::new(8.0, 0.0), NSSize::new(260.0, 36.0));
    let _: () = msg_send![clock_layer, setFrame: clock_rect];
    let _: () = msg_send![clock_layer, setWrapped: NO];
    let _: () = msg_send![root_layer, addSublayer: clock_layer];

    // Retain explicitly — we hand them out as raw pointers and must
    // outlive any contentView ownership churn.
    let _: id = msg_send![view, retain];
    let _: id = msg_send![border_layer, retain];
    let _: id = msg_send![label_layer, retain];
    let _: id = msg_send![clock_layer, retain];

    // Add as subview above the WKWebView (Tauri's first subview of contentView).
    let content_view: id = msg_send![ns_window_ptr, contentView];
    let subviews: id = msg_send![content_view, subviews];
    let count: usize = msg_send![subviews, count];
    if count > 0 {
        let web_view: id = msg_send![subviews, objectAtIndex: 0usize];
        let _: () = msg_send![
            content_view,
            addSubview: view
            positioned: NS_WINDOW_ABOVE
            relativeTo: web_view
        ];
    } else {
        let _: () = msg_send![content_view, addSubview: view];
    }

    MountHandle {
        view: view as usize,
        border_layer: border_layer as usize,
        label_layer: label_layer as usize,
        clock_layer: clock_layer as usize,
    }
}

#[tauri::command]
pub async fn native_mount_set_rect(
    state: State<'_, NativeMountState>,
    rect: WebRect,
    dpr: f64,
    seq: u64,
) -> Result<(), String> {
    // Latest-wins backpressure: atomically publish monotonic sequence updates.
    // This avoids racing load/store pairs from briefly regressing last_seq.
    let prev = state.last_seq.fetch_max(seq, Ordering::AcqRel);
    if seq <= prev {
        return Ok(());
    }

    let handle = {
        let inner = state
            .inner
            .lock()
            .map_err(|_| "native_mount: set_rect lock poisoned".to_string())?;
        match *inner {
            Some(h) => h,
            None => return Ok(()),
        }
    };

    Queue::main().exec_async(move || unsafe {
        apply_rect(handle, rect, dpr);
    });

    Ok(())
}

unsafe fn apply_rect(handle: MountHandle, rect: WebRect, dpr: f64) {
    let view = handle.view();
    let window: id = msg_send![view, window];
    if window.is_null() {
        return;
    }
    let content_view: id = msg_send![window, contentView];
    let content_frame: NSRect = msg_send![content_view, frame];
    let content_h = content_frame.size.height;

    let frame = NSRect::new(
        NSPoint::new(rect.x, content_h - (rect.y + rect.height)),
        NSSize::new(rect.width, rect.height),
    );
    let _: () = msg_send![view, setFrame: frame];

    let root_layer: id = msg_send![view, layer];
    let _: () = msg_send![root_layer, setContentsScale: dpr];
    let _: () = msg_send![handle.border_layer(), setContentsScale: dpr];
    let _: () = msg_send![handle.label_layer(), setContentsScale: dpr];
    let _: () = msg_send![handle.clock_layer(), setContentsScale: dpr];

    // Re-anchor the label to top-left of the (now-resized) view.
    let label_rect = NSRect::new(
        NSPoint::new(8.0, rect.height - 18.0),
        NSSize::new(100.0, 14.0),
    );
    let _: () = msg_send![handle.label_layer(), setFrame: label_rect];

    let clock_rect = NSRect::new(
        NSPoint::new(rect.width - 268.0, rect.height - 52.0),
        NSSize::new(260.0, 36.0),
    );
    let _: () = msg_send![handle.clock_layer(), setFrame: clock_rect];
}

#[tauri::command]
pub async fn native_mount_set_visible(
    state: State<'_, NativeMountState>,
    visible: bool,
) -> Result<(), String> {
    let handle = {
        let inner = state
            .inner
            .lock()
            .map_err(|_| "native_mount: set_visible lock poisoned".to_string())?;
        match *inner {
            Some(h) => h,
            None => return Ok(()),
        }
    };

    Queue::main().exec_async(move || unsafe {
        let hidden = if visible { NO } else { YES };
        let _: () = msg_send![handle.view(), setHidden: hidden];
    });

    Ok(())
}

#[tauri::command]
pub async fn native_mount_set_clock_text(
    state: State<'_, NativeMountState>,
    text: String,
) -> Result<(), String> {
    let handle = {
        let inner = state
            .inner
            .lock()
            .map_err(|_| "native_mount: set_clock_text lock poisoned".to_string())?;
        match *inner {
            Some(h) => h,
            None => return Ok(()),
        }
    };

    Queue::main().exec_async(move || unsafe {
        let ns_text = NSString::alloc(nil).init_str(&text);
        let _: () = msg_send![handle.clock_layer(), setString: ns_text];
        let _: () = msg_send![ns_text, release];
    });

    Ok(())
}

// Compile-time assertion that `Object` (re-exported from objc) is referenced
// at least once so the unused-import lint stays quiet.
#[allow(dead_code)]
const _: fn() = || {
    let _: *const Object = std::ptr::null();
};
