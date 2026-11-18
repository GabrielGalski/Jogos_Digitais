"""Extend the open-world sides and dress its grass/forest with existing assets.

One-time, seeded LDtk authoring. Original vegetation is retained; new tree
stamps use three editable depth layers so overlapping crowns lose no cells.
Roads, river, heights and encounters keep their original sizes and spacing.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
from copy import deepcopy
from datetime import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import random
import tempfile
import uuid

from PIL import Image

from configure_ldtk_water import all_levels, editor_busy
from complete_room_2_grass_borders import convert as invert_borders
from extend_room_2_sides import convert as extend_sides
from split_ldtk_room2 import REFERENCE, composed_layers, reference_bytes

ROOT = Path(__file__).resolve().parents[1]
GRID = 16
SEED = 30102026
TREE_LAYERS = ("Trees_Border", "Trees_Border_2", "Trees_Border_3")
DRESSED = {*TREE_LAYERS, "Bushes", "GrassAnimated", "Floor_Grass"}


def cells(layer: dict) -> set[tuple[int, int]]:
    return {tuple(t["px"]) for t in layer["gridTiles"] + layer["autoLayerTiles"]}


def grow(points: set[tuple[int, int]], count: int = 1) -> set[tuple[int, int]]:
    return {(x + dx * GRID, y + dy * GRID) for x, y in points
            for dx in range(-count, count + 1) for dy in range(-count, count + 1)}


def noise(x: float, y: float, scale: float = 160.0) -> float:
    x, y = x / scale, y / scale
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)

    def value(cx: int, cy: int) -> float:
        n = (cx * 73856093 ^ cy * 19349663 ^ SEED) & 0xffffffff
        n = ((n ^ (n >> 13)) * 1274126177) & 0xffffffff
        return (n ^ (n >> 16)) / 4294967295.0

    top = value(ix, iy) * (1 - fx) + value(ix + 1, iy) * fx
    bottom = value(ix, iy + 1) * (1 - fx) + value(ix + 1, iy + 1) * fx
    return top * (1 - fy) + bottom * fy


def origins(layer: dict, size: int) -> set[tuple[int, int, int]]:
    result = set()
    for tile in layer["gridTiles"] + layer["autoLayerTiles"]:
        sx, sy = tile["src"]
        flip = int(tile.get("f", 0))
        if flip & 1: sx = size - GRID - sx
        if flip & 2: sy = size - GRID - sy
        result.add((tile["px"][0] - sx, tile["px"][1] - sy, flip))
    return result


def rectangle(x: float, y: float, width: float, height: float) -> set[tuple[int, int]]:
    return {(cx, cy) for cy in range(math.floor(y / GRID) * GRID, math.ceil((y + height) / GRID) * GRID, GRID)
            for cx in range(math.floor(x / GRID) * GRID, math.ceil((x + width) / GRID) * GRID, GRID)}


def add_stamp(layer: dict, origin: tuple[int, int], size: int, columns: int, flip: int = 0) -> None:
    for sy in range(0, size, GRID):
        for sx in range(0, size, GRID):
            x = origin[0] + (size - GRID - sx if flip & 1 else sx)
            y = origin[1] + sy
            if not (0 <= x < layer["__cWid"] * GRID and 0 <= y < layer["__cHei"] * GRID):
                continue
            layer["gridTiles"].append({"px": [x, y], "src": [sx, sy], "f": flip,
                "t": sy // GRID * columns + sx // GRID,
                "d": [y // GRID * layer["__cWid"] + x // GRID], "a": 1})


def add_tree_layers(data: dict) -> list[int]:
    added = []
    for name in TREE_LAYERS[1:]:
        if any(d["identifier"] == name for d in data["defs"]["layers"]):
            continue
        template = next(d for d in data["defs"]["layers"] if d["identifier"] == TREE_LAYERS[0])
        definition = deepcopy(template)
        definition.update(identifier=name, uid=data["nextUid"],
            doc="CENARIO / Floresta lateral/inferior, carimbos 80x80. Plano de pintura separado para copas sobrepostas; ordem Y e tronco fisico compartilhados com Trees. Limite de 10 tiles.")
        data["nextUid"] += 1
        data["defs"]["layers"].insert(data["defs"]["layers"].index(template), definition)
        added.append(definition["uid"])
        for level in all_levels(data):
            template_layer = next(l for l in level["layerInstances"] if l["__identifier"] == TREE_LAYERS[0])
            layer = deepcopy(template_layer)
            layer.update(__identifier=name, layerDefUid=definition["uid"],
                iid=str(uuid.uuid5(uuid.UUID(level["iid"]), "dressed_forest:" + name)),
                visible=level["identifier"] == "Room_2_Cenario", gridTiles=[], autoLayerTiles=[],
                entityInstances=[], intGridCsv=[])
            level["layerInstances"].insert(level["layerInstances"].index(template_layer), layer)
    return added


def dress(data: dict) -> dict:
    room = next(l for l in all_levels(data) if l["identifier"] == "Room_2")
    scenery = next(l for l in all_levels(data) if l["identifier"] == "Room_2_Cenario")
    art = {l["__identifier"]: l for l in scenery["layerInstances"]}
    if art[TREE_LAYERS[0]]["gridTiles"]:
        return {"changed": False, "reason": "Forest already dressed; preserving subsequent painting."}
    before = deepcopy(data)
    added_definitions = add_tree_layers(data)
    art = {l["__identifier"]: l for l in scenery["layerInstances"]}
    width, height = room["pxWid"], room["pxHei"]
    roads = set().union(*(cells(art[n]) for n in ("Floor_Paths", "Floor_Bridges", "TerrainStairs")))
    floor = cells(art["Floor"])
    ground = cells(art["GroundBase"])
    entities = [e for l in room["layerInstances"] for e in l["entityInstances"]]
    structural = set()
    platforms = set()
    for entity in entities:
        x, y = entity["px"]
        if entity["__identifier"] in ("ElevationArea", "ElevationRamp"):
            structural.update(rectangle(x, y, entity["width"], entity["height"]))
        if entity["__identifier"] in ("HordePedestal", "Warp"):
            platforms.update(rectangle(x - 72, y - 72, 144, 144))
    protected = grow(roads) | platforms

    def is_band(x: float, y: float) -> bool:
        return x < 160 or x >= width - 160 or y >= height - 160

    def land_projection(x: float, y: float) -> bool:
        # Sample the bank, rather than requiring Floor under the external
        # non-walkable strip. This also keeps the river mouths open.
        py = min(height - 176, max(32, y)) // GRID * GRID
        px = min(width - 176, max(176, x)) // GRID * GRID
        return (int(px), int(py)) in floor

    existing_trees = set().union(*(origins(layer, 80) for layer in art.values()
        if str(layer.get("__tilesetRelPath") or "").endswith("/tree.png") and layer["visible"]))
    root_buckets: dict[tuple[int, int], list[tuple[float, float]]] = defaultdict(list)
    all_roots = []

    def add_root(x: float, y: float) -> None:
        all_roots.append((x, y))
        root_buckets[(int(x // 64), int(y // 64))].append((x, y))

    def near_root(x: float, y: float, radius: float) -> bool:
        bx, by = int(x // 64), int(y // 64)
        return any((x - px) ** 2 + (y - py) ** 2 < radius * radius
            for dy in (-1, 0, 1) for dx in (-1, 0, 1)
            for px, py in root_buckets[(bx + dx, by + dy)])

    for x, y, flip in existing_trees:
        add_root(x + 40, y + (10 if flip & 2 else 70))
    rng = random.Random(SEED)
    occupied_planes = [cells(art[name]) for name in TREE_LAYERS]
    new_trees = []
    for _ in range(65000):
        side = rng.randrange(3)
        if side == 0:
            x, y = rng.randrange(-1, 9) * GRID, rng.randrange(-1, (height - 64) // GRID + 1) * GRID
        elif side == 1:
            x, y = rng.randrange((width - 192) // GRID, (width - 64) // GRID + 1) * GRID, rng.randrange(-1, (height - 64) // GRID + 1) * GRID
        else:
            x, y = rng.randrange(-1, (width - 64) // GRID + 1) * GRID, rng.randrange((height - 224) // GRID, (height - 64) // GRID + 1) * GRID
        rx, ry = x + 40, y + 70
        if not is_band(rx, ry) or not land_projection(rx, ry): continue
        # Pockets along the inner forest edge receive bushes/tall grass.
        depth = min(rx, width - rx, height - ry)
        if depth > 80 and noise(rx, ry, 128) < 0.27: continue
        stamp_cells = rectangle(x, y, 80, 80) & ground
        if stamp_cells & protected or near_root(rx, ry, 56): continue
        if not all(land_projection(rx + dx, ry) for dx in (-40, 40)): continue
        plane = next((i for i, used in enumerate(occupied_planes) if not used & stamp_cells), None)
        if plane is None: continue
        flip = rng.randrange(2)
        add_stamp(art[TREE_LAYERS[plane]], (x, y), 80, 5, flip)
        occupied_planes[plane].update(stamp_cells)
        add_root(rx, ry)
        new_trees.append((x, y, flip, plane))

    existing_grass = cells(art["Floor_Grass"])
    existing_bush_origins = origins(art["Bushes"], 32)
    occupied_bushes = set().union(*(rectangle(x, y, 32, 32) for x, y, _ in existing_bush_origins))
    grass_candidates = floor - roads - structural - platforms
    grass_sources = [(32, 0), (64, 0), (80, 0), (96, 0), (32, 16), (64, 16),
                     (96, 16), (112, 16), (0, 32), (48, 32), (80, 32), (96, 32),
                     (0, 48), (32, 48), (96, 48), (112, 48)]
    new_floor_grass = 0
    for x, y in sorted(grass_candidates - existing_grass, key=lambda p: (p[1], p[0])):
        forest = is_band(x + 8, y + 8) or y >= 2304 or x > width * 0.78
        patch = noise(x + 8, y + 8, 176) * 0.7 + noise(x + 8, y + 8, 64) * 0.3
        chance = max(0.0, patch - 0.24) * (1.05 if forest else 0.53)
        if rng.random() >= chance: continue
        sx, sy = rng.choice(grass_sources)
        art["Floor_Grass"]["gridTiles"].append({"px": [x, y], "src": [sx, sy],
            "f": rng.randrange(2), "t": sy // GRID * 8 + sx // GRID,
            "d": [y // GRID * (width // GRID) + x // GRID], "a": 1})
        new_floor_grass += 1

    # Underbrush is non-blocking, but never obscures roads or platforms.
    existing_animated = cells(art["GrassAnimated"])
    new_bushes = new_animated = 0
    for x, y in sorted(ground, key=lambda p: (p[1], p[0])):
        band = is_band(x + 8, y + 8)
        land = (x, y) in floor or (band and land_projection(x + 8, y + 8))
        if not land or (x, y) in protected: continue
        if not band and (x, y) in structural: continue
        forest = band or y >= 2304 or x > width * 0.78
        patch = noise(x, y, 144) * 0.65 + noise(x, y, 48) * 0.35
        bush_chance = (0.065 if band else 0.014 if forest else 0.004) * (0.45 + patch)
        bush_cells = rectangle(x, y, 32, 32)
        bush_land = bush_cells <= floor or (band and all(land_projection(px + 8, py + 8) for px, py in bush_cells))
        if (rng.random() < bush_chance and x + 32 <= width and y + 32 <= height
                and bush_land and not bush_cells & (protected | occupied_bushes)
                and not near_root(x + 16, y + 28, 43)):
            add_stamp(art["Bushes"], (x, y), 32, 2, rng.randrange(2))
            occupied_bushes.update(bush_cells)
            new_bushes += 1
        if (x, y) in existing_animated or (x, y) in occupied_bushes: continue
        animated_chance = (0.19 if band else 0.085 if forest else 0.032) * max(0.15, (patch - 0.18) * 1.8)
        if rng.random() < animated_chance and not near_root(x + 8, y + 15, 24):
            add_stamp(art["GrassAnimated"], (x, y), 16, 1, rng.randrange(2))
            new_animated += 1

    assert cells(art["Floor_Grass"]) <= floor, "Grass must not create land over the river"
    for name in TREE_LAYERS:
        points = [tuple(t["px"]) for t in art[name]["gridTiles"]]
        assert len(points) == len(set(points)), "Overlapping stamps need a separate paint layer"
    # Keep all initial pieces and all unrelated authored data verbatim.
    checked = deepcopy(data)
    checked["nextUid"] = before["nextUid"]
    checked["defs"]["layers"] = [d for d in checked["defs"]["layers"] if d["uid"] not in added_definitions]
    before_levels = {l["iid"]: l for l in all_levels(before)}
    for level in all_levels(checked):
        level["layerInstances"] = [l for l in level["layerInstances"] if l["layerDefUid"] not in added_definitions]
        old_layers = {l["__identifier"]: l for l in before_levels[level["iid"]]["layerInstances"]}
        if level["identifier"] == "Room_2_Cenario":
            for layer in level["layerInstances"]:
                if layer["__identifier"] in DRESSED:
                    previous = old_layers[layer["__identifier"]]["gridTiles"]
                    assert layer["gridTiles"][:len(previous)] == previous
                    layer["gridTiles"] = previous
    assert checked == before, "Vegetation authoring changed unrelated map content"
    return {"changed": True, "seed": SEED, "retained_tree_stamps": len(existing_trees),
            "new_tree_stamps": len(new_trees), "tree_planes": len(TREE_LAYERS),
            "out_of_bounds_crowns": sum(x < 0 or y < 0 or x + 80 > width or y + 80 > height for x, y, _, _ in new_trees),
            "new_bush_stamps": new_bushes, "new_animated_grass": new_animated,
            "new_floor_grass_tiles": new_floor_grass, "no_new_floor_support": True}


def apply(project: Path, dry_run: bool = False) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    data = deepcopy(before)
    report = {"extension": extend_sides(data), "borders": invert_borders(data, project.parent),
              "vegetation": dress(data)}
    report.update(changed=data != before, dry_run=dry_run)
    if dry_run: return report
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("LDtk aberto ou arquivo alterado; nenhuma pintura sobrescrita.")
    png = reference_bytes(data, project.parent)
    if report["changed"]:
        folder = project.parent / "ldtk_backups"
        folder.mkdir(exist_ok=True)
        backup = folder / f"before_world_vegetation_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
        backup.write_bytes(original)
        content = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
        if b"\r\n" in original: content = content.replace("\n", "\r\n")
        with tempfile.NamedTemporaryFile(mode="wb", dir=project.parent, prefix=".world_vegetation_", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(content.encode("utf-8"))
        try:
            if editor_busy() or project.read_bytes() != original:
                raise RuntimeError("Mapa mudou durante a autoria; arquivo preservado.")
            os.replace(temporary, project)
        finally:
            temporary.unlink(missing_ok=True)
        report["backup"] = str(backup)
    (project.parent / REFERENCE).write_bytes(png)
    output = project.parent / "output/vegetacao_mapa"
    output.mkdir(exist_ok=True, parents=True)
    (output / "01_ldtk.png").write_bytes(png)
    (output / "resultado.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "monster_booster.ldtk")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    print(json.dumps(apply(args.project.resolve(), args.dry_run), ensure_ascii=False))
