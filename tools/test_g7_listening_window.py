"""Experimental: answer inside the G7's short listening window.

Ported from garmin7-scout iteration 61 (2026-10-30). On a Forerunner 255
Music the G7 accepted a write only within ~70 ms after its own transmission;
later writes waited for its next ~3.1 s beat. These guards keep the ported
ordering: the ExtraData CCCD and START_ROUND1 go out before any logging,
rounds 1-2 are computed while scanning, and round frames are handled once.
Not yet proven on a watch.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "source" / "ScoutApp.mc").read_text(encoding="utf-8")


class SensorWindowTests(unittest.TestCase):
    def test_extra_cccd_is_requested_before_any_logging_on_connect(self):
        body = APP.split("static function markConnected(connectedDevice, source) {", 1)[1].split("\n    }", 1)[0]
        request = body.index('enableCharacteristicIndications(connectedDevice, UUID_EXTRA, "EXTRA", 0x01);')
        self.assertLess(request, body.index('ScoutLog.println("CC"'))
        self.assertLess(request, body.index("describeGatt(connectedDevice);"))
        callback = APP.split("function onConnectedStateChanged(connectedDevice, state) {", 1)[1]
        self.assertLess(callback.index("ScoutView.markConnected(connectedDevice"), callback.index('ScoutLog.println("LS"'))

    def test_cccd_write_is_requested_before_its_log(self):
        body = APP.split("static function enableCharacteristicIndications(", 1)[1].split("\n    }", 1)[0]
        self.assertLess(body.index("cccd.requestWrite([cccdValue, 0x00]b);"), body.index('ScoutLog.println("WQ"'))

    def test_start_round1_uses_prepared_rounds_and_goes_first(self):
        body = APP.split("static function beginFreshKeks(code) {", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("if (!prepReadyFor(code)) {", body)
        start = body.index('queueKeks(null, [0x0A,0x00]b, "START_ROUND1");')
        self.assertLess(body.index("keksLocal1 = prepLocal1;"), start)
        self.assertLess(start, body.index('ScoutLog.println("KB"'))
        self.assertNotIn("extractPrivateScalarPkcs8", body)
        self.assertIn('prepareFreshKeks("scan-" + reason);', APP)
        self.assertIn('"PREP_ROUND2"', APP)

    def test_round_chunks_are_not_logged_one_by_one_during_pairing(self):
        body = APP.split("function onCharacteristicChanged(characteristic, value) {", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("if (ScoutView.isFreshKeksActive() && ScoutView.UUID_EXTRA.equals(uuid)) { return; }", body)
        self.assertIn("if (ScoutView.keksRoundReceiving()) { return; }", body)
        self.assertNotIn('ScoutLog.println("K1" + freshKeksState', APP)

    def test_round3_waits_for_the_shared_key(self):
        self.assertIn("if (packet == null || (n == 3 && freshKeksSharedKey == null)) {", APP)
        finish = APP.split('} else if (action.equals("ROUND3_FINISH")) {', 1)[1].split("} else if", 1)[0]
        self.assertIn("if (keksPendingSend == 3) { sendLocalRound(3); }", finish)

    def test_no_scout_timing_instrumentation(self):
        for name in ("ScoutBleTiming", "ScoutLogUpload"):
            self.assertNotIn(name, APP)


if __name__ == "__main__":
    unittest.main()
