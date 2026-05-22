// Tauri port: `require("howler")` and `__dirname` are gone. Howl/Howler come
// from the UMD bundle loaded in ui.html; WAV paths are document-relative URLs
// resolved by the WKWebView against the Tauri-served frontend root.
class AudioManager {
    constructor() {
        const audioUrl = name => `assets/audio/${name}.wav`;

        if (window.settings.audio === true) {
            if (window.settings.disableFeedbackAudio === false) {
                this.stdout  = new Howl({ src: [audioUrl("stdout")],  volume: 0.4 });
                this.stdin   = new Howl({ src: [audioUrl("stdin")],   volume: 0.4 });
                this.folder  = new Howl({ src: [audioUrl("folder")] });
                this.granted = new Howl({ src: [audioUrl("granted")] });
            }
            this.keyboard = new Howl({ src: [audioUrl("keyboard")] });
            this.theme    = new Howl({ src: [audioUrl("theme")] });
            this.expand   = new Howl({ src: [audioUrl("expand")] });
            this.panels   = new Howl({ src: [audioUrl("panels")] });
            this.scan     = new Howl({ src: [audioUrl("scan")] });
            this.denied   = new Howl({ src: [audioUrl("denied")] });
            this.info     = new Howl({ src: [audioUrl("info")] });
            this.alarm    = new Howl({ src: [audioUrl("alarm")] });
            this.error    = new Howl({ src: [audioUrl("error")] });

            Howler.volume(window.settings.audioVolume);
        } else {
            Howler.volume(0.0);
        }

        // Proxy so missing/unloaded sounds resolve to a no-op `.play()`.
        return new Proxy(this, {
            get: (target, sound) => {
                if (sound in target) {
                    return target[sound];
                }
                return { play: () => true };
            }
        });
    }
}
