// window.si used to be built inside renderer.js's async boot; it now
// lives here so non-renderer code (and future native callers reaching
// in via FFI) have one canonical accessor.
//
// The Proxy maps camelCase property reads to snake_case Tauri commands:
//   bridge.sysinfo.networkInterfaces() → invoke("si_network_interfaces")
//
// Backward compat: window.si is still set, so existing classes that
// reference window.si keep working unchanged.

(function (globalScope) {
    if (!globalScope.__TAURI__ || !globalScope.__TAURI__.core) {
        throw new Error("bridge/sysinfo.js: window.__TAURI__ must be present before this script loads.");
    }

    const { invoke } = globalScope.__TAURI__.core;

    const proxy = new Proxy({}, {
        apply: () => { throw new Error("Cannot use the sysinfo proxy directly as a function"); },
        set: () => { throw new Error("Cannot set a property on the sysinfo proxy"); },
        get: (_, prop) => {
            const cmd = "si_" + String(prop).replace(/[A-Z]/g, m => "_" + m.toLowerCase());
            return function (...args) {
                let payload = {};
                if (cmd === "si_network_stats" && args.length >= 1) {
                    payload = { iface: args[0] };
                }
                return invoke(cmd, payload);
            };
        }
    });

    globalScope.bridge = globalScope.bridge || {};
    globalScope.bridge.sysinfo = proxy;
    globalScope.si = proxy;
})(typeof window !== "undefined" ? window : globalThis);
