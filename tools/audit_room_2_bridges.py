"""Audit the authored-map diff against the automatic pre-migration backup."""
from __future__ import annotations

from copy import deepcopy
import hashlib
import json
from pathlib import Path

from configure_ldtk_water import all_levels
from configure_room_2_bridges import PARTS, ROOT, clear_road_bushes, connect_approaches, convert
from complete_room_2_grass_borders import convert as fringe
from widen_room_2_paths import convert as widen


def audit(project: Path) -> dict:
    manifest = json.loads((project.parent / "output/pontes/01_caminhos_altares_pontes.json").read_text(encoding="utf-8"))
    baseline = Path(manifest["backup"])
    before = json.loads(baseline.read_text(encoding="utf-8-sig"))
    current_bytes = project.read_bytes()
    after = json.loads(current_bytes.decode("utf-8-sig"))
    old_levels, new_levels = all_levels(before), all_levels(after)
    entity_moves = []
    bush_tiles_moved = 0
    for old in old_levels:
        new = next(l for l in new_levels if l["iid"] == old["iid"])
        old_header, new_header = deepcopy(old), deepcopy(new)
        old_header.pop("layerInstances")
        new_header.pop("layerInstances")
        assert old_header == new_header, "Level headers/fields changed"
        for added in new["layerInstances"]:
            if added["__identifier"] in PARTS and old["identifier"] != "Room_2_Cenario":
                assert not (added["gridTiles"] or added["entityInstances"] or added["autoLayerTiles"])
        for previous in old["layerInstances"]:
            actual = next(l for l in new["layerInstances"] if l["iid"] == previous["iid"])
            layer_name = previous["__identifier"]
            if old["identifier"] == "Room_2_Cenario" and layer_name in ("Floor_Paths", "Floor_GrassBorders", "Floor_Bridges"):
                continue
            if old["identifier"] == "Room_2" and previous["__type"] == "Entities":
                assert len(previous["entityInstances"]) == len(actual["entityInstances"])
                for entity in previous["entityInstances"]:
                    updated = next(e for e in actual["entityInstances"] if e["iid"] == entity["iid"])
                    if entity == updated:
                        continue
                    assert entity["__identifier"] in ("HordePedestal", "PedestalArena")
                    restored = deepcopy(updated)
                    for key in ("px", "__grid", "__worldX", "__worldY"):
                        restored[key] = entity[key]
                    assert restored == entity, "Unrelated encounter field changed"
                    entity_moves.append({"kind": entity["__identifier"], "before": entity["px"], "after": updated["px"]})
                continue
            for key in ("gridTiles", "autoLayerTiles", "intGridCsv", "entityInstances"):
                if old["identifier"] == "Room_2_Cenario" and layer_name == "Bushes" and key == "gridTiles":
                    assert len(previous[key]) == len(actual[key])
                    for old_tile, new_tile in zip(previous[key], actual[key]):
                        if old_tile == new_tile:
                            continue
                        restored = deepcopy(new_tile)
                        restored["px"], restored["d"] = old_tile["px"], old_tile["d"]
                        assert restored == old_tile
                        assert new_tile["px"] == [old_tile["px"][0], old_tile["px"][1] + 16]
                        bush_tiles_moved += 1
                else:
                    assert previous[key] == actual[key], (old["identifier"], layer_name, key)
    assert len(entity_moves) == 4 and bush_tiles_moved == 4
    repeated = deepcopy(after)
    widen(repeated, project.parent, rebuild_borders=False)
    convert(repeated, project.parent)
    connect_approaches(repeated)
    clear_road_bushes(repeated)
    fringe(repeated, project.parent)
    assert repeated == after, "The full migration is not idempotent"
    scenery = next(l for l in new_levels if l["identifier"] == "Room_2_Cenario")
    counts = {l["__identifier"]: len(l["gridTiles"]) for l in scenery["layerInstances"]}
    report = {"result": "PASS", "baseline": str(baseline), "sha256": hashlib.sha256(current_bytes).hexdigest(),
              "moved_entities": entity_moves, "bush_stamps_moved": bush_tiles_moved // 4,
              "floor_and_other_paint_preserved": True, "all_other_levels_paint_preserved": True,
              "all_authored_entity_iids_and_encounter_settings_preserved": True, "idempotent": True,
              "tile_counts": counts}
    output = project.parent / "output/pontes/auditoria_estrutural.json"
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    return report


if __name__ == "__main__":
    print(json.dumps(audit(ROOT / "monster_booster.ldtk"), ensure_ascii=False, indent=2))
