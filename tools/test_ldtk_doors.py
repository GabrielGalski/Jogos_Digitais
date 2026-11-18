from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from configure_ldtk_water import ROOT, all_levels, serialize_preserving_layout
from configure_ldtk_doors import assert_preserved, convert_data, register


class DoorMigrationTests(unittest.TestCase):
    def setUp(self):
        self.data = json.loads((ROOT/"monster_booster.ldtk").read_bytes())
        self.data["defs"]["entities"] = [x for x in self.data["defs"]["entities"] if x["identifier"] != "DoorControl"]
        trigger = next(x for x in self.data["defs"]["entities"] if x["identifier"] == "GameplayTrigger")
        trigger["fieldDefs"] = []
        layer = next(x for x in all_levels(self.data)[0]["layerInstances"] if x["__identifier"] == "GameplayAreas")
        layer["entityInstances"].append({"__identifier":"GameplayTrigger","iid":"old_trigger",
            "defUid":trigger["uid"],"px":[96,112],"width":32,"height":48,"__pivot":[0,0],"fieldInstances":[]})

    def test_palette_condition_fields_and_preserved_authorship(self):
        before = deepcopy(self.data)
        self.assertTrue(convert_data(self.data))
        assert_preserved(before,self.data)
        gameplay = next(x for x in self.data["defs"]["layers"] if x["identifier"] == "Gameplay")
        self.assertEqual(next(x["identifier"] for x in gameplay["intGridValues"] if x["value"] == 3),"DoorBlock")
        door = next(x for x in self.data["defs"]["entities"] if x["identifier"] == "DoorControl")
        self.assertEqual({x["identifier"] for x in door["fieldDefs"]},{"DoorId","ConditionId","Enabled"})
        trigger = next(e for l in all_levels(self.data) for a in l["layerInstances"] for e in a["entityInstances"] if e["iid"] == "old_trigger")
        self.assertEqual((trigger["px"],trigger["width"],trigger["height"]),([96,112],32,48))
        self.assertEqual(next(x["__value"] for x in trigger["fieldInstances"] if x["__identifier"] == "ConditionId"),"")
        original = json.dumps(before,indent="\t").encode()
        self.assertEqual(json.loads(serialize_preserving_layout(original,before,self.data)),self.data)
        self.assertFalse(convert_data(self.data))

    def test_backup_race_and_idempotence(self):
        with tempfile.TemporaryDirectory(dir=ROOT/"tmp") as temporary:
            path = Path(temporary)/"doors.ldtk"
            original = json.dumps(self.data,indent="\t").encode()
            path.write_bytes(original)
            self.assertTrue(register(path,True)["changed"])
            self.assertEqual(path.read_bytes(),original)
            with patch("configure_ldtk_doors.editor_busy",side_effect=[False,True]):
                with self.assertRaises(RuntimeError):
                    register(path)
            self.assertEqual(path.read_bytes(),original)
            with patch("configure_ldtk_doors.editor_busy",return_value=False):
                result = register(path)
            self.assertEqual(Path(result["backup"]).read_bytes(),original)
            self.assertFalse(register(path)["changed"])

    def test_cleanup_preserves_controls_and_does_not_restore_encounter_block(self):
        from clean_ldtk_model import clean_data
        convert_data(self.data)
        door = next(x for x in self.data["defs"]["entities"] if x["identifier"] == "DoorControl")
        instance = {"__identifier":"DoorControl","iid":"authored_control","defUid":door["uid"],
                    "px":[64,48],"width":16,"height":64,"fieldInstances":[]}
        layer = next(x for x in all_levels(self.data)[0]["layerInstances"] if x["__identifier"] == "GameplayAreas")
        layer["entityInstances"].append(deepcopy(instance))
        clean_data(self.data)
        self.assertIn(instance,layer["entityInstances"])
        self.assertEqual(next(x["identifier"] for x in self.data["defs"]["layers"][0]["intGridValues"] if x["value"] == 3),"DoorBlock")

    def test_invalid_registration_preserves_input(self):
        self.data["levels"][0]["layerInstances"] = None
        before = deepcopy(self.data)
        with self.assertRaises(ValueError):
            convert_data(self.data)
        self.assertEqual(before,self.data)


if __name__ == "__main__":
    unittest.main()
