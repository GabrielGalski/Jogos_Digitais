"""Totem registration preserves paint, encounter links, controls and source art."""
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from configure_ldtk_water import ROOT, all_levels, serialize_preserving_layout
from configure_ldtk_pedestals import SOURCE, choose_center, convert_data, register


class PedestalMigrationTests(unittest.TestCase):
    def setUp(self):
        self.data = json.loads((ROOT/"monster_booster.ldtk").read_bytes())
        self.data["defs"]["entities"] = [e for e in self.data["defs"]["entities"] if e["identifier"] != "HordePedestal"]
        self.data["defs"]["tilesets"] = [t for t in self.data["defs"]["tilesets"] if t["identifier"] != "Pedestal_16"]
        for level in all_levels(self.data):
            for layer in level["layerInstances"]:
                layer["entityInstances"] = [e for e in layer["entityInstances"] if e["__identifier"] != "HordePedestal"]

    def test_model_size_links_mask_source_and_preservation(self):
        before = deepcopy(self.data)
        png = (ROOT/SOURCE).read_bytes()
        original = json.dumps(before,indent="\t").encode()
        self.assertTrue(convert_data(self.data))
        self.assertEqual(json.loads(serialize_preserving_layout(original,before,self.data)),self.data)
        self.assertEqual((ROOT/SOURCE).read_bytes(),png)
        self.assertFalse(convert_data(self.data))
        for old,new in zip(all_levels(before),all_levels(self.data),strict=True):
            for old_layer,new_layer in zip(old["layerInstances"],new["layerInstances"],strict=True):
                self.assertEqual({k:v for k,v in old_layer.items() if k!="entityInstances"}, {k:v for k,v in new_layer.items() if k!="entityInstances"})
        room = next(l for l in all_levels(self.data) if l["identifier"] == "Room_1")
        entities = [e for l in room["layerInstances"] for e in l["entityInstances"]]
        pedestal = next(e for e in entities if e["__identifier"] == "HordePedestal")
        area = next(e for e in entities if e["__identifier"] == "SpiritHordeArea")
        fields = lambda e:{f["__identifier"]:f["__value"] for f in e["fieldInstances"]}
        self.assertEqual((pedestal["width"],pedestal["height"]),(80,40))
        self.assertEqual(pedestal["px"], choose_center(room, area))
        self.assertEqual((pedestal["__tile"]["w"],pedestal["__tile"]["h"]),(128,64))
        self.assertEqual(pedestal["__pivot"],[0.5,0.5])
        self.assertEqual(fields(pedestal)["HeightPx"],0)
        self.assertEqual(fields(pedestal)["EncounterId"],fields(area)["EncounterId"])
        self.assertFalse(fields(area)["ActivateOnEnter"])
        self.assertEqual(fields(area)["KillTarget"],40)
        self.assertEqual(len([e for e in entities if e["__identifier"]=="DoorControl"]),2)

    def test_placed_pedestal_is_not_moved_on_repeat_or_cleanup(self):
        convert_data(self.data)
        room = next(l for l in all_levels(self.data) if l["identifier"] == "Room_1")
        pedestal = next(e for l in room["layerInstances"] for e in l["entityInstances"] if e["__identifier"] == "HordePedestal")
        pedestal["px"] = [736,816]
        self.assertFalse(convert_data(self.data))
        from clean_ldtk_model import clean_data
        clean_data(self.data)
        self.assertEqual(pedestal["px"],[736,816])

    def test_atomic_backup_and_busy_editor(self):
        with tempfile.TemporaryDirectory(dir=ROOT/"tmp") as temporary:
            path = Path(temporary)/"fixture.ldtk"
            original = json.dumps(self.data,indent="\t").encode()
            path.write_bytes(original)
            self.assertTrue(register(path,True)["changed"])
            self.assertEqual(path.read_bytes(),original)
            with patch("configure_ldtk_pedestals.editor_busy",side_effect=[False,True]):
                with self.assertRaises(RuntimeError):
                    register(path)
            self.assertEqual(path.read_bytes(),original)
            with patch("configure_ldtk_pedestals.editor_busy",return_value=False):
                result = register(path)
            self.assertEqual(Path(result["backup"]).read_bytes(),original)
            self.assertFalse(register(path)["changed"])


if __name__ == "__main__":
    unittest.main()
