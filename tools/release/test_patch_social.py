#!/usr/bin/env python3
"""Проверка ассета BGSocial рядом с патчем, без настоящего экспорта и GitHub."""

import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import release


class PatchSocialTest(unittest.TestCase):
	def test_patch_publishes_new_social_and_later_patch_keeps_it(self) -> None:
		with tempfile.TemporaryDirectory() as folder, patch.object(release, "OUT", Path(folder)):
			out = Path(folder)
			base, full = out / "0.8.12", out / "0.9.1.2"
			base.mkdir()
			full.mkdir()
			(out / "current.txt").write_text(base.name, encoding="utf-8")
			(base / "base.pck").write_bytes(b"base")
			release.write_json(base / "base.json", {"version": base.name, "file": "base.zip"})
			release.write_json(base / "full.json", {"dir": full.name, "patch_from": "0.9.1"})
			release.write_json(full / "base.json", {"version": full.name, "file": "full.zip"})
			(full / release.SOCIAL_EXE).write_bytes(b"old BGSocial")
			release.describe_social(full, full.name)

			with patch.object(release, "godot", side_effect=self.fake_export) as godot, \
					patch.object(release, "fingerprint", return_value={}), \
					patch.object(release, "project_version", return_value="0.9.5"), \
					patch.object(release.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as gh, \
					redirect_stdout(StringIO()):
				release.cmd_patch(self.args("0.9.5", True))
				release.cmd_publish(SimpleNamespace(version="0.9.5"))
				self.assertEqual(godot.call_count, 2, "Один экспорт патча и один экспорт BGSocial")
				asset = out / "0.9.5" / release.SOCIAL_EXE
				self.assertEqual(asset.read_bytes(), b"new BGSocial")
				social = release.read_json(base / "latest.json", {})["social"]
				self.assertEqual(social, {
					"version": "0.9.5", "file": release.SOCIAL_EXE, "size": asset.stat().st_size,
					"sha256": release.sha256(asset), "url": release.url_for("0.9.5", release.SOCIAL_EXE, ""),
				})
				self.assertIn(str(asset), gh.call_args.args[0], "Публикация прикладывает заявленный BGSocial")
				self.assertEqual((out / "current.txt").read_text(encoding="utf-8"), "0.8.12")

				release.cmd_patch(self.args("0.9.6", False))
				release.cmd_publish(SimpleNamespace(version="0.9.6"))
				self.assertEqual(godot.call_count, 3, "Следующий патч не пересобирает BGSocial без флага")
				self.assertEqual(release.read_json(base / "latest.json", {})["social"], social)
				self.assertNotIn(str(asset), gh.call_args.args[0], "Прежний BGSocial остаётся в своём релизе")

	@staticmethod
	def fake_export(operation: str, preset: str, path: str, *args: str) -> None:
		if operation == "--export-release" and preset == release.SOCIAL_PRESET:
			Path(path).write_bytes(b"new BGSocial")
		elif operation == "--export-patch" and preset == release.PRESET:
			Path(path).write_bytes(b"patch")
		else:
			raise AssertionError(f"Неожиданный экспорт: {operation}, {preset}, {args}")

	@staticmethod
	def args(version: str, with_social: bool) -> SimpleNamespace:
		return SimpleNamespace(version=version, with_social=with_social, no_bump=True,
							   allow_project=False, local="", title="")


if __name__ == "__main__":
	unittest.main()
