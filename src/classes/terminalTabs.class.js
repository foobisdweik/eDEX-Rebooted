class TerminalTabs {
    constructor(opts) {
        if (!opts || !opts.containerId) throw new Error("Missing terminal tabs container");
        if (!opts.shell) throw new Error("Missing shell binary");

        this.container = document.getElementById(opts.containerId);
        if (!this.container) throw new Error(`Terminal tabs container not found: ${opts.containerId}`);

        this.shell = opts.shell;
        this.shellArgs = opts.shellArgs || [];
        this.defaultCwd = opts.defaultCwd || "/";
        this.maxTabs = opts.maxTabs || 5;
        this.onActiveCwdChange = opts.onActiveCwdChange || (() => {});
        this.onActiveProcessChange = opts.onActiveProcessChange || (() => {});
        this.onFocus = opts.onFocus || (() => {});
        this.slots = new Array(this.maxTabs).fill(null);
        this.activeIndex = 0;
    }

    mount() {
        const tabs = [];
        const panes = [];
        for (let index = 0; index < this.maxTabs; index++) {
            const active = index === 0 ? "active" : "";
            tabs.push(`<li id="shell_tab${index}" data-tab-index="${index}" class="${active}"><p>${index === 0 ? "MAIN SHELL" : "EMPTY"}</p></li>`);
            panes.push(`<pre id="terminal${index}" class="${active}"></pre>`);
        }

        this.container.innerHTML += `
            <ul id="main_shell_tabs">${tabs.join("")}</ul>
            <div id="main_shell_innercontainer">${panes.join("")}</div>`;

        document.querySelectorAll("#main_shell_tabs > li").forEach(node => {
            node.addEventListener("click", () => {
                this.openOrFocus(Number(node.dataset.tabIndex)).catch(e => console.error("tab focus failed:", e));
            });
        });
    }

    syncGlobals() {
        window.term = this.slots;
        window.currentTerm = this.activeIndex;
    }

    active() {
        return this.slots[this.activeIndex];
    }

    isOpen(index) {
        return Boolean(this.slots[index]);
    }

    label(index, text) {
        const tab = document.getElementById(`shell_tab${index}`);
        if (tab) tab.innerHTML = `<p>${window._escapeHtml(text)}</p>`;
    }

    setActiveDom(index) {
        document.querySelectorAll("#main_shell_tabs > li").forEach(node => node.classList.remove("active"));
        document.querySelectorAll("#main_shell_innercontainer > pre").forEach(node => node.classList.remove("active"));
        const tab = document.getElementById(`shell_tab${index}`);
        const pane = document.getElementById(`terminal${index}`);
        if (tab) tab.classList.add("active");
        if (pane) pane.classList.add("active");
    }

    async openOrFocus(index) {
        if (this.isOpen(index)) {
            this.focus(index);
            return this.slots[index];
        }
        return this.open(index);
    }

    async open(index, opts) {
        if (index < 0 || index >= this.maxTabs) throw new Error(`Tab index out of range: ${index}`);
        if (this.slots[index]) return this.openOrFocus(index);

        const cwd = (opts && opts.cwd) || (this.active() && this.active().cwd) || this.defaultCwd;
        this.label(index, "LOADING...");

        const terminal = new Terminal({
            role: "client",
            parentId: `terminal${index}`,
            shell: this.shell,
            args: this.shellArgs,
            cwd
        });

        this.slots[index] = terminal;
        this.syncGlobals();

        terminal.onprocesschange = processName => {
            const prefix = index === 0 ? "MAIN" : `#${index + 1}`;
            this.label(index, processName ? `${prefix} - ${processName}` : prefix);
            if (index === this.activeIndex) this.onActiveProcessChange(processName);
        };

        terminal.oncwdchange = cwd => {
            if (index === this.activeIndex) this.onActiveCwdChange(cwd);
        };

        terminal.onclose = () => {
            this.close(index, { fromProcessExit: true }).catch(e => console.warn("tab close failed:", e));
        };

        try {
            if (terminal._init) await terminal._init;
            if (index === 0) {
                terminal.term.writeln("\x1b[1m" + `Welcome to eDEX-UI v${window.appVersion} - Tauri/Rust port` + "\x1b[0m");
                this.label(index, "MAIN SHELL");
            } else {
                this.label(index, `#${index + 1}`);
            }
            this.focus(index);
            return terminal;
        } catch (e) {
            this.slots[index] = null;
            this.label(index, "ERROR");
            this.syncGlobals();
            throw e;
        }
    }

    focus(index) {
        if (!this.slots[index]) return false;
        this.activeIndex = index;
        this.syncGlobals();
        this.setActiveDom(index);
        this.slots[index].fit();
        this.slots[index].term.focus();
        this.slots[index].resendCWD();
        this.onFocus(index, this.slots[index]);
        return true;
    }

    async close(index, opts) {
        const terminal = this.slots[index];
        if (!terminal) return false;
        if (index === 0 && !(opts && opts.allowMainClose)) return false;

        this.slots[index] = null;
        this.syncGlobals();

        if (!(opts && opts.fromProcessExit)) {
            await terminal.close();
        }
        if (terminal.dispose) {
            await terminal.dispose();
        } else if (terminal.term && terminal.term.dispose) {
            terminal.term.dispose();
        }

        const pane = document.getElementById(`terminal${index}`);
        if (pane) pane.innerHTML = "";
        this.label(index, index === 0 ? "MAIN SHELL" : "EMPTY");

        if (this.activeIndex === index) {
            this.focus(this.previousOpenIndex(index));
        }
        return true;
    }

    next() {
        for (let step = 1; step <= this.maxTabs; step++) {
            const index = (this.activeIndex + step) % this.maxTabs;
            if (this.slots[index]) return this.focus(index);
        }
        return false;
    }

    previous() {
        for (let step = 1; step <= this.maxTabs; step++) {
            const index = (this.activeIndex - step + this.maxTabs) % this.maxTabs;
            if (this.slots[index]) return this.focus(index);
        }
        return false;
    }

    previousOpenIndex(fromIndex) {
        for (let step = 1; step <= this.maxTabs; step++) {
            const index = (fromIndex - step + this.maxTabs) % this.maxTabs;
            if (this.slots[index]) return index;
        }
        return 0;
    }

    resizeActive() {
        const terminal = this.active();
        if (terminal) terminal.fit();
    }

    writeActive(data) {
        const terminal = this.active();
        if (terminal) terminal.write(data);
    }

    writelrActive(data) {
        const terminal = this.active();
        if (terminal) terminal.writelr(data);
    }
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { TerminalTabs };
}
