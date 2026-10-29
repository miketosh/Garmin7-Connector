"""The committed simulator vectors must match their host-side generator."""
from pathlib import Path
import unittest

from keks_engine_vectors import OUTPUT, render


class KeksEngineVectorTests(unittest.TestCase):
    def test_committed_vectors_match_generator(self):
        committed = Path(OUTPUT).read_text(encoding="utf-8").replace("\r\n", "\n")
        self.assertEqual(render(), committed)

    def test_vectors_use_only_the_synthetic_code(self):
        text = render()
        self.assertIn('PASSWORD = "2468"', text)
        self.assertNotIn("5985", text)


if __name__ == "__main__":
    unittest.main()
