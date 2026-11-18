"""Prove cleanup preserves authored visuals, utilities and safe file handling."""
from collections import Counter
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from clean_ldtk_model import ROOT, ORDER, REMOVED_TILESETS, all_levels, clean_data, clean_project, serialize_layout


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.before = json.loads((ROOT / "monster_booster.ldtk").read_text(encoding="utf-8-sig"))

    def test_paint_and_placed_water_survive(self):
        after = deepcopy(self.before)
        clean_data(after)
        old_tiles = Counter()
        new_tiles = Counter()
        for previous, current in zip(all_levels(self.before), all_levels(after), strict=True):
            self.assertEqual({key: value for key, value in previous.items() if key != "layerInstances"},
                             {key: value for key, value in current.items() if key != "layerInstances"})
            for collection, level in ((old_tiles, previous), (new_tiles, current)):
                for layer in level["layerInstances"]:
                    if layer["__tilesetDefUid"] in REMOVED_TILESETS:
                        continue
                    for tile in [*layer["gridTiles"], *layer["autoLayerTiles"]]:
                        collection[(level["iid"], layer["__tilesetDefUid"], json.dumps(tile, sort_keys=True))] += 1
            old_water = [entity for layer in previous["layerInstances"] for entity in layer["entityInstances"] if entity["__identifier"] == "WaterArea"]
            water_layer = next(layer for layer in current["layerInstances"] if layer["__identifier"] == "WaterAreas")
            self.assertEqual(old_water, water_layer["entityInstances"])
        self.assertEqual(old_tiles, new_tiles)

    def test_model_order_groups_descriptions_and_idempotence(self):
        data = deepcopy(self.before)
        clean_data(data)
        self.assertEqual([layer["identifier"] for layer in data["defs"]["layers"]], ORDER)
        self.assertTrue(all(layer["doc"] for layer in data["defs"]["layers"]))
        self.assertEqual({entity["identifier"] for entity in data["defs"]["entities"]}, {entity["identifier"] for entity in self.before["defs"]["entities"]})
        self.assertFalse(any(source["uid"] in REMOVED_TILESETS for source in data["defs"]["tilesets"]))
        gameplay = data["defs"]["layers"][0]
        self.assertEqual({group["identifier"] for group in gameplay["intGridValuesGroups"]}, {"Colisao", "Travessia", "FluxoDaSala", "Perigos"})
        self.assertFalse(clean_data(data)["changed"])

    def test_collisions_and_character_start_become_gameplay_cells(self):
        data = deepcopy(self.before)
        level = all_levels(data)[0]
        gameplay = next(layer for layer in level["layerInstances"] if layer["__identifier"] == "Gameplay")
        gameplay["intGridCsv"] = [0] * (gameplay["__cWid"] * gameplay["__cHei"])
        collision = deepcopy(gameplay)
        collision.update(__identifier="Collisions", layerDefUid=210, iid="test_collisions", intGridCsv=[0] * len(gameplay["intGridCsv"]))
        collision["intGridCsv"][:3] = [1, 2, 3]
        level["layerInstances"] = [layer for layer in level["layerInstances"] if layer["__identifier"] != "Collisions"] + [collision]
        utilities = next(layer for layer in level["layerInstances"] if layer["__identifier"] in ("Entities", "GameplayAreas"))
        utilities["entityInstances"].append({"__identifier": "NoxStart", "px": [56, 8], "iid": "start_marker"})
        clean_data(data)
        self.assertEqual(gameplay["intGridCsv"][:4], [6, 3, 7, 4])
        self.assertFalse(any(layer["__identifier"] == "Collisions" for layer in level["layerInstances"]))

    def test_ambiguous_cell_overlap_is_rejected(self):
        data = deepcopy(self.before)
        level = all_levels(data)[0]
        gameplay = next(layer for layer in level["layerInstances"] if layer["__identifier"] == "Gameplay")
        gameplay["intGridCsv"] = [0] * (gameplay["__cWid"] * gameplay["__cHei"])
        gameplay["intGridCsv"][0] = 2
        collision = deepcopy(gameplay)
        collision.update(__identifier="Collisions", layerDefUid=210)
        collision["intGridCsv"][0] = 1
        level["layerInstances"] = [layer for layer in level["layerInstances"] if layer["__identifier"] != "Collisions"] + [collision]
        with self.assertRaises(ValueError):
            clean_data(data)

    def test_serializer_and_write_backup_and_busy_editor(self):
        fixture = deepcopy(self.before)
        fixture["tutorialDesc"] = "Fixture anterior a limpeza"
        original = json.dumps(fixture, ensure_ascii=False, indent="\t").encode()
        data = deepcopy(fixture)
        clean_data(data)
        self.assertEqual(json.loads(serialize_layout(original, fixture, data)), data)
        (ROOT / "tmp").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as temporary:
            project = Path(temporary) / "fixture.ldtk"
            project.write_bytes(original)
            clean_project(project, dry_run=True)
            self.assertEqual(project.read_bytes(), original)
            with patch("clean_ldtk_model.editor_busy", return_value=True):
                with self.assertRaises(RuntimeError):
                    clean_project(project)
            self.assertEqual(project.read_bytes(), original)
            with patch("clean_ldtk_model.editor_busy", return_value=False):
                report = clean_project(project)
            if report["changed"]:
                self.assertEqual(Path(report["backup"]).read_bytes(), original)
            self.assertFalse(clean_project(project)["changed"])


if __name__ == "__main__":
    unittest.main()
