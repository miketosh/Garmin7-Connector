"""A sensor name passed over is picked up again by a rescan."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "source" / "ScoutApp.mc").read_text(encoding="utf-8")


def section(start, end):
    return APP[APP.index(start):APP.index(end, APP.index(start))]


class PassOverRescanTests(unittest.TestCase):
    def test_the_end_of_a_pass_over_rescans(self):
        # A Connect IQ scan reports an advertiser once unless its advertising
        # restarts; a nonstop advertiser passed over was never tried again.
        offer = section("static function offerUnboundCandidate(", "static function onPassOverEnded()")
        self.assertLess(offer.index('ScoutLog.println("DA:" + ALTERNATE_WAIT_MS);'),
                        offer.index("passOverTimer.start(ALTERNATE_WAIT_MS);"))
        ended = section("static function onPassOverEnded()", "static const SEEN_NAMES_KEY")
        self.assertIn("if (!scanning || targetScanResult != null || connectionAttempted || connectionInFlight) { return; }", ended)
        self.assertLess(ended.index("Ble.setScanState(Ble.SCAN_STATE_OFF);"),
                        ended.index('startScan(false, retryScanActive, "pass-over");'))
        self.assertIn('ScoutClock.get().schedule("passOver", delayMs, method(:onTimeout));', APP)


if __name__ == "__main__":
    unittest.main()
