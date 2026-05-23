// Tauri/Rust port of the eDEX-UI terminal client. The legacy file had a dual
// role:"client" / role:"server" implementation tied to node-pty + ws.Server.
// Under Tauri, PTY lifecycle is owned by src-tauri/src/pty.rs and the JS side
// only acts as a client: invoke() to spawn/write/resize/kill, and event listen
// for the data stream emitted on the `pty://{id}/data` channel.
//
// Dependencies:
//   - window.__XTERM__          : xterm.Terminal constructor
//   - window.__XTERM_FIT__      : FitAddon class
//   - window.__XTERM_LIGATURES__: LigaturesAddon class
//   - window.__XTERM_WEBGL__    : WebglAddon class
// All four are aliased by inline <script> tags in ui.html after each xterm
// UMD script loads, because xterm UMD attaches as `window.Terminal` which
// would collide with this class.

class Terminal {
    constructor(opts) {
        if (opts.role && opts.role !== "client") {
            throw new Error("Tauri build supports role:'client' only");
        }
        if (!opts.parentId) throw "Missing options";

        const { invoke } = window.__TAURI__.core;
        const { listen } = window.__TAURI__.event;

        const XTerm = window.__XTERM__;
        const FitAddon = window.__XTERM_FIT__;
        const LigaturesAddon = window.__XTERM_LIGATURES__;
        const WebglAddon = window.__XTERM_WEBGL__;
        if (!XTerm) throw new Error("xterm.js is not loaded (window.__XTERM__ missing)");

        this.cwd = "";
        this.oncwdchange = () => {};

        // The legacy renderer applied a per-theme colorFilter chain via the
        // `color` npm package (CommonJS-only — incompatible with WKWebView).
        // v1 drops the filter; themes with explicit terminal colors render the
        // same, themes that relied on derived colors fall back to defaults.
        const themeColors = window.theme.colors || {};

        this.term = new XTerm({
            cols: 80,
            rows: 24,
            cursorBlink: window.theme.terminal.cursorBlink || true,
            cursorStyle: window.theme.terminal.cursorStyle || "block",
            allowTransparency: window.theme.terminal.allowTransparency || false,
            fontFamily: window.theme.terminal.fontFamily || "Fira Mono",
            fontSize: window.theme.terminal.fontSize || window.settings.termFontSize || 15,
            fontWeight: window.theme.terminal.fontWeight || "normal",
            fontWeightBold: window.theme.terminal.fontWeightBold || "bold",
            letterSpacing: window.theme.terminal.letterSpacing || 0,
            lineHeight: window.theme.terminal.lineHeight || 1,
            scrollback: 1500,
            bellStyle: "none",
            theme: {
                foreground: window.theme.terminal.foreground,
                background: window.theme.terminal.background,
                cursor: window.theme.terminal.cursor,
                cursorAccent: window.theme.terminal.cursorAccent,
                selection: window.theme.terminal.selection,
                black: themeColors.black || "#2e3436",
                red: themeColors.red || "#cc0000",
                green: themeColors.green || "#4e9a06",
                yellow: themeColors.yellow || "#c4a000",
                blue: themeColors.blue || "#3465a4",
                magenta: themeColors.magenta || "#75507b",
                cyan: themeColors.cyan || "#06989a",
                white: themeColors.white || "#d3d7cf",
                brightBlack: themeColors.brightBlack || "#555753",
                brightRed: themeColors.brightRed || "#ef2929",
                brightGreen: themeColors.brightGreen || "#8ae234",
                brightYellow: themeColors.brightYellow || "#fce94f",
                brightBlue: themeColors.brightBlue || "#729fcf",
                brightMagenta: themeColors.brightMagenta || "#ad7fa8",
                brightCyan: themeColors.brightCyan || "#34e2e2",
                brightWhite: themeColors.brightWhite || "#eeeeec"
            }
        });

        const fitAddon = new FitAddon();
        this.term.loadAddon(fitAddon);
        this.term.open(document.getElementById(opts.parentId));
        try { if (WebglAddon) this.term.loadAddon(new WebglAddon()); }
        catch (e) { console.warn("WebGL addon failed:", e); }
        const ligaturesEnabled = window.theme.terminal.ligatures === true
            || /fira code/i.test(window.theme.terminal.fontFamily || "");
        try { if (LigaturesAddon && ligaturesEnabled) this.term.loadAddon(new LigaturesAddon()); }
        catch (e) { console.warn("Ligatures addon failed:", e); }

        this.term.attachCustomKeyEventHandler(e => {
            if (window.keyboard) window.keyboard.keydownHandler(e);
            return true;
        });
        document.querySelectorAll('.xterm-helper-textarea').forEach(t => t.setAttribute('readonly', 'readonly'));
        this.term.focus();

        this.ptyId = null;
        this.lastSoundFX = Date.now();
        this.lastRefit = Date.now();
        this._unlistenData = null;
        this._unlistenExit = null;
        this._lastProc = null;
        this._disposed = false;

        // _init is awaited from the renderer before treating this Terminal as
        // ready — it owns spawning the PTY and wiring the data stream.
        this._init = (async () => {
            const env = Object.assign({
                TERM: "xterm-256color",
                COLORTERM: "truecolor",
                TERM_PROGRAM: "eDEX-UI",
                TERM_PROGRAM_VERSION: window.appVersion || ""
            }, window.settings.env || {});

            const id = await invoke("pty_spawn", {
                opts: {
                    shell: opts.shell || window.__SHELL_BIN__ || "/bin/zsh",
                    args: opts.args || [],
                    cwd: opts.cwd || window.settings.cwd || "/",
                    env,
                    cols: this.term.cols,
                    rows: this.term.rows
                }
            });
            this.ptyId = id;

            this._unlistenData = await listen(`pty://${id}/data`, e => {
                const now = Date.now();
                if (now - this.lastSoundFX > 30) {
                    if (window.passwordMode == "false") window.audioManager.stdout.play();
                    this.lastSoundFX = now;
                }
                if (now - this.lastRefit > 10000) this.fit();
                this.term.write(atob(e.payload));
            });

            this._unlistenExit = await listen(`pty://${id}/exit`, () => {
                if (this.onclose) this.onclose();
            });

            this.term.onData(d => {
                if (this.ptyId !== null) {
                    invoke("pty_write", { id: this.ptyId, data: d }).catch(() => {});
                }
            });

            this.fit();

            // CWD + foreground-process polling. The legacy server tracked these
            // via /proc on Linux and lsof on macOS at a 1s cadence — that logic
            // now lives in pty.rs and is queried by invoke from here.
            this._poll = setInterval(async () => {
                if (this.ptyId === null) return;
                try {
                    const cwd = await invoke("pty_cwd", { id: this.ptyId });
                    if (cwd && cwd !== this.cwd) {
                        this.cwd = cwd;
                        this.oncwdchange(cwd);
                    }
                } catch (_) {}
                try {
                    const proc = await invoke("pty_process", { id: this.ptyId });
                    if (proc && this._lastProc !== proc) {
                        this._lastProc = proc;
                        if (this.onprocesschange) this.onprocesschange(proc);
                    }
                } catch (_) {}
            }, 1000);
        })();

        this.resendCWD = () => {
            this.oncwdchange(this.cwd || null);
        };

        const parent = document.getElementById(opts.parentId);
        parent.addEventListener("wheel", e => {
            this.term.scrollLines(Math.round(e.deltaY / 10));
        });
        this._lastTouchY = null;
        parent.addEventListener("touchstart", e => {
            this._lastTouchY = e.targetTouches[0].screenY;
        });
        parent.addEventListener("touchmove", e => {
            if (this._lastTouchY) {
                const y = e.changedTouches[0].screenY;
                const deltaY = y - this._lastTouchY;
                this._lastTouchY = y;
                this.term.scrollLines(-Math.round(deltaY / 10));
            }
        });
        parent.addEventListener("touchend", () => { this._lastTouchY = null; });
        parent.addEventListener("touchcancel", () => { this._lastTouchY = null; });

        const helperTa = document.querySelector(".xterm-helper-textarea");
        if (helperTa) {
            helperTa.addEventListener("keydown", e => {
                if (e.key === "F11" && window.settings.allowWindowed) {
                    e.preventDefault();
                    if (window.toggleFullScreen) window.toggleFullScreen();
                }
            });
        }

        this.fit = () => {
            this.lastRefit = Date.now();
            const proposed = fitAddon.proposeDimensions();
            if (!proposed) return;
            let { cols, rows } = proposed;

            // Aspect-ratio nudge, preserved from the legacy implementation.
            const w = screen.width;
            const h = screen.height;
            let x = 1, y = 0;
            const gcd = (a, b) => (b == 0) ? a : gcd(b, a % b);
            const d = gcd(w, h);
            if (d === 100) { y = 1; x = 3; }
            if (d === 256) x = 2;
            if (window.settings.termFontSize < 15) y = y - 1;
            cols = cols + x;
            rows = rows + y;

            if (this.term.cols !== cols || this.term.rows !== rows) {
                this.resize(cols, rows);
            }
        };

        this.resize = (cols, rows) => {
            this.term.resize(cols, rows);
            if (this.ptyId !== null) {
                invoke("pty_resize", { id: this.ptyId, cols, rows }).catch(() => {});
            }
        };

        this.write = cmd => {
            if (this.ptyId !== null) {
                invoke("pty_write", { id: this.ptyId, data: cmd }).catch(() => {});
            }
        };
        this.writelr = cmd => this.write(cmd + "\r");

        this.clipboard = {
            didCopy: false,
            copy: () => {
                if (!this.term.hasSelection()) return false;
                try {
                    navigator.clipboard.writeText(this.term.getSelection());
                } catch (_) {
                    document.execCommand("copy");
                }
                this.term.clearSelection();
                this.clipboard.didCopy = true;
            },
            paste: async () => {
                try {
                    const text = await navigator.clipboard.readText();
                    this.write(text);
                } catch (_) {}
                this.clipboard.didCopy = false;
            }
        };

        this.close = async () => {
            if (this._poll) { clearInterval(this._poll); this._poll = null; }
            if (this._unlistenData) { this._unlistenData(); this._unlistenData = null; }
            if (this._unlistenExit) { this._unlistenExit(); this._unlistenExit = null; }
            if (this.ptyId !== null) {
                try { await invoke("pty_kill", { id: this.ptyId }); } catch (_) {}
                this.ptyId = null;
            }
        };

        this.dispose = async () => {
            if (this._disposed) return;
            this._disposed = true;
            await this.close();
            if (this.term && this.term.dispose) this.term.dispose();
        };
    }
}

// Kept so Node-side tooling (eslint, etc.) doesn't choke. Inert in WKWebView.
if (typeof module !== "undefined" && module.exports) {
    module.exports = { Terminal };
}
