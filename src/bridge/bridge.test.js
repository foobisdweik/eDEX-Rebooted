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
