"""Encounter registration must preserve every authored tile and existing entity position."""
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from configure_ldtk_water import ROOT, all_levels, serialize_preserving_layout
from configure_ldtk_spirit_horde import convert_data, register, fields, ENTRY_IID, EXIT_IID


class SpiritHordeMigrationTests(unittest.TestCase):
    def setUp(self):
        self.data = json.loads((ROOT / "monster_booster.ldtk").read_bytes())
        self.data["defs"]["entities"] = [e for e in self.data["defs"]["entities"] if e["identifier"] != "SpiritHordeArea"]
        for definition in self.data["defs"]["entities"]:
            if definition["identifier"] == "Warp":
                definition["fieldDefs"] = [f for f in definition["fieldDefs"] if f["identifier"] not in ("Interact", "RequiredCondition", "RestartGame", "WhiteRing")]
        for level in all_levels(self.data):
            for layer in level["layerInstances"]:
                layer["entityInstances"] = [e for e in layer["entityInstances"] if e["__identifier"] != "SpiritHordeArea" and not (e["__identifier"] == "DoorControl" and fields(e).get("DoorId", "").startswith("spirit_"))]
                for entity in layer["entityInstances"]:
                    if entity["__identifier"] == "Warp":
                        entity["fieldInstances"] = [f for f in entity["fieldInstances"] if f["__identifier"] not in ("Interact", "RequiredCondition", "RestartGame", "WhiteRing")]

    def test_paint_geometry_links_idempotence_and_serialization(self):
        before = deepcopy(self.data)
        original = json.dumps(before,indent="\t").encode()
        self.assertTrue(convert_data(self.data))
        self.assertEqual(json.loads(serialize_preserving_layout(original,before,self.data)),self.data)
        self.assertFalse(convert_data(self.data))
        for old, new in zip(all_levels(before), all_levels(self.data), strict=True):
            for old_layer, new_layer in zip(old["layerInstances"],new["layerInstances"],strict=True):
                self.assertEqual({k:v for k,v in old_layer.items() if k != "entityInstances"}, {k:v for k,v in new_layer.items() if k != "entityInstances"})
        room = next(l for l in all_levels(self.data) if l["identifier"] == "Room_1")
        entities = {e["iid"]: e for a in room["layerInstances"] for e in a["entityInstances"]}
        self.assertTrue(fields(entities[ENTRY_IID])["IsEntrance"])
        exit_fields = fields(entities[EXIT_IID])
        self.assertTrue(exit_fields["Interact"] and exit_fields["RestartGame"] and exit_fields["WhiteRing"])
        self.assertEqual(exit_fields["TargetWarp"], "entry")
        encounter = next(e for e in entities.values() if e["__identifier"] == "SpiritHordeArea")
        self.assertEqual((encounter["px"],encounter["width"],encounter["height"]), ([464,656],368,320))
        self.assertEqual(fields(encounter)["KillTarget"],40)

    def test_safe_atomic_registration_and_backup(self):
        with tempfile.TemporaryDirectory(dir=ROOT/"tmp") as temporary:
            path = Path(temporary)/"fixture.ldtk"
            original = json.dumps(self.data,indent="\t").encode()
            path.write_bytes(original)
            self.assertTrue(register(path,True)["changed"])
            self.assertEqual(path.read_bytes(),original)
            with patch("configure_ldtk_spirit_horde.editor_busy",side_effect=[False,True]):
                with self.assertRaises(RuntimeError):
                    register(path)
            self.assertEqual(path.read_bytes(),original)
            with patch("configure_ldtk_spirit_horde.editor_busy",return_value=False):
                result = register(path)
            self.assertEqual(Path(result["backup"]).read_bytes(), original)
            self.assertFalse(register(path)["changed"])


if __name__ == "__main__":
    unittest.main()
