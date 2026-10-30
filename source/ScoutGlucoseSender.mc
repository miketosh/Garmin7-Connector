using Toybox.Communications;
using Toybox.Lang;

class ScoutGlucoseSender extends Communications.ConnectionListener {
    static var instance = null;
    static var lastSentSequence = -1;
    static var lastResult = "--";
    var sequence = -1;

    static function send(sensorName, seq, mgdl, ageSeconds, trendTenths, rawPredicted, algorithmState, displayOnly) {
        if (seq == lastSentSequence || sensorName == null || sensorName.length() == 0 || sensorName.length() > 8) { return; }
        lastSentSequence = seq;
        var now = ScoutReading.nowEpoch();
        var message = {
            "t" => "glucose",
            "v" => 1,
            "tx" => sensorName,
            "sq" => seq,
            "mg" => mgdl,
            "st" => now - ageSeconds,
            "rt" => now,
            "tr" => trendTenths,
            "rel" => true
        };
        if (ScoutPhoneLink.supportsPhoneField("glucose.alg", 2)) { message["alg"] = algorithmState; }
        if (ScoutPhoneLink.supportsPhoneField("glucose.do", 2)) { message["do"] = displayOnly; }
        if (rawPredicted != 0xFFFF && ScoutPhoneLink.supportsPhoneField("glucose.pr", 2)) {
            message["pr"] = rawPredicted & 0x0FFF;
        }
        if (instance == null) { instance = new ScoutGlucoseSender(); }
        instance.sequence = seq;
        try {
            Communications.transmit(message, null, instance);
        } catch (e) {
            lastResult = "error " + ScoutView.timestamp();
            ScoutLog.println("PG" + seq + ":exception");
        }
    }

    function initialize() {
        ConnectionListener.initialize();
    }

    function onComplete() as Void {
        lastResult = "sent " + ScoutView.timestamp();
        ScoutLog.println("PG" + sequence + ":ok");
        ScoutCollector.retryPending();
    }

    function onError() as Void {
        lastResult = "no phone " + ScoutView.timestamp();
        ScoutLog.println("PG" + sequence + ":error");
    }
}
