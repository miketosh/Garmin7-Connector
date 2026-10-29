"""Regression checks for case-insensitive G7 identity matching and original-case storage."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "source" / "ScoutApp.mc").read_text(encoding="utf-8")


def section(start, end):
    return APP[APP.index(start):APP.index(end, APP.index(start))]


class SensorNameCaseTests(unittest.TestCase):
    def test_matching_is_case_insensitive(self):
        matching = section("static function namesMatch(", "static function loadTargetBinding(")
        self.assertIn("left.toUpper().equals(right.toUpper())", matching)
        scan = section("function onScanResults(scanResults)", "function onScanStateChange(")
        self.assertIn("name.toUpper()", scan)
        self.assertIn('normalizedName.substring(0, 4).equals("DXCM")', scan)

    def test_candidate_names_are_stored_in_original_case(self):
        offer = section("static function offerUnboundCandidate(", "static const SEEN_NAMES_KEY")
        self.assertIn("seenCandidates.add(name);", offer)
        self.assertIn('Application.Storage.setValue("g7LastTriedName", name);', offer)
        self.assertNotIn('Application.Storage.setValue("g7LastTriedName", upper);', offer)

    def test_wrong_and_seen_lists_match_without_normalizing_storage(self):
        wrong = section("static function isWrongName(", "static function markWrongName(")
        self.assertIn("nameIndexOf(wrongNameList(), candidateName)", wrong)
        mark = section("static function markWrongName()", "static function unpairAllDevices()")
        self.assertIn("list.add(targetName);", mark)
        self.assertIn("removeName(seenCandidates, targetName);", mark)

    def test_bound_advertisement_refreshes_original_spelling(self):
        bound = section("static function onBoundScanResult(", "static function markConnected(")
        self.assertIn("!namesMatch(name, targetName)", bound)
        self.assertIn("targetName = name;", bound)
        self.assertIn("TARGET_NAME_UPPER = name.toUpper();", bound)
        self.assertIn('Application.Storage.setValue("g7DeviceName", targetName)', APP)


if __name__ == "__main__":
    unittest.main()
