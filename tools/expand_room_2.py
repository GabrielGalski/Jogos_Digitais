"""One-time grid-preserving enlargement of the authored, paired open world.

River reference: 240 -> 272 pixels. Extra vertical space belongs to the castle
and its approach; everything below y=1520 is translated, not stretched vertically.
Always backs up the current LDtk and validates both bridges before replacing it.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import tempfile

from configure_ldtk_water import all_levels, editor_busy
from configure_room_2 import validate
from split_ldtk_room2 import composed_layers, reference_bytes, REFERENCE
from apply_monstershift_ground import path_tile

ROOT = Path(__file__).resolve().parents[1]
OLD_SIZE = (3120, 2864)
NEW_SIZE = (3536, 3248)
PAIR = {"Room_2", "Room_2_Cenario"}


def coordinate(value: float, axis: int) -> float:
    if axis == 0:
        return value * 17 / 15
    if value <= 960:
        return value * 17 / 15
    if value < 1520:
        return 1088 + (value - 960) * 816 / 560
    return value + 384


def snap(value: float, grid: int = 16) -> int:
    return math.floor(value / grid + 0.5) * grid


def mapped(value: float, axis: int, grid: int = 16) -> int:
    return snap(coordinate(value, axis), grid)


def convert(data: dict) -> dict:
    levels = all_levels(data)
    room = next(l for l in levels if l["identifier"] == "Room_2")
    scenery = next(l for l in levels if l["identifier"] == "Room_2_Cenario")
    if (room["pxWid"], room["pxHei"]) == NEW_SIZE:
        return dict(validate(data), changed=False)
    if any((l["pxWid"], l["pxHei"]) != OLD_SIZE for l in (room, scenery)):
        raise ValueError("Unexpected authored dimensions; refusing to rescale again.")
    composed_layers(data, room)
    scenery["worldX"] = room["worldX"] + NEW_SIZE[0] + 320
    for level in (room, scenery):
        level["pxWid"], level["pxHei"] = NEW_SIZE
        if level.get("__bgPos"):
            level["__bgPos"]["cropRect"] = [0, 0, *NEW_SIZE]
            level["__bgPos"]["scale"] = [1, 1]
            level["__bgPos"]["topLeftPx"] = [0, 0]
        for layer in level["layerInstances"]:
            grid = layer["__gridSize"]
            if layer.get("__pxTotalOffsetX", 0) or layer.get("__pxTotalOffsetY", 0):
                raise ValueError("Layer offsets require manual mapping.")
            old_w, old_h = layer["__cWid"], layer["__cHei"]
            new_w, new_h = NEW_SIZE[0] // grid, NEW_SIZE[1] // grid
            layer["__cWid"], layer["__cHei"] = new_w, new_h
            edges_x = [mapped(x * grid, 0, grid) // grid for x in range(old_w + 1)]
            edges_y = [mapped(y * grid, 1, grid) // grid for y in range(old_h + 1)]
            for key in ("gridTiles", "autoLayerTiles"):
                tiles = []
                for tile in layer[key]:
                    x, y = tile["px"][0] // grid, tile["px"][1] // grid
                    for ny in range(edges_y[y], edges_y[y + 1]):
                        for nx in range(edges_x[x], edges_x[x + 1]):
                            stamp = deepcopy(tile)
                            stamp["px"] = [nx * grid, ny * grid]
                            if stamp.get("d"):
                                stamp["d"][0] = nx + ny * new_w
                            tiles.append(stamp)
                layer[key] = tiles
            values = layer.get("intGridCsv", [])
            if values:
                expanded = [0] * (new_w * new_h)
                for index, value in enumerate(values):
                    if not value:
                        continue
                    x, y = index % old_w, index // old_w
                    for ny in range(edges_y[y], edges_y[y + 1]):
                        for nx in range(edges_x[x], edges_x[x + 1]):
                            expanded[nx + ny * new_w] = value
                layer["intGridCsv"] = expanded
            for entity in layer["entityInstances"]:
                x, y = entity["px"]
                kind = entity["__identifier"]
                # Sprites keep their authored size; area entities expand with terrain.
                entity["px"] = [mapped(x, 0, 8), mapped(y, 1, 8)]
                if kind in ("WaterArea", "ElevationArea", "ElevationRamp"):
                    entity["px"] = [mapped(x, 0), mapped(y, 1)]
                    entity["width"] = mapped(x + entity["width"], 0) - entity["px"][0]
                    entity["height"] = mapped(y + entity["height"], 1) - entity["px"][1]
                elif kind == "PedestalArena":
                    # Preserve round event boundaries; lower encounter sizes stay authored.
                    if y < 1520:
                        entity["width"] = snap(entity["width"] * 17 / 15, 32)
                        entity["height"] = snap(entity["height"] * 17 / 15, 32)
                values_by_name = {f["__identifier"]: f["__value"] for f in entity["fieldInstances"]}
                if values_by_name.get("EncounterId") == "room_2_forest_west":
                    entity["px"][0] = 160
                entity["__grid"] = [v // grid for v in entity["px"]]
                entity["__worldX"] = level["worldX"] + entity["px"][0]
                entity["__worldY"] = level["worldY"] + entity["px"][1]
    layers = {l["__identifier"]: l for l in scenery["layerInstances"]}
    # Extend the existing lower-left branch to its repositioned altar on real ground.
    paths = layers["Floor_Paths"]
    painted = {tuple(t["px"]) for t in paths["gridTiles"]}
    ground = {tuple(t["px"]) for t in layers["Floor"]["gridTiles"]}
    example = paths["gridTiles"][0]
    for y in range(2944, 3008, 16):
        for x in range(128, 320, 16):
            if (x, y) not in painted and (x, y) in ground:
                tile = deepcopy(example)
                tile.update(px=[x, y], d=[x // 16 + y // 16 * paths["__cWid"]])
                paths["gridTiles"].append(tile)
    network = {tuple(t["px"]) for name in ("Floor_Paths", "Floor_Bridges", "TerrainStairs") for t in layers[name]["gridTiles"]}
    for name, layer in layers.items():
        for tile in layer["gridTiles"]:
            x, y = tile["px"]
            if name in ("Floor", "Floor_Castle"):
                sx, sy = x // 16 % 32, y // 16 % 32
                tile.update(src=[sx * 16, sy * 16], t=sy * 32 + sx, f=0)
            elif name in ("Floor_Paths", "Floor_Bridges", "TerrainStairs"):
                sx, sy, flip = path_tile((x, y), network)
                if name == "TerrainStairs" and sx == 8 and y // 16 % 2 == 0:
                    sx, sy = 1, 0
                tile.update(src=[sx * 16, sy * 16], t=sy * 16 + sx, f=flip)
    return dict(validate(data), changed=True, river_reference=[240, 272], upper_approach_extra=256,
                lower_depth_preserved=True, lower_left_altar=[160, 2976])


def apply(dry_run: bool) -> dict:
    project = ROOT / "monster_booster.ldtk"
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    after = deepcopy(before)
    report = convert(after)
    for old, new in zip(all_levels(before), all_levels(after), strict=True):
        if old["identifier"] not in PAIR:
            assert old == new, "Unrelated level modified"
    assert before["defs"] == after["defs"]
    if dry_run or not report["changed"]:
        return report
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("LDtk open or file changed; no map replaced.")
    png = reference_bytes(after, ROOT)
    backup = ROOT / "ldtk_backups" / f"before_room2_expand_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
    backup.write_bytes(original)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=ROOT, prefix=".room2_expand_", suffix=".tmp", delete=False) as stream:
        temporary = Path(stream.name)
        json.dump(after, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    try:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk opened or map changed during preparation.")
        os.replace(temporary, project)
        (ROOT / REFERENCE).write_bytes(png)
    finally:
        temporary.unlink(missing_ok=True)
    report["backup"] = str(backup)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    print(json.dumps(apply(args.dry_run), ensure_ascii=False))
