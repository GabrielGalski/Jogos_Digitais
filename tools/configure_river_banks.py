"""Register the gray shore atlas and paint only Room_2's low western riverbank.

Preserves floor support, gameplay, castle cliffs, bridges and the eastern bank.
Coordinates are derived from the saved terrain; no old river waypoints are used.
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

from PIL import Image
from configure_ldtk_water import all_levels, editor_busy
from configure_room_2_bridges import painted_spans
from ldtk_editor_coordinates import synchronize
from split_ldtk_room2 import REFERENCE, composed_layers, reference_bytes, validate

ROOT = Path(__file__).resolve().parents[1]
ART = "assets/tiles/floor/water_bank_tileset_64_mapped.png"
NAME = "WaterBank_Gray_16"
LAYER = "WaterBanks"
GRID = 16
SIDES = {"N": (0, -1), "E": (1, 0), "S": (0, 1), "W": (-1, 0)}


def fields(entity: dict) -> dict:
    return {f["__identifier"]: f.get("__value") for f in entity["fieldInstances"]}


def rect(entity: dict) -> tuple[int, int, int, int]:
    pivot = entity.get("__pivot", [0, 0])
    return (int(entity["px"][0] - pivot[0] * entity["width"]),
            int(entity["px"][1] - pivot[1] * entity["height"]), entity["width"], entity["height"])


def inside(cell: tuple[int, int], bounds: tuple[int, int, int, int], padding: int = 0) -> bool:
    x, y = cell[0] * GRID + 8, cell[1] * GRID + 8
    left, top, width, height = bounds
    return left - padding <= x < left + width + padding and top - padding <= y < top + height + padding


def shore_geometry(data: dict) -> dict:
    room = next(l for l in all_levels(data) if l["identifier"] == "Room_2")
    layers = {l["__identifier"]: l for l in composed_layers(data, room)}
    land = {(t["px"][0] // GRID, t["px"][1] // GRID) for t in layers["Floor"]["gridTiles"]}
    decks = painted_spans(layers)
    for x, y, width, height in decks:
        land.difference_update((cx, cy) for cy in range(y // GRID, (y + height) // GRID)
                               for cx in range(x // GRID, (x + width) // GRID))
    entities = [e for l in room["layerInstances"] for e in l["entityInstances"]]
    water = next(e for e in entities if e["__identifier"] == "WaterArea" and fields(e).get("SurfaceId") == "room_2_river")
    wx, wy, ww, wh = rect(water)
    forbidden = [rect(e) for e in entities if e["__identifier"] in ["ElevationArea", "ElevationRamp"] and fields(e).get("Enabled", True)]
    wet: set[tuple[int, int]] = set()
    midpoints: dict[int, float] = {}
    # The real river is the bounded void between two banks. Unbounded void
    # below the terrain is not shoreline and must not create a bottom-map rim.
    for y in range(max(0, wy // GRID), min(room["pxHei"] // GRID, (wy + wh) // GRID)):
        runs: list[list[int]] = []
        for x in range(wx // GRID, (wx + ww) // GRID):
            if (x, y) in land:
                continue
            if runs and runs[-1][-1] + 1 == x:
                runs[-1].append(x)
            else:
                runs.append([x])
        bounded = [r for r in runs if (r[0] - 1, y) in land and (r[-1] + 1, y) in land]
        if not bounded:
            continue
        run = max(bounded, key=len)
        midpoints[y] = (run[0] + run[-1] + 1) * 0.5
        wet.update((x, y) for x in run)
    candidates: set[tuple[int, int]] = set()
    for x, y in wet:
        for dx, dy in SIDES.values():
            point = (x + dx, y + dy)
            if point not in land or point[0] >= midpoints[y]:
                continue
            if any(inside(point, r) for r in forbidden) or any(inside(point, r, GRID) for r in decks):
                continue
            candidates.add(point)
        # A diagonal water cell also needs an inner corner in the dry cell
        # between its two dry cardinal neighbors. Otherwise a bare square remains.
        for dx, dy in [(-1, -1), (-1, 1), (1, -1), (1, 1)]:
            point = (x + dx, y + dy)
            if point not in land or point[0] >= midpoints[y]: continue
            if (point[0] - dx, point[1]) not in land or (point[0], point[1] - dy) not in land: continue
            if any(inside(point, r) for r in forbidden) or any(inside(point, r, GRID) for r in decks): continue
            candidates.add(point)
    return {"candidates": candidates, "wet": wet, "forbidden": forbidden, "decks": decks, "water_rect": rect(water)}


def tile_id(cell: tuple[int, int], wet: set[tuple[int, int]]) -> int:
    x, y = cell
    exposed = {name for name, (dx, dy) in SIDES.items() if (x + dx, y + dy) in wet}
    for pair, index in [({"N", "E"}, 3), ({"S", "E"}, 15), ({"N", "W"}, 0), ({"S", "W"}, 12)]:
        if pair.issubset(exposed):
            return index
    if "E" in exposed: return 7 if y % 2 == 0 else 11
    if "W" in exposed: return 4 if y % 2 == 0 else 8
    if "N" in exposed: return 1 if x % 2 == 0 else 2
    if "S" in exposed: return 13 if x % 2 == 0 else 14
    for dx, dy, index in [(-1, -1, 5), (1, -1, 6), (-1, 1, 9), (1, 1, 10)]:
        if (x + dx, y + dy) in wet: return index
    raise ValueError("Shore tile has no water neighbor: " + str(cell))


def convert(data: dict) -> dict:
    before = deepcopy(data)
    with Image.open(ROOT / ART) as image:
        if image.size != (64, 64) or image.mode != "RGBA":
            raise ValueError("Expected the approved 64x64 RGBA atlas.")
    atlas = next((t for t in data["defs"]["tilesets"] if t["identifier"] == NAME or t.get("relPath") == ART), None)
    if atlas is None:
        atlas = deepcopy(next(t for t in data["defs"]["tilesets"] if t["identifier"] == "Cliff_Purple_16"))
        atlas.update(identifier=NAME, uid=data["nextUid"], relPath=ART, pxWid=64, pxHei=64,
                     __cWid=4, __cHei=4, tileGridSize=GRID, padding=0, spacing=0,
                     tags=["water", "shore", "stone"], enumTags=[], customData=[], cachedPixelData=None,
                     savedSelections=[{"ids": list(range(16)), "mode": "Stamp"},
                                      {"ids": [7, 11], "mode": "Stamp"}, {"ids": [4, 8], "mode": "Stamp"},
                                      {"ids": [1, 2], "mode": "Stamp"}, {"ids": [13, 14], "mode": "Stamp"}])
        data["nextUid"] += 1
        data["defs"]["tilesets"].append(atlas)
    atlas["relPath"] = ART
    atlas["cachedPixelData"] = None
    if (atlas["pxWid"], atlas["pxHei"], atlas["tileGridSize"]) != (64, 64, GRID):
        raise ValueError("Existing shore atlas settings do not match the approved image.")
    geometry = shore_geometry(data)
    definition = next(l for l in data["defs"]["layers"] if l["identifier"] == LAYER)
    definition.update(tilesetDefUid=atlas["uid"],
                      doc="CENARIO / Margem rochosa baixa, atlas cinza 64x64, grade 16px. Pintar em Room_2_Cenario. Z=-17; sem suporte ou colisao. Transparencia recorta somente a agua. Excluir cliff do castelo e entradas de pontes.")
    counts: dict[str, int] = {}
    for level in all_levels(data):
        layer = next(l for l in level["layerInstances"] if l["__identifier"] == LAYER)
        if level["identifier"] != "Room_2_Cenario" and (layer["gridTiles"] or layer["autoLayerTiles"]):
            # Preserve any legacy artwork in other scenes by retaining its source override.
            layer["overrideTilesetUid"] = layer["__tilesetDefUid"]
            continue
        layer.update(__tilesetDefUid=atlas["uid"], __tilesetRelPath=ART, overrideTilesetUid=None)
        if level["identifier"] != "Room_2_Cenario":
            continue
        layer["visible"] = True
        layer["gridTiles"] = []
        for x, y in sorted(geometry["candidates"], key=lambda p: (p[1], p[0])):
            index = tile_id((x, y), geometry["wet"])
            counts[str(index)] = counts.get(str(index), 0) + 1
            layer["gridTiles"].append({"px": [x * GRID, y * GRID], "src": [index % 4 * GRID, index // 4 * GRID],
                                       "f": 0, "t": index, "d": [y * layer["__cWid"] + x], "a": 1})
        synchronize(level, layer)
    checked = deepcopy(data)
    checked["nextUid"] = before["nextUid"]
    checked["defs"]["tilesets"] = before["defs"]["tilesets"]
    checked["defs"]["layers"] = before["defs"]["layers"]
    for old, current in zip(all_levels(before), all_levels(checked), strict=True):
        for i, layer in enumerate(current["layerInstances"]):
            if layer["__identifier"] == LAYER:
                current["layerInstances"][i] = deepcopy(next(l for l in old["layerInstances"] if l["__identifier"] == LAYER))
    assert checked == before, "Changes escaped atlas registration and WaterBanks painting."
    points = geometry["candidates"]
    assert points and all(not any(inside(p, r) for r in geometry["forbidden"]) for p in points)
    assert all(not any(inside(p, r, GRID) for r in geometry["decks"]) for p in points)
    report = validate(data)
    report.update(atlas=NAME, atlas_uid=atlas["uid"], painted_tiles=len(points), pieces=counts,
                  bounds=[min(x for x, _ in points) * GRID, min(y for _, y in points) * GRID,
                          (max(x for x, _ in points) + 1) * GRID, (max(y for _, y in points) + 1) * GRID],
                  gameplay_and_other_paint_preserved=True, eastern_bank_preserved=True,
                  cliff_and_bridge_exclusions=True)
    return report


def apply(project: Path, dry_run: bool = False) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    after = deepcopy(before)
    report = convert(after)
    repeated = deepcopy(after)
    convert(repeated)
    assert repeated == after, "Migration must be idempotent."
    report.update(changed=before != after, dry_run=dry_run, idempotent=True)
    if report["changed"] and not dry_run:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk aberto ou mapa alterado; nenhuma autoria sobrescrita.")
        guide = reference_bytes(after, project.parent)
        backup = project.parent / "ldtk_backups" / f"before_river_banks_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
        backup.write_bytes(original)
        content = json.dumps(after, ensure_ascii=False, indent=2) + "\n"
        if b"\r\n" in original: content = content.replace("\n", "\r\n")
        with tempfile.NamedTemporaryFile(mode="wb", dir=project.parent, prefix=".river_banks_", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(content.encode("utf-8"))
        try:
            if editor_busy() or project.read_bytes() != original:
                raise RuntimeError("Mapa mudou durante a importacao; original preservado.")
            os.replace(temporary, project)
        finally:
            temporary.unlink(missing_ok=True)
        (project.parent / REFERENCE).write_bytes(guide)
        report["backup"] = str(backup)
    output = project.parent / "output/water_bank"
    output.mkdir(exist_ok=True, parents=True)
    (output / ("migration_preview.json" if dry_run else "migration.json")).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    print(json.dumps(apply(ROOT / "monster_booster.ldtk", args.dry_run), ensure_ascii=False, indent=2))
