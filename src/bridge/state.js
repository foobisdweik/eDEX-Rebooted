// Cross-slice state accessors. During the JS-frontend era these are
// thin shims over the existing window.* globals; after the terminal
// slice goes native they become FFI calls into Rust-owned state.

(function (globalScope) {
    globalScope.bridge = globalScope.bridge || {};
    globalScope.bridge.state = {
        getTerm(index) {
            return globalScope.term && globalScope.term[index] ? globalScope.term[index] : null;
        },
        getCurrentTerm() {
            return typeof globalScope.currentTerm === "number" ? globalScope.currentTerm : 0;
        },
        setCurrentTerm(index) {
            globalScope.currentTerm = index;
        },
        getTheme() {
            return globalScope.theme || null;
        },
        getSettings() {
            return globalScope.settings || null;
        },
        getCwd(index) {
            const term = globalScope.bridge.state.getTerm(index);
            return term && term.cwd ? term.cwd : null;
        }
    };

    if (typeof module !== "undefined" && module.exports) {
        module.exports = globalScope.bridge.state;
    }
})(typeof window !== "undefined" ? window : globalThis);
