// Audio cue facade. Today it forwards to the howler-backed
// AudioManager; after the shell slice goes native it forwards to the
// native audio FFI. Callers (terminal, modal, keyboard, filesystem)
// should migrate to bridge.audio.play("name") so that swap requires
// no further consumer changes.

(function (globalScope) {
    globalScope.bridge = globalScope.bridge || {};
    globalScope.bridge.audio = {
        play(name) {
            const manager = globalScope.audioManager;
            if (!manager || !manager[name] || typeof manager[name].play !== "function") {
                return false;
            }
            manager[name].play();
            return true;
        }
    };

    if (typeof module !== "undefined" && module.exports) {
        module.exports = globalScope.bridge.audio;
    }
})(typeof window !== "undefined" ? window : globalThis);
