"""Safe borders registration and native atlas dimension checks."""
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image
from configure_ldtk_water import ROOT, serialize_preserving_layout
from configure_ldtk_borders import PIECES, SOURCE, assert_preserved, convert_data, register


class BorderMigrationTests(unittest.TestCase):
    def setUp(self):
        self.data = json.loads((ROOT / "monster_booster.ldtk").read_text(encoding="utf-8-sig"))
        self.data["defs"]["tilesets"] = [x for x in self.data["defs"]["tilesets"] if x["identifier"] != "Borders_8"]
        self.data["defs"]["layers"] = [x for x in self.data["defs"]["layers"] if x["identifier"] != "Borders"]
        for level in self.data["levels"]:
            level["layerInstances"] = [x for x in level["layerInstances"] if x["__identifier"] != "Borders"]

    def test_preservation_layout_and_idempotence(self):
        before = deepcopy(self.data)
        original = json.dumps(before, indent="\t").encode()
        self.assertTrue(convert_data(self.data))
        assert_preserved(before, self.data)
        content = serialize_preserving_layout(original, before, self.data)
        self.assertEqual(json.loads(content), self.data)
        # Old tiles/layers retain their literal serialized bytes.
        for layer in before["defs"]["layers"]:
            serialized = json.dumps(layer, indent="\t").replace("\n", "\n\t\t\t").encode()
            self.assertIn(serialized, content)
        self.assertFalse(convert_data(self.data))
        for level in self.data["levels"]:
            layer = next(x for x in level["layerInstances"] if x["__identifier"] == "Borders")
            self.assertEqual(layer["__cWid"], (level["pxWid"] + 7) // 8)
            self.assertFalse(layer["gridTiles"])

    def test_native_visible_bounds_and_complete_coverage(self):
        image = Image.open(ROOT / SOURCE).convert("RGBA")
        self.assertEqual(image.size, (128, 128))
        covered = set()
        for _, box, visible in PIECES:
            x, y, width, height = box
            crop = image.crop((x, y, x + width, y + height)).getchannel("A")
            left, top, right, bottom = crop.getbbox()
            self.assertEqual((x + left, y + top, right - left, bottom - top), visible)
            for py in range(y, y + height):
                for px in range(x, x + width):
                    if image.getpixel((px, py))[3]:
                        self.assertNotIn((px, py), covered)
                        covered.add((px, py))
        self.assertEqual(len(covered), sum(image.getchannel("A").histogram()[1:]))

    def test_dry_run_editor_race_and_backup(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as temporary:
            project = Path(temporary) / "fixture.ldtk"
            original = json.dumps(self.data, indent="\t").encode()
            project.write_bytes(original)
            self.assertTrue(register(project, True)["changed"])
            self.assertEqual(project.read_bytes(), original)
            with patch("configure_ldtk_borders.editor_busy", side_effect=[False, True]):
                with self.assertRaises(RuntimeError):
                    register(project)
            self.assertEqual(project.read_bytes(), original)
            with patch("configure_ldtk_borders.editor_busy", return_value=False):
                result = register(project)
            self.assertEqual(Path(result["backup"]).read_bytes(), original)
            self.assertFalse(register(project)["changed"])

    def test_rejects_incompatible_layer(self):
        convert_data(self.data)
        next(x for x in self.data["defs"]["layers"] if x["identifier"] == "Borders")["gridSize"] = 16
        with self.assertRaises(ValueError):
            convert_data(self.data)

    def test_cleanup_keeps_painted_borders_and_supports_older_copies(self):
        from clean_ldtk_model import clean_data
        older = deepcopy(self.data)
        clean_data(older)
        self.assertFalse(any(x["identifier"] == "Borders" for x in older["defs"]["layers"]))
        convert_data(self.data)
        layer = next(x for x in self.data["levels"][0]["layerInstances"] if x["__identifier"] == "Borders")
        layer["gridTiles"] = [{"px": [80, 88], "src": [96, 96], "f": 3, "t": 204}]
        painted = deepcopy(layer)
        source = deepcopy(next(x for x in self.data["defs"]["tilesets"] if x["identifier"] == "Borders_8"))
        clean_data(self.data)
        self.assertEqual(painted, next(x for x in self.data["levels"][0]["layerInstances"] if x["__identifier"] == "Borders"))
        self.assertEqual(source, next(x for x in self.data["defs"]["tilesets"] if x["identifier"] == "Borders_8"))


if __name__ == "__main__":
    unittest.main()
