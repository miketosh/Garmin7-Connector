using Toybox.Application;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;

class ScoutCollector extends Communications.ConnectionListener {
    static const KEY = "g7Collector";
    static const LEGACY_SLOT_KEY = "g7SlotForce";
    static var mode = null;
    static var changedAt = 0;
    static var pending = false;
    static var instance = null;
    static var lastResult = "--";

    static function isMode(value) {
        return value instanceof Lang.String && (value.equals("none") || value.equals("phone") ||
            value.equals("watch02") || value.equals("watch03") || value.equals("dual"));
    }

    static function fromLegacy(value) {
        if (value.equals("both")) { return "dual"; }
        if (value.equals("phone")) { return "phone"; }
        var slot = null;
        try { slot = Application.Storage.getValue(LEGACY_SLOT_KEY); } catch (e) { slot = null; }
        return (slot instanceof Lang.String && slot.equals("02")) ? "watch02" : "watch03";
    }

    static function load() {
        var stored = null;
        try { stored = Application.Storage.getValue(KEY); } catch (e) { stored = null; }
        mode = "watch03";
        changedAt = 0;
        pending = false;
        if (stored instanceof Lang.Array && stored.size() == 3 &&
                stored[1] instanceof Lang.Number && stored[2] instanceof Lang.Boolean) {
            if (stored[0] instanceof Lang.Boolean) {
                mode = fromLegacy(stored[0] ? "watch" : "phone");
            } else if (isMode(stored[0])) {
                mode = stored[0];
            } else if (stored[0] instanceof Lang.String) {
                mode = fromLegacy(stored[0]);
            }
            changedAt = stored[1];
            pending = stored[2];
        }
    }

    static function isWatch() {
        if (mode == null) { load(); }
        return mode.equals("watch02") || mode.equals("watch03") || mode.equals("dual");
    }

    static function isBoth() {
        if (mode == null) { load(); }
        return mode.equals("dual");
    }

    static function displayType() {
        if (mode == null) { load(); }
        return mode.equals("watch02") ? 0x02 : 0x03;
    }

    static function label() {
        if (mode == null) { load(); }
        if (mode.equals("none")) { return "None"; }
        if (mode.equals("phone")) { return "Phone as App"; }
        if (mode.equals("watch02")) { return "Watch as App"; }
        if (mode.equals("watch03")) { return "Watch as Watch"; }
        return "Dual Collector";
    }

    static function nextMode() {
        if (mode == null) { load(); }
        if (mode.equals("none")) { return "phone"; }
        if (mode.equals("phone")) { return "watch02"; }
        if (mode.equals("watch02")) { return "watch03"; }
        if (mode.equals("watch03")) { return "dual"; }
        return "none";
    }

    static function toggle() {
        apply(nextMode(), Time.now().value(), "menu");
        pending = true;
        save();
        sendToPhone();
    }

    static function onPhoneMessage(data) {
        var c = data["c"];
        var ts = data["ts"];
        if (!(ts instanceof Lang.Number) || !(isMode(c) || (c instanceof Lang.String &&
                (c.equals("watch") || c.equals("both"))))) {
            ScoutLog.println("CLformat:phone:0");
            return;
        }
        var wanted = isMode(c) ? c : fromLegacy(c);
        isWatch();
        if (ts < changedAt) {
            ScoutLog.println("CL" + mode + ":phone-older:" + ts);
            pending = true;
            save();
            sendToPhone();
            return;
        }
        if (ts == changedAt && wanted.equals(mode)) { return; }
        apply(wanted, ts, "phone");
        pending = false;
        save();
    }

    static function apply(toMode, at, source) {
        var wasWatch = isWatch();
        var wasType = displayType();
        mode = toMode;
        changedAt = at;
        save();
        ScoutLog.println("CL" + mode + ":" + source + ":" + at);
        ScoutView.noteDebug("COLLECTOR " + mode);
        if (wasType != displayType()) { ScoutView.applySlotChoice("collector-" + mode); }
        if (wasWatch && !isWatch()) {
            ScoutView.stopForPhoneCollector();
        } else if (!wasWatch && isWatch()) {
            ScoutView.startScan(false, false, "collector");
        }
        WatchUi.requestUpdate();
    }

    static function save() {
        try { Application.Storage.setValue(KEY, [mode, changedAt, pending]); } catch (e) { }
    }

    static function onStart() {
        isWatch();
        if (pending || (changedAt == 0 && ScoutPlatform.PHONE_QUERY_AT_START)) { sendToPhone(); }
    }

    static function retryPending() {
        isWatch();
        if (pending) { sendToPhone(); }
    }

    static function wireValue() {
        if (ScoutPhoneLink.supportsPhoneField("collector.c", 2)) { return mode; }
        if (mode.equals("dual")) { return "both"; }
        return isWatch() ? "watch" : "phone";
    }

    static function sendToPhone() {
        if (!System.getDeviceSettings().phoneConnected) {
            lastResult = "no phone " + ScoutView.timestamp();
            return;
        }
        if (instance == null) { instance = new ScoutCollector(); }
        try {
            Communications.transmit({ "t" => "collector", "v" => 1, "c" => wireValue(), "ts" => changedAt },
                null, instance);
        } catch (e) {
            lastResult = "error " + ScoutView.timestamp();
        }
    }

    function initialize() {
        ConnectionListener.initialize();
    }

    function onComplete() as Void {
        pending = false;
        save();
        lastResult = "sent " + ScoutView.timestamp();
        ScoutLog.println("CL" + mode + ":sent:" + changedAt);
    }

    function onError() as Void {
        lastResult = "no phone " + ScoutView.timestamp();
    }
}
