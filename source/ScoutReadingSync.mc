using Toybox.Lang;
using Toybox.System;




class ScoutReadingSync {
    static var instance = null;

    static function get() {
        if (instance == null) { instance = new ScoutReadingSync(); }
        return instance;
    }

    function initialize() { }

    static function onAccepted(mgdl, trend, sequence, ageSeconds) {
        ScoutReading.record(mgdl, trend, sequence, ageSeconds);
        publish();
    }


    static function onCleared() {
        ScoutReading.clear();
        publish();
    }



    static function restore() {
        var entry = ScoutReading.load();
        if (entry != null && !ScoutView.glucoseHasValue) {
            var now = ScoutReading.nowEpoch();
            var current = ScoutReading.isCurrent(entry, now);
            ScoutView.glucoseValue = entry[ScoutReading.VALUE];
            ScoutView.glucoseSequence = entry[ScoutReading.SEQUENCE];
            ScoutView.glucoseAgeSeconds = ScoutReading.ageSeconds(entry, now);
            ScoutView.glucoseReceivedAtMs = System.getTimer();
            ScoutView.glucoseTrendDirection = current ? entry[ScoutReading.TREND] : 0;
            ScoutView.glucoseHasValue = true;
        }
        publish();
    }


    static function publish() {
        ScoutComplication.publish();
        var entry = ScoutReading.load();
        var now = ScoutReading.nowEpoch();
        if (ScoutReading.isCurrent(entry, now)) {
            var leftS = ScoutReading.MAX_CURRENT_AGE_S - ScoutReading.ageSeconds(entry, now) + 1;
            ScoutClock.get().schedule("readingStale", leftS * 1000, get().method(:onStale));
        } else {
            ScoutClock.get().cancel("readingStale");
        }
    }

    function onStale() as Void {
        publish();
    }
}
