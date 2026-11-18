"""Native editor coordinates and preservation of existing authoring during migration."""
from copy import deepcopy
import json
import unittest

from configure_elemental_ldtk import ROOT, ROOM, assert_preserved, convert
from ldtk_editor_coordinates import grid_dimensions


class ElementalLdtkTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads((ROOT / "monster_booster.ldtk").read_text(encoding="utf-8-sig"))

    def test_editor_coordinates_and_sources(self):
        sources = {item["uid"]: item for item in self.data["defs"]["tilesets"]}
        room = next(item for item in self.data["levels"] if item["identifier"] == ROOM)
        for layer in room["layerInstances"]:
            self.assertEqual((layer["__cWid"], layer["__cHei"]), grid_dimensions(room, layer))
            if layer["__type"] == "IntGrid":
                self.assertEqual(len(layer["intGridCsv"]), layer["__cWid"] * layer["__cHei"])
            for tile in layer["gridTiles"]:
                grid = layer["__gridSize"]
                x, y = tile["px"]
                self.assertEqual((x % grid, y % grid), (0, 0))
                self.assertEqual(tile["d"], [x // grid + y // grid * layer["__cWid"]])
                source = sources[layer["__tilesetDefUid"]]
                sx, sy = tile["src"]
                self.assertLessEqual(sx + grid, source["pxWid"])
                self.assertLessEqual(sy + grid, source["pxHei"])
                self.assertEqual(tile["t"], sx // grid + sy // grid * source["__cWid"])

    def test_reapply_preserves_later_painting(self):
        edited = deepcopy(self.data)
        room = next(item for item in edited["levels"] if item["identifier"] == ROOM)
        floor = next(item for item in room["layerInstances"] if item["__identifier"] == "Floor_Elemental")
        floor["gridTiles"][0]["f"] ^= 1
        before = deepcopy(edited)
        self.assertFalse(convert(edited)["changed"])
        self.assertEqual(edited, before)

    def test_first_migration_preserves_other_rooms(self):
        before = deepcopy(self.data)
        names = {"ElementalLayout", "Floor_Elemental"}
        removed = [item["uid"] for item in before["defs"]["layers"] if item["identifier"] in names]
        before["defs"]["layers"] = [item for item in before["defs"]["layers"] if item["identifier"] not in names]
        before["defs"]["tilesets"] = [item for item in before["defs"]["tilesets"] if item["identifier"] != "DungeonFloor_8"]
        before["defs"]["entities"] = [item for item in before["defs"]["entities"] if item["identifier"] != "ElementalGolemSpawn"]
        before["nextUid"] = min(removed) - 1
        for room in before["levels"]:
            room["layerInstances"] = [item for item in room["layerInstances"] if item["__identifier"] not in names]
            if room["identifier"] != ROOM: continue
            room.update(pxWid=512, pxHei=352)
            for layer in room["layerInstances"]:
                layer["gridTiles"], layer["autoLayerTiles"], layer["entityInstances"] = [], [], []
                layer["__cWid"], layer["__cHei"] = grid_dimensions(room, layer)
                layer["intGridCsv"] = [0] * (layer["__cWid"] * layer["__cHei"]) if layer["__type"] == "IntGrid" else []
        after = deepcopy(before)
        self.assertTrue(convert(after)["changed"])
        assert_preserved(before, after)


if __name__ == "__main__":
    unittest.main()
