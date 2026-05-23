const test = require("node:test");
const assert = require("node:assert/strict");

const { TerminalTabs } = require("./terminalTabs.class.js");

function makeElement(id) {
    return {
        id,
        dataset: {},
        innerHTML: "",
        listeners: {},
        classList: {
            values: new Set(),
            add(name) { this.values.add(name); },
            remove(name) { this.values.delete(name); },
            contains(name) { return this.values.has(name); }
        },
        addEventListener(name, handler) {
            this.listeners[name] = handler;
        }
    };
}

function setupDom(maxTabs = 5) {
    const elements = new Map();
    const container = makeElement("main_shell");
    elements.set("main_shell", container);

    for (let index = 0; index < maxTabs; index++) {
        const tab = makeElement(`shell_tab${index}`);
        tab.dataset.tabIndex = String(index);
        elements.set(tab.id, tab);
        elements.set(`terminal${index}`, makeElement(`terminal${index}`));
    }

    global.window = {
        appVersion: "3.0.0-test",
        _escapeHtml: value => String(value)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
    };
    global.document = {
        getElementById(id) {
            return elements.get(id) || null;
        },
        querySelectorAll(selector) {
            if (selector === "#main_shell_tabs > li") {
                return Array.from({ length: maxTabs }, (_, index) => elements.get(`shell_tab${index}`));
            }
            if (selector === "#main_shell_innercontainer > pre") {
                return Array.from({ length: maxTabs }, (_, index) => elements.get(`terminal${index}`));
            }
            return [];
        }
    };

    return elements;
}

class FakeTerminal {
    static instances = [];

    constructor(opts) {
        this.opts = opts;
        this.cwd = opts.cwd;
        this._init = Promise.resolve();
        this.fitCount = 0;
        this.closeCount = 0;
        this.disposeCount = 0;
        this.resendCount = 0;
        this.term = {
            focusCount: 0,
            writes: [],
            writeln: value => this.term.writes.push(value),
            focus: () => { this.term.focusCount++; },
            dispose: () => { this.disposeCount++; }
        };
        FakeTerminal.instances.push(this);
    }

    fit() {
        this.fitCount++;
    }

    resendCWD() {
        this.resendCount++;
    }

    write(value) {
        this.lastWrite = value;
    }

    writelr(value) {
        this.lastWriteLine = `${value}\r`;
    }

    async close() {
        this.closeCount++;
    }

    async dispose() {
        this.disposeCount++;
    }
}

function createTabs() {
    FakeTerminal.instances = [];
    global.Terminal = FakeTerminal;
    return new TerminalTabs({
        containerId: "main_shell",
        shell: "/bin/zsh",
        shellArgs: ["--login"],
        defaultCwd: "/Users/test",
        maxTabs: 5
    });
}

test("opens a tab and syncs legacy globals", async () => {
    const elements = setupDom();
    const tabs = createTabs();

    await tabs.open(0);

    assert.equal(window.currentTerm, 0);
    assert.equal(window.term, tabs.slots);
    assert.equal(tabs.active(), FakeTerminal.instances[0]);
    assert.equal(FakeTerminal.instances[0].opts.parentId, "terminal0");
    assert.equal(FakeTerminal.instances[0].opts.cwd, "/Users/test");
    assert.match(elements.get("shell_tab0").innerHTML, /MAIN SHELL/);
    assert.equal(elements.get("terminal0").classList.contains("active"), true);
});

test("cycles only through open tabs", async () => {
    setupDom();
    const tabs = createTabs();

    await tabs.open(0);
    await tabs.open(2);
    tabs.focus(0);

    assert.equal(tabs.next(), true);
    assert.equal(window.currentTerm, 2);
    assert.equal(tabs.next(), true);
    assert.equal(window.currentTerm, 0);
    assert.equal(tabs.previous(), true);
    assert.equal(window.currentTerm, 2);
});

test("closing the active non-main tab disposes it and falls back to main", async () => {
    const elements = setupDom();
    const tabs = createTabs();

    await tabs.open(0);
    await tabs.open(1);
    const closed = FakeTerminal.instances[1];

    assert.equal(await tabs.close(1), true);

    assert.equal(closed.closeCount, 1);
    assert.equal(closed.disposeCount, 1);
    assert.equal(tabs.slots[1], null);
    assert.equal(window.currentTerm, 0);
    assert.match(elements.get("shell_tab1").innerHTML, /EMPTY/);
    assert.equal(elements.get("terminal1").innerHTML, "");
});
