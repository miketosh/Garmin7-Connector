using Toybox.Application;
using Toybox.Communications;
using Toybox.Cryptography;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;

class ScoutPhoneLink {
    static var instance = null;
    static var lastMessage = "--";
    static var phoneFieldVersions = null;
    static var capsListener = null;
    static const LOCAL_FIELD_VERSIONS = "caps.t=1|caps.v=1|caps.f=1|caps.r=2|ping.t=1|ping.v=1|ping.ts=1|collector.t=1|collector.v=1|collector.c=2|collector.ts=1|key.t=1|key.v=1|key.key=1|key.tx=1|key.name=2";

    static function start() {
        if (instance != null) { return; }
        instance = new ScoutPhoneLink();
        try {
            Communications.registerForPhoneAppMessages(instance.method(:onMessage));
            if (ScoutPlatform.PHONE_QUERY_AT_START) { sendCapabilities(true); }
            ScoutLog.println("PL");
            ScoutCollector.onStart();
        } catch (e) {
            ScoutLog.println("PF" + e);
        }
    }

    function onMessage(message as Communications.PhoneAppMessage) as Void {
        var data = message.data;
        var type = "?";
        var size = 0;
        if (data instanceof Lang.Dictionary) {
            size = data.size();
            var t = data["t"];
            if (t instanceof Lang.String && t.length() <= 12) { type = t; }
        }
        ScoutLog.println("PM" + type + ":" + size);
        if (!(data instanceof Lang.Dictionary)) { return; }
        var wireVersion = data["v"];
        if (!(wireVersion instanceof Lang.Number) || wireVersion != 1) { return; }
        ScoutView.noteDebug("PHONE " + type);
        lastMessage = type + " " + ScoutView.timestamp();
        if (type.equals("caps")) { onPhoneCapabilities(data); }
        if (type.equals("key")) { storeKey(data); }
        if (type.equals("collector")) { ScoutCollector.onPhoneMessage(data); }
    }

    static function sendCapabilities(requestReply) {
        if (!System.getDeviceSettings().phoneConnected || instance == null) { return; }
        if (capsListener == null) { capsListener = new ScoutPhoneCapsListener(); }
        var message = { "t" => "caps", "v" => 1, "f" => LOCAL_FIELD_VERSIONS };
        if (requestReply) { message["r"] = 1; }
        try {
            Communications.transmit(message, null, capsListener);
        } catch (e) {
            ScoutLog.println("P1send-exception");
        }
    }

    static function onPhoneCapabilities(data) {
        var version = data["v"];
        var fields = data["f"];
        if (!(version instanceof Lang.Number) || version != 1 ||
                !(fields instanceof Lang.String) || fields.length() > 512) {
            ScoutLog.println("P1format");
            return;
        }
        phoneFieldVersions = parseFieldVersions(fields);
        ScoutLog.println("P1received");
        var replyWanted = data["r"];
        if (replyWanted instanceof Lang.Number && replyWanted == 1) { sendCapabilities(false); }
        ScoutCollector.retryPending();
    }

    static function parseFieldVersions(text) {
        var versions = {};
        var rest = text;
        while (rest.length() > 0) {
            var bar = rest.find("|");
            var item = bar == null ? rest : rest.substring(0, bar);
            rest = bar == null ? "" : rest.substring(bar + 1, rest.length());
            var eq = item.find("=");
            if (eq != null && eq > 0 && eq < item.length() - 1) {
                var version = item.substring(eq + 1, item.length()).toNumber();
                if (version != null && version >= 0 && version <= 255) { versions[item.substring(0, eq)] = version; }
            }
        }
        return versions;
    }

    static function supportsPhoneField(field, version) {
        if (phoneFieldVersions == null) { return version <= 1; }
        var supported = phoneFieldVersions[field];
        return supported instanceof Lang.Number && supported >= version;
    }

    function storeKey(data) {
        var key = data["key"];
        var tx = data["tx"];
        if (!(key instanceof Lang.String) || !isHex32(key)) {
            ScoutLog.println("PJformat");
            ScoutView.noteDebug("KEY REJECTED");
            noteKey("rejected");
            return;
        }
        try {
            Application.Storage.setValue("savedAuthKeyHex", key.toUpper());
        } catch (e) {
            ScoutLog.println("PJstorage:" + e);
            noteKey("not saved");
            return;
        }
        try { Application.Storage.deleteValue(ScoutView.WRONG_NAMES_KEY); } catch (e2) { }
        ScoutView.wrongNames = null;
        var name = data["name"];
        var keyName = (name instanceof Lang.String && name.length() >= 5 && name.length() <= 8 &&
            name.substring(0, 4).toUpper().equals("DXCM")) ? name : null;
        try {
            if (keyName != null) {
                Application.Storage.setValue(KEY_NAME_KEY, keyName);
            } else {
                Application.Storage.deleteValue(KEY_NAME_KEY);
            }
        } catch (e3) { }
        cachedKeyName = null;
        ScoutLog.println("PK16:" + (keyName != null));
        ScoutView.noteDebug("KEY STORED");
        noteKey("stored");
    }

    static function noteKey(outcome) {
        var t = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var text = outcome + " " + t.month.format("%02d") + "/" + t.day.format("%02d") + " " +
            t.hour.format("%02d") + ":" + t.min.format("%02d");
        try { Application.Storage.setValue("g7PhoneKeyStatus", text); } catch (e) { }
    }

    static const KEY_NAME_KEY = "g7KeyName";
    static var cachedKeyName = null;

    static function keyName() {
        if (cachedKeyName == null) {
            var name = null;
            try { name = Application.Storage.getValue(KEY_NAME_KEY); } catch (e) { name = null; }
            cachedKeyName = (name instanceof Lang.String && ScoutView.hasSavedAuthKey()) ? name : "";
        }
        return cachedKeyName;
    }

    static var printedHex = null;
    static var cachedPrint = "?";

    static function keyPrint() {
        var hex = null;
        try { hex = Application.Storage.getValue("savedAuthKeyHex"); } catch (e) { hex = null; }
        if (hex == null) {
            try { hex = Application.Properties.getValue("savedAuthKeyHex"); } catch (e2) { hex = null; }
        }
        if (!(hex instanceof Lang.String)) { return "?"; }
        if (!hex.equals(printedHex)) {
            printedHex = hex;
            cachedPrint = "?";
            var bytes = ScoutView.parseHexBytes(hex);
            if (bytes != null && bytes.size() == 16) {
                var hash = new Cryptography.Hash({ :algorithm => Cryptography.HASH_SHA256 });
                hash.update(bytes);
                var digest = hash.digest();
                cachedPrint = (digest[0] & 0xFF).format("%02X") + (digest[1] & 0xFF).format("%02X");
            }
        }
        return cachedPrint;
    }

    static function keyStatus() {
        var text = null;
        try { text = Application.Storage.getValue("g7PhoneKeyStatus"); } catch (e) { text = null; }
        return text instanceof Lang.String ? text : "none yet";
    }

    static function isHex32(text) {
        if (text.length() != 32) { return false; }
        var chars = text.toUpper().toCharArray();
        for (var i = 0; i < chars.size(); i += 1) {
            var c = chars[i];
            if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F'))) { return false; }
        }
        return true;
    }
}

class ScoutPhoneCapsListener extends Communications.ConnectionListener {
    function initialize() { ConnectionListener.initialize(); }
    function onComplete() as Void { }
    function onError() as Void { ScoutLog.println("P1send-failed"); }
}
