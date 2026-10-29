using Toybox.Lang;
using Toybox.Test;



(:test)
class ScoutReadingTestUtil {
    static const NOW = 1800000000;

    static function entry() {
        return [ScoutReading.FORMAT, 123, 1, 4321, NOW - 60, NOW - 30];
    }
}

(:test)
function testReadingValidRecordIsAccepted(logger) {
    var e = ScoutReadingTestUtil.entry();
    return ScoutReading.isValid(e, ScoutReadingTestUtil.NOW) &&
        ScoutReading.ageSeconds(e, ScoutReadingTestUtil.NOW) == 60 &&
        ScoutReading.isCurrent(e, ScoutReadingTestUtil.NOW);
}

(:test)
function testReadingRejectsWrongShapeOrFormat(logger) {
    var now = ScoutReadingTestUtil.NOW;
    var shortEntry = [ScoutReading.FORMAT, 123, 1, 4321, now - 60];
    var otherFormat = ScoutReadingTestUtil.entry();
    otherFormat[0] = ScoutReading.FORMAT + 1;
    var textValue = ScoutReadingTestUtil.entry();
    textValue[ScoutReading.VALUE] = "123";
    return !ScoutReading.isValid(null, now) &&
        !ScoutReading.isValid("123", now) &&
        !ScoutReading.isValid(shortEntry, now) &&
        !ScoutReading.isValid(otherFormat, now) &&
        !ScoutReading.isValid(textValue, now);
}

(:test)
function testReadingRejectsOutOfRangeFields(logger) {
    var now = ScoutReadingTestUtil.NOW;
    var cases = [
        [ScoutReading.VALUE, 0], [ScoutReading.VALUE, 0x0FFF],
        [ScoutReading.TREND, 2], [ScoutReading.TREND, -2],
        [ScoutReading.SEQUENCE, -1], [ScoutReading.SEQUENCE, 0x10000],

        [ScoutReading.MEASURED, now - 10]
    ];
    for (var i = 0; i < cases.size(); i += 1) {
        var e = ScoutReadingTestUtil.entry();
        e[cases[i][0]] = cases[i][1];
        if (ScoutReading.isValid(e, now)) {
            logger.debug("accepted case " + i);
            return false;
        }
    }
    return true;
}

(:test)
function testReadingFromTheFutureIsRejected(logger) {

    var e = ScoutReadingTestUtil.entry();
    var earlier = ScoutReadingTestUtil.NOW - 60 - ScoutReading.CLOCK_SKEW_S - 1;
    var slightlyEarlier = ScoutReadingTestUtil.NOW - 60 - ScoutReading.CLOCK_SKEW_S;
    return !ScoutReading.isValid(e, earlier) &&
        ScoutReading.isValid(e, slightlyEarlier) &&
        ScoutReading.ageSeconds(e, slightlyEarlier) == 0;
}

(:test)
function testReadingStopsBeingCurrentAfterFifteenMinutes(logger) {
    var e = ScoutReadingTestUtil.entry();
    var measured = e[ScoutReading.MEASURED];
    return ScoutReading.isCurrent(e, measured + ScoutReading.MAX_CURRENT_AGE_S) &&
        !ScoutReading.isCurrent(e, measured + ScoutReading.MAX_CURRENT_AGE_S + 1) &&
        !ScoutReading.isCurrent(null, measured) &&
        ScoutReading.ageSeconds(null, measured) == -1;
}
