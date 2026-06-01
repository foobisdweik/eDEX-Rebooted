const test = require("node:test");
const assert = require("node:assert/strict");

function freshBridge({ anchors = ["mod_sysinfo"], dpr = 2, invokeImpl = null, invokeCalls = [] } = {}) {
    const rafQueue = [];
    const observerInstances = [];
    const elements = new Map();
    const windowListeners = new Map();
    const documentListeners = new Map();
    const elementListeners = new Map();

    class FakeResizeObserver {
        constructor(cb) { this.cb = cb; observerInstances.push(this); }
        observe(el) { this.observedEl = el; }
        disconnect() { this.disconnected = true; this.cb = null; }
        fire() { if (this.cb) this.cb(); }
    }

    for (const id of anchors) {
        let rect = id === "mod_hardwareInspector"
            ? { left: 30, top: 40, width: 300, height: 90 }
            : { left: 10, top: 20, width: 100, height: 200 };
        const classes = new Set();
        elements.set(id, {
            id,
            getBoundingClientRect: () => ({ ...rect }),
            setRect: next => { rect = { ...next }; },
            addEventListener(event, cb) {
                const key = `${id}:${event}`;
                if (!elementListeners.has(key)) elementListeners.set(key, []);
                elementListeners.get(key).push(cb);
            },
            removeEventListener(event, cb) {
                const key = `${id}:${event}`;
                const listeners = elementListeners.get(key) || [];
                elementListeners.set(key, listeners.filter(listener => listener !== cb));
            },
            fireEvent(event) {
                for (const cb of elementListeners.get(`${id}:${event}`) || []) cb();
            },
            listenerCount(event) {
                return (elementListeners.get(`${id}:${event}`) || []).length;
            },
            classList: {
                add(c) { classes.add(c); },
                remove(c) { classes.delete(c); },
                has(c) { return classes.has(c); },
            },
        });
    }

    const sandbox = {
        __TAURI__: {
            core: {
                invoke: invokeImpl || ((cmd, payload) => {
                    invokeCalls.push({ cmd, payload });
                    return Promise.resolve(null);
                }),
            },
        },
        devicePixelRatio: dpr,
        requestAnimationFrame: cb => {
            rafQueue.push(cb);
            return rafQueue.length;
        },
        cancelAnimationFrame: () => {},
        document: {
            getElementById: id => elements.get(id) || null,
            addEventListener(event, cb) {
                if (!documentListeners.has(event)) documentListeners.set(event, []);
                documentListeners.get(event).push(cb);
            },
            removeEventListener(event, cb) {
                const listeners = documentListeners.get(event) || [];
                documentListeners.set(event, listeners.filter(listener => listener !== cb));
            },
        },
        addEventListener(event, cb) {
            if (!windowListeners.has(event)) windowListeners.set(event, []);
            windowListeners.get(event).push(cb);
        },
        removeEventListener(event, cb) {
            const listeners = windowListeners.get(event) || [];
            windowListeners.set(event, listeners.filter(listener => listener !== cb));
        },
        fireWindowEvent(event) {
            for (const cb of windowListeners.get(event) || []) cb();
        },
        fireDocumentEvent(event) {
            for (const cb of documentListeners.get(event) || []) cb();
        },
        ResizeObserver: FakeResizeObserver,
    };

    delete require.cache[require.resolve("./native_panels.js")];
    global.window = sandbox;
    require("./native_panels.js");

    function flushRaf() {
        const pending = rafQueue.splice(0);
        for (const cb of pending) cb();
    }

    return {
        window: sandbox,
        invokeCalls,
        observerInstances,
        elements,
        windowListeners,
        documentListeners,
        flushRaf,
        setDpr(next) { sandbox.devicePixelRatio = next; },
    };
}

test("setPanelText invokes native_panel_set_text with anchor, key, and text", async () => {
    const h = freshBridge();
    await h.window.bridge.nativePanels.setPanelText("mod_sysinfo", "type_value", "macOS");

    assert.deepEqual(h.invokeCalls, [
        {
            cmd: "native_panel_set_text",
            payload: { anchor: "mod_sysinfo", key: "type_value", text: "macOS" },
        },
    ]);
});

test("mountPanel calls native_panel_mount before initial rect and visible", async () => {
    const h = freshBridge();
    await h.window.bridge.nativePanels.mountPanel("mod_sysinfo");

    assert.ok(h.elements.get("mod_sysinfo").classList.has("native-panel-hidden"));
    assert.equal(h.invokeCalls.length, 3);
    assert.equal(h.invokeCalls[0].cmd, "native_panel_mount");
    assert.deepEqual(h.invokeCalls[0].payload, { anchor: "mod_sysinfo" });
    assert.equal(h.invokeCalls[1].cmd, "native_panel_set_rect");
    assert.deepEqual(h.invokeCalls[1].payload.rect, { x: 10, y: 20, width: 100, height: 200 });
    assert.equal(h.invokeCalls[1].payload.dpr, 2);
    assert.equal(h.invokeCalls[1].payload.seq, 1);
    assert.equal(h.invokeCalls[2].cmd, "native_panel_set_visible");
    assert.deepEqual(h.invokeCalls[2].payload, { anchor: "mod_sysinfo", visible: true });
});

test("setPanelText waits for an existing mountPromise before pushing text", async () => {
    let releaseMount;
    const invokeCalls = [];
    const h = freshBridge({ invokeImpl: (cmd, payload) => {
        invokeCalls.push({ cmd, payload });
        if (cmd === "native_panel_mount") {
            return new Promise(resolve => { releaseMount = resolve; });
        }
        return Promise.resolve(null);
    }, invokeCalls });

    const mountPromise = h.window.bridge.nativePanels.mountPanel("mod_sysinfo");
    const textPromise = h.window.bridge.nativePanels.setPanelText("mod_sysinfo", "type_value", "macOS");
    await Promise.resolve();
    assert.deepEqual(h.invokeCalls.map(c => c.cmd), ["native_panel_mount"]);

    releaseMount(null);
    await Promise.all([mountPromise, textPromise]);
    assert.deepEqual(h.invokeCalls.map(c => c.cmd), [
        "native_panel_mount",
        "native_panel_set_rect",
        "native_panel_set_visible",
        "native_panel_set_text",
    ]);
});

test("per-anchor seq counters are independent", async () => {
    const h = freshBridge({ anchors: ["mod_sysinfo", "mod_hardwareInspector"] });
    await h.window.bridge.nativePanels.mountPanel("mod_sysinfo");
    await h.window.bridge.nativePanels.mountPanel("mod_hardwareInspector");

    const rectCalls = h.invokeCalls.filter(c => c.cmd === "native_panel_set_rect");
    assert.equal(rectCalls.length, 2);
    assert.deepEqual(rectCalls.map(c => [c.payload.anchor, c.payload.seq]), [
        ["mod_sysinfo", 1],
        ["mod_hardwareInspector", 1],
    ]);
});

test("identical rect within epsilon does not invoke again", async () => {
    const h = freshBridge();
    await h.window.bridge.nativePanels.mountPanel("mod_sysinfo");
    const baseline = h.invokeCalls.length;

    h.elements.get("mod_sysinfo").setRect({ left: 10.3, top: 20.4, width: 100.1, height: 200.4 });
    h.observerInstances[0].fire();
    h.flushRaf();

    assert.equal(h.invokeCalls.length, baseline);
});

test("0.6pt delta invokes another rect update", async () => {
    const h = freshBridge();
    await h.window.bridge.nativePanels.mountPanel("mod_sysinfo");
    const baseline = h.invokeCalls.length;

    h.elements.get("mod_sysinfo").setRect({ left: 10, top: 20, width: 100.6, height: 200 });
    h.observerInstances[0].fire();
    h.flushRaf();

    assert.equal(h.invokeCalls.length, baseline + 1);
    const last = h.invokeCalls[h.invokeCalls.length - 1];
    assert.equal(last.cmd, "native_panel_set_rect");
    assert.equal(last.payload.anchor, "mod_sysinfo");
    assert.equal(last.payload.seq, 2);
});

test("second mountPanel call is idempotent", async () => {
    const h = freshBridge();
    await h.window.bridge.nativePanels.mountPanel("mod_sysinfo");
    const obsBefore = h.observerInstances.length;
    const callsBefore = h.invokeCalls.length;

    await h.window.bridge.nativePanels.mountPanel("mod_sysinfo");
    h.flushRaf();

    assert.equal(h.observerInstances.length, obsBefore);
    assert.equal(h.invokeCalls.length, callsBefore);
});

test("unmountPanel disconnects observer, unhides DOM element, invokes unmount, and clears state", async () => {
    const h = freshBridge();
    await h.window.bridge.nativePanels.mountPanel("mod_sysinfo");
    const el = h.elements.get("mod_sysinfo");
    assert.ok(el.classList.has("native-panel-hidden"));

    await h.window.bridge.nativePanels.unmountPanel("mod_sysinfo");

    assert.ok(h.observerInstances[0].disconnected);
    assert.ok(!el.classList.has("native-panel-hidden"));
    const last = h.invokeCalls[h.invokeCalls.length - 1];
    assert.deepEqual(last, { cmd: "native_panel_unmount", payload: { anchor: "mod_sysinfo" } });

    await h.window.bridge.nativePanels.mountPanel("mod_sysinfo");
    assert.equal(h.invokeCalls.filter(c => c.cmd === "native_panel_mount").length, 2);
});

test("window resize and fullscreen changes reship rects with latest seq", async () => {
    const h = freshBridge();
    await h.window.bridge.nativePanels.mountPanel("mod_sysinfo");

    h.elements.get("mod_sysinfo").setRect({ left: 12, top: 24, width: 100, height: 200 });
    h.window.fireWindowEvent("resize");
    h.flushRaf();

    h.elements.get("mod_sysinfo").setRect({ left: 14, top: 28, width: 100, height: 200 });
    h.window.fireDocumentEvent("fullscreenchange");
    h.flushRaf();

    const rectCalls = h.invokeCalls.filter(c => c.cmd === "native_panel_set_rect");
    assert.equal(rectCalls.at(-2).payload.seq, 2);
    assert.equal(rectCalls.at(-1).payload.seq, 3);
    assert.deepEqual(rectCalls.at(-1).payload.rect, { x: 14, y: 28, width: 100, height: 200 });
});

test("zero-sized rect hides native slot without unmounting", async () => {
    const h = freshBridge();
    await h.window.bridge.nativePanels.mountPanel("mod_sysinfo");

    h.elements.get("mod_sysinfo").setRect({ left: 10, top: 20, width: 0, height: 0 });
    h.observerInstances[0].fire();
    h.flushRaf();

    const visibleCalls = h.invokeCalls.filter(c => c.cmd === "native_panel_set_visible");
    assert.deepEqual(visibleCalls.at(-1), {
        cmd: "native_panel_set_visible",
        payload: { anchor: "mod_sysinfo", visible: false },
    });
});

test("unmountPanel removes event listeners to avoid leaked schedulers", async () => {
    const h = freshBridge();
    await h.window.bridge.nativePanels.mountPanel("mod_sysinfo");
    assert.equal((h.windowListeners.get("resize") || []).length, 1);
    assert.equal((h.documentListeners.get("fullscreenchange") || []).length, 1);
    assert.equal(h.elements.get("mod_sysinfo").listenerCount("animationend"), 1);

    await h.window.bridge.nativePanels.unmountPanel("mod_sysinfo");

    assert.equal((h.windowListeners.get("resize") || []).length, 0);
    assert.equal((h.documentListeners.get("fullscreenchange") || []).length, 0);
    assert.equal(h.elements.get("mod_sysinfo").listenerCount("animationend"), 0);
});

test("setTheme invokes native_set_theme with theme payload", async () => {
    const h = freshBridge();
    const theme = { r: 1, g: 2, b: 3, font_main: "Main", font_main_light: "Light" };
    await h.window.bridge.nativePanels.setTheme(theme);

    assert.deepEqual(h.invokeCalls, [
        { cmd: "native_set_theme", payload: { theme } },
    ]);
});

test("setTheme forces mounted panels to reship rect after native restyle", async () => {
    const h = freshBridge();
    await h.window.bridge.nativePanels.mountPanel("mod_sysinfo");
    const theme = { r: 1, g: 2, b: 3, font_main: "Main", font_main_light: "Light" };

    await h.window.bridge.nativePanels.setTheme(theme);
    h.flushRaf();

    const rectCalls = h.invokeCalls.filter(c => c.cmd === "native_panel_set_rect");
    assert.equal(rectCalls.at(-1).payload.seq, 2);
});

test("missing anchor logs and does not invoke", async () => {
    const h = freshBridge({ anchors: [] });
    const origError = console.error;
    let errored = false;
    console.error = () => { errored = true; };
    try {
        await h.window.bridge.nativePanels.mountPanel("mod_sysinfo");
    } finally {
        console.error = origError;
    }

    assert.ok(errored);
    assert.equal(h.invokeCalls.length, 0);
});

test("mountPanel logs backend mount failure without rejecting", async () => {
    const invokeCalls = [];
    const h = freshBridge({ invokeImpl: (cmd, payload) => {
        invokeCalls.push({ cmd, payload });
        if (cmd === "native_panel_mount") return Promise.reject(new Error("boom"));
        return Promise.resolve(null);
    }, invokeCalls });
    const origWarn = console.warn;
    let warned = false;
    console.warn = () => { warned = true; };
    try {
        await h.window.bridge.nativePanels.mountPanel("mod_sysinfo");
    } finally {
        console.warn = origWarn;
    }

    assert.ok(warned);
    assert.equal(h.invokeCalls[0].cmd, "native_panel_mount");
    assert.ok(h.invokeCalls.some(c => c.cmd === "native_panel_set_rect"));
});
