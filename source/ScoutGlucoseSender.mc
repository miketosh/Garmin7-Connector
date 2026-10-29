using Toybox.Lang;

// Phone forwarding is intentionally disabled in the public standalone test build.
class ScoutGlucoseSender {
    static var lastResult = "disabled";
    static function send(targetName, sequence, glucoseValue, age, signedTrend, rawPredicted, algorithmState, displayOnly) {
        lastResult = "disabled";
    }
}
