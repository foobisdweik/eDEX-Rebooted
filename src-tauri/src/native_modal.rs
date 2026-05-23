//! Slice 1 pilot: native modal bridge for simple info/warning/error dialogs.
//! Custom HTML modals still use the legacy DOM path.
#![allow(deprecated)]
#![allow(unexpected_cfgs)]

use cocoa::base::{id, nil};
use cocoa::foundation::NSString;
use dispatch::Queue;
use objc::{class, msg_send, sel, sel_impl};

#[tauri::command]
pub async fn native_modal_notify(
    kind: String,
    title: String,
    message: String,
) -> Result<(), String> {
    // Block this command until the user dismisses NSAlert so JS-side `finally`
    // keeps the same acknowledgement semantics as legacy DOM modals.
    Queue::main().exec_sync(move || unsafe {
        let alert: id = msg_send![class!(NSAlert), alloc];
        let alert: id = msg_send![alert, init];

        let title_ns = NSString::alloc(nil).init_str(&title);
        let msg_ns = NSString::alloc(nil).init_str(&message);
        let ok_ns = NSString::alloc(nil).init_str("OK");

        // NSAlertStyle values: warning=0, informational=1, critical=2.
        let style: u64 = match kind.as_str() {
            "error" => 2,
            "warning" => 0,
            _ => 1,
        };

        let _: () = msg_send![alert, setAlertStyle: style];
        let _: () = msg_send![alert, setMessageText: title_ns];
        let _: () = msg_send![alert, setInformativeText: msg_ns];
        let _: id = msg_send![alert, addButtonWithTitle: ok_ns];
        let _: i64 = msg_send![alert, runModal];
        let _: () = msg_send![alert, release];
        let _: () = msg_send![title_ns, release];
        let _: () = msg_send![msg_ns, release];
        let _: () = msg_send![ok_ns, release];
    });
    Ok(())
}
