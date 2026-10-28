"""Независимая сверка банка с backup; без записи production и генерации анкеты."""
import collections
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("review", ROOT / "tools/st_question_review.py")
review = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(review)
OLD = (ROOT / "backups/batch28_stillion_2026-10-28/st_questions.gd").read_text(encoding="utf-8")
CURRENT = (ROOT / "games/stillion/logic/st_questions.gd").read_text(encoding="utf-8")
AUTHORIZED_DELTA = ", творожный сырок|сырок|глазированный сырок"
old_rows = review.parse(OLD)
rows = review.parse(CURRENT)
added = rows[len(old_rows):]

def normalize(text):
    return re.sub(r"[^a-zа-я0-9]+", " ", text.lower().replace("ё", "е")).strip()

class QuestionsReview(unittest.TestCase):
    def test_prefix(self):
        self.assertEqual(len(old_rows), 120)
        self.assertEqual(CURRENT.count(AUTHORIZED_DELTA), 1)
        without_import = CURRENT.replace(AUTHORIZED_DELTA, "", 1)
        self.assertEqual(review.parse(without_import)[:120], old_rows)
        old_text = review.PATTERN.search(OLD)[2]
        self.assertTrue(review.PATTERN.search(without_import)[2].startswith(old_text))

    def test_distribution(self):
        self.assertEqual(len(rows), 240)
        self.assertEqual(len(added), 120)
        old_categories = set(q["category"] for q in old_rows)
        self.assertEqual(set(q["category"] for q in added), old_categories)
        self.assertEqual(set(collections.Counter(q["category"] for q in added).values()), {12})
        self.assertEqual(set(collections.Counter(q["category"] for q in rows).values()), {24})

    def test_questions_unique(self):
        titles = [normalize(q["question"]) for q in rows]
        self.assertEqual(len(titles), len(set(titles)))

    def test_answers(self):
        for q in added:
            with self.subTest(question=q["question"]):
                names = []
                aliases = {}
                for line in q["answers"]:
                    self.assertRegex(line, r"^[csue]:")
                    for item in line[2:].split(","):
                        name = normalize(item.split("|")[0])
                        self.assertTrue(name)
                        self.assertFalse(item.rstrip().endswith("?"))
                        names.append(name)
                        for alias in item.split("|"):
                            key = normalize(alias)
                            self.assertTrue(key)
                            self.assertTrue(key not in aliases or aliases[key] == name)
                            aliases[key] = name
                self.assertGreaterEqual(len(names), 6)
                self.assertEqual(len(names), len(set(names)))

    def test_no_new_football(self):
        for q in added:
            self.assertNotIn("футбол", (q["question"] + str(q["answers"])).lower())

if __name__ == "__main__":
    summary = {"old": len(old_rows), "total": len(rows), "added": len(added),
        "added_per_category": dict(collections.Counter(q["category"] for q in added)),
        "new_base_answers": sum(len(line[2:].split(",")) for q in added for line in q["answers"]),
        "new_min_answers": min(sum(len(line[2:].split(",")) for line in q["answers"]) for q in added),
        "source_sha256": hashlib.sha256(CURRENT.encode("utf-8")).hexdigest()}
    (ROOT / "build/batch28_stillion/low-questions-structure.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    unittest.main()
