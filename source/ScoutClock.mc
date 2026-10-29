using Toybox.Lang;
using Toybox.System;
using Toybox.Timer;












class ScoutClock {
    static const MIN_DELAY_MS = 50;
    static var instance = null;

    var timer;
    var entries;

    static function get() {
        if (instance == null) { instance = new ScoutClock(); }
        return instance;
    }

    function initialize() {
        timer = new Timer.Timer();
        entries = [];
    }

    function schedule(key, delayMs, callback) {
        add(key, delayMs, callback, 1);
    }

    function scheduleBackground(key, delayMs, callback) {
        add(key, delayMs, callback, 0);
    }

    function add(key, delayMs, callback, priority) {
        removeEntry(key);
        entries.add([key, System.getTimer() + (delayMs > 0 ? delayMs : 0), callback, priority]);
        arm();
    }

    function cancel(key) {
        if (removeEntry(key)) { arm(); }
    }

    function isScheduled(key) {
        return findEntry(key) != null;
    }

    function remainingMs(key) {
        var entry = findEntry(key);
        if (entry == null) { return -1; }
        var remaining = entry[1] - System.getTimer();
        return remaining > 0 ? remaining : 0;
    }

    function findEntry(key) {
        for (var i = 0; i < entries.size(); i += 1) {
            if (entries[i][0].equals(key)) { return entries[i]; }
        }
        return null;
    }

    function removeEntry(key) {
        var entry = findEntry(key);
        if (entry == null) { return false; }
        entries.remove(entry);
        return true;
    }

    function earliest() {
        var best = null;
        for (var i = 0; i < entries.size(); i += 1) {
            if (best == null || entries[i][1] - best[1] < 0) { best = entries[i]; }
        }
        return best;
    }

    function arm() {
        timer.stop();
        var next = earliest();
        if (next == null) { return; }
        var delay = next[1] - System.getTimer();
        timer.start(method(:fire), delay > MIN_DELAY_MS ? delay : MIN_DELAY_MS, false);
    }

    function nextDue() {
        var now = System.getTimer();
        var best = null;
        for (var i = 0; i < entries.size(); i += 1) {
            var e = entries[i];
            if (e[1] - now > 0) { continue; }
            if (best == null || e[3] > best[3] || (e[3] == best[3] && e[1] - best[1] < 0)) { best = e; }
        }
        return best;
    }

    function fire() {
        var next = nextDue();
        if (next != null) {
            entries.remove(next);
            arm();
            (next[2] as Lang.Method).invoke();
            return;
        }
        arm();
    }
}
