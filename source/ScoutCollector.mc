using Toybox.Application;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;









class ScoutCollector extends Communications.ConnectionListener {
    static const KEY = "g7Collector";

    static var mode = null;
    static var changedAt = 0;


    static var pending = false;
    static var instance = null;

    static var lastResult = "--";

    static function load() {
        var stored = null;
        try { stored = Application.Storage.getValue(KEY); } catch (e) { stored = null; }
        mode = "watch";
        changedAt = 0;
        pending = false;
        if (stored instanceof Lang.Array && stored.size() == 3 &&
                stored[1] instanceof Lang.Number && stored[2] instanceof Lang.Boolean) {
            if (stored[0] instanceof Lang.Boolean) {
                mode = stored[0] ? "watch" : "phone";
            } else if (isMode(stored[0])) {
                mode = stored[0];
            }
            changedAt = stored[1];
            pending = stored[2];
        }
    }

    static function isMode(value) {
        return value instanceof Lang.String && (value.equals("watch") || value.equals("phone") || value.equals("both"));
    }

    static function isWatch() {
        if (mode == null) { load(); }
        return !mode.equals("phone");
    }

    static function isBoth() {
        if (mode == null) { load(); }
        return mode.equals("both");
    }

    static function label() {
        isWatch();
        return mode.equals("both") ? "Both" : (mode.equals("watch") ? "Watch" : "Phone");
    }

    static function toggle() {
        apply(isWatch() ? "phone" : "watch", Time.now().value(), "menu");
        pending = true;
        save();
        sendToPhone();
    }


    static function onPhoneMessage(data) {
        var c = data["c"];
        var ts = data["ts"];
        if (!isMode(c) || !(ts instanceof Lang.Number)) {
            ScoutLog.println("CLformat:phone:0");
            return;
        }
        isWatch();
        if (ts < changedAt) {
            ScoutLog.println("CL" + label() + ":phone-older:" + ts);
            pending = true;
            save();
            sendToPhone();
            return;
        }
        if (ts == changedAt && c.equals(mode)) { return; }
        apply(c, ts, "phone");
        pending = false;
        save();
    }

    static function apply(toMode, at, source) {
        var wasWatch = isWatch();
        var wasBoth = isBoth();
        mode = toMode;
        changedAt = at;
        save();
        ScoutLog.println("CL" + label() + ":" + source + ":" + at);
        ScoutView.noteDebug("COLLECTOR " + label());
        if (wasBoth != isBoth()) { ScoutView.applySlotChoice("collector-" + mode); }
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

    static function sendToPhone() {

        if (!System.getDeviceSettings().phoneConnected) {
            lastResult = "no phone " + ScoutView.timestamp();
            return;
        }
        if (instance == null) { instance = new ScoutCollector(); }
        try {
            Communications.transmit({ "t" => "collector", "v" => 1, "c" => mode, "ts" => changedAt },
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
        ScoutLog.println("CL" + label() + ":sent:" + changedAt);
    }

    function onError() as Void {
        lastResult = "no phone " + ScoutView.timestamp();
    }
}
