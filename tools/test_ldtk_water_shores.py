"""Preservation and concurrent-editor safety of the optional shore migration."""
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from configure_ldtk_water import ROOT, assert_preserved, serialize_preserving_layout
from configure_ldtk_water_shores import convert_data, register


class ShoreMigrationTests(unittest.TestCase):
    def setUp(self):
        self.data = json.loads((ROOT / "monster_booster.ldtk").read_text(encoding="utf-8-sig"))
        self.data["defs"]["entities"] = [e for e in self.data["defs"]["entities"] if e["identifier"] != "WaterShoreOverride"]

    def test_preservation_layout_and_idempotence(self):
        before = deepcopy(self.data)
        original = json.dumps(before, indent="\t").encode()
        self.assertTrue(convert_data(self.data))
        assert_preserved(before, self.data)
        content = serialize_preserving_layout(original, before, self.data)
        self.assertEqual(json.loads(content), self.data)
        self.assertFalse(convert_data(self.data))
        for level in self.data["levels"]:
            self.assertEqual(level, next(old for old in before["levels"] if old["iid"] == level["iid"]))

    def test_dry_run_backup_and_editor_race(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as temporary:
            project = Path(temporary) / "fixture.ldtk"
            original = json.dumps(self.data, indent="\t").encode()
            project.write_bytes(original)
            self.assertTrue(register(project, True)["changed"])
            self.assertEqual(original, project.read_bytes())
            with patch("configure_ldtk_water_shores.editor_busy", side_effect=[False, True]):
                with self.assertRaises(RuntimeError):
                    register(project)
            self.assertEqual(original, project.read_bytes())
            with patch("configure_ldtk_water_shores.editor_busy", return_value=False):
                result = register(project)
            self.assertEqual(original, Path(result["backup"]).read_bytes())
            self.assertFalse(register(project)["changed"])

    def test_rejects_incompatible_contract_and_external_levels(self):
        convert_data(self.data)
        entity = next(e for e in self.data["defs"]["entities"] if e["identifier"] == "WaterShoreOverride")
        entity["fieldDefs"][0]["__type"] = "Int"
        with self.assertRaises(ValueError):
            convert_data(self.data)
        self.data["levels"][0]["layerInstances"] = None
        with self.assertRaises(ValueError):
            convert_data(self.data)


if __name__ == "__main__":
    unittest.main()
