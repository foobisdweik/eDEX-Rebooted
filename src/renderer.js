// Disable eval() — same defensive posture as the legacy renderer.
window.eval = function () {
    throw new Error("eval() is disabled for security reasons.");
};
window._escapeHtml = text => {
    let map = {
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#039;'
    };
    return text.replace(/[&<>"']/g, m => map[m]);
};
window._encodePathURI = uri => encodeURI(uri).replace(/#/g, "%23");
window._purifyCSS = str => {
    if (typeof str === "undefined") return "";
    if (typeof str !== "string") str = str.toString();
    return str.replace(/[<]/g, "");
};
window._delay = ms => new Promise(resolve => setTimeout(resolve, ms));

// Boot-screen error handling — replaced with modal handler once UI is up.
window.onerror = (msg, path, line, col, error) => {
    const el = document.getElementById("boot_screen");
    if (el) el.innerHTML += `${error} :  ${msg}<br/>==> at ${path}  ${line}:${col}`;
};

// Tauri globals (relies on app.withGlobalTauri = true in tauri.conf.json).
const tauri = window.__TAURI__;
const { invoke } = tauri.core;
const { listen } = tauri.event;
const getCurrentWindow = tauri.window.getCurrentWindow;

// macOS-only POSIX-style path join; the legacy renderer used node's path.join.
const pathJoin = (...parts) => parts.filter(Boolean).join("/").replace(/\/+/g, "/");

// Async entry: load config + theme via invoke before the boot animation can start.
(async () => {
    const paths = await invoke("get_paths");
    window.__USER_DATA__ = paths;

    // FilesystemDisplay needs the file-icons map before it can render. The
    // legacy renderer pulled this via Node `require(...json)`; under Tauri we
    // fetch it from the bundled frontend at boot.
    try {
        window.__FILE_ICONS__ = await fetch("assets/icons/file-icons.json").then(r => r.json());
    } catch (e) {
        console.warn("file-icons.json fetch failed:", e);
        window.__FILE_ICONS__ = {};
    }

    const settingsDir = paths.userData;
    const themesDir = paths.themesDir;
    const keyboardsDir = paths.keyboardsDir;
    const fontsDir = paths.fontsDir;
    const settingsFile = paths.settingsFile;
    const shortcutsFile = paths.shortcutsFile;
    const lastWindowStateFile = paths.lastWindowStateFile;

    window.settings = await invoke("get_settings");
    window.shortcuts = await invoke("get_shortcuts");
    window.lastWindowState = await invoke("get_window_state");
    window.appVersion = await invoke("get_app_version");

    // CLI overrides — Tauri's argv plugin is not wired in v1; defaults match the legacy paths.
    window.settings.nointroOverride = false;
    window.settings.nocursorOverride = false;

    const themeOverride = await invoke("get_theme_override");
    if (themeOverride) {
        window.settings.theme = themeOverride;
        window.settings.nointroOverride = true;
    }
    const kbOverride = await invoke("get_kb_override");
    if (kbOverride) {
        window.settings.keyboard = kbOverride;
        window.settings.nointroOverride = true;
    }

    function fontFileName(fontFamily) {
        return `${fontFamily.toLowerCase().replace(/ /g, "_")}.woff2`;
    }

    async function loadFontFamily(fontFamily) {
        const fileName = fontFileName(fontFamily);
        const sources = [`assets/fonts/${fileName}`];

        if (tauri.core.convertFileSrc) {
            sources.push(tauri.core.convertFileSrc(pathJoin(fontsDir, fileName)));
        }

        for (const source of sources) {
            try {
                const face = new FontFace(fontFamily, `url("${source}")`);
                await face.load();
                document.fonts.add(face);
                return;
            } catch (_) {}
        }

        console.warn(`Font load failed for ${fontFamily}; falling back to system fonts.`);
    }

    window._loadTheme = async theme => {
        if (document.querySelector("style.theming")) {
            document.querySelector("style.theming").remove();
        }
        await Promise.all(
            Array.from(new Set([
                theme.cssvars.font_main,
                theme.cssvars.font_main_light,
                theme.terminal.fontFamily
            ])).map(loadFontFamily)
        );

        document.querySelector("head").innerHTML += `<style class="theming">
        :root {
            --font_main: "${window._purifyCSS(theme.cssvars.font_main)}";
            --font_main_light: "${window._purifyCSS(theme.cssvars.font_main_light)}";
            --font_mono: "${window._purifyCSS(theme.terminal.fontFamily)}";
            --color_r: ${window._purifyCSS(theme.colors.r)};
            --color_g: ${window._purifyCSS(theme.colors.g)};
            --color_b: ${window._purifyCSS(theme.colors.b)};
            --color_black: ${window._purifyCSS(theme.colors.black)};
            --color_light_black: ${window._purifyCSS(theme.colors.light_black)};
            --color_grey: ${window._purifyCSS(theme.colors.grey)};
            --color_red: ${window._purifyCSS(theme.colors.red) || "red"};
            --color_yellow: ${window._purifyCSS(theme.colors.yellow) || "yellow"};
        }
        body {
            font-family: var(--font_main), sans-serif;
            cursor: ${(window.settings.nocursorOverride || window.settings.nocursor) ? "none" : "default"} !important;
        }
        * {
            ${(window.settings.nocursorOverride || window.settings.nocursor) ? "cursor: none !important;" : ""}
        }
        ${window._purifyCSS(theme.injectCSS || "")}
        </style>`;

        window.theme = theme;
        window.theme.r = theme.colors.r;
        window.theme.g = theme.colors.g;
        window.theme.b = theme.colors.b;
    };

    const theme = await invoke("get_theme", { name: window.settings.theme });
    await window._loadTheme(theme);

    function initGraphicalErrorHandling() {
        window.edexErrorsModals = [];
        window.onerror = (msg, p, line, col, error) => {
            const errorModal = new Modal({
                type: "error",
                title: error,
                message: `${msg}<br/>        at ${p}  ${line}:${col}`
            });
            window.edexErrorsModals.push(errorModal);
            console.error(`${error}: ${msg}`, `at ${p} ${line}:${col}`);
        };
    }

    function waitForFonts() {
        if (!document.fonts) return Promise.resolve();
        return document.fonts.ready;
    }

    // window.si is owned by bridge/sysinfo.js — see ui.html script order.

    window.audioManager = new AudioManager();

    try { await getCurrentWindow().setFocus(); } catch (_) {}

    let i = 0;
    let bootLog = [];
    if (window.settings.nointro || window.settings.nointroOverride) {
        initGraphicalErrorHandling();
        const bs = document.getElementById("boot_screen");
        if (bs) bs.remove();
        document.body.setAttribute("class", "");
        waitForFonts().then(initUI);
    } else {
        bootLog = (await invoke("get_boot_log")).split("\n");
        displayLine();
    }

    function displayLine() {
        const bootScreen = document.getElementById("boot_screen");
        if (typeof bootLog[i] === "undefined") {
            setTimeout(displayTitleScreen, 300);
            return;
        }
        if (bootLog[i] === "Boot Complete") {
            window.audioManager.granted.play();
        } else {
            window.audioManager.stdout.play();
        }
        bootScreen.innerHTML += bootLog[i] + "<br/>";
        i++;

        switch (true) {
            case i === 2:
                bootScreen.innerHTML += `eDEX-UI Kernel version ${window.appVersion} boot at ${Date().toString()}; root:xnu-1699.22.73~1/RELEASE_X86_64`;
            case i === 4:
                setTimeout(displayLine, 500);
                break;
            case i > 4 && i < 25:
                setTimeout(displayLine, 30);
                break;
            case i === 25:
                setTimeout(displayLine, 400);
                break;
            case i === 42:
                setTimeout(displayLine, 300);
                break;
            case i > 42 && i < 82:
                setTimeout(displayLine, 25);
                break;
            case i === 83:
                setTimeout(displayLine, 25);
                break;
            case i >= bootLog.length - 2 && i < bootLog.length:
                setTimeout(displayLine, 300);
                break;
            default:
                setTimeout(displayLine, Math.pow(1 - (i / 1000), 3) * 25);
        }
    }

    async function displayTitleScreen() {
        let bootScreen = document.getElementById("boot_screen");
        if (bootScreen === null) {
            bootScreen = document.createElement("section");
            bootScreen.setAttribute("id", "boot_screen");
            bootScreen.setAttribute("style", "z-index: 9999999");
            document.body.appendChild(bootScreen);
        }
        bootScreen.innerHTML = "";
        window.audioManager.theme.play();

        await window._delay(400);
        document.body.setAttribute("class", "");
        bootScreen.setAttribute("class", "center");
        bootScreen.innerHTML = "<h1>eDEX-UI</h1>";
        let title = document.querySelector("section > h1");

        await window._delay(200);
        document.body.setAttribute("class", "solidBackground");
        await window._delay(100);
        title.setAttribute("style", `background-color: rgb(${window.theme.r}, ${window.theme.g}, ${window.theme.b});border-bottom: 5px solid rgb(${window.theme.r}, ${window.theme.g}, ${window.theme.b});`);
        await window._delay(300);
        title.setAttribute("style", `border: 5px solid rgb(${window.theme.r}, ${window.theme.g}, ${window.theme.b});`);
        await window._delay(100);
        title.setAttribute("style", "");
        title.setAttribute("class", "glitch");
        await window._delay(500);
        document.body.setAttribute("class", "");
        title.setAttribute("class", "");
        title.setAttribute("style", `border: 5px solid rgb(${window.theme.r}, ${window.theme.g}, ${window.theme.b});`);
        await window._delay(1000);

        if (window.term) {
            bootScreen.remove();
            return true;
        }
        initGraphicalErrorHandling();
        waitForFonts().then(() => {
            bootScreen.remove();
            initUI();
        });
    }

    async function getDisplayName() {
        if (window.settings.username) return window.settings.username;
        try { return await invoke("get_username"); } catch (_) { return null; }
    }

    async function initUI() {
        document.body.innerHTML += `<section class="mod_column" id="mod_column_left">
            <h3 class="title"><p>PANEL</p><p>SYSTEM</p></h3>
        </section>
        <section id="main_shell" style="height:0%;width:0%;opacity:0;margin-bottom:30vh;" augmented-ui="bl-clip tr-clip exe">
            <h3 class="title" style="opacity:0;"><p>TERMINAL</p><p>MAIN SHELL</p></h3>
            <h1 id="main_shell_greeting"></h1>
        </section>
        <section class="mod_column" id="mod_column_right">
            <h3 class="title"><p>PANEL</p><p>NETWORK</p></h3>
        </section>`;

        await window._delay(10);
        window.audioManager.expand.play();
        document.getElementById("main_shell").setAttribute("style", "height:0%;margin-bottom:30vh;");
        await window._delay(500);
        document.getElementById("main_shell").setAttribute("style", "margin-bottom: 30vh;");
        document.querySelector("#main_shell > h3.title").setAttribute("style", "");
        await window._delay(700);

        document.getElementById("main_shell").setAttribute("style", "opacity: 0;");
        document.body.innerHTML += `
        <section id="filesystem" style="width: 0px;" class="${window.settings.hideDotfiles ? "hideDotfiles" : ""} ${window.settings.fsListView ? "list-view" : ""}">
        </section>
        <section id="keyboard" style="opacity:0;">
        </section>`;
        const kbLayout = await invoke("get_keyboard_layout", { name: window.settings.keyboard });
        window.keyboard = new Keyboard({
            layout: kbLayout,
            container: "keyboard"
        });

        await window._delay(10);
        document.getElementById("main_shell").setAttribute("style", "");
        await window._delay(270);

        const greeter = document.getElementById("main_shell_greeting");
        getDisplayName().then(user => {
            greeter.innerHTML += user ? `Welcome back, <em>${user}</em>` : "Welcome back";
        });
        greeter.setAttribute("style", "opacity: 1;");

        document.getElementById("filesystem").setAttribute("style", "");
        document.getElementById("keyboard").setAttribute("style", "");
        document.getElementById("keyboard").setAttribute("class", "animation_state_1");
        window.audioManager.keyboard.play();

        await window._delay(100);
        document.getElementById("keyboard").setAttribute("class", "animation_state_1 animation_state_2");
        await window._delay(1000);
        greeter.setAttribute("style", "opacity: 0;");
        await window._delay(100);
        document.getElementById("keyboard").setAttribute("class", "");
        await window._delay(400);
        greeter.remove();

        // Modules — UpdateChecker / LocationGlobe / Conninfo / Netstat deferred
        // to v0.2. (Netstat needs Rust-side HTTPS + ping commands before it can
        // be reinstated; the `iface` setting still persists for forward compat.)
        window.mods = {};
        window.mods.clock = new Clock("mod_column_left");
        window.mods.sysinfo = new Sysinfo("mod_column_left");
        window.mods.hardwareInspector = new HardwareInspector("mod_column_left");
        window.mods.cpuinfo = new Cpuinfo("mod_column_left");
        window.mods.ramwatcher = new RAMwatcher("mod_column_left");
        window.mods.toplist = new Toplist("mod_column_left");

        document.querySelectorAll(".mod_column").forEach(e => {
            e.setAttribute("class", "mod_column activated");
        });
        let idx = 0;
        const left = document.querySelectorAll("#mod_column_left > div");
        const right = document.querySelectorAll("#mod_column_right > div");
        const tickHandle = setInterval(() => {
            if (!left[idx] && !right[idx]) {
                clearInterval(tickHandle);
            } else {
                window.audioManager.panels.play();
                if (left[idx]) left[idx].setAttribute("style", "animation-play-state: running;");
                if (right[idx]) right[idx].setAttribute("style", "animation-play-state: running;");
                idx++;
            }
        }, 500);

        await window._delay(100);

        // Slice 1b: opt-in native panel mount. Defaults false; users enable
        // via settings.json. Activation hides the JS panels in #mod_column_left
        // and shows the native NSView placeholder in their slot. Must run
        // after panels mount so #mod_column_left has its final layout rect.
        if (window.settings.experimentalNativePanels === true
                && window.bridge && window.bridge.nativeMount) {
            try {
                await window.bridge.nativeMount.activate();
            } catch (e) {
                console.warn("native_mount.activate() failed:", e);
            }
        }

        // Resolve the shell binary up-front (legacy did this in main).
        let shellBin;
        try {
            shellBin = await invoke("resolve_shell", { name: window.settings.shell || "zsh" });
        } catch (_) {
            shellBin = window.settings.shell || "/bin/zsh";
        }
        window.__SHELL_BIN__ = shellBin;

        window.terminalTabs = new TerminalTabs({
            containerId: "main_shell",
            shell: shellBin,
            shellArgs: window.settings.shellArgs ? window.settings.shellArgs.split(/\s+/).filter(Boolean) : [],
            defaultCwd: window.settings.cwd || settingsDir,
            maxTabs: 5,
            onFocus: () => {
                if (window.fsDisp) window.fsDisp.followTab();
            }
        });
        window.terminalTabs.mount();
        window.onmouseup = () => {
            if (window.keyboard.linkedToTerm && window.term && window.term[window.currentTerm]) {
                window.term[window.currentTerm].term.focus();
            }
        };
        await window.terminalTabs.open(0, { cwd: window.settings.cwd || settingsDir });

        await window._delay(100);
        window.fsDisp = new FilesystemDisplay({ parentId: "filesystem" });

        await window._delay(200);
        document.getElementById("filesystem").setAttribute("style", "opacity: 1;");

        if (window.performance.navigation && window.performance.navigation.type === 1) {
            window.term[window.currentTerm].resendCWD();
        }

        const sb = document.getElementById("settings_button");
        if (sb) sb.classList.add("ready");
    }

    // --- window.* command surface (called from inline onclick handlers, the
    // settings modal, and the global-shortcut callbacks) ---

    window.themeChanger = async name => {
        await invoke("set_theme_override", { theme: name });
        setTimeout(() => { window.location.reload(); }, 100);
    };

    window.remakeKeyboard = async layout => {
        if (window.keyboard && window.keyboard.destroy) {
            window.keyboard.destroy();
        }
        document.getElementById("keyboard").innerHTML = "";
        const kbLayout = await invoke("get_keyboard_layout", { name: layout || window.settings.keyboard });
        window.keyboard = new Keyboard({
            layout: kbLayout,
            container: "keyboard"
        });
        await invoke("set_kb_override", { layout });
    };

    window.focusShellTab = async number => {
        window.audioManager.folder.play();

        if (!window.terminalTabs) return false;
        try {
            await window.terminalTabs.openOrFocus(number);
            return true;
        } catch (e) {
            console.error("TTY spawn failed:", e);
            const tab = document.getElementById("shell_tab" + number);
            if (tab) tab.innerHTML = "<p>ERROR</p>";
            return false;
        }
    };

    window.openSettingsButton = () => {
        if (document.querySelector("div.modal_popup")) return;
        if (!window.openSettings) return;
        window.openSettings();
    };

    window.restartEdex = async () => {
        if (!confirm("Restart eDEX-UI?\n\nPending settings will be saved first. Under `cargo tauri dev` the window will go black after exit because cargo cannot re-spawn the child — relaunch from the terminal. Packaged builds restart normally.")) return;
        try { await window.writeSettingsFile(); } catch (_) {}
        try { await window.__TAURI__.process.relaunch(); } catch (e) { console.error("relaunch failed:", e); }
    };

    window.openSettings = async () => {
        if (document.getElementById("settingsEditor")) return;

        const themeList = await invoke("list_themes");
        const kbList = await invoke("list_keyboards");
        const displays = await invoke("get_displays");

        let keyboards = "";
        kbList.forEach(kb => {
            if (kb === window.settings.keyboard) return;
            keyboards += `<option>${kb}</option>`;
        });
        let themes = "";
        themeList.forEach(th => {
            if (th === window.settings.theme) return;
            themes += `<option>${th}</option>`;
        });
        let monitors = "";
        displays.forEach(d => {
            if (d.index !== window.settings.monitor) monitors += `<option>${d.index}</option>`;
        });
        let ifaces = "";
        const nets = await window.si.networkInterfaces();
        const currentIface = window.settings.iface || (nets[0] && nets[0].iface) || "";
        nets.forEach(net => {
            if (net.iface !== currentIface) ifaces += `<option>${net.iface}</option>`;
        });

        window.keyboard.detach();

        new Modal({
            type: "custom",
            title: `Settings <i>(v${window.appVersion})</i>`,
            html: `<table id="settingsEditor">
                        <tr><th>Key</th><th>Description</th><th>Value</th></tr>
                        <tr><td>shell</td><td>The program to run as a terminal emulator</td><td><input type="text" id="settingsEditor-shell" value="${window.settings.shell}"></td></tr>
                        <tr><td>shellArgs</td><td>Arguments to pass to the shell</td><td><input type="text" id="settingsEditor-shellArgs" value="${window.settings.shellArgs || ''}"></td></tr>
                        <tr><td>cwd</td><td>Working Directory to start in</td><td><input type="text" id="settingsEditor-cwd" value="${window.settings.cwd}"></td></tr>
                        <tr><td>username</td><td>Custom username to display at boot</td><td><input type="text" id="settingsEditor-username" value="${window.settings.username || ''}"></td></tr>
                        <tr><td>keyboard</td><td>On-screen keyboard layout code</td><td><select id="settingsEditor-keyboard"><option>${window.settings.keyboard}</option>${keyboards}</select></td></tr>
                        <tr><td>theme</td><td>Name of the theme to load</td><td><select id="settingsEditor-theme"><option>${window.settings.theme}</option>${themes}</select></td></tr>
                        <tr><td>termFontSize</td><td>Size of the terminal text in pixels</td><td><input type="number" id="settingsEditor-termFontSize" value="${window.settings.termFontSize}"></td></tr>
                        <tr><td>audio</td><td>Activate audio sound effects</td><td><select id="settingsEditor-audio"><option>${window.settings.audio}</option><option>${!window.settings.audio}</option></select></td></tr>
                        <tr><td>audioVolume</td><td>Set default volume for sound effects (0.0 - 1.0)</td><td><input type="number" id="settingsEditor-audioVolume" value="${window.settings.audioVolume || '1.0'}"></td></tr>
                        <tr><td>disableFeedbackAudio</td><td>Disable recurring feedback sound FX</td><td><select id="settingsEditor-disableFeedbackAudio"><option>${window.settings.disableFeedbackAudio}</option><option>${!window.settings.disableFeedbackAudio}</option></select></td></tr>
                        <tr><td>pingAddr</td><td>IPv4 address to test Internet connectivity</td><td><input type="text" id="settingsEditor-pingAddr" value="${window.settings.pingAddr || "1.1.1.1"}"></td></tr>
                        <tr><td>clockHours</td><td>Clock format (12/24 hours)</td><td><select id="settingsEditor-clockHours"><option>${(window.settings.clockHours === 12) ? "12" : "24"}</option><option>${(window.settings.clockHours === 12) ? "24" : "12"}</option></select></td></tr>
                        <tr><td>monitor</td><td>Which monitor to spawn the UI in</td><td><select id="settingsEditor-monitor">${(typeof window.settings.monitor !== "undefined") ? "<option>" + window.settings.monitor + "</option>" : ""}${monitors}</select></td></tr>
                        <tr><td>nointro</td><td>Skip the intro boot log and logo</td><td><select id="settingsEditor-nointro"><option>${window.settings.nointro}</option><option>${!window.settings.nointro}</option></select></td></tr>
                        <tr><td>nocursor</td><td>Hide the mouse cursor</td><td><select id="settingsEditor-nocursor"><option>${window.settings.nocursor}</option><option>${!window.settings.nocursor}</option></select></td></tr>
                        <tr><td>iface</td><td>Override the interface used for network monitoring (Netstat deferred to v0.2; setting persists)</td><td><select id="settingsEditor-iface"><option>${currentIface}</option>${ifaces}</select></td></tr>
                        <tr><td>allowWindowed</td><td>Allow F11 to enter windowed mode</td><td><select id="settingsEditor-allowWindowed"><option>${window.settings.allowWindowed}</option><option>${!window.settings.allowWindowed}</option></select></td></tr>
                        <tr><td>keepGeometry</td><td>Keep 16:9 aspect ratio in windowed mode</td><td><select id="settingsEditor-keepGeometry"><option>${(window.settings.keepGeometry === false) ? 'false' : 'true'}</option><option>${(window.settings.keepGeometry === false) ? 'true' : 'false'}</option></select></td></tr>
                        <tr><td>excludeThreadsFromToplist</td><td>Display threads in the top processes list</td><td><select id="settingsEditor-excludeThreadsFromToplist"><option>${window.settings.excludeThreadsFromToplist}</option><option>${!window.settings.excludeThreadsFromToplist}</option></select></td></tr>
                        <tr><td>hideDotfiles</td><td>Hide files starting with a dot</td><td><select id="settingsEditor-hideDotfiles"><option>${window.settings.hideDotfiles}</option><option>${!window.settings.hideDotfiles}</option></select></td></tr>
                        <tr><td>fsListView</td><td>Show files in a detailed list</td><td><select id="settingsEditor-fsListView"><option>${window.settings.fsListView}</option><option>${!window.settings.fsListView}</option></select></td></tr>
                    </table>
                    <h6 id="settingsEditorStatus">Loaded values from memory</h6>
                    <br>`,
            buttons: [
                { label: "Open in External Editor", action: `window.__TAURI__.shell.open('${settingsFile}');` },
                { label: "Save to Disk", action: "window.writeSettingsFile()" },
                { label: "Reload UI", action: "window.location.reload();" },
                { label: "Save &amp; Restart eDEX", action: "window.restartEdex();" }
            ]
        }, () => {
            window.keyboard.attach();
            window.term[window.currentTerm].term.focus();
        });
    };

    window.writeFile = path => {
        invoke("fs_writefile", { path, content: document.getElementById("fileEdit").value })
            .then(() => { document.getElementById("fedit-status").innerHTML = "<i>File saved.</i>"; })
            .catch(e => { document.getElementById("fedit-status").innerHTML = `<i>Save failed: ${e}</i>`; });
    };

    window.writeSettingsFile = async () => {
        const prevSettings = Object.assign({}, window.settings);
        const newSettings = {
            shell: document.getElementById("settingsEditor-shell").value,
            shellArgs: document.getElementById("settingsEditor-shellArgs").value,
            cwd: document.getElementById("settingsEditor-cwd").value,
            username: document.getElementById("settingsEditor-username").value,
            keyboard: document.getElementById("settingsEditor-keyboard").value,
            theme: document.getElementById("settingsEditor-theme").value,
            termFontSize: Number(document.getElementById("settingsEditor-termFontSize").value),
            audio: document.getElementById("settingsEditor-audio").value === "true",
            audioVolume: Number(document.getElementById("settingsEditor-audioVolume").value),
            disableFeedbackAudio: document.getElementById("settingsEditor-disableFeedbackAudio").value === "true",
            pingAddr: document.getElementById("settingsEditor-pingAddr").value,
            clockHours: Number(document.getElementById("settingsEditor-clockHours").value),
            monitor: Number(document.getElementById("settingsEditor-monitor").value),
            nointro: document.getElementById("settingsEditor-nointro").value === "true",
            nocursor: document.getElementById("settingsEditor-nocursor").value === "true",
            iface: document.getElementById("settingsEditor-iface").value,
            allowWindowed: document.getElementById("settingsEditor-allowWindowed").value === "true",
            forceFullscreen: window.settings.forceFullscreen,
            keepGeometry: document.getElementById("settingsEditor-keepGeometry").value === "true",
            excludeThreadsFromToplist: document.getElementById("settingsEditor-excludeThreadsFromToplist").value === "true",
            hideDotfiles: document.getElementById("settingsEditor-hideDotfiles").value === "true",
            fsListView: document.getElementById("settingsEditor-fsListView").value === "true"
        };
        Object.keys(newSettings).forEach(k => {
            if (newSettings[k] === "undefined") delete newSettings[k];
        });
        window.settings = newSettings;
        await invoke("write_settings", { contents: newSettings });
        const rebootKeys = ["shell", "shellArgs", "cwd", "username", "monitor", "nointro", "forceFullscreen", "allowWindowed", "keepGeometry", "theme", "keyboard"];
        const changed = rebootKeys.filter(k => prevSettings[k] !== newSettings[k]);
        const status = document.getElementById("settingsEditorStatus");
        status.innerText = "New values written to settings.json at " + new Date().toTimeString();
        if (changed.length) {
            status.innerHTML += `<br><span class="settingsRebootNotice">Some changes require an application restart to take effect: ${changed.join(", ")}.</span>`;
        }
    };

    window.toggleFullScreen = async () => {
        const win = getCurrentWindow();
        const isFs = await win.isFullscreen();
        const next = !isFs;
        await win.setFullscreen(next);
        window.lastWindowState.useFullscreen = next;
        await invoke("write_window_state", { contents: window.lastWindowState });
    };

    window.openShortcutsHelp = () => {
        if (document.getElementById("settingsEditor")) return;

        const shortcutsDefinition = {
            "COPY": "Copy selected buffer from the terminal.",
            "PASTE": "Paste system clipboard to the terminal.",
            "NEXT_TAB": "Switch to the next opened terminal tab (left to right order).",
            "PREVIOUS_TAB": "Switch to the previous opened terminal tab (right to left order).",
            "TAB_X": "Switch to terminal tab <strong>X</strong>, or create it if it hasn't been opened yet.",
            "SETTINGS": "Open the settings editor.",
            "SHORTCUTS": "List and edit available keyboard shortcuts.",
            "FUZZY_SEARCH": "Search for entries in the current working directory.",
            "FS_LIST_VIEW": "Toggle between list and grid view in the file browser.",
            "FS_DOTFILES": "Toggle hidden files and directories in the file browser.",
            "KB_PASSMODE": "Toggle the on-screen keyboard's \"Password Mode\".",
            "DEV_DEBUG": "Open Dev Tools.",
            "DEV_RELOAD": "Trigger front-end hot reload."
        };

        let appList = "";
        window.shortcuts.filter(e => e.type === "app").forEach(cut => {
            const action = cut.action.startsWith("TAB_") ? "TAB_X" : cut.action;
            appList += `<tr>
                            <td>${cut.enabled ? 'YES' : 'NO'}</td>
                            <td><input disabled type="text" maxlength=25 value="${cut.trigger}"></td>
                            <td>${shortcutsDefinition[action]}</td>
                        </tr>`;
        });

        let customList = "";
        window.shortcuts.filter(e => e.type === "shell").forEach(cut => {
            customList += `<tr>
                                <td>${cut.enabled ? 'YES' : 'NO'}</td>
                                <td><input disabled type="text" maxlength=25 value="${cut.trigger}"></td>
                                <td>
                                    <input disabled type="text" placeholder="Run terminal command..." value="${cut.action}">
                                    <input disabled type="checkbox" name="shortcutsHelpNew_Enter" ${cut.linebreak ? 'checked' : ''}>
                                    <label for="shortcutsHelpNew_Enter">Enter</label>
                                </td>
                            </tr>`;
        });

        window.keyboard.detach();
        new Modal({
            type: "custom",
            title: `Available Keyboard Shortcuts <i>(v${window.appVersion})</i>`,
            html: `<h5>Using either the on-screen or a physical keyboard, you can use the following shortcuts:</h5>
                    <details open id="shortcutsHelpAccordeon1">
                        <summary>Emulator shortcuts</summary>
                        <table class="shortcutsHelp">
                            <tr><th>Enabled</th><th>Trigger</th><th>Action</th></tr>
                            ${appList}
                        </table>
                    </details>
                    <br>
                    <details id="shortcutsHelpAccordeon2">
                        <summary>Custom command shortcuts</summary>
                        <table class="shortcutsHelp">
                            <tr><th>Enabled</th><th>Trigger</th><th>Command</th></tr>
                           ${customList}
                        </table>
                    </details>
                    <br>`,
            buttons: [
                { label: "Open Shortcuts File", action: `window.__TAURI__.shell.open('${shortcutsFile}');` },
                { label: "Reload UI", action: "window.location.reload();" }
            ]
        }, () => {
            window.keyboard.attach();
            window.term[window.currentTerm].term.focus();
        });

        const wrap1 = document.getElementById('shortcutsHelpAccordeon1');
        const wrap2 = document.getElementById('shortcutsHelpAccordeon2');
        wrap1.addEventListener('toggle', () => { wrap2.open = !wrap1.open; });
        wrap2.addEventListener('toggle', () => { wrap1.open = !wrap2.open; });
    };

    window.useAppShortcut = action => {
        switch (action) {
            case "COPY":
                window.term[window.currentTerm].clipboard.copy();
                return true;
            case "PASTE":
                window.term[window.currentTerm].clipboard.paste();
                return true;
            case "NEXT_TAB":
                if (window.terminalTabs) window.terminalTabs.next();
                return true;
            case "PREVIOUS_TAB":
                if (window.terminalTabs) window.terminalTabs.previous();
                return true;
            case "TAB_1": window.focusShellTab(0); return true;
            case "TAB_2": window.focusShellTab(1); return true;
            case "TAB_3": window.focusShellTab(2); return true;
            case "TAB_4": window.focusShellTab(3); return true;
            case "TAB_5": window.focusShellTab(4); return true;
            case "SETTINGS": window.openSettings(); return true;
            case "SHORTCUTS": window.openShortcutsHelp(); return true;
            case "FUZZY_SEARCH": window.activeFuzzyFinder = new FuzzyFinder(); return true;
            case "FS_LIST_VIEW": window.fsDisp.toggleListview(); return true;
            case "FS_DOTFILES": window.fsDisp.toggleHidedotfiles(); return true;
            case "KB_PASSMODE": window.keyboard.togglePasswordMode(); return true;
            case "DEV_DEBUG":
                // Tauri 2 webview devtools are gated by the `devtools` feature
                // on the tauri crate; the global-shortcut user can also use
                // the OS-native menu shortcut. No-op for v1.
                return true;
            case "DEV_RELOAD":
                window.location.reload();
                return true;
            default:
                console.warn(`Unknown "${action}" app shortcut action`);
                return false;
        }
    };

    // Global shortcuts via the Tauri plugin. The legacy code used
    // electron.remote.globalShortcut — the JS surface here is the
    // tauri-plugin-global-shortcut plugin.
    const gs = tauri.globalShortcut;

    window.registerKeyboardShortcuts = async () => {
        try { await gs.unregisterAll(); } catch (_) {}
        for (const cut of window.shortcuts) {
            if (!cut.enabled) continue;
            if (cut.type === "app") {
                if (cut.action === "TAB_X") {
                    for (let n = 1; n <= 5; n++) {
                        const trigger = cut.trigger.replace("X", String(n));
                        try { await gs.register(trigger, () => window.useAppShortcut(`TAB_${n}`)); } catch (_) {}
                    }
                } else {
                    try { await gs.register(cut.trigger, () => window.useAppShortcut(cut.action)); } catch (_) {}
                }
            } else if (cut.type === "shell") {
                try {
                    await gs.register(cut.trigger, () => {
                        const fn = cut.linebreak ? "writelr" : "write";
                        window.term[window.currentTerm][fn](cut.action);
                    });
                } catch (_) {}
            }
        }
    };
    window.registerKeyboardShortcuts();

    window.addEventListener("focus", () => { window.registerKeyboardShortcuts(); });
    window.addEventListener("blur", () => { gs.unregisterAll().catch(() => {}); });

    document.addEventListener("keydown", e => {
        if (e.key === "Alt") e.preventDefault();
        if (e.code.startsWith("Alt") && e.ctrlKey && e.shiftKey) e.preventDefault();
        if (e.key === "F11" && !window.settings.allowWindowed) e.preventDefault();
        if (e.code === "KeyD" && e.ctrlKey) e.preventDefault();
        if (e.code === "KeyA" && e.ctrlKey) e.preventDefault();
    });

    window.onresize = () => {
        if (window.terminalTabs) window.terminalTabs.resizeActive();
    };

    // Aspect-ratio enforcement during windowed-mode resize is handled
    // natively via NSWindow.setContentAspectRatio = (16, 10), installed
    // in src-tauri/src/window_chrome.rs. macOS clamps the user's drag
    // live, which is smoother than the post-release JS snap the legacy
    // code did. No window-resize listener needed here for that.

    window.addEventListener("beforeunload", () => {
        if (window.keyboard && window.keyboard.destroy) {
            window.keyboard.destroy();
        }
        gs.unregisterAll().catch(() => {});
    });
})().catch(e => {
    console.error("Renderer init failed:", e);
    const bs = document.getElementById("boot_screen");
    if (bs) bs.innerHTML += `<br><br>RENDERER INIT FAILED:<br>${(e && e.stack) || e}`;
});
