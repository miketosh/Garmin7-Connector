using Toybox.Complications;
using Toybox.Lang;








class ScoutComplication {
    static const ID = 0;


    static var published = null;

    static var publishedMeasured = 0;

    static var lastResult = "--";

    static function isSupported() {
        return Toybox has :Complications;
    }

    static function publish() {
        var now = ScoutReading.nowEpoch();
        var entry = ScoutReading.load();
        var value = ScoutReading.isCurrent(entry, now) ? entry[ScoutReading.VALUE] : -1;
        if (published != null && published == value &&
            (value < 0 || publishedMeasured == entry[ScoutReading.MEASURED])) {
            return;
        }
        if (send(value)) {
            published = value;
            publishedMeasured = value < 0 ? 0 : entry[ScoutReading.MEASURED];
        }
    }

    static function send(value) {
        if (!isSupported()) {
            lastResult = "unsupported";
            return false;
        }
        try {
            Complications.updateComplication(ID, {
                :value => value < 0 ? null : value,
                :unit => "mg/dL"
            });
        } catch (e) {
            lastResult = "error";
            return false;
        }
        lastResult = value < 0 ? "none" : "" + value;
        return true;
    }
}
