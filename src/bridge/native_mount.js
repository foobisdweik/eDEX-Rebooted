// Slice 1b: ship #mod_column_left's bounding rect to Rust, which positions
// a sibling NSView in the Tauri window. Activate() is the only public entry
// and is invoked from renderer.js once at boot, ONLY when
// settings.experimentalNativePanels === true.
//
// Protocol:
//   measureAndShip() reads getBoundingClientRect() in CSS pixels and ships
//   { rect, dpr, seq } via invoke("native_mount_set_rect"). Rust treats rect
//   units as AppKit points (CSS pixel == AppKit point) and uses DPR only
//   for layer.contentsScale, not for frame dimensions.
//
// Hardening:
//   - rAF coalesce: many ResizeObserver fires in one frame trigger one ship.
//   - 0.5pt epsilon dedupe: layout micro-jitter does not produce IPC.
//   - seq numbers: Rust drops anything older than its last_seq.
//   - latest-wins: schedule() returns early if a rAF is already pending.
//   - idempotent activate(): second call is a no-op.

(function (globalScope) {
    if (!globalScope.__TAURI__ || !globalScope.__TAURI__.core) {
        throw new Error("bridge/native_mount.js: window.__TAURI__ must be present before this script loads.");
    }
    const { invoke } = globalScope.__TAURI__.core;

    let seq = 0;
    let lastRect = null;
    let lastDpr = null;
    let rafId = 0;
    let activated = false;
    let resizeObserver = null;

    function epsilonDiffers(a, b) {
        if (!a || !b) return true;
        return Math.abs(a.x - b.x) > 0.5
            || Math.abs(a.y - b.y) > 0.5
            || Math.abs(a.width - b.width) > 0.5
            || Math.abs(a.height - b.height) > 0.5;
    }

    function measureAndShip() {
        rafId = 0;
        const el = globalScope.document.getElementById("mod_column_left");
        if (!el) return;
        const r = el.getBoundingClientRect();
        const dpr = globalScope.devicePixelRatio || 1;
        const rect = { x: r.left, y: r.top, width: r.width, height: r.height };
        if (!epsilonDiffers(rect, lastRect) && dpr === lastDpr) return;
        lastRect = rect;
        lastDpr = dpr;
        const mySeq = ++seq;
        invoke("native_mount_set_rect", { rect, dpr, seq: mySeq })
            .catch(e => console.warn("native_mount_set_rect failed:", e));
    }

    function schedule() {
        if (rafId) return;
        rafId = globalScope.requestAnimationFrame(measureAndShip);
    }

    async function activate() {
        if (activated) return;
        activated = true;
        const target = globalScope.document.getElementById("mod_column_left");
        if (!target) {
            console.error("native_mount: #mod_column_left missing; aborting activate");
            return;
        }
        globalScope.document.body.classList.add("native-left-active");
        resizeObserver = new globalScope.ResizeObserver(schedule);
        resizeObserver.observe(target);
        if (typeof globalScope.matchMedia === "function") {
            const mq = globalScope.matchMedia("(resolution: 1dppx)");
            if (mq && typeof mq.addEventListener === "function") {
                mq.addEventListener("change", schedule);
            }
        }
        globalScope.addEventListener("resize", schedule);
        // Ship the initial rect SYNCHRONOUSLY (not via rAF) so the native
        // view is sized before it becomes visible. Otherwise the user sees
        // a one-frame flash of the cyan-bordered region at NSZeroRect.
        measureAndShip();
        try {
            await invoke("native_mount_set_visible", { visible: true });
        } catch (e) {
            console.warn("native_mount_set_visible failed:", e);
        }
        console.info("native_mount: activated (flag-on, restart required to disable)");
    }

    async function setClockText(text) {
        try {
            await invoke("native_mount_set_clock_text", { text });
        } catch (e) {
            console.warn("native_mount_set_clock_text failed:", e);
        }
    }

    function _resetForTests() {
        seq = 0;
        lastRect = null;
        lastDpr = null;
        rafId = 0;
        activated = false;
        if (resizeObserver && typeof resizeObserver.disconnect === "function") {
            resizeObserver.disconnect();
        }
        resizeObserver = null;
    }

    globalScope.bridge = globalScope.bridge || {};
    globalScope.bridge.nativeMount = { activate, setClockText, _resetForTests };

    if (typeof module !== "undefined" && module.exports) {
        module.exports = globalScope.bridge.nativeMount;
    }
})(typeof window !== "undefined" ? window : globalThis);
