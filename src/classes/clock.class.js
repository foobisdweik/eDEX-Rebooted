class Clock {
    constructor(parentId) {
        if (!parentId) throw "Missing parameters";

        // Load settings
        this.twelveHours = (window.settings.clockHours === 12);
        this.nativeClock = (
            window.settings.experimentalNativePanels === true
            && window.settings.experimentalNativeClock === true
            && window.bridge
            && window.bridge.nativeMount
            && typeof window.bridge.nativeMount.setClockText === "function"
        );

        // Create DOM
        this.parent = document.getElementById(parentId);
        if (!this.nativeClock) {
            this.parent.innerHTML += `<div id="mod_clock" class="${(this.twelveHours) ? "mod_clock_twelve" : ""}">
                <h1 id="mod_clock_text"><span>?</span><span>?</span><span>:</span><span>?</span><span>?</span><span>:</span><span>?</span><span>?</span></h1>
            </div>`;
        }

        this.lastTime = new Date();

        this.updateClock();
        this.updater = setInterval(() => {
            this.updateClock();
        }, 1000);
    }
    updateClock() {
        let time = new Date();
        let array = [time.getHours(), time.getMinutes(), time.getSeconds()];

        // 12-hour mode translation
        if (this.twelveHours) {
            this.ampm = (array[0] >= 12) ? "PM" : "AM";
            if (array[0] > 12) array[0] = array[0] - 12;
            if (array[0] === 0) array[0] = 12;
        }

        array.forEach((e, i) => {
            if (e.toString().length !== 2) {
                array[i] = "0"+e;
            }
        });
        const plainClock = `${array[0]}:${array[1]}:${array[2]}${this.twelveHours ? " " + this.ampm : ""}`;

        if (this.nativeClock) {
            window.bridge.nativeMount.setClockText(plainClock);
            this.lastTime = time;
            return;
        }

        let clockString = `${array[0]}:${array[1]}:${array[2]}`;
        array = clockString.match(/.{1}/g);
        clockString = "";
        array.forEach(e => {
            if (e === ":") clockString += "<em>"+e+"</em>";
            else clockString += "<span>"+e+"</span>";
        });
        if (this.twelveHours) clockString += `<span>${this.ampm}</span>`;

        const textNode = document.getElementById("mod_clock_text");
        if (textNode) textNode.innerHTML = clockString;
        this.lastTime = time;
    }
}

module.exports = {
    Clock
};
