using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;













class ScoutLog {
    static const LINES = 80;
    static var ring = new [LINES];
    static var times = new [LINES];
    static var next = 0;
    static var count = 0;
    static var lastMs = -1;

    static function println(text) {
        var now = toFile(text);
        ring[next] = text;
        times[next] = now;
        next = (next + 1) % LINES;
        if (count < LINES) { count += 1; }
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

    static function unsent() {
        var n = total - sentTotal;
        return n > count ? count : n;
    }


    static function text(n) {
        if (n == 0) { return ""; }
        var first = (next - n + LINES) % LINES;
        var out = "@" + times[first] + " " + clock() + " " + System.getTimer() + "\n";
        var previous = times[first];
        for (var i = 0; i < n; i += 1) {
            var k = (first + i) % LINES;
            out += (times[k] - previous) + bits(ring[k]) + "\n";
            previous = times[k];
        }
        return out;
    }

    static function bits(line) {
        var out = "";
        var rest = line;
        while (true) {
            var t = rest.find("true");
            var f = rest.find("false");
            if (t == null && f == null) { return out + rest; }
            if (f == null || (t != null && t < f)) {
                out += rest.substring(0, t) + "1";
                rest = rest.substring(t + 4, rest.length());
            } else {
                out += rest.substring(0, f) + "0";
                rest = rest.substring(f + 5, rest.length());
            }
        }
        return out;
    }
}
