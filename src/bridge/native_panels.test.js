const test = require("node:test");
const assert = require("node:assert/strict");

function freshBridge({ anchors = ["mod_sysinfo"], dpr = 2, invokeImpl = null, invokeCalls = [] } = {}) {
    const rafQueue = [];
    const observerInstances = [];
    const elements = new Map();

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

test("setTheme invokes native_set_theme with theme payload", async () => {
    const h = freshBridge();
    const theme = { r: 1, g: 2, b: 3, font_main: "Main", font_main_light: "Light" };
    await h.window.bridge.nativePanels.setTheme(theme);

    assert.deepEqual(h.invokeCalls, [
        { cmd: "native_set_theme", payload: { theme } },
    ]);
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
