"""Проверки автономной анкеты и безопасного применения решений владельца."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("review", Path(__file__).resolve().parents[1] / "tools/st_question_review.py")
review = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(review)
SOURCE = 'extends RefCounted\nconst TEXT := """\n# Еда\n? Первый вопрос\nc:Сыр\n? Второй вопрос\ns:Молоко\n# Язык\n? </script><script>alert(1)</script>\nu:Слово\n"""\n'


class ReviewTests(unittest.TestCase):
    def document(self):
        return {"schema": 1, "source_sha256": review.digest(SOURCE), "decisions": [dict(r, choice="pending", reason="") for r in review.parse(SOURCE)]}

    def test_keep_pending_preserve_source(self):
        d = self.document()
        d["decisions"][0]["choice"] = "keep"
        self.assertEqual(review.apply_decisions(SOURCE, d), (SOURCE, []))

    def test_drop_only_selected_question(self):
        d = self.document()
        d["decisions"][1].update(choice="drop", reason="Пояснение")
        result, removed = review.apply_decisions(SOURCE, d)
        self.assertEqual(len(removed), 1)
        self.assertEqual(len(review.parse(result)), 2)
        self.assertNotIn("Второй вопрос", result)
        self.assertNotIn("s:Молоко", result)
        self.assertIn("# Язык", result)

    def test_invalid_payloads(self):
        invalid = [[], None, {}, {"schema": 1, "source_sha256": "stale"}]
        for value in invalid:
            with self.subTest(value=value), self.assertRaises(ValueError):
                review.apply_decisions(SOURCE, value)
        for kind in ["duplicate", "unknown", "changed", "choice", "reason", "all"]:
            d = self.document()
            if kind == "duplicate": d["decisions"].append(d["decisions"][0])
            if kind == "unknown": d["decisions"][0]["id"] = "unknown"
            if kind == "changed": d["decisions"][0]["question"] = "Подмена"
            if kind == "choice": d["decisions"][0]["choice"] = "erase"
            if kind == "reason": d["decisions"][0]["reason"] = "x" * 4001
            if kind == "all":
                for item in d["decisions"]: item["choice"] = "drop"
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                review.apply_decisions(SOURCE, d)

    def test_generated_data_cannot_end_script(self):
        temp_root = Path(__file__).resolve().parents[1] / "build/batch28_stillion/review-tests"
        temp_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=temp_root) as folder:
            path = Path(folder) / "review.html"
            review.generate(SOURCE.replace("Первый вопрос", "Что означают <!-- и <script> ?"), path)
            html = path.read_text(encoding="utf-8")
            payload = html.split('<script id="data" type="application/json">')[1].split('</script>')[0]
            self.assertNotIn("</script>", payload)
            self.assertNotIn("<", payload)
            self.assertEqual(len(json.loads(payload)["questions"]), 3)


if __name__ == "__main__":
    unittest.main()
