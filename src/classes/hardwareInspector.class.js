class HardwareInspector {
    constructor(parentId) {
        if (!parentId) throw "Missing parameters";

        // Create DOM
        this.parent = document.getElementById(parentId);
        this._native = window.settings
            && window.settings.experimentalNativePanels === true
            && window.settings.experimentalNativeHwInspector === true
            && window.bridge
            && window.bridge.nativePanels;
        this._infoSeq = 0;
        this._element = document.createElement("div");
        this._element.setAttribute("id", "mod_hardwareInspector");
        this._element.innerHTML = `<div id="mod_hardwareInspector_inner">
            <div>
                <h1>MANUFACTURER</h1>
                <h2 id="mod_hardwareInspector_manufacturer" >NONE</h2>
            </div>
            <div>
                <h1>MODEL</h1>
                <h2 id="mod_hardwareInspector_model" >NONE</h2>
            </div>
            <div>
                <h1>CHASSIS</h1>
                <h2 id="mod_hardwareInspector_chassis" >NONE</h2>
            </div>
        </div>`;

        this.parent.append(this._element);

        if (this._native) {
            window.bridge.nativePanels.mountPanel("mod_hardwareInspector");
        }
        this.updateInfo();
        this.infoUpdater = setInterval(() => {
            this.updateInfo();
        }, 20000);
    }
    updateInfo() {
        const seq = ++this._infoSeq;
        window.si.system().then(d => {
            window.si.chassis().then(e => {
                if (seq !== this._infoSeq) return;
                const manufacturer = this._trimDataString(d.manufacturer);
                const model = this._trimDataString(d.model, d.manufacturer, e.type);
                const chassis = e.type;
                document.getElementById("mod_hardwareInspector_manufacturer").innerText = manufacturer;
                document.getElementById("mod_hardwareInspector_model").innerText = model;
                document.getElementById("mod_hardwareInspector_chassis").innerText = chassis;
                if (this._native) {
                    window.bridge.nativePanels.setPanelText("mod_hardwareInspector", "manufacturer_value", manufacturer);
                    window.bridge.nativePanels.setPanelText("mod_hardwareInspector", "model_value", model);
                    window.bridge.nativePanels.setPanelText("mod_hardwareInspector", "chassis_value", chassis);
                }
            });
        });
    }
    _trimDataString(str, ...filters) {
        return String(str || "").trim().split(" ").filter(word => {
            if (typeof filters !== "object") return true;

            return !filters.includes(word);
        }).slice(0, 2).join(" ");
    }
}

module.exports = {
    HardwareInspector
};
