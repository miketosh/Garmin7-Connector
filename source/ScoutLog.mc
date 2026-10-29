using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;

// Local-only diagnostics. This public build never uploads logs or sends them
// to a remote service. Review and sanitize any log before sharing it.
class ScoutLog {
    static var lastMs = -1;

    static function println(text) {
        toFile(text);
    }

    static function fileOnly(text) {
        toFile(text);
    }

    static function toFile(text) {
        var now = System.getTimer();
        if (lastMs < 0) {
            System.println("@" + now + " " + clock());
            lastMs = now;
        }
        System.println((now - lastMs) + text);
        lastMs = now;
        return now;
    }

    static function clock() {
        var t = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        return t.hour.format("%02d") + t.min.format("%02d") + t.sec.format("%02d");
    }
}
