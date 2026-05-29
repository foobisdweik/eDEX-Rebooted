class Sysinfo {
    constructor(parentId) {
        if (!parentId) throw "Missing parameters";

        // Tauri port targets aarch64-apple-darwin exclusively (per ULTRAPLAN);
        // require("os") is gone with Node. v0.2 may reintroduce platform branches.
        const os = "macOS";

        // Create DOM
        this.parent = document.getElementById(parentId);
        this._native = window.settings
            && window.settings.experimentalNativePanels === true
            && window.settings.experimentalNativeSysinfo === true
            && window.bridge
            && window.bridge.nativePanels;
        this.parent.innerHTML += `<div id="mod_sysinfo">
            <div>
                <h1>1970</h1>
                <h2>JAN 1</h2>
            </div>
            <div>
                <h1>UPTIME</h1>
                <h2>0:0:0</h2>
            </div>
            <div>
                <h1>TYPE</h1>
                <h2>${os}</h2>
            </div>
            <div>
                <h1>POWER</h1>
                <h2>00%</h2>
            </div>
        </div>`;

        if (this._native) {
            window.bridge.nativePanels.mountPanel("mod_sysinfo");
            window.bridge.nativePanels.setPanelText("mod_sysinfo", "type_value", os);
        }
        this.updateDate();
        this.updateUptime();
        this.uptimeUpdater = setInterval(() => {
            this.updateUptime();
        }, 60000);
        this.updateBattery();
        this.batteryUpdater = setInterval(() => {
            this.updateBattery();
        }, 3000);
    }
    updateDate() {
        let time = new Date();

        const year = time.getFullYear().toString();
        document.querySelector("#mod_sysinfo > div:first-child > h1").innerHTML = year;

        let month = time.getMonth();
        switch(month) {
            case 0:
                month = "JAN";
                break;
            case 1:
                month = "FEB";
                break;
            case 2:
                month = "MAR";
                break;
            case 3:
                month = "APR";
                break;
            case 4:
                month = "MAY";
                break;
            case 5:
                month = "JUN";
                break;
            case 6:
                month = "JUL";
                break;
            case 7:
                month = "AUG";
                break;
            case 8:
                month = "SEP";
                break;
            case 9:
                month = "OCT";
                break;
            case 10:
                month = "NOV";
                break;
            case 11:
                month = "DEC";
                break;
        }
        const dateSubvalue = month+" "+time.getDate();
        document.querySelector("#mod_sysinfo > div:first-child > h2").innerHTML = dateSubvalue;
        if (this._native) {
            window.bridge.nativePanels.setPanelText("mod_sysinfo", "date_value", year);
            window.bridge.nativePanels.setPanelText("mod_sysinfo", "date_subvalue", dateSubvalue);
        }

        let timeToNewDay = ((23 - time.getHours()) * 3600000) + ((59 - time.getMinutes()) * 60000);
        setTimeout(() => {
            this.updateDate();
        }, timeToNewDay);
    }
    async updateUptime() {
        // Tauri port: require("os").uptime() replaced by the si_uptime invoke
        // (window.si.uptime → snake_case-mapped by the renderer Proxy).
        let uptime = {
            raw: Math.floor(await window.si.uptime()),
            days: 0,
            hours: 0,
            minutes: 0
        };

        uptime.days = Math.floor(uptime.raw/86400);
        uptime.raw -= uptime.days*86400;
        uptime.hours = Math.floor(uptime.raw/3600);
        uptime.raw -= uptime.hours*3600;
        uptime.minutes = Math.floor(uptime.raw/60);

        if (uptime.hours.toString().length !== 2) uptime.hours = "0"+uptime.hours;
        if (uptime.minutes.toString().length !== 2) uptime.minutes = "0"+uptime.minutes;

        const uptimeText = uptime.days + "d" + uptime.hours + ":" + uptime.minutes;
        document.querySelector("#mod_sysinfo > div:nth-child(2) > h2").innerHTML = uptime.days + '<span style="opacity:0.5;">d</span>' + uptime.hours + '<span style="opacity:0.5;">:</span>' + uptime.minutes;
        if (this._native) {
            window.bridge.nativePanels.setPanelText("mod_sysinfo", "uptime_value", uptimeText);
        }
    }
    updateBattery() {
        window.si.battery().then(bat => {
            let indicator = document.querySelector("#mod_sysinfo > div:last-child > h2");
            let powerText;
            if (bat.hasBattery) {
                if (bat.isCharging) {
                    powerText = "CHARGE";
                } else if (bat.acConnected) {
                    powerText = "WIRED";
                } else {
                    powerText = bat.percent+"%";
                }
            } else {
                powerText = "ON";
            }
            indicator.innerHTML = powerText;
            if (this._native) {
                window.bridge.nativePanels.setPanelText("mod_sysinfo", "power_value", powerText);
            }
        });
    }
}

module.exports = {
    Sysinfo
};
