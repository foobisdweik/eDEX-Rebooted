const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

function freshBridge() {
    const sandbox = { __TAURI__: null };
    delete require.cache[require.resolve("./state.js")];
    delete require.cache[require.resolve("./audio.js")];
    delete require.cache[require.resolve("./events.js")];
    global.window = sandbox;
    require("./state.js");
    require("./audio.js");
    require("./events.js");
    return sandbox;
}

test("state.getCurrentTerm defaults to 0 when window.currentTerm is unset", () => {
    const window = freshBridge();
    assert.equal(window.bridge.state.getCurrentTerm(), 0);
});

test("state.setCurrentTerm/getCurrentTerm round-trip", () => {
    const window = freshBridge();
    window.bridge.state.setCurrentTerm(3);
    assert.equal(window.bridge.state.getCurrentTerm(), 3);
    assert.equal(window.currentTerm, 3);
});

test("state.getTerm returns null for empty slots", () => {
    const window = freshBridge();
    window.term = [null, null, null];
    assert.equal(window.bridge.state.getTerm(0), null);
    assert.equal(window.bridge.state.getTerm(5), null);
});

test("state.getCwd returns the active term's cwd or null", () => {
    const window = freshBridge();
    window.term = [{ cwd: "/Users/test" }, null];
    window.bridge.state.setCurrentTerm(0);
    assert.equal(window.bridge.state.getCwd(0), "/Users/test");
    assert.equal(window.bridge.state.getCwd(1), null);
});

test("audio.play is a no-op when audioManager is absent", () => {
    const window = freshBridge();
    assert.equal(window.bridge.audio.play("folder"), false);
});

test("audio.play forwards to audioManager[name].play()", () => {
    const window = freshBridge();
    let played = 0;
    window.audioManager = { folder: { play: () => { played++; } } };
    assert.equal(window.bridge.audio.play("folder"), true);
    assert.equal(played, 1);
});

test("events.on/emit delivers payload synchronously", () => {
    const window = freshBridge();
    const received = [];
    window.bridge.events.on("tab-focus", payload => received.push(payload));
    window.bridge.events.emit("tab-focus", 2);
    window.bridge.events.emit("tab-focus", 0);
    assert.deepEqual(received, [2, 0]);
});

test("events.on returns an unsubscribe handle", () => {
    const window = freshBridge();
    let calls = 0;
    const unsub = window.bridge.events.on("cwd-change", () => calls++);
    window.bridge.events.emit("cwd-change", "/a");
    unsub();
    window.bridge.events.emit("cwd-change", "/b");
    assert.equal(calls, 1);
});

test("events.emit returns successful-delivery count and survives throwing handlers", () => {
    const window = freshBridge();
    const originalError = console.error;
    console.error = () => {};
    try {
        let ok = 0;
        window.bridge.events.on("theme-change", () => { throw new Error("boom"); });
        window.bridge.events.on("theme-change", () => { ok++; });
        assert.equal(window.bridge.events.emit("theme-change", {}), 1);
        assert.equal(ok, 1);
    } finally {
        console.error = originalError;
    }
});

test("events.listenerCount reflects active subscribers", () => {
    const window = freshBridge();
    assert.equal(window.bridge.events.listenerCount("x"), 0);
    const off = window.bridge.events.on("x", () => {});
    assert.equal(window.bridge.events.listenerCount("x"), 1);
    off();
    assert.equal(window.bridge.events.listenerCount("x"), 0);
});

test("events.on rejects non-function handlers", () => {
    const window = freshBridge();
    assert.throws(() => window.bridge.events.on("x", null), TypeError);
    assert.throws(() => window.bridge.events.on("x", "string"), TypeError);
    assert.throws(() => window.bridge.events.on("x", 42), TypeError);
});

test("events.emit uses a snapshot, so concurrent subscribe doesn't fire this round", () => {
    const window = freshBridge();
    let outerCalls = 0;
    let innerCalls = 0;
    window.bridge.events.on("x", () => {
        outerCalls++;
        window.bridge.events.on("x", () => { innerCalls++; });
    });
    window.bridge.events.emit("x");
    assert.equal(outerCalls, 1);
    assert.equal(innerCalls, 0);
    // The newly-added handler fires on the NEXT emit.
    window.bridge.events.emit("x");
    assert.ok(innerCalls >= 1);
});

test("events.emit uses a snapshot, so concurrent unsubscribe doesn't skip handlers mid-iteration", () => {
    const window = freshBridge();
    let calls = 0;
    const handlerA = () => { calls++; off(); };
    const handlerB = () => { calls++; };
    window.bridge.events.on("x", handlerA);
    const off = window.bridge.events.on("x", handlerB);
    window.bridge.events.emit("x");
    assert.equal(calls, 2);
});

function freshSysinfoBridge(invokeImpl) {
    delete require.cache[require.resolve("./sysinfo.js")];
    global.window = {
        __TAURI__: { core: { invoke: invokeImpl } }
    };
    require("./sysinfo.js");
    return global.window;
}

test("sysinfo proxy forwards camelCase reads to snake_case invoke commands", () => {
    const calls = [];
    const window = freshSysinfoBridge((cmd, payload) => {
        calls.push([cmd, payload]);
        return Promise.resolve(null);
    });
    window.bridge.sysinfo.cpu();
    window.bridge.sysinfo.networkInterfaces();
    window.bridge.sysinfo.networkStats("en0");
    window.bridge.sysinfo.panelSnapshot(true, 8, false);
    assert.deepEqual(calls, [
        ["si_cpu", {}],
        ["si_network_interfaces", {}],
        ["si_network_stats", { iface: "en0" }],
        ["si_panel_snapshot", { collapseThreadsByName: true, topLimit: 8, includeProcessList: false }]
    ]);
});

test("sysinfo panelSnapshot reuses short-lived cache and in-flight request", async () => {
    let calls = 0;
    const window = freshSysinfoBridge(() => {
        calls++;
        return Promise.resolve({ ok: true, calls });
    });
    const [a, b] = await Promise.all([
        window.bridge.sysinfo.panelSnapshot(false, 5, false),
        window.bridge.sysinfo.panelSnapshot(false, 5, false)
    ]);
    assert.equal(calls, 1);
    assert.deepEqual(a, b);
    const c = await window.bridge.sysinfo.panelSnapshot(false, 5, false);
    assert.equal(calls, 1);
    assert.deepEqual(c, a);
});

test("sysinfo panelSnapshot cache is keyed by collapse, topLimit, and includeProcessList", async () => {
    const payloads = [];
    const window = freshSysinfoBridge((_cmd, payload) => {
        payloads.push(payload);
        return Promise.resolve(payload);
    });
    await window.bridge.sysinfo.panelSnapshot(false, 5, false);
    await window.bridge.sysinfo.panelSnapshot(true, 5, false);
    await window.bridge.sysinfo.panelSnapshot(false, 8, false);
    await window.bridge.sysinfo.panelSnapshot(false, 5, true);
    assert.equal(payloads.length, 4);
});

test("sysinfo proxy does not impersonate a thenable when awaited", async () => {
    const window = freshSysinfoBridge(() => Promise.resolve("never invoked"));
    assert.equal(typeof window.bridge.sysinfo.then, "undefined");
    // Awaiting the proxy directly must NOT trigger si_then.
    const awaited = await window.bridge.sysinfo;
    assert.equal(awaited, window.bridge.sysinfo);
});

test("sysinfo proxy ignores Symbol property reads", () => {
    const window = freshSysinfoBridge(() => { throw new Error("invoke called"); });
    assert.equal(window.bridge.sysinfo[Symbol.iterator], undefined);
    assert.equal(window.bridge.sysinfo[Symbol.toPrimitive], undefined);
});

test("sysinfo proxy passes Object.prototype methods through", () => {
    const window = freshSysinfoBridge(() => { throw new Error("invoke called"); });
    // toString / hasOwnProperty must be the standard Object methods, not si_to_string.
    assert.equal(typeof window.bridge.sysinfo.toString, "function");
    assert.equal(window.bridge.sysinfo.toString(), "[object Object]");
});
