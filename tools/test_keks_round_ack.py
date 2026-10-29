"""Regression guards for the G7 KEKS 0A 00 00 round acknowledgement."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "source" / "ScoutApp.mc"
SIMULATOR = ROOT / "sim" / "ScoutSimSensor.mc"


class KeksRoundAckRegressionTests(unittest.TestCase):
    def test_round_ack_is_tolerated_without_resetting_round_state(self):
        source = SOURCE.read_text(encoding="utf-8")
        start = source.index("static function handleFreshKeksAuthMessage(value)")
        end = source.index("static function requestGlucose()", start)
        method = source[start:end]

        ack_start = method.index("if (opcode == 0x0A")
        ack_end = method.index('if (freshKeksState.equals("WAIT_CERT_A_HEADER")', ack_start)
        ack_branch = method[ack_start:ack_end]
        abort_at = method.index('abortFreshKeks("auth-indication-in-wrong-state")')

        self.assertLess(ack_start, abort_at)
        for state in ("WAIT_ROUND1", "WAIT_ROUND2", "WAIT_ROUND3"):
            self.assertIn('freshKeksState.equals("' + state + '")', ack_branch)
        self.assertIn("ackStatus == 0 && ackRound == expectedRound", ack_branch)
        self.assertIn('ScoutLog.println("KR" + matched', ack_branch)
        self.assertIn("return;", ack_branch)

        for forbidden in (
            "keksRxBuffer = null",
            "keksRxCount = 0",
            "keksWatchdog.stop()",
            "abortFreshKeks(",
        ):
            self.assertNotIn(forbidden, ack_branch)

    def test_simulator_interleaves_ack_between_120_and_40_bytes(self):
        simulator = SIMULATOR.read_text(encoding="utf-8")
        start = simulator.index("function notifyRound1WithAuthAck(bytes)")
        end = simulator.index("function guardRequest()", start)
        helper = simulator[start:end]

        first_chunk = helper.index("notifyExtraRange(bytes, 0, 120);")
        ack = helper.index("notify(auth, [0x0A,0x00,0x00]b);")
        final_chunk = helper.index("notifyExtraRange(bytes, 120, bytes.size());")
        self.assertLess(first_chunk, ack)
        self.assertLess(ack, final_chunk)
        self.assertIn('log("ROUND_ACK_SENT opcode=0A status=0 phase=0 afterBytes=120");', helper)

        command_start = simulator.index("function onAuthCommand(value)")
        command_end = simulator.index("function onBondRequest()", command_start)
        command = simulator[command_start:command_end]
        self.assertIn("notifyRound1WithAuthAck(hexBytes(KeksEngineVectors.S1));", command)

    def test_abort_reports_partial_round_bytes_before_clearing(self):
        source = SOURCE.read_text(encoding="utf-8")
        start = source.index("static function abortFreshKeks(reason)")
        end = source.index("static function finishFreshKeks(source)", start)
        method = source[start:end]
        captured = method.index("var rxBytes = keksRxCount;")
        cleared = method.index("clearFreshKeksSecrets();")
        self.assertLess(captured, cleared)
        self.assertIn('":" + rxBytes', method)

    def test_auth_callback_routes_round_ack_to_fresh_keks_handler(self):
        source = SOURCE.read_text(encoding="utf-8")
        callback_start = source.index("function onCharacteristicChanged(characteristic, value)")
        callback_end = source.index("function onDescriptorWrite(descriptor, status)", callback_start)
        callback = source[callback_start:callback_end]
        self.assertIn("ScoutView.handleFreshKeksAuthMessage(value);", callback)


    def test_round1_ack_timestamp_only_records_a_matched_ack(self):
        source = SOURCE.read_text(encoding="utf-8")
        start = source.index("function handleFreshKeksAuthMessage(value)")
        end = source.index("static function requestGlucose()", start)
        method = source[start:end]

        stamp = method.index("keksRoundAckAtMs = System.getTimer();")
        matched = method.index("if (matched && freshKeksState.equals(\"WAIT_ROUND1\"))")
        ack_log = method.index('ScoutLog.println("KR" + matched')
        self.assertLess(matched, stamp)
        self.assertLess(stamp, ack_log)
        self.assertIn("value.size() == 3 && ackStatus == 0 && ackRound == expectedRound", method)
        self.assertIn("keksRoundAckAtMs = -1;", source)

    def test_round1_ack_to_write_timing_is_logged_after_write_is_issued(self):
        source = SOURCE.read_text(encoding="utf-8")
        start = source.index("function handleFreshKeksRoundPacket(frame)")
        end = source.index("static function sendLocalRound(n)", start)
        method = source[start:end]

        send = method.index("sendLocalRound(1);")
        send_queued = method.index('ScoutLog.println("ABsend-queued:1:')
        ack_queue = method.index('ScoutLog.println("ABack-queue:1:')
        parse = method.index("KeksP256.parsePacket(frame)")
        self.assertLess(send, send_queued)
        self.assertLess(send_queued, ack_queue)
        self.assertLess(ack_queue, parse)
        self.assertIn("System.getTimer() - keksRoundAckAtMs", method)

    def test_ble_auth_callback_handles_keks_before_backlight_and_ui(self):
        source = SOURCE.read_text(encoding="utf-8")
        start = source.index("function onCharacteristicChanged(characteristic, value)")
        end = source.index("function onDescriptorWrite(descriptor, status)", start)
        callback = source[start:end]

        protocol = callback.index("ScoutView.handleFreshKeksAuthMessage(value);")
        backlight = callback.index("ScoutView.lightBacklight();", protocol)
        update = callback.index("WatchUi.requestUpdate();", backlight)
        self.assertLess(protocol, backlight)
        self.assertLess(backlight, update)



if __name__ == "__main__":
    unittest.main()
