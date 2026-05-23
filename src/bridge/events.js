// Cross-slice pub/sub. Reserved event names today: "cwd-change",
// "tab-focus", "theme-change". Adding a new event is implicit (just
// call emit) but please document it here when you do.
//
// Subscribers receive the payload synchronously. Handlers that throw
// are logged and skipped; one bad handler never blocks the others.

(function (globalScope) {
    globalScope.bridge = globalScope.bridge || {};

    const subscribers = new Map();

    function getSet(event) {
        if (!subscribers.has(event)) subscribers.set(event, new Set());
        return subscribers.get(event);
    }

    globalScope.bridge.events = {
        on(event, handler) {
            if (typeof handler !== "function") {
                throw new TypeError("bridge.events.on: handler must be a function");
            }
            getSet(event).add(handler);
            return () => globalScope.bridge.events.off(event, handler);
        },
        off(event, handler) {
            const set = subscribers.get(event);
            if (!set) return;
            set.delete(handler);
            if (set.size === 0) subscribers.delete(event);
        },
        emit(event, payload) {
            const set = subscribers.get(event);
            if (!set || set.size === 0) return 0;
            // Snapshot before dispatch so handlers that subscribe or
            // unsubscribe during iteration don't perturb this round.
            const snapshot = [...set];
            let delivered = 0;
            for (const handler of snapshot) {
                try {
                    handler(payload);
                    delivered++;
                } catch (e) {
                    console.error(`bridge.events: handler for "${event}" threw:`, e);
                }
            }
            return delivered;
        },
        listenerCount(event) {
            const set = subscribers.get(event);
            return set ? set.size : 0;
        }
    };

    if (typeof module !== "undefined" && module.exports) {
        module.exports = globalScope.bridge.events;
    }
})(typeof window !== "undefined" ? window : globalThis);
