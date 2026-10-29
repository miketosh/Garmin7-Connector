using Toybox.Application;
using Toybox.Lang;
using Toybox.Time;












class ScoutReading {
    static const STORAGE_KEY = "g7LastReading";
    static const FORMAT = 1;
    static const SIZE = 6;

    static const MAX_CURRENT_AGE_S = 900;


    static const CLOCK_SKEW_S = 120;

    static const MAX_MGDL = 0x0FFE;

    static const VALUE = 1;
    static const TREND = 2;
    static const SEQUENCE = 3;
    static const MEASURED = 4;
    static const RECEIVED = 5;

    static var cached = null;
    static var cacheLoaded = false;

    static function nowEpoch() {
        return Time.now().value();
    }

    static function record(mgdl, trend, sequence, ageSeconds) {
        var now = nowEpoch();
        var entry = [FORMAT, mgdl, trend, sequence, now - ageSeconds, now];
        if (!isValid(entry, now)) { return false; }
        cached = entry;
        cacheLoaded = true;
        try {
            Application.Storage.setValue(STORAGE_KEY, entry);
        } catch (e) {
            return false;
        }
        return true;
    }

    static function clear() {
        cached = null;
        cacheLoaded = true;
        try { Application.Storage.deleteValue(STORAGE_KEY); } catch (e) { }
    }

    static function load() {
        if (!cacheLoaded) {
            var stored = null;
            try { stored = Application.Storage.getValue(STORAGE_KEY); } catch (e) { stored = null; }
            cached = isValid(stored, nowEpoch()) ? stored : null;
            cacheLoaded = true;
        }
        return cached;
    }

    static function reload() {
        cacheLoaded = false;
        return load();
    }

    static function isValid(entry, now) {
        if (!(entry instanceof Lang.Array) || entry.size() != SIZE) { return false; }
        for (var i = 0; i < SIZE; i += 1) {
            if (!(entry[i] instanceof Lang.Number)) { return false; }
        }
        if (entry[0] != FORMAT) { return false; }
        if (entry[VALUE] < 1 || entry[VALUE] > MAX_MGDL) { return false; }
        if (entry[TREND] < -1 || entry[TREND] > 1) { return false; }
        if (entry[SEQUENCE] < 0 || entry[SEQUENCE] > 0xFFFF) { return false; }
        if (entry[MEASURED] > entry[RECEIVED]) { return false; }
        return entry[MEASURED] <= now + CLOCK_SKEW_S;
    }


    static function ageSeconds(entry, now) {
        if (entry == null) { return -1; }
        var age = now - entry[MEASURED];
        return age > 0 ? age : 0;
    }

    static function isCurrent(entry, now) {
        var age = ageSeconds(entry, now);
        return age >= 0 && age <= MAX_CURRENT_AGE_S;
    }
}
