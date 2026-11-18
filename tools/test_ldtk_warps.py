from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from configure_ldtk_water import ROOT, all_levels, serialize_preserving_layout
from configure_ldtk_warps import assert_preserved, convert_data, register


class WarpMigrationTests(unittest.TestCase):
    def setUp(self):
        self.data = json.loads((ROOT/"monster_booster.ldtk").read_bytes())
        for key, identifier in [("entities","Warp"),("tilesets","Warp_16")]:
            self.data["defs"][key] = [x for x in self.data["defs"][key] if x["identifier"] != identifier]
        for level in all_levels(self.data):
            for layer in level["layerInstances"]:
                layer["entityInstances"] = [x for x in layer["entityInstances"] if x["__identifier"] != "Warp"]

    def test_preservation_layout_idempotence_and_spawn(self):
        before = deepcopy(self.data)
        original = json.dumps(before,indent="\t").encode()
        self.assertTrue(convert_data(self.data))
        assert_preserved(before,self.data)
        self.assertEqual(json.loads(serialize_preserving_layout(original,before,self.data)),self.data)
        self.assertFalse(convert_data(self.data))
        for level in all_levels(self.data):
            warp = next(x for l in level["layerInstances"] for x in l["entityInstances"] if x["__identifier"] == "Warp")
            gameplay = next(x for x in level["layerInstances"] if x["__identifier"] == "Gameplay")
            starts = [(i%gameplay["__cWid"]*16+8,i//gameplay["__cWid"]*16+8) for i,n in enumerate(gameplay["intGridCsv"]) if n == 4]
            self.assertEqual(warp["px"],[round(sum(x for x,y in starts)/len(starts)),round(sum(y for x,y in starts)/len(starts))+10])
            self.assertEqual((warp["width"],warp["height"]),(48,48))
            self.assertEqual(warp["__pivot"],[0.5,0.5])
            self.assertNotIn("HeightPx",[x["__identifier"] for x in warp["fieldInstances"]])

    def test_upgrade_keeps_authored_routes_positions_and_png(self):
        convert_data(self.data)
        entity = next(x for x in self.data["defs"]["entities"] if x["identifier"] == "Warp")
        tileset = next(x for x in self.data["defs"]["tilesets"] if x["identifier"] == "Warp_16")
        entity.update(height=16,pivotY=0.5)
        entity["tileRect"]["h"] = 16
        entity["fieldDefs"] = [x for x in entity["fieldDefs"] if x["identifier"] != "HeightPx"]
        legacy_height = deepcopy(entity["fieldDefs"][0])
        legacy_height.update(identifier="HeightPx",uid=self.data["nextUid"],__type="Int",type="F_Int",
                             defaultOverride={"id":"V_Int","params":[8]})
        self.data["nextUid"] += 1
        entity["fieldDefs"].append(legacy_height)
        tileset.update(pxHei=16,__cHei=1,savedSelections=[{"ids":[0,1,2,3],"mode":"Stamp"}])
        for level in all_levels(self.data):
            for layer in level["layerInstances"]:
                for warp in layer["entityInstances"]:
                    if warp["__identifier"] == "Warp":
                        warp.update(height=16,__pivot=[0.5,0.5])
                        warp["fieldInstances"] = [x for x in warp["fieldInstances"] if x["__identifier"] != "HeightPx"]
                        warp["fieldInstances"].append({"__identifier":"HeightPx","__type":"Int",
                            "defUid":legacy_height["uid"],"__value":8,"realEditorValues":[]})
                        next(x for x in warp["fieldInstances"] if x["__identifier"] == "TargetLevel")["__value"] = "CustomDestination"
        before = deepcopy(self.data)
        png_path = ROOT/"assets/tiles/floor/warp.png"
        png = png_path.read_bytes()
        self.assertTrue(convert_data(self.data))
        assert_preserved(before,self.data)
        self.assertIn("HeightPx",[x["identifier"] for x in next(x for x in before["defs"]["entities"] if x["identifier"]=="Warp")["fieldDefs"]])
        original = json.dumps(before,indent="\t").encode()
        self.assertEqual(json.loads(serialize_preserving_layout(original,before,self.data)),self.data)
        self.assertEqual(png_path.read_bytes(),png)
        for level in all_levels(self.data):
            for layer in level["layerInstances"]:
                for warp in layer["entityInstances"]:
                    if warp["__identifier"] == "Warp":
                        self.assertEqual(next(x for x in warp["fieldInstances"] if x["__identifier"] == "TargetLevel")["__value"],"CustomDestination")
                        self.assertNotIn("HeightPx",[x["__identifier"] for x in warp["fieldInstances"]])
        self.assertFalse(convert_data(self.data))

    def test_editor_race_backup_and_repeat(self):
        with tempfile.TemporaryDirectory(dir=ROOT/"tmp") as temporary:
            path = Path(temporary)/"fixture.ldtk"
            original = json.dumps(self.data,indent="\t").encode()
            path.write_bytes(original)
            self.assertTrue(register(path,True)["changed"])
            self.assertEqual(path.read_bytes(),original)
            with patch("configure_ldtk_warps.editor_busy",side_effect=[False,True]):
                with self.assertRaises(RuntimeError):
                    register(path)
            self.assertEqual(path.read_bytes(),original)
            with patch("configure_ldtk_warps.editor_busy",return_value=False):
                result = register(path)
            self.assertEqual(Path(result["backup"]).read_bytes(),original)
            self.assertFalse(register(path)["changed"])

    def test_old_cleanup_preserves_warps(self):
        from clean_ldtk_model import clean_data
        convert_data(self.data)
        previous = [deepcopy(x) for l in all_levels(self.data) for a in l["layerInstances"] for x in a["entityInstances"] if x["__identifier"] == "Warp"]
        clean_data(self.data)
        current = [x for l in all_levels(self.data) for a in l["layerInstances"] for x in a["entityInstances"] if x["__identifier"] == "Warp"]
        self.assertEqual(previous,current)


if __name__ == "__main__":
    unittest.main()
