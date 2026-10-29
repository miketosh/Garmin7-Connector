import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIRS = [ROOT / "source"]

class PublicLogCodeTableTests(unittest.TestCase):
    def test_every_literal_compact_log_code_has_a_public_mapping(self):
        table = json.loads((ROOT / "tools" / "log_codes.json").read_text(encoding="utf-8"))
        used = set()
        for source in ROOT.joinpath("source").glob("*.mc"):
            text = source.read_text(encoding="utf-8")
            used.update(re.findall(r'ScoutLog\\.(?:println|fileOnly)\\(\\s*"([A-Z][A-Z0-9])', text))
        self.assertTrue(used, "expected to find compact log calls")
        self.assertEqual(used - set(table), set(), "every literal log code must have a mapping")

    def test_table_is_public_project_scoped(self):
        table_text = (ROOT / "tools" / "log_codes.json").read_text(encoding="utf-8")
        self.assertNotIn("expectedSensor", table_text)
        self.assertNotIn("Z8", table_text)

if __name__ == "__main__":
    unittest.main()
