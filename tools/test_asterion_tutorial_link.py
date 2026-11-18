"""The Asterion link changes a route, never the user's level paint or placements."""
from copy import deepcopy
import json
import unittest

from configure_asterion_tutorial import TARGET, convert_data
from configure_ldtk_water import ROOT, all_levels
from configure_ldtk_pedestals import convert_data as configure_pedestals
from configure_ldtk_spirit_horde import EXIT_IID
from ldtk_field_values import set_value


class AsterionLinkTests(unittest.TestCase):
    def setUp(self):
        self.data = json.loads((ROOT / "monster_booster.ldtk").read_bytes())

    def exit(self, data):
        return next(e for level in all_levels(data) for layer in level["layerInstances"]
                    for e in layer["entityInstances"] if e["iid"] == EXIT_IID)

    def test_preserves_paint_positions_conditions_and_editor_values(self):
        route = {"TargetScene": "", "TargetLevel": "Room_1", "RestartGame": True}
        for field in self.exit(self.data)["fieldInstances"]:
            if field["__identifier"] in route:
                set_value(field, route[field["__identifier"]])
        before = deepcopy(self.data)
        self.assertTrue(convert_data(self.data))
        stripped = deepcopy(self.data)
        self.exit(stripped)["fieldInstances"] = deepcopy(self.exit(before)["fieldInstances"])
        self.assertEqual(stripped, before)
        fields = {f["__identifier"]: f for f in self.exit(self.data)["fieldInstances"]}
        self.assertEqual(fields["TargetScene"]["__value"], TARGET)
        self.assertEqual(fields["TargetScene"]["realEditorValues"], [{"id": "V_String", "params": [TARGET]}])
        self.assertFalse(fields["RestartGame"]["__value"])
        self.assertEqual(fields["RequiredCondition"]["__value"], "spirit_horde_1_clear")
        self.assertFalse(convert_data(self.data))

    def test_pedestal_link_repair_keeps_scene_destination(self):
        configure_pedestals(self.data, repair_links=True)
        fields = {f["__identifier"]: f["__value"] for f in self.exit(self.data)["fieldInstances"]}
        self.assertEqual(fields["TargetScene"], TARGET)
        self.assertEqual(fields["TargetLevel"], "")
        self.assertFalse(fields["RestartGame"])


if __name__ == "__main__":
    unittest.main()
