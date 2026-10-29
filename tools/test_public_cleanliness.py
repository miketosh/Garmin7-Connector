from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "source" / "ScoutApp.mc").read_text(encoding="utf-8")
SCREENS = (ROOT / "source" / "ScoutScreens.mc").read_text(encoding="utf-8")
LOG = (ROOT / "source" / "ScoutLog.mc").read_text(encoding="utf-8")
QR = (ROOT / "source" / "KeksQrMaterial.mc").read_text(encoding="utf-8")


class PublicCleanlinessTests(unittest.TestCase):
    def test_owner_pairing_code_and_sensor_names_are_absent(self):
        self.assertIn('static const DEFAULT_PAIRING_CODE = "----";', APP)
        for marker in ("5985", "DXCMzP", "DXCMz8"):
            self.assertNotIn(marker, APP)

    def test_private_log_upload_integration_is_absent(self):
        self.assertNotIn("ScoutLogUpload", APP)
        self.assertNotIn("ScoutLogUpload", SCREENS)
        self.assertNotIn("garmin7-scout-logs", APP + SCREENS + LOG)

    def test_pairing_code_is_not_written_to_diagnostics(self):
        self.assertNotIn('noteDebug("CODE SET " + code)', APP)
        self.assertNotIn('ScoutLog.println("PC" + code', APP)

    def test_generated_qr_key_material_is_not_committed(self):
        self.assertIn("return []b;", QR)
        self.assertEqual(3, QR.count("return []b;"))
        self.assertNotIn("0x", QR)

    def test_glucose_payload_is_not_written_to_diagnostics(self):
        match = re.search(r'ScoutLog\.println\("GL"[^;]+;', APP)
        self.assertIsNotNone(match)
        self.assertNotIn("rawGlucose", match.group(0))
        self.assertNotIn("glucoseValue", match.group(0))


if __name__ == "__main__":
    unittest.main()
