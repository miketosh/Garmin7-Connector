"""The pairing math's per-tick budget must stay below each watch's watchdog.

Connect IQ SDK 9.3.0 device profiles (simulator.json watchdogCount): 240,000
VM instructions on the Forerunner 255 Music / 255S Music and on every epix
(Gen 2) / epix Pro (Gen 2); 120,000 on the Forerunner 255 / 255S. Only the
240k parts may use the 100k budget; the others keep 10k.
"""
from pathlib import Path
import unittest

TASKS = (Path(__file__).resolve().parents[1] / "source" / "KeksTasks.mc").read_text(encoding="utf-8")


class DeviceBudgetTests(unittest.TestCase):
    def test_240k_watchdog_parts_get_the_larger_budget(self):
        start = TASKS.index("static const WATCHDOG_240K_PARTS = [")
        parts = TASKS[start:TASKS.index("];", start)]
        for part in ("006-B3990-00", "006-B3991-00",
                     "006-B3943-00", "006-B3944-00",
                     "006-B4312-00", "006-B4313-00", "006-B4314-00", "006-B4542-00", "006-B4556-00"):
            self.assertIn('"' + part + '"', parts)
        for part in ("006-B3992-00", "006-B3993-00"):
            self.assertNotIn(part, parts)
        budget = TASKS[TASKS.index("static function tickBudget()"):TASKS.index("function enqueue(")]
        self.assertIn("return 100;", budget)
        self.assertIn("return 10;", budget)


if __name__ == "__main__":
    unittest.main()
