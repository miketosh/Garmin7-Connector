"""Regression guards for KEKS write timing and its diagnostics.

Build 255 sent its round-1 packet, then ran VERIFY_ROUND1 math ticks inside
the 500 ms pre-command pause, so 0A 01 went out 1.17 s after the sensor's
packet (xDrip ~0.8 s). The math runner must hold until the command is on the air.
"""
from pathlib import Path
import unittest


SOURCE = (Path(__file__).resolve().parents[1] / "source" / "ScoutApp.mc").read_text(encoding="utf-8")
APP = SOURCE


def method(name, end_marker):
    start = SOURCE.index(name)
    return SOURCE[start:SOURCE.index(end_marker, start)]


class KeksWriteSchedulerTests(unittest.TestCase):
    def test_math_holds_through_pre_command_pause(self):
        body = method("function isSendingPayload()", "function scheduleAfterChunk()")
        self.assertIn("(command != null && awaiting != 2)", body)
        self.assertIn("awaiting == 1 || offset < packet.size()", body)

    def test_command_is_sent_on_the_last_chunk_then_logged(self):
        # Iteration 61: nothing is logged ahead of the command write.
        body = method("function scheduleAfterChunk()", "function finishTransaction()")
        command = body.index("} else if (command != null) {")
        send_at = body.index("send();", command)
        log_at = body.index('ScoutLog.println("KP" + label')
        self.assertLess(send_at, log_at)
        self.assertIn("var payloadMs = System.getTimer() - payloadStartMs;", body)

    def test_paced_rounds_keep_the_sensor_listening_then_send_the_rest(self):
        # Iteration 61: one chunk at once, CCCD reads, the rest ~0.84 s after
        # the sensor's frame (the phone's pacing, HCI 2026-10-25).
        body = method("function scheduleAfterChunk()", "function finishTransaction()")
        self.assertIn("if (pacedUntilMs >= 0 && !keepAliveBroken && System.getTimer() < pacedUntilMs) {", body)
        self.assertIn("keepAlive();", body)
        self.assertIn("static const PACE_AFTER_SENSOR_MS = 840;", APP)
        keep = method("function keepAlive()", "function onCallbackTimeout()")
        self.assertIn("cccd.requestRead();", keep)
        self.assertIn("awaiting = 4;", keep)
        self.assertIn("ScoutView.keksWriteScheduler.onKeepAliveRead(status);", APP)
        timeout = method("function onCallbackTimeout()", "function isSendingPayload()")
        self.assertLess(timeout.index("if (awaiting == 4) {"), timeout.index("keepAliveBroken = true;"))
        self.assertIn('return queueKeksPaced(packet, [0x0A,0x01]b, "ROUND1");', APP)
        self.assertIn('return queueKeksPaced(packet, [0x0A,0x02]b, "ROUND2");', APP)

    def test_writes_go_out_without_clock_pauses(self):
        # Build 271: 0A 01 left ~50 ms (the clock floor) after its last chunk
        # and the G7 acked it only on its next ~3.3 s beat. The G7 answers
        # quickly only while the link is still busy, so nothing waits on the
        # clock: a transaction starts when queued, its command follows the
        # last chunk's callback. Juggluco sleeps 40 ms, xDrip 500 ms.
        self.assertNotIn("COMMAND_DELAY_MS", SOURCE)
        start = method("function startNext()", "function noteLink()")
        self.assertIn("send();", start)
        self.assertNotIn('schedule("keksWrite", 1,', SOURCE)

    def test_lost_chunk_is_resent_once(self):
        # Build 290 after a watch restart: chunk 0 got no callback, chunks 1-7
        # followed 8 s later, and the G7 answered 0A 01 with ioError.
        timeout = method("function onCallbackTimeout()", "function isSendingPayload()")
        self.assertIn('ScoutLog.println("KX"', timeout)
        self.assertIn("offset -= chunkSize;", timeout)
        resent = timeout.index("chunkResent = true;")
        self.assertLess(resent, timeout.index("send();", resent))
        self.assertIn("chunkResent = false;", method("function onWriteComplete(status)", "function onSensorResponse()"))
        self.assertIn("static const CHUNK_RESPONSE_FAST_MS = 1000;", SOURCE)
        self.assertIn("(lastAckMs < FAST_ACK_MS ? CHUNK_RESPONSE_FAST_MS : CHUNK_RESPONSE_MS)", SOURCE)
        self.assertIn('if (source.equals("ack")) { lastAckMs = System.getTimer() - commandSentMs; }', SOURCE)

    def test_command_gap_since_last_link_exchange_is_logged(self):
        self.assertIn("ScoutView.keksWriteScheduler.noteLink();",
                      method("function onCharacteristicChanged(", "function onDescriptorWrite("))
        self.assertIn("ScoutView.keksWriteScheduler.noteLink();",
                      method("function onDescriptorWrite(", "function onCharacteristicWrite("))
        self.assertIn("noteLink();", method("function onWriteComplete(status)", "function onSensorResponse()"))
        self.assertIn("commandGapMs = commandSentMs - lastLinkMs;", SOURCE)
        self.assertIn('":" + commandGapMs', method("function completeCommand(source)", "function onCallbackTimeout()"))

    def test_abort_reports_time_since_connection(self):
        self.assertIn("connectedAtMs = System.getTimer();",
                      method("static function markConnected(", "connectionTimerPurpose"))
        self.assertIn('":" + (System.getTimer() - connectedAtMs)',
                      method("static function abortFreshKeks(reason)", "static function finishFreshKeks("))


if __name__ == "__main__":
    unittest.main()
