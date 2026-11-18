"""Regression for the editor read/save contract: __value alone is not authoritative."""
from copy import deepcopy
import json
import unittest

from configure_ldtk_water import ROOT, all_levels
from configure_ldtk_pedestals import convert_data, _fields
from ldtk_field_values import set_value


def editor_resave(data: dict) -> None:
    # FieldInstance.fromJson loads internalValues from realEditorValues;
    # toJson recomputes __value from internalValues or the field default.
    definitions = {f["uid"]:f for e in data["defs"]["entities"] for f in e["fieldDefs"]}
    for level in all_levels(data):
        for layer in level["layerInstances"]:
            for entity in layer["entityInstances"]:
                for field in entity["fieldInstances"]:
                    definition = definitions[field["defUid"]]
                    raw = field.get("realEditorValues", [])
                    if raw and raw[0] is not None:
                        field["__value"] = raw[0]["params"][0]
                    else:
                        field["__value"] = definition["defaultOverride"]["params"][0]


class EditorFieldPersistenceTests(unittest.TestCase):
    def test_scalar_value_wrapper_types(self):
        for kind,value in (("Bool",False),("Bool",True),("String","spirit_entry"),("Int",40),("Float",0.4)):
            field = {"__type":kind}
            set_value(field,value)
            self.assertEqual(field["__value"],value)
            self.assertEqual(field["realEditorValues"],[{"id":f"V_{kind}","params":[value]}])

    def test_editor_save_preserves_repaired_room_links(self):
        data = json.loads((ROOT/"monster_booster.ldtk").read_bytes())
        room = next(l for l in all_levels(data) if l["identifier"]=="Room_1")
        areas = next(l for l in room["layerInstances"] if l["__identifier"]=="GameplayAreas")
        # Reproduce the actual broken save: missing entry control, default exit condition,
        # exported fields backed by no editor override and a manually moved pedestal.
        areas["entityInstances"] = [e for e in areas["entityInstances"] if not (e["__identifier"]=="DoorControl" and _fields(e).get("DoorId")=="spirit_entry")]
        for entity in areas["entityInstances"]:
            for field in entity["fieldInstances"]:
                field["realEditorValues"] = []
        editor_resave(data)
        self.assertTrue(next(_fields(e)["ActivateOnEnter"] for e in areas["entityInstances"] if e["__identifier"]=="SpiritHordeArea"))
        before = deepcopy(data)
        self.assertTrue(convert_data(data,repair_links=True))
        repaired = deepcopy(data)
        editor_resave(data)
        self.assertEqual(data,repaired)
        self.assertFalse(convert_data(data,repair_links=True))
        for old,new in zip(all_levels(before),all_levels(data),strict=True):
            for old_layer,new_layer in zip(old["layerInstances"],new["layerInstances"],strict=True):
                self.assertEqual({k:v for k,v in old_layer.items() if k!="entityInstances"}, {k:v for k,v in new_layer.items() if k!="entityInstances"})
                by_iid = {e["iid"]:e for e in new_layer["entityInstances"]}
                for entity in old_layer["entityInstances"]:
                    self.assertEqual(entity["px"],by_iid[entity["iid"]]["px"])


if __name__ == "__main__":
    unittest.main()
