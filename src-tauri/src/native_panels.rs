//! Approach A: per-panel native NSView "slots" mounted above the WKWebView.
//! See docs/superpowers/plans/2026-05-29-native-panel-slots-phase0-1.md.
//!
//! Thread safety: AppKit/CALayer pointers are stored as `usize` and only
//! dereferenced inside `dispatch::Queue::main()` work, matching
//! `native_mount.rs`.

// cocoa 0.26 deprecates its own NSPoint/NSSize/NSRect helpers in favor of
// objc2-foundation. Keep this module aligned with native_mount.rs.
#![allow(deprecated)]
// `objc` 0.2's `sel_impl!` macro expands to `cfg(feature = "cargo-clippy")`,
// which the modern Rust lint treats as an unknown cfg.
#![allow(unexpected_cfgs)]

use std::collections::HashMap;
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

/// Latest-wins guard. Returns true if `seq` should be applied given the
/// previously-seen max `prev`.
pub(crate) fn seq_wins(prev: u64, seq: u64) -> bool {
    seq > prev
}

/// Web (top-left origin) -> AppKit (bottom-left origin) y-flip.
/// `content_h` is the window contentView height in points.
pub(crate) fn flip_y(content_h: f64, y: f64, h: f64) -> f64 {
    content_h - (y + h)
}

#[derive(Clone, Debug)]
pub(crate) struct ThemeSnapshot {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub font_main: String,
    pub font_main_light: String,
}

impl Default for ThemeSnapshot {
    fn default() -> Self {
        Self {
            r: 255,
            g: 255,
            b: 255,
            font_main: "Menlo".into(),
            font_main_light: "Menlo".into(),
        }
    }
}

#[derive(Default)]
pub struct NativeThemeState {
    inner: Mutex<ThemeSnapshot>,
}

impl NativeThemeState {
    fn snapshot(&self) -> ThemeSnapshot {
        self.inner.lock().map(|g| g.clone()).unwrap_or_default()
    }
}

#[derive(Default)]
pub struct NativePanelsState {
    host: Mutex<Option<PanelHost>>,
    slots: Mutex<HashMap<String, Slot>>,
}

#[derive(Clone, Copy)]
struct PanelHost {
    window: usize,
    content_view: usize,
    web_view: usize,
}

#[derive(Clone)]
struct Slot {
    anchor: String,
    view: usize,
    root_layer: usize,
    border_layers: Vec<usize>,
    label_layers: Vec<usize>,
    value_layers: Vec<usize>,
    text_layers: HashMap<String, usize>,
    last_seq: u64,
}

#[derive(Deserialize)]
pub struct WebRect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[derive(Deserialize)]
pub struct ThemePayload {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub font_main: String,
    pub font_main_light: String,
}

const NS_WINDOW_ABOVE: isize = 1;
const BORDER_ALPHA: f64 = 0.3;
const DIM_ALPHA: f64 = 0.5;
const CA_AUTORESIZE_W: std::os::raw::c_uint = 0x02;
const CA_AUTORESIZE_MIN_Y_MARGIN: std::os::raw::c_uint = 0x08;

pub fn install(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    debug_assert!(
        is_main_thread(),
        "native_panels::install must run on the main thread"
    );

    let window = app
        .get_webview_window("main")
        .ok_or("native_panels: main webview window not found")?;
    let ns_window = window
        .ns_window()
        .map_err(|e| format!("native_panels: ns_window() failed: {e}"))? as id;
    if ns_window.is_null() {
        return Err("native_panels: ns_window() returned null".into());
    }

    let content_view: id = unsafe { msg_send![ns_window, contentView] };
    if content_view.is_null() {
        return Err("native_panels: contentView returned null".into());
    }

    let subviews: id = unsafe { msg_send![content_view, subviews] };
    let count: usize = unsafe { msg_send![subviews, count] };
    let web_view = if count > 0 {
        unsafe { msg_send![subviews, objectAtIndex: 0usize] }
    } else {
        nil
    };

    let state = app.state::<NativePanelsState>();
    let mut host = state
        .host
        .lock()
        .map_err(|_| "native_panels: install lock poisoned")?;
    *host = Some(PanelHost {
        window: ns_window as usize,
        content_view: content_view as usize,
        web_view: web_view as usize,
    });

    Ok(())
}

fn valid_anchor(anchor: &str) -> bool {
    matches!(anchor, "mod_sysinfo" | "mod_hardwareInspector")
}

fn is_main_thread() -> bool {
    unsafe {
        let nsthread: id = msg_send![class!(NSThread), currentThread];
        let is_main: bool = msg_send![nsthread, isMainThread];
        is_main
    }
}

#[tauri::command]
pub async fn native_set_theme(
    panels: State<'_, NativePanelsState>,
    theme_state: State<'_, NativeThemeState>,
    theme: ThemePayload,
) -> Result<(), String> {
    let snapshot = ThemeSnapshot {
        r: theme.r,
        g: theme.g,
        b: theme.b,
        font_main: theme.font_main,
        font_main_light: theme.font_main_light,
    };
    {
        let mut guard = theme_state
            .inner
            .lock()
            .map_err(|_| "native_panels: theme lock poisoned".to_string())?;
        *guard = snapshot.clone();
    }

    let slots: Vec<Slot> = panels
        .slots
        .lock()
        .map_err(|_| "native_panels: slots lock poisoned".to_string())?
        .values()
        .cloned()
        .collect();

    Queue::main().exec_async(move || unsafe {
        for slot in slots {
            restyle_slot(&slot, &snapshot);
        }
    });

    Ok(())
}

#[tauri::command]
pub async fn native_panel_mount(
    state: State<'_, NativePanelsState>,
    theme: State<'_, NativeThemeState>,
    anchor: String,
) -> Result<(), String> {
    if !valid_anchor(&anchor) {
        eprintln!("native_panels: unknown anchor `{anchor}`");
        return Ok(());
    }
    if state
        .slots
        .lock()
        .map_err(|_| "native_panels: mount slots lock poisoned".to_string())?
        .contains_key(&anchor)
    {
        return Ok(());
    }

    let host = {
        let guard = state
            .host
            .lock()
            .map_err(|_| "native_panels: mount host lock poisoned".to_string())?;
        match *guard {
            Some(h) => h,
            None => return Ok(()),
        }
    };
    let snapshot = theme.snapshot();
    let build_anchor = anchor.clone();
    let slot = if is_main_thread() {
        unsafe { build_slot(&build_anchor, host, &snapshot) }
    } else {
        Queue::main().exec_sync(move || unsafe { build_slot(&build_anchor, host, &snapshot) })
    };

    state
        .slots
        .lock()
        .map_err(|_| "native_panels: mount insert lock poisoned".to_string())?
        .entry(anchor)
        .or_insert(slot);

    Ok(())
}

#[tauri::command]
pub async fn native_panel_set_rect(
    state: State<'_, NativePanelsState>,
    anchor: String,
    rect: WebRect,
    dpr: f64,
    seq: u64,
) -> Result<(), String> {
    if !valid_anchor(&anchor) {
        eprintln!("native_panels: unknown anchor `{anchor}`");
        return Ok(());
    }

    let slot = {
        let mut slots = state
            .slots
            .lock()
            .map_err(|_| "native_panels: set_rect lock poisoned".to_string())?;
        let Some(slot) = slots.get_mut(&anchor) else {
            return Ok(());
        };
        if !seq_wins(slot.last_seq, seq) {
            return Ok(());
        }
        slot.last_seq = seq;
        slot.clone()
    };

    Queue::main().exec_async(move || unsafe {
        apply_slot_rect(&slot, rect, dpr);
    });

    Ok(())
}

#[tauri::command]
pub async fn native_panel_set_visible(
    state: State<'_, NativePanelsState>,
    anchor: String,
    visible: bool,
) -> Result<(), String> {
    if !valid_anchor(&anchor) {
        eprintln!("native_panels: unknown anchor `{anchor}`");
        return Ok(());
    }
    let slot = {
        let slots = state
            .slots
            .lock()
            .map_err(|_| "native_panels: set_visible lock poisoned".to_string())?;
        match slots.get(&anchor) {
            Some(s) => s.clone(),
            None => return Ok(()),
        }
    };

    Queue::main().exec_async(move || unsafe {
        let hidden = if visible { NO } else { YES };
        let _: () = msg_send![slot.view(), setHidden: hidden];
    });

    Ok(())
}

#[tauri::command]
pub async fn native_panel_set_text(
    state: State<'_, NativePanelsState>,
    theme: State<'_, NativeThemeState>,
    anchor: String,
    key: String,
    text: String,
) -> Result<(), String> {
    if !valid_anchor(&anchor) {
        eprintln!("native_panels: unknown anchor `{anchor}`");
        return Ok(());
    }
    let slot = {
        let slots = state
            .slots
            .lock()
            .map_err(|_| "native_panels: set_text lock poisoned".to_string())?;
        match slots.get(&anchor) {
            Some(s) => s.clone(),
            None => return Ok(()),
        }
    };
    let Some(layer) = slot.text_layers.get(&key).copied() else {
        eprintln!("native_panels: unknown text key `{key}` for `{anchor}`");
        return Ok(());
    };
    let snapshot = theme.snapshot();

    Queue::main().exec_async(move || unsafe {
        let ns_text = NSString::alloc(nil).init_str(&text);
        let layer = layer as id;
        let _: () = msg_send![layer, setString: ns_text];
        let _: () = msg_send![ns_text, release];
        restyle_slot(&slot, &snapshot);
    });

    Ok(())
}

#[tauri::command]
pub async fn native_panel_unmount(
    state: State<'_, NativePanelsState>,
    anchor: String,
) -> Result<(), String> {
    if !valid_anchor(&anchor) {
        eprintln!("native_panels: unknown anchor `{anchor}`");
        return Ok(());
    }
    let slot = {
        let mut slots = state
            .slots
            .lock()
            .map_err(|_| "native_panels: unmount lock poisoned".to_string())?;
        match slots.remove(&anchor) {
            Some(s) => s,
            None => return Ok(()),
        }
    };

    Queue::main().exec_async(move || unsafe {
        release_slot(&slot);
    });

    Ok(())
}

impl PanelHost {
    fn window(self) -> id {
        self.window as id
    }

    fn content_view(self) -> id {
        self.content_view as id
    }

    fn web_view(self) -> id {
        self.web_view as id
    }
}

impl Slot {
    fn view(&self) -> id {
        self.view as id
    }

    fn root_layer(&self) -> id {
        self.root_layer as id
    }
}

unsafe fn build_slot(anchor: &str, host: PanelHost, theme: &ThemeSnapshot) -> Slot {
    if host.window().is_null() {
        eprintln!("native_panels: cannot build `{anchor}`, window is null");
    }

    let zero_rect = NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(0.0, 0.0));

    let view: id = msg_send![class!(NSView), alloc];
    let view: id = msg_send![view, initWithFrame: zero_rect];
    let _: () = msg_send![view, setWantsLayer: YES];
    let _: () = msg_send![view, setHidden: YES];

    let root_layer: id = msg_send![view, layer];
    let black = CGColor::rgb(0.0, 0.0, 0.0, 1.0);
    let _: () = msg_send![root_layer, setBackgroundColor: black.as_concrete_TypeRef()];

    let mut slot = Slot {
        anchor: anchor.to_string(),
        view: view as usize,
        root_layer: root_layer as usize,
        border_layers: Vec::new(),
        label_layers: Vec::new(),
        value_layers: Vec::new(),
        text_layers: HashMap::new(),
        last_seq: 0,
    };

    make_panel_accents(root_layer, &mut slot);
    match anchor {
        "mod_sysinfo" => build_sysinfo_layers(root_layer, &mut slot),
        "mod_hardwareInspector" => build_hardware_layers(root_layer, &mut slot),
        _ => {}
    }
    restyle_slot(&slot, theme);

    let _: id = msg_send![view, retain];
    let _: id = msg_send![root_layer, retain];

    let content_view = host.content_view();
    let web_view = host.web_view();
    if !web_view.is_null() {
        let _: () = msg_send![
            content_view,
            addSubview: view
            positioned: NS_WINDOW_ABOVE
            relativeTo: web_view
        ];
    } else {
        let _: () = msg_send![content_view, addSubview: view];
    }

    slot
}

unsafe fn make_panel_accents(root_layer: id, slot: &mut Slot) {
    for _ in 0..3 {
        let layer: id = msg_send![class!(CALayer), layer];
        let color = themed_color(&ThemeSnapshot::default(), BORDER_ALPHA);
        let _: () = msg_send![layer, setBackgroundColor: color.as_concrete_TypeRef()];
        let _: () = msg_send![root_layer, addSublayer: layer];
        let _: id = msg_send![layer, retain];
        slot.border_layers.push(layer as usize);
    }
}

unsafe fn build_sysinfo_layers(root_layer: id, slot: &mut Slot) {
    let keys = [
        "date_value",
        "date_subvalue",
        "uptime_value",
        "type_value",
        "power_value",
    ];
    for key in keys {
        let layer = make_text_layer(root_layer, "", 11.0, "left");
        slot.text_layers.insert(key.to_string(), layer as usize);
        slot.value_layers.push(layer as usize);
    }

    for label in ["UPTIME", "TYPE", "POWER"] {
        let layer = make_text_layer(root_layer, label, 9.0, "left");
        slot.label_layers.push(layer as usize);
    }
}

unsafe fn build_hardware_layers(root_layer: id, slot: &mut Slot) {
    for label in ["MANUFACTURER", "MODEL", "CHASSIS"] {
        let layer = make_text_layer(root_layer, label, 10.0, "left");
        slot.label_layers.push(layer as usize);
    }
    for key in ["manufacturer_value", "model_value", "chassis_value"] {
        let layer = make_text_layer(root_layer, "", 10.0, "left");
        slot.text_layers.insert(key.to_string(), layer as usize);
        slot.value_layers.push(layer as usize);
    }
}

unsafe fn make_text_layer(root_layer: id, text: &str, font_size: f64, alignment: &str) -> id {
    let layer: id = msg_send![class!(CATextLayer), layer];
    let ns_text = NSString::alloc(nil).init_str(text);
    let _: () = msg_send![layer, setString: ns_text];
    let _: () = msg_send![ns_text, release];
    let _: () = msg_send![layer, setFontSize: font_size];
    let font = NSString::alloc(nil).init_str("Menlo");
    let _: () = msg_send![layer, setFont: font];
    let _: () = msg_send![font, release];
    let align = NSString::alloc(nil).init_str(alignment);
    let _: () = msg_send![layer, setAlignmentMode: align];
    let _: () = msg_send![align, release];
    let _: () = msg_send![layer, setWrapped: NO];
    let _: () = msg_send![root_layer, addSublayer: layer];
    let _: id = msg_send![layer, retain];
    layer
}

unsafe fn apply_slot_rect(slot: &Slot, rect: WebRect, dpr: f64) {
    let view = slot.view();
    let window: id = msg_send![view, window];
    if window.is_null() {
        return;
    }
    let content_view: id = msg_send![window, contentView];
    let content_frame: NSRect = msg_send![content_view, frame];
    let frame = NSRect::new(
        NSPoint::new(
            rect.x,
            flip_y(content_frame.size.height, rect.y, rect.height),
        ),
        NSSize::new(rect.width, rect.height),
    );
    let _: () = msg_send![view, setFrame: frame];

    set_contents_scale(slot, dpr);
    layout_slot(slot, rect.width, rect.height);
}

unsafe fn set_contents_scale(slot: &Slot, dpr: f64) {
    let _: () = msg_send![slot.root_layer(), setContentsScale: dpr];
    for layer in slot
        .border_layers
        .iter()
        .chain(slot.label_layers.iter())
        .chain(slot.value_layers.iter())
    {
        let _: () = msg_send![*layer as id, setContentsScale: dpr];
    }
}

unsafe fn layout_slot(slot: &Slot, width: f64, height: f64) {
    layout_accents(slot, width, height);
    match slot.anchor.as_str() {
        "mod_sysinfo" => layout_sysinfo(slot, width, height),
        "mod_hardwareInspector" => layout_hardware(slot, width, height),
        _ => {}
    }
}

unsafe fn layout_accents(slot: &Slot, width: f64, height: f64) {
    if slot.border_layers.len() < 3 {
        return;
    }
    let top = slot.border_layers[0] as id;
    let left = slot.border_layers[1] as id;
    let right = slot.border_layers[2] as id;
    let line_h = 1.0;
    let tick_h = height.clamp(6.0, 10.0);
    let _: () = msg_send![
        top,
        setFrame: NSRect::new(
            NSPoint::new(0.0, height - line_h),
            NSSize::new(width.max(0.0), line_h),
        )
    ];
    let _: () = msg_send![
        left,
        setFrame: NSRect::new(
            NSPoint::new(0.0, height - tick_h),
            NSSize::new(line_h, tick_h),
        )
    ];
    let _: () = msg_send![
        right,
        setFrame: NSRect::new(
            NSPoint::new((width - line_h).max(0.0), height - tick_h),
            NSSize::new(line_h, tick_h),
        )
    ];
    let _: () = msg_send![top, setAutoresizingMask: CA_AUTORESIZE_W | CA_AUTORESIZE_MIN_Y_MARGIN];
}

unsafe fn layout_sysinfo(slot: &Slot, width: f64, height: f64) {
    let cell_w = width / 4.0;
    let pad_x = 5.0;
    let value_h = (height * 0.32).clamp(12.0, 22.0);
    let label_h = (height * 0.24).clamp(10.0, 16.0);
    let value_y = (height * 0.16).max(3.0);
    let label_y = (height * 0.56).max(value_y + value_h);

    set_layer_frame(
        slot.text_layers["date_value"] as id,
        pad_x,
        label_y,
        cell_w - pad_x,
        label_h,
    );
    set_layer_frame(
        slot.text_layers["date_subvalue"] as id,
        pad_x,
        value_y,
        cell_w - pad_x,
        value_h,
    );

    for (i, key) in ["uptime_value", "type_value", "power_value"]
        .iter()
        .enumerate()
    {
        let x = ((i + 1) as f64 * cell_w) + pad_x;
        set_layer_frame(
            slot.label_layers[i] as id,
            x,
            label_y,
            cell_w - pad_x,
            label_h,
        );
        set_layer_frame(
            slot.text_layers[*key] as id,
            x,
            value_y,
            cell_w - pad_x,
            value_h,
        );
    }
}

unsafe fn layout_hardware(slot: &Slot, width: f64, height: f64) {
    let cell_w = width / 3.0;
    let pad_x = 6.0;
    let label_h = (height * 0.25).clamp(10.0, 16.0);
    let value_h = label_h;
    let value_y = (height * 0.22).max(2.0);
    let label_y = value_y + value_h + 1.0;
    let keys = ["manufacturer_value", "model_value", "chassis_value"];

    for (i, key) in keys.iter().enumerate() {
        let x = (i as f64 * cell_w) + pad_x;
        let w = cell_w - (pad_x * 2.0);
        set_layer_frame(slot.label_layers[i] as id, x, label_y, w, label_h);
        set_layer_frame(slot.text_layers[*key] as id, x, value_y, w, value_h);
    }
}

unsafe fn set_layer_frame(layer: id, x: f64, y: f64, width: f64, height: f64) {
    let _: () = msg_send![
        layer,
        setFrame: NSRect::new(
            NSPoint::new(x, y),
            NSSize::new(width.max(0.0), height.max(0.0)),
        )
    ];
}

unsafe fn restyle_slot(slot: &Slot, theme: &ThemeSnapshot) {
    let border = themed_color(theme, BORDER_ALPHA);
    for layer in &slot.border_layers {
        let _: () = msg_send![*layer as id, setBackgroundColor: border.as_concrete_TypeRef()];
    }

    let font_family = if theme.font_main_light.is_empty() {
        &theme.font_main
    } else {
        &theme.font_main_light
    };
    let font_name = NSString::alloc(nil).init_str(font_family);
    let text = themed_color(theme, 1.0);
    let dim = themed_color(theme, DIM_ALPHA);
    let (label_alpha, value_alpha) = match slot.anchor.as_str() {
        "mod_hardwareInspector" => (1.0, DIM_ALPHA),
        _ => (DIM_ALPHA, 1.0),
    };
    let label_color = if (label_alpha - 1.0_f64).abs() < f64::EPSILON {
        &text
    } else {
        &dim
    };
    let value_color = if (value_alpha - 1.0_f64).abs() < f64::EPSILON {
        &text
    } else {
        &dim
    };

    for layer in &slot.label_layers {
        let layer = *layer as id;
        let _: () = msg_send![layer, setForegroundColor: label_color.as_concrete_TypeRef()];
        let _: () = msg_send![layer, setFont: font_name];
    }
    for layer in &slot.value_layers {
        let layer = *layer as id;
        let _: () = msg_send![layer, setForegroundColor: value_color.as_concrete_TypeRef()];
        let _: () = msg_send![layer, setFont: font_name];
    }
    let _: () = msg_send![font_name, release];
}

fn themed_color(theme: &ThemeSnapshot, alpha: f64) -> CGColor {
    CGColor::rgb(
        f64::from(theme.r) / 255.0,
        f64::from(theme.g) / 255.0,
        f64::from(theme.b) / 255.0,
        alpha,
    )
}

unsafe fn release_slot(slot: &Slot) {
    let _: () = msg_send![slot.view(), removeFromSuperview];
    for layer in slot
        .border_layers
        .iter()
        .chain(slot.label_layers.iter())
        .chain(slot.value_layers.iter())
    {
        let _: () = msg_send![*layer as id, removeFromSuperlayer];
        let _: () = msg_send![*layer as id, release];
    }
    let _: () = msg_send![slot.root_layer(), release];
    let _: () = msg_send![slot.view(), release];
}

// Compile-time assertion that `Object` is referenced at least once so the
// unused-import lint stays quiet, matching native_mount.rs.
#[allow(dead_code)]
const _: fn() = || {
    let _: *const Object = std::ptr::null();
};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seq_wins_only_for_strictly_newer() {
        assert!(seq_wins(0, 1));
        assert!(seq_wins(5, 6));
        assert!(!seq_wins(5, 5));
        assert!(!seq_wins(5, 4));
    }

    #[test]
    fn flip_y_inverts_origin() {
        assert_eq!(flip_y(1000.0, 0.0, 100.0), 900.0);
        assert_eq!(flip_y(1000.0, 200.0, 100.0), 700.0);
    }

    #[test]
    fn theme_snapshot_defaults_to_white_menlo_and_stores_rgb() {
        let st = ThemeSnapshot::default();
        assert_eq!((st.r, st.g, st.b), (255, 255, 255));
        assert_eq!(st.font_main, "Menlo");
        assert_eq!(st.font_main_light, "Menlo");

        let updated = ThemeSnapshot {
            r: 0,
            g: 170,
            b: 255,
            font_main: "Font A".into(),
            font_main_light: "Font B".into(),
        };
        assert_eq!(updated.r, 0);
        assert_eq!(updated.font_main_light, "Font B");
    }
}
