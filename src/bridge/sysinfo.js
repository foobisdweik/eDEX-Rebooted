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
    const panelSnapshotCache = {
        inFlight: null,
        value: null,
        timestamp: 0,
        ttlMs: 900
    };

    const proxy = new Proxy({}, {
        apply: () => { throw new Error("Cannot use the sysinfo proxy directly as a function"); },
        set: () => { throw new Error("Cannot set a property on the sysinfo proxy"); },
        get: (target, prop) => {
            // Pass through Symbol keys, anything already on the target,
            // and the "then" property so the proxy is not mistaken for a
            // thenable when accidentally awaited or inspected by tooling.
            if (typeof prop !== "string" || prop === "then" || prop in target) {
                return target[prop];
            }
            const cmd = "si_" + prop.replace(/[A-Z]/g, m => "_" + m.toLowerCase());
            return function (...args) {
                let payload = {};
                if (cmd === "si_network_stats" && args.length >= 1) {
                    payload = { iface: args[0] };
                }
                if (cmd === "si_panel_snapshot") {
                    payload = {
                        collapseThreadsByName: args[0] === true,
                        topLimit: Number.isInteger(args[1]) ? args[1] : 5
                    };
                    const now = Date.now();
                    if (panelSnapshotCache.value && now - panelSnapshotCache.timestamp < panelSnapshotCache.ttlMs) {
                        return Promise.resolve(panelSnapshotCache.value);
                    }
                    if (panelSnapshotCache.inFlight) {
                        return panelSnapshotCache.inFlight;
                    }
                    panelSnapshotCache.inFlight = invoke(cmd, payload)
                        .then(result => {
                            panelSnapshotCache.value = result;
                            panelSnapshotCache.timestamp = Date.now();
                            return result;
                        })
                        .finally(() => {
                            panelSnapshotCache.inFlight = null;
                        });
                    return panelSnapshotCache.inFlight;
                }
                return invoke(cmd, payload);
            };
        }
    });

    globalScope.bridge = globalScope.bridge || {};
    globalScope.bridge.sysinfo = proxy;
    globalScope.si = proxy;
})(typeof window !== "undefined" ? window : globalThis);
