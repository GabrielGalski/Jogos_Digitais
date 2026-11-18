"""Water migration safety: preservation, repeated runs, dry-run, editor race."""
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from configure_ldtk_water import ROOT, all_levels, assert_preserved, convert_data, register, serialize_preserving_layout


class WaterMigrationTests(unittest.TestCase):
    def setUp(self):
        self.data = json.loads((ROOT / "monster_booster.ldtk").read_text(encoding="utf-8-sig"))
        water_layer_uids = {layer["uid"] for layer in self.data["defs"]["layers"] if layer["identifier"] in ("WaterAreas", "WaterBanks")}
        self.data["defs"]["entities"] = [entity for entity in self.data["defs"]["entities"] if entity["identifier"] != "WaterArea"]
        self.data["defs"]["layers"] = [layer for layer in self.data["defs"]["layers"] if layer["uid"] not in water_layer_uids]
        for level in all_levels(self.data):
            level["layerInstances"] = [layer for layer in level["layerInstances"] if layer["layerDefUid"] not in water_layer_uids]

    def test_preserves_all_authored_data_and_is_idempotent(self):
        before = deepcopy(self.data)
        self.assertTrue(convert_data(self.data))
        assert_preserved(before, self.data)
        first = deepcopy(self.data)
        self.assertFalse(convert_data(self.data))
        self.assertEqual(first, self.data)
        for level in all_levels(self.data):
            added = [layer for layer in level["layerInstances"] if layer["__identifier"] in ("WaterAreas", "WaterBanks")]
            self.assertEqual(len(added), 2)
            self.assertTrue(all(not layer["entityInstances"] and not layer["gridTiles"] for layer in added))

    def test_dry_run_and_busy_editor_never_write(self):
        (ROOT / "tmp").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as temporary:
            project = Path(temporary) / "fixture.ldtk"
            original = json.dumps(self.data).encode()
            project.write_bytes(original)
            self.assertTrue(register(project, dry_run=True)["changed"])
            self.assertEqual(original, project.read_bytes())
            with patch("configure_ldtk_water.editor_busy", return_value=True):
                with self.assertRaises(RuntimeError):
                    register(project)
            self.assertEqual(original, project.read_bytes())

    def test_external_levels_fail_before_write(self):
        self.data["levels"][0]["layerInstances"] = None
        with self.assertRaises(ValueError):
            convert_data(self.data)

    def test_write_backup_repeat_and_editor_race(self):
        (ROOT / "tmp").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as temporary:
            project = Path(temporary) / "fixture.ldtk"
            original = json.dumps(self.data, indent="\t").encode()
            project.write_bytes(original)
            with patch("configure_ldtk_water.editor_busy", side_effect=[False, True]):
                with self.assertRaises(RuntimeError):
                    register(project)
            self.assertEqual(original, project.read_bytes())
            with patch("configure_ldtk_water.editor_busy", return_value=False):
                result = register(project)
            self.assertEqual(Path(result["backup"]).read_bytes(), original)
            migrated = project.read_bytes()
            self.assertFalse(register(project)["changed"])
            self.assertEqual(migrated, project.read_bytes())

    def test_partial_registration_adds_only_missing_instances(self):
        convert_data(self.data)
        level = all_levels(self.data)[0]
        level["layerInstances"] = [layer for layer in level["layerInstances"] if layer["__identifier"] != "WaterBanks"]
        before = deepcopy(self.data)
        self.assertTrue(convert_data(self.data))
        assert_preserved(before, self.data)
        self.assertFalse(convert_data(self.data))

    def test_serialization_preserves_existing_layout(self):
        original = json.dumps(self.data, ensure_ascii=False, indent="\t").encode()
        before = deepcopy(self.data)
        convert_data(self.data)
        result = serialize_preserving_layout(original, before, self.data)
        self.assertEqual(json.loads(result), self.data)
        self.assertIn(b'\n\t"__header__": {', result)
        floor = next(layer for layer in before["levels"][0]["layerInstances"] if layer["__identifier"] == "Floor")
        original_tiles = json.dumps(floor["gridTiles"], ensure_ascii=False, indent="\t")
        # The exact existing tile-array formatting must survive insertion.
        self.assertIn(original_tiles.replace("\n", "\n\t\t\t\t\t").encode(), result)


if __name__ == "__main__":
    unittest.main()
