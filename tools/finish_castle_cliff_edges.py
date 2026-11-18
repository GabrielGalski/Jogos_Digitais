"""Finish the authored castle perimeter, preserving gameplay and recent paint.

The rim follows the actual Floor, not the ElevationArea rectangle. Water is
explicitly clipped against logical support; GroundBase is cleared below the art.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import tempfile
import uuid

from configure_ldtk_water import all_levels, editor_busy
from ldtk_field_values import set_value
from ldtk_editor_coordinates import synchronize_level
from split_ldtk_room2 import REFERENCE, reference_bytes

ROOT = Path(__file__).resolve().parents[1]
RIM = "TerrainCliffRim"
LEFT = -160
GRID = 16


def layer(level: dict, name: str) -> dict:
    return next(item for item in level["layerInstances"] if item["__identifier"] == name)


def fields(entity: dict) -> dict:
    return {field["__identifier"]: field.get("__value") for field in entity["fieldInstances"]}


def tile(instance: dict, world_x: int, world_y: int, tile_id: int, flip: int = 0) -> dict:
    x = world_x - instance["pxOffsetX"]
    y = world_y - instance["pxOffsetY"]
    if x % GRID or y % GRID:
        raise ValueError("Cliff stamp is off its authored grid.")
    return {"px": [x, y], "src": [tile_id % 3 * GRID, tile_id // 3 * GRID],
            "f": flip, "t": tile_id, "d": [y // GRID * instance["__cWid"] + x // GRID], "a": 1}


def finish_shore_steps(data: dict) -> dict:
    scenery = next(item for item in all_levels(data) if item["identifier"] == "Room_2_Cenario")
    face, rim, base = layer(scenery, "TerrainFaces"), layer(scenery, RIM), layer(scenery, "GroundBase")
    cells = {(item["px"][0] // GRID, item["px"][1] // GRID) for item in layer(scenery, "Floor")["gridTiles"]
             if item["px"][1] < 1088 and item["px"][0] < 2688}
    face_points = {(item["px"][0] + face["pxOffsetX"], item["px"][1]) for item in face["gridTiles"]}
    rim_points = {(item["px"][0] + rim["pxOffsetX"], item["px"][1]) for item in rim["gridTiles"]}
    added: list[dict] = []
    lip_added = 0
    for x, y in sorted(cells):
        if x * GRID < 2400 or (y + 1) * GRID >= 1088 or (x, y + 1) in cells:
            continue
        column = 2 if (x + 1, y) not in cells else 1
        baseline = (y + 1) * GRID
        for index, source_row in enumerate([2, 3, 3, 3, 4]):
            py = baseline - 80 + index * GRID
            if (x * GRID, py) in face_points:
                continue
            flip = (2 if column == 2 else 3) if index == 2 else 0
            stamp = tile(face, x * GRID, py + 11, source_row * 3 + column, flip)
            face["gridTiles"].append(stamp)
            face_points.add((x * GRID, py))
            added.append(stamp)
        if (x * GRID, y * GRID) not in rim_points:
            rim["gridTiles"].append(tile(rim, x * GRID, y * GRID - 56, 8 if column == 2 else 7))
            rim_points.add((x * GRID, y * GRID))
            lip_added += 1
    covered = set()
    for stamp in added:
        x = stamp["px"][0] + face["pxOffsetX"]
        y = stamp["px"][1] + face["pxOffsetY"]
        covered.update((cx, cy) for cx in range(x // GRID, (x + 15) // GRID + 1)
                       for cy in range(y // GRID, (y + 15) // GRID + 1))
    old_count = len(base["gridTiles"])
    base["gridTiles"] = [item for item in base["gridTiles"] if (item["px"][0] // GRID, item["px"][1] // GRID) not in covered]
    return {"changed": bool(added or lip_added or old_count != len(base["gridTiles"])),
            "shore_face_tiles_added": len(added), "shore_lips_added": lip_added,
            "groundbase_removed_tiles": old_count - len(base["gridTiles"]),
            "face_tiles": len(face["gridTiles"]), "rim_tiles": len(rim["gridTiles"])}


def convert(data: dict) -> dict:
    levels = all_levels(data)
    primary = next(item for item in levels if item["identifier"] == "Room_2")
    scenery = next(item for item in levels if item["identifier"] == "Room_2_Cenario")
    face = layer(scenery, "TerrainFaces")
    floor = layer(scenery, "Floor")
    base = layer(scenery, "GroundBase")
    cliff_uid = face["__tilesetDefUid"]
    entities = [entity for item in primary["layerInstances"] for entity in item["entityInstances"]]
    area = next(item for item in entities if item["__identifier"] == "ElevationArea")
    height = int(fields(area)["HeightPx"])
    if height != 56 or face["pxOffsetY"] != 11:
        raise ValueError("Re-map the perimeter before changing the current 56px castle.")
    if next((item for item in data["defs"]["layers"] if item["identifier"] == RIM), None):
        return finish_shore_steps(data)

    # Keep authored tiles at the same world positions. A negative layer offset
    # extends the left face beyond the level while local tile coordinates stay valid.
    old_offset = int(face["pxOffsetX"])
    shift = old_offset - LEFT
    for item in face["gridTiles"]:
        item["px"][0] += shift
        item["d"] = [item["px"][1] // GRID * face["__cWid"] + item["px"][0] // GRID]
    face["pxOffsetX"] = face["__pxTotalOffsetX"] = LEFT
    index = {(item["px"][0] + LEFT, item["px"][1]): item for item in face["gridTiles"]}
    extended = 0
    for y, source_id in [(1008, 7), (1024, 10), (1040, 10), (1056, 10), (1072, 13)]:
        leftmost = min(x for x, row in index if row == y)
        for x in range(LEFT, leftmost, GRID):
            face["gridTiles"].append(tile(face, x, y + 11, source_id, 3 if y == 1040 else 0))
            extended += 1
    # End caps must retain their outward silhouette when the body is mirrored.
    repaired_caps = 0
    for item in face["gridTiles"]:
        x, y = item["px"][0] + LEFT, item["px"][1]
        if y == 1040 and x == 2544:
            item.update(src=[32, 48], t=11, f=2)
            repaired_caps += 1

    definition = deepcopy(next(item for item in data["defs"]["layers"] if item["identifier"] == "TerrainFaces"))
    definition.update(identifier=RIM, uid=data["nextUid"],
                      doc="TERRENO / Contorno do topo do planalto, seguindo Floor. Apenas visual; altura -56 px, Z=-18. Nao fornece piso ou colisao.")
    data["nextUid"] += 1
    insertion = next(i for i, item in enumerate(data["defs"]["layers"]) if item["identifier"] == "TerrainFaces") + 1
    data["defs"]["layers"].insert(insertion, definition)
    rim: dict = {}
    for level in levels:
        instance = deepcopy(layer(level, "TerrainFaces"))
        instance.update(__identifier=RIM, layerDefUid=definition["uid"],
                        iid=str(uuid.uuid5(uuid.UUID(level["iid"]), "castle_cliff_rim")),
                        gridTiles=[], autoLayerTiles=[], entityInstances=[], intGridCsv=[],
                        pxOffsetX=LEFT if level is scenery else 0,
                        __pxTotalOffsetX=LEFT if level is scenery else 0,
                        pxOffsetY=-height if level is scenery else 0,
                        __pxTotalOffsetY=-height if level is scenery else 0,
                        visible=level is scenery)
        position = next(i for i, item in enumerate(level["layerInstances"]) if item["__identifier"] == "TerrainFaces") + 1
        level["layerInstances"].insert(position, instance)
        if level is scenery:
            rim = instance

    floor_cells = {(item["px"][0] // GRID, item["px"][1] // GRID) for item in floor["gridTiles"]}
    baseline = area["px"][1] + area["height"]
    upper = {(x, y) for x, y in floor_cells
             if area["px"][0] <= x * GRID < area["px"][0] + area["width"] and 112 <= y * GRID < baseline}
    # This continuation is decoration inside/outside the forest border, not new support.
    upper.update((x, y) for x in range(LEFT // GRID, 128 // GRID) for y in range(112 // GRID, baseline // GRID))
    ramps = [entity for entity in entities if entity["__identifier"] == "ElevationRamp"]
    upper = {(x, y) for x, y in upper if not any(
        ramp["px"][0] <= x * GRID + 8 < ramp["px"][0] + ramp["width"]
        and ramp["px"][1] <= y * GRID + 8 < ramp["px"][1] + ramp["height"] for ramp in ramps)}
    boundary_count = {"north": 0, "west": 0, "east": 0, "corners": 0}
    for x, y in sorted(upper, key=lambda point: (point[1], point[0])):
        north, west, east = (x, y - 1) not in upper, (x - 1, y) not in upper, (x + 1, y) not in upper
        south = (x, y + 1) not in upper
        # The original facade supplies the complete south edge and ramp endings.
        if not (north or west or east):
            continue
        if north:
            source_id = 0 if west else 2 if east else 1
            boundary_count["north"] += 1
        elif south and east:
            source_id = 8
            boundary_count["corners"] += 1
        elif west:
            source_id = 3
            boundary_count["west"] += 1
        else:
            source_id = 5
            boundary_count["east"] += 1
        rim["gridTiles"].append(tile(rim, x * GRID, y * GRID - height, source_id))

    # Clear only GroundBase paint intersecting the two decorative cliff layers.
    covered: set[tuple[int, int]] = set()
    for instance in (face, rim):
        for item in instance["gridTiles"]:
            x = item["px"][0] + instance["pxOffsetX"]
            y = item["px"][1] + instance["pxOffsetY"]
            for cy in range(y // GRID, (y + GRID - 1) // GRID + 1):
                for cx in range(x // GRID, (x + GRID - 1) // GRID + 1):
                    covered.add((cx, cy))
    old_base_count = len(base["gridTiles"])
    base["gridTiles"] = [item for item in base["gridTiles"] if (item["px"][0] // GRID, item["px"][1] // GRID) not in covered]

    water_definition = next(item for item in data["defs"]["entities"] if item["identifier"] == "WaterArea")
    field = next((item for item in water_definition["fieldDefs"] if item["identifier"] == "ClipToTerrain"), None)
    if field is None:
        field = deepcopy(next(item for item in water_definition["fieldDefs"] if item["identifier"] == "Enabled"))
        field.update(identifier="ClipToTerrain", uid=data["nextUid"], defaultOverride={"id": "V_Bool", "params": [False]},
                     doc="Recorta a agua retangular pelo piso logico. Evita vazamentos abaixo de terreno elevado; nao modifica colisao.")
        data["nextUid"] += 1
        water_definition["fieldDefs"].append(field)
    clipped = 0
    for level in levels:
        for instance in level["layerInstances"]:
            for entity in instance["entityInstances"]:
                if entity["__identifier"] != "WaterArea":
                    continue
                entry = next((item for item in entity["fieldInstances"] if item["__identifier"] == "ClipToTerrain"), None)
                if entry is None:
                    entry = {"__identifier": "ClipToTerrain", "__type": "Bool", "defUid": field["uid"], "__tile": None}
                    entity["fieldInstances"].append(entry)
                enabled = level is primary and fields(entity).get("Preset") == "River"
                set_value(entry, enabled)
                clipped += int(enabled)
    shore = finish_shore_steps(data)
    return {"changed": True, "height_px": height, "left_extent_px": LEFT,
            "face_tiles": len(face["gridTiles"]), "extended_tiles": extended,
            "cap_repairs": repaired_caps, "rim_tiles": len(rim["gridTiles"]), "rim_edges": boundary_count,
            "groundbase_removed_tiles": old_base_count - len(base["gridTiles"]),
            "terrain_clipped_water_regions": clipped, "gameplay_floor_and_entities_preserved": True,
            "shore_steps": shore}


def assert_scope(before: dict, after: dict) -> None:
    checked = deepcopy(after)
    checked["defs"], checked["nextUid"] = before["defs"], before["nextUid"]
    for prior in all_levels(before):
        current = next(level for level in all_levels(checked) if level["iid"] == prior["iid"])
        old_rim = next((item for item in prior["layerInstances"] if item["__identifier"] == RIM), None)
        if old_rim is None:
            current["layerInstances"] = [item for item in current["layerInstances"] if item["__identifier"] != RIM]
        for old_layer in prior["layerInstances"]:
            index = next(i for i, item in enumerate(current["layerInstances"]) if item["iid"] == old_layer["iid"])
            item = current["layerInstances"][index]
            if item["__identifier"] == RIM or prior["identifier"] == "Room_2_Cenario" and item["__identifier"] in ["TerrainFaces", "GroundBase"]:
                current["layerInstances"][index] = old_layer
                continue
            for entity in item["entityInstances"]:
                if entity["__identifier"] == "WaterArea":
                    old_entity = next(entry for entry in old_layer["entityInstances"] if entry["iid"] == entity["iid"])
                    old_clip = next((entry for entry in old_entity["fieldInstances"] if entry["__identifier"] == "ClipToTerrain"), None)
                    entity["fieldInstances"] = [entry for entry in entity["fieldInstances"] if entry["__identifier"] != "ClipToTerrain"]
                    if old_clip is not None:
                        entity["fieldInstances"].append(old_clip)
    # Already migrated maps have no delta and need no synthetic strip of fields.
    if before != after and checked != before:
        raise AssertionError("Change escaped cliff paint, GroundBase, water clipping or new empty rim layers.")


def apply(project: Path, dry_run: bool = False) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    after = deepcopy(before)
    report = convert(after)
    for level in all_levels(after):
        if level["identifier"] in ["Room_2", "Room_2_Cenario"]:
            synchronize_level(level)
    if before != after:
        assert_scope(before, after)
    repeated = deepcopy(after)
    convert(repeated)
    for level in all_levels(repeated):
        if level["identifier"] in ["Room_2", "Room_2_Cenario"]:
            synchronize_level(level)
    assert repeated == after, "Migration must be idempotent."
    report.update(changed=before != after, dry_run=dry_run, idempotent=True)
    if report["changed"] and not dry_run:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk aberto ou mapa modificado; nenhum arquivo sobrescrito.")
        guide = reference_bytes(after, project.parent)
        backup = project.parent / "ldtk_backups" / f"before_cliff_edges_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
        backup.write_bytes(original)
        text = json.dumps(after, ensure_ascii=False, indent=2) + "\n"
        if b"\r\n" in original:
            text = text.replace("\n", "\r\n")
        with tempfile.NamedTemporaryFile(dir=project.parent, prefix=".cliff_edges_", suffix=".tmp", mode="wb", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(text.encode("utf-8"))
        try:
            if editor_busy() or project.read_bytes() != original:
                raise RuntimeError("Mapa alterado durante a operacao; autoria preservada.")
            os.replace(temporary, project)
        finally:
            temporary.unlink(missing_ok=True)
        (project.parent / REFERENCE).write_bytes(guide)
        report["backup"] = str(backup)
    output = project.parent / "output/castle_cliffs"
    output.mkdir(exist_ok=True, parents=True)
    (output / ("edges_preview.json" if dry_run else "edges_migration.json")).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    print(json.dumps(apply(ROOT / "monster_booster.ldtk", args.dry_run), ensure_ascii=False, indent=2))
