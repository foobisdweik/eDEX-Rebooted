const test = require("node:test");
const assert = require("node:assert/strict");

// Minimal sandbox: fresh window with mocks for everything the bridge touches.
// Each test calls freshBridge() to get a clean module instance + spy harness.
function freshBridge({ withModColumn = true, dpr = 2 } = {}) {
    const invokeCalls = [];
    const rafQueue = [];
    let mqListeners = [];
    let resizeListeners = [];
    let observerInstances = [];

    class FakeResizeObserver {
        constructor(cb) { this.cb = cb; observerInstances.push(this); }
        observe(el) { this.observedEl = el; }
        disconnect() { this.cb = null; }
        fire() { if (this.cb) this.cb(); }
    }

    let columnRect = { left: 10, top: 20, width: 100, height: 200 };
    const modColumnEl = {
        getBoundingClientRect: () => ({ ...columnRect }),
    };

    const sandbox = {
        __TAURI__: {
            core: {
                invoke: (cmd, payload) => {
                    invokeCalls.push({ cmd, payload });
                    return Promise.resolve(null);
                },
            },
        },
        devicePixelRatio: dpr,
        requestAnimationFrame: (cb) => {
            rafQueue.push(cb);
            return rafQueue.length;
        },
        document: {
            getElementById: (id) => {
                if (id === "mod_column_left" && withModColumn) return modColumnEl;
                return null;
            },
            body: {
                _classes: new Set(),
                classList: {
                    add(c) { sandbox.document.body._classes.add(c); },
                    has(c) { return sandbox.document.body._classes.has(c); },
                },
            },
        },
        ResizeObserver: FakeResizeObserver,
        matchMedia: (q) => ({
            media: q,
            addEventListener: (event, cb) => { mqListeners.push({ event, cb }); },
        }),
        addEventListener: (event, cb) => { resizeListeners.push({ event, cb }); },
    };

    delete require.cache[require.resolve("./native_mount.js")];
    global.window = sandbox;
    require("./native_mount.js");

    function setRect(next) { columnRect = { ...next }; }
    function setDpr(next) { sandbox.devicePixelRatio = next; }
    function flushRaf() {
        const pending = rafQueue.splice(0);
        for (const cb of pending) cb();
    }

    return {
        window: sandbox,
        invokeCalls,
        observerInstances,
        mqListeners,
        resizeListeners,
        setRect,
        setDpr,
        flushRaf,
    };
}

test("activate adds native-left-active class and ships first rect with seq=1", async () => {
    const h = freshBridge();
    await h.window.bridge.nativeMount.activate();
    h.flushRaf();
    assert.ok(h.window.document.body.classList.has("native-left-active"));
    assert.equal(h.invokeCalls.length, 2);
    assert.equal(h.invokeCalls[0].cmd, "native_mount_set_rect");
    assert.deepEqual(h.invokeCalls[0].payload.rect, { x: 10, y: 20, width: 100, height: 200 });
    assert.equal(h.invokeCalls[0].payload.dpr, 2);
    assert.equal(h.invokeCalls[0].payload.seq, 1);
    assert.equal(h.invokeCalls[1].cmd, "native_mount_set_visible");
    assert.deepEqual(h.invokeCalls[1].payload, { visible: true });
});

test("two ResizeObserver fires within one rAF coalesce to one invoke", async () => {
    const h = freshBridge();
    await h.window.bridge.nativeMount.activate();
    h.flushRaf();
    h.invokeCalls.length = 0;

    h.setRect({ left: 11, top: 22, width: 100, height: 200 });
    h.observerInstances[0].fire();
    h.observerInstances[0].fire();
    h.flushRaf();

    assert.equal(h.invokeCalls.length, 1);
    assert.equal(h.invokeCalls[0].payload.seq, 2);
});

test("identical rect within epsilon does not invoke a second time", async () => {
    const h = freshBridge();
    await h.window.bridge.nativeMount.activate();
    h.flushRaf();
    const baseline = h.invokeCalls.length;

    h.setRect({ left: 10.3, top: 20.4, width: 100.1, height: 200.4 });
    h.observerInstances[0].fire();
    h.flushRaf();

    assert.equal(h.invokeCalls.length, baseline);
});

test("0.6pt delta on width does invoke", async () => {
    const h = freshBridge();
    await h.window.bridge.nativeMount.activate();
    h.flushRaf();
    const baseline = h.invokeCalls.length;

    h.setRect({ left: 10, top: 20, width: 100.6, height: 200 });
    h.observerInstances[0].fire();
    h.flushRaf();

    assert.equal(h.invokeCalls.length, baseline + 1);
    const last = h.invokeCalls[h.invokeCalls.length - 1];
    assert.equal(last.cmd, "native_mount_set_rect");
    assert.equal(last.payload.rect.width, 100.6);
});

test("DPR change with same rect does invoke", async () => {
    const h = freshBridge();
    await h.window.bridge.nativeMount.activate();
    h.flushRaf();
    const baseline = h.invokeCalls.length;

    h.setDpr(3);
    h.observerInstances[0].fire();
    h.flushRaf();

    assert.equal(h.invokeCalls.length, baseline + 1);
    const last = h.invokeCalls[h.invokeCalls.length - 1];
    assert.equal(last.payload.dpr, 3);
});

test("second activate() is idempotent (no extra observers, no extra invokes)", async () => {
    const h = freshBridge();
    await h.window.bridge.nativeMount.activate();
    h.flushRaf();
    const obsBefore = h.observerInstances.length;
    const callsBefore = h.invokeCalls.length;

    await h.window.bridge.nativeMount.activate();
    h.flushRaf();

    assert.equal(h.observerInstances.length, obsBefore);
    assert.equal(h.invokeCalls.length, callsBefore);
});

test("missing #mod_column_left logs error and does not throw", async () => {
    const h = freshBridge({ withModColumn: false });
    const origError = console.error;
    let errored = false;
    console.error = () => { errored = true; };
    try {
        await h.window.bridge.nativeMount.activate();
    } finally {
        console.error = origError;
    }
    assert.ok(errored);
    assert.equal(h.invokeCalls.length, 0);
    assert.ok(!h.window.document.body.classList.has("native-left-active"));
});

test("seq numbers are monotonic across many ships", async () => {
    const h = freshBridge();
    await h.window.bridge.nativeMount.activate();
    h.flushRaf();
    const seqs = [h.invokeCalls[0].payload.seq];
    for (let i = 1; i <= 5; i++) {
        h.setRect({ left: 10 + i * 5, top: 20, width: 100, height: 200 });
        h.observerInstances[0].fire();
        h.flushRaf();
        const last = h.invokeCalls[h.invokeCalls.length - 1];
        if (last.cmd === "native_mount_set_rect") seqs.push(last.payload.seq);
    }
    for (let i = 1; i < seqs.length; i++) {
        assert.ok(seqs[i] > seqs[i - 1], `seq ${seqs[i]} should be > ${seqs[i - 1]}`);
    }
});
