// Approach A native panel slots: ship one DOM anchor's rect to Rust, where an
// AppKit NSView is layered over the WKWebView for that panel only.
(function (globalScope) {
    if (!globalScope.__TAURI__ || !globalScope.__TAURI__.core) {
        throw new Error("bridge/native_panels.js: window.__TAURI__ must be present before this script loads.");
    }
    const { invoke } = globalScope.__TAURI__.core;
    const states = new Map();

    function epsilonDiffers(a, b) {
        if (!a || !b) return true;
        return Math.abs(a.x - b.x) > 0.5
            || Math.abs(a.y - b.y) > 0.5
            || Math.abs(a.width - b.width) > 0.5
            || Math.abs(a.height - b.height) > 0.5;
    }

    function measureAndShip(anchorId) {
        const state = states.get(anchorId);
        if (!state) return;
        state.rafId = 0;
        const el = globalScope.document.getElementById(anchorId);
        if (!el) return;
        const r = el.getBoundingClientRect();
        const dpr = globalScope.devicePixelRatio || 1;
        const rect = { x: r.left, y: r.top, width: r.width, height: r.height };
        if (!epsilonDiffers(rect, state.lastRect) && dpr === state.lastDpr) return;
        state.lastRect = rect;
        state.lastDpr = dpr;
        const mySeq = ++state.seq;
        invoke("native_panel_set_rect", { anchor: anchorId, rect, dpr, seq: mySeq })
            .catch(e => console.warn("native_panel_set_rect failed:", e));
    }

    function schedule(anchorId) {
        const state = states.get(anchorId);
        if (!state || state.rafId) return;
        state.rafId = globalScope.requestAnimationFrame(() => measureAndShip(anchorId));
    }

    async function mountPanel(anchorId) {
        if (states.has(anchorId)) return states.get(anchorId).mountPromise;
        const target = globalScope.document.getElementById(anchorId);
        if (!target) {
            console.error(`native_panels: #${anchorId} missing; aborting mount`);
            return;
        }

        target.classList.add("native-panel-hidden");
        const state = {
            mountPromise: null,
            seq: 0,
            lastRect: null,
            lastDpr: null,
            rafId: 0,
            observer: null,
        };
        states.set(anchorId, state);
        state.observer = new globalScope.ResizeObserver(() => schedule(anchorId));
        state.observer.observe(target);
        state.mountPromise = invoke("native_panel_mount", { anchor: anchorId })
            .catch(e => {
                console.warn("native_panel_mount failed:", e);
            });

        await state.mountPromise;
        measureAndShip(anchorId);
        try {
            await invoke("native_panel_set_visible", { anchor: anchorId, visible: true });
        } catch (e) {
            console.warn("native_panel_set_visible failed:", e);
        }
    }

    async function setPanelText(anchorId, key, text) {
        const state = states.get(anchorId);
        if (state && state.mountPromise) {
            await state.mountPromise;
        }
        try {
            await invoke("native_panel_set_text", { anchor: anchorId, key, text });
        } catch (e) {
            console.warn("native_panel_set_text failed:", e);
        }
    }

    async function unmountPanel(anchorId) {
        const state = states.get(anchorId);
        const target = globalScope.document.getElementById(anchorId);
        if (state) {
            if (state.observer && typeof state.observer.disconnect === "function") {
                state.observer.disconnect();
            }
            if (state.rafId && typeof globalScope.cancelAnimationFrame === "function") {
                globalScope.cancelAnimationFrame(state.rafId);
            }
            states.delete(anchorId);
        }
        if (target) {
            target.classList.remove("native-panel-hidden");
        }
        try {
            await invoke("native_panel_unmount", { anchor: anchorId });
        } catch (e) {
            console.warn("native_panel_unmount failed:", e);
        }
    }

    async function setTheme(theme) {
        try {
            await invoke("native_set_theme", { theme });
        } catch (e) {
            console.warn("native_set_theme failed:", e);
        }
    }

    function _resetForTests() {
        for (const [anchorId, state] of states.entries()) {
            if (state.observer && typeof state.observer.disconnect === "function") {
                state.observer.disconnect();
            }
            if (state.rafId && typeof globalScope.cancelAnimationFrame === "function") {
                globalScope.cancelAnimationFrame(state.rafId);
            }
            const target = globalScope.document.getElementById(anchorId);
            if (target) target.classList.remove("native-panel-hidden");
        }
        states.clear();
    }

    globalScope.bridge = globalScope.bridge || {};
    globalScope.bridge.nativePanels = { mountPanel, setPanelText, unmountPanel, setTheme, _resetForTests };

    if (typeof module !== "undefined" && module.exports) {
        module.exports = globalScope.bridge.nativePanels;
    }
})(typeof window !== "undefined" ? window : globalThis);
