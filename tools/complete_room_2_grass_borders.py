"""Complete the authored grass fringe inside Room_2's existing roads.

Uses only transparent perimeter pieces of the current GrassBorder_16 PNG,
mirrored into the first three pixels of the road. Never repaints roads,
scenery, entities or other maps. The castle/ramp footprints and a one-tile
clearance around bridge decks stay bare.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
from copy import deepcopy
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import tempfile

from PIL import Image

from configure_ldtk_water import all_levels, editor_busy
from split_ldtk_room2 import REFERENCE, composed_layers, reference_bytes

ROOT = Path(__file__).resolve().parents[1]
GRID = 16
LAYER = "Floor_GrassBorders"


def cells(layer: dict) -> set[tuple[int, int]]:
    return {tuple(t["px"]) for t in layer["gridTiles"] + layer["autoLayerTiles"]}


def grow(points: set[tuple[int, int]]) -> set[tuple[int, int]]:
    return {(x + dx, y + dy) for x, y in points
            for dx in (-GRID, 0, GRID) for dy in (-GRID, 0, GRID)}


def convert(data: dict, root: Path) -> dict:
    room = next(l for l in all_levels(data) if l["identifier"] == "Room_2")
    layers = {l["__identifier"]: l for l in composed_layers(data, room)}
    layer = layers[LAYER]
    if layer["autoLayerTiles"] or layer["__gridSize"] != GRID:
        raise ValueError("Esperada uma camada manual de bordas com grade 16 px.")
    definition = next(t for t in data["defs"]["tilesets"] if t["uid"] == layer["__tilesetDefUid"])
    with Image.open(root / definition["relPath"]) as image:
        if image.size != (96, 96) or (definition["pxWid"], definition["pxHei"]) != image.size:
            raise ValueError("O carimbo GrassBorder_16 precisa conservar o bloco atual de 96 px.")
        artwork = image.convert("RGBA")
    roads = set().union(*(cells(layers[n]) for n in ("Floor_Paths", "Floor_WarpPlaza", "Floor_Bridges", "TerrainStairs") if n in layers))
    floor = cells(layers["Floor"])
    forbidden = grow(cells(layers["Floor_Bridges"]))
    for source in room["layerInstances"]:
        for entity in source["entityInstances"]:
            if entity["__identifier"] not in ("ElevationArea", "ElevationRamp"):
                continue
            x, y = entity["px"]
            pivot = entity.get("__pivot", [0, 0])
            left, top = int(x - pivot[0] * entity["width"]), int(y - pivot[1] * entity["height"])
            right, bottom = left + entity["width"], top + entity["height"]
            forbidden.update((cx, cy) for cy in range(top // GRID * GRID, bottom, GRID)
                             for cx in range(left // GRID * GRID, right, GRID))
    original = layer["gridTiles"]
    by_point: dict[tuple[int, int], list[dict]] = defaultdict(list)
    for tile in original:
        by_point[tuple(tile["px"])].append(tile)
    result = []
    reused = perimeter_edges = concave_corners = 0
    checked_pieces = set()
    # A strip is reflected across the road boundary, then placed in the road
    # cell itself. Its opaque pixels occupy at most three pixels of that cell;
    # the atlas's opaque 64 px square is never painted over the path centre.
    plaza = cells(layers["Floor_WarpPlaza"]) if "Floor_WarpPlaza" in layers else set()
    candidates = (cells(layers["Floor_Paths"]) | plaza) & floor - forbidden
    for x, y in sorted(candidates, key=lambda p: (p[1], p[0])):
        requested = []
        up, right, down, left = ((x, y - GRID) in roads, (x + GRID, y) in roads,
                                 (x, y + GRID) in roads, (x - GRID, y) in roads)
        if not left: requested.append(([(0, sy) for sy in (16, 32, 48, 64)], 1, "left"))
        if not right: requested.append(([(80, sy) for sy in (16, 32, 48, 64)], 1, "right"))
        if not up: requested.append(([(sx, 0) for sx in (16, 32, 48, 64)], 2, "top"))
        if not down: requested.append(([(sx, 80) for sx in (16, 32, 48, 64)], 2, "bottom"))
        perimeter_edges += len(requested)
        # At convex corners the two reflected strips meet without a special
        # opaque tile. At concave junctions only the tiny transparent atlas
        # corner reaches the road cell between its two road neighbours.
        for dx, dy, source in ((-GRID, -GRID, (0, 0)), (GRID, -GRID, (80, 0)),
                               (-GRID, GRID, (0, 80)), (GRID, GRID, (80, 80))):
            if ((x + dx, y + dy) not in roads and (x + dx, y) in roads
                    and (x, y + dy) in roads):
                requested.append(([source], 3, "corner"))
                concave_corners += 1
        for options, flip, kind in requested:
            found = next((t for t in by_point[(x, y)] if tuple(t["src"]) in options
                          and t.get("f", 0) == flip and t.get("a", 1) == 1), None)
            if found is not None:
                result.append(deepcopy(found))
                reused += 1
                sx, sy = found["src"]
            else:
                # Keep the atlas's four-cell rhythm along each straight edge.
                sx, sy = options[((y if kind in ("left", "right") else x) // GRID) % len(options)]
                result.append({"px": [x, y], "src": [sx, sy], "f": flip,
                               "t": sy // GRID * definition["__cWid"] + sx // GRID,
                               "d": [y // GRID * layer["__cWid"] + x // GRID], "a": 1})
            key = (sx, sy, flip, kind)
            if key in checked_pieces:
                continue
            checked_pieces.add(key)
            piece = artwork.crop((sx, sy, sx + GRID, sy + GRID))
            if flip & 1:
                piece = piece.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            if flip & 2:
                piece = piece.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
            opaque = {(px, py) for py in range(GRID) for px in range(GRID)
                      if piece.getpixel((px, py))[3]}
            if not opaque or any(3 <= px < GRID - 3 and 3 <= py < GRID - 3 for px, py in opaque):
                raise AssertionError("A borda precisa ser transparente e conservar o centro do caminho.")
            limits = {"left": lambda px, py: px < 3, "right": lambda px, py: px >= GRID - 3,
                      "top": lambda px, py: py < 3, "bottom": lambda px, py: py >= GRID - 3}
            if kind != "corner":
                if any(not limits[kind](px, py) for px, py in opaque):
                    raise AssertionError("Folhas excederam a faixa de 3 px para dentro do caminho.")
                covered = {py if kind in ("left", "right") else px for px, py in opaque}
                if covered != set(range(GRID)):
                    raise AssertionError("Uma faixa do PNG deixou um trecho do perímetro sem folhas.")
    layer["gridTiles"] = result
    painted = cells(layer)
    if painted & forbidden or painted - candidates:
        raise AssertionError("Borda fora dos caminhos, em escada, castelo, ponte ou fora do terreno.")
    return {"layer": LAYER, "before_tiles": len(original), "after_tiles": len(result),
            "starter_pieces_reused": reused, "new_pieces": len(result) - reused,
            "road_width_preserved": True, "no_new_walkable_cells": True,
            "castle_and_ramps_excluded": True, "bridge_clearance_tiles": 1,
            "foliage_direction": "inside", "leaf_depth_pixels": 3,
            "perimeter_edges_covered": perimeter_edges, "concave_corners": concave_corners,
            "transparent_atlas_pieces_only": True}


def complete(project: Path, dry_run: bool = False) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    after = deepcopy(before)
    report = convert(after, project.parent)
    checked = deepcopy(after)
    old_scenery = next(l for l in all_levels(before) if l["identifier"] == "Room_2_Cenario")
    new_scenery = next(l for l in all_levels(checked) if l["identifier"] == "Room_2_Cenario")
    old_layer = next(l for l in old_scenery["layerInstances"] if l["__identifier"] == LAYER)
    new_layer = next(l for l in new_scenery["layerInstances"] if l["__identifier"] == LAYER)
    new_layer["gridTiles"] = old_layer["gridTiles"]
    if checked != before:
        raise AssertionError("Conteúdo externo à pintura das bordas foi alterado.")
    report.update(changed=after != before, dry_run=dry_run)
    if dry_run:
        return report
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("LDtk aberto ou mapa alterado; autoria existente preservada.")
    png = reference_bytes(after, project.parent)
    if report["changed"]:
        backup_dir = project.parent / "ldtk_backups"
        backup_dir.mkdir(exist_ok=True)
        backup = backup_dir / f"before_grass_borders_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
        backup.write_bytes(original)
        newline = "\r\n" if b"\r\n" in original else "\n"
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline=newline,
                                        dir=project.parent, prefix=".grass_borders_", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(after, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        try:
            if editor_busy() or project.read_bytes() != original:
                raise RuntimeError("Mapa mudou durante a preparação; pintura preservada.")
            os.replace(temporary, project)
        finally:
            temporary.unlink(missing_ok=True)
        report["backup"] = str(backup)
    (project.parent / REFERENCE).write_bytes(png)
    output = project.parent / "output/bordas_caminhos"
    output.mkdir(exist_ok=True, parents=True)
    (output / "01_depois_ldtk.png").write_bytes(png)
    (output / "resultado.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "monster_booster.ldtk")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    print(json.dumps(complete(args.project.resolve(), args.dry_run), ensure_ascii=False))
