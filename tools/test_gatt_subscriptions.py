"""Regression guards for the CCCD value written to each G7 characteristic.

xDrip doCheckAuth2() uses setupNotification(ExtraData) and
setupIndication(Authentication); Juggluco enableNotification(3538) and
enableIndication(3535). Build 254 subscribed ExtraData with indications and
the G7 sent a single 20-byte chunk before dropping the link.
"""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "source" / "ScoutApp.mc").read_text(encoding="utf-8")
SIMULATOR = (ROOT / "sim" / "ScoutSimSensor.mc").read_text(encoding="utf-8")
CALL = re.compile(r'enableCharacteristicIndications\([^;]*?UUID_(\w+),\s*"(\w+)",\s*(0x0[12])\)', re.S)


class GattSubscriptionTests(unittest.TestCase):
    def test_cccd_value_per_channel(self):
        calls = CALL.findall(SOURCE)
        self.assertTrue(calls)
        expected = {"EXTRA": "0x01", "AUTH": "0x02", "CONTROL": "0x02"}
        for uuid_name, label, value in calls:
            self.assertEqual(uuid_name, label)
            self.assertEqual(value, expected[label], label)
        self.assertEqual({label for _, label, _ in calls}, set(expected))

    def test_simulator_stalls_extra_data_without_notifications(self):
        self.assertIn("if (descriptor.getCharacteristic() == extra) { extraCccd = value[0] & 0xFF; }", SIMULATOR)
        self.assertIn("if (characteristic == extra && extraCccd != 0x01)", SIMULATOR)


if __name__ == "__main__":
    unittest.main()
