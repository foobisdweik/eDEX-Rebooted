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
        entries: new Map(),
        ttlMs: 900
    };

    function panelSnapshotCacheKey(collapseThreadsByName, topLimit) {
        return `${collapseThreadsByName ? 1 : 0}:${topLimit}`;
    }

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
                    const cacheKey = panelSnapshotCacheKey(
                        payload.collapseThreadsByName,
                        payload.topLimit
                    );
                    const now = Date.now();
                    const cached = panelSnapshotCache.entries.get(cacheKey);
                    if (cached && cached.value && now - cached.timestamp < panelSnapshotCache.ttlMs) {
                        return Promise.resolve(cached.value);
                    }
                    if (cached && cached.inFlight) {
                        return cached.inFlight;
                    }
                    const inFlight = invoke(cmd, payload)
                        .then(result => {
                            const entry = panelSnapshotCache.entries.get(cacheKey) || {};
                            entry.value = result;
                            entry.timestamp = Date.now();
                            entry.inFlight = null;
                            panelSnapshotCache.entries.set(cacheKey, entry);
                            return result;
                        })
                        .catch(err => {
                            const entry = panelSnapshotCache.entries.get(cacheKey);
                            if (entry) entry.inFlight = null;
                            throw err;
                        });
                    panelSnapshotCache.entries.set(cacheKey, {
                        value: cached ? cached.value : null,
                        timestamp: cached ? cached.timestamp : 0,
                        inFlight
                    });
                    return inFlight;
                }
                return invoke(cmd, payload);
            };
        }
    });

    globalScope.bridge = globalScope.bridge || {};
    globalScope.bridge.sysinfo = proxy;
    globalScope.si = proxy;
})(typeof window !== "undefined" ? window : globalThis);
