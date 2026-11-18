"""Widen the currently painted Room_2 roads to four cells, in memory only.

No route preset is reapplied: every existing path tile survives, and the new
right/bottom fringe is clipped to already-authored Floor. Bridge and stair
tiles, all terrain support and scenery remain untouched. Only pedestals that
were left away from an authored road terminal are moved, with their arenas.
Call ``convert(data, root, rebuild_borders=False)`` to compose this migration
with bridge authoring before rebuilding the grass perimeter once.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict, deque
from copy import deepcopy
import json
import math
from pathlib import Path

from PIL import Image

from complete_room_2_grass_borders import convert as rebuild_grass_borders
from configure_ldtk_water import all_levels
from split_ldtk_room2 import composed_layers

ROOT = Path(__file__).resolve().parents[1]
GRID = 16
FILL = (128, 32)
PATH_LAYER = "Floor_Paths"
NEIGHBOURS = ((-GRID, 0), (GRID, 0), (0, -GRID), (0, GRID))


def cells(layer: dict) -> set[tuple[int, int]]:
    return {tuple(tile["px"]) for key in ("gridTiles", "autoLayerTiles")
            for tile in layer[key]}


def section_histogram(points: set[tuple[int, int]]) -> Counter:
    """Count short straight sections in both axes, excluding long branches."""
    result = Counter()
    for axis in (0, 1):
        by_axis = defaultdict(list)
        for point in points:
            by_axis[point[axis]].append(point[1 - axis])
        for values in by_axis.values():
            lengths = []
            last = None
            for value in sorted(values):
                if last is not None and value == last + GRID:
                    lengths[-1] += 1
                else:
                    lengths.append(1)
                last = value
            result.update(length for length in lengths if 2 <= length <= 8)
    return result


def terminals(network: set[tuple[int, int]]) -> list[tuple[int, int]]:
    """Recover the end-cap centres of an authored, three-cell-wide network."""
    centreline = {point for point in network
                  if all((point[0] + dx, point[1] + dy) in network
                         for dx in (-GRID, 0, GRID) for dy in (-GRID, 0, GRID))}
    return sorted((x + GRID // 2, y + GRID // 2) for x, y in centreline
                  if sum((x + dx, y + dy) in centreline for dx, dy in NEIGHBOURS) == 1)


def components(network: set[tuple[int, int]]) -> int:
    remaining = set(network)
    count = 0
    while remaining:
        queue = deque([remaining.pop()])
        count += 1
        while queue:
            x, y = queue.popleft()
            for dx, dy in NEIGHBOURS:
                point = (x + dx, y + dy)
                if point in remaining:
                    remaining.remove(point)
                    queue.append(point)
    return count


def encounter_id(entity: dict) -> str:
    return next((field["__value"] for field in entity["fieldInstances"]
                 if field["__identifier"] == "EncounterId"), "")


def move_entity(entity: dict, position: tuple[int, int], room: dict, grid: int) -> None:
    entity["px"] = list(position)
    entity["__grid"] = [value // grid for value in position]
    entity["__worldX"] = room["worldX"] + position[0]
    entity["__worldY"] = room["worldY"] + position[1]


def convert(data: dict, root: Path, rebuild_borders: bool = True) -> dict:
    """Mutate a loaded LDtk project and return a reviewable change manifest."""
    room = next(level for level in all_levels(data) if level["identifier"] == "Room_2")
    layers = {layer["__identifier"]: layer for layer in composed_layers(data, room)}
    layer = layers[PATH_LAYER]
    if layer["__gridSize"] != GRID or layer["autoLayerTiles"]:
        raise ValueError("Floor_Paths precisa ser uma pintura manual na grade de 16 px.")
    original = cells(layer)
    histogram = section_histogram(original)
    if not histogram:
        raise ValueError("Não foi possível medir a largura dos caminhos atuais.")
    measured_width = histogram.most_common(1)[0][0]
    if measured_width not in (3, 4):
        raise ValueError(f"Largura predominante inesperada: {measured_width} tiles.")
    before_network = set().union(*(cells(layers[name]) for name in
                                  (PATH_LAYER, "Floor_Bridges", "TerrainStairs")))
    original_components = components(before_network)
    floor = cells(layers["Floor"])
    protected = cells(layers["Floor_Bridges"]) | cells(layers["TerrainStairs"])
    movements = []
    added = set()
    if measured_width == 3:
        # An even-width section needs an explicit alignment. Keep the author's
        # top/left edge, extending one cell towards positive X/Y without scaling.
        proposed = {(x + dx, y + dy) for x, y in original
                    for dx in (0, GRID) for dy in (0, GRID)}
        added = proposed & floor - original - protected
        gameplay = layers["Gameplay"]
        solid = {(index % gameplay["__cWid"] * GRID,
                  index // gameplay["__cWid"] * GRID)
                 for index, value in enumerate(gameplay["intGridCsv"])
                 if value in (1, 2, 3, 6, 7)}
        if added & solid:
            raise ValueError("A ampliação encontrou uma parede ou limite de gameplay.")
        source = next(definition for definition in data["defs"]["tilesets"]
                      if definition["uid"] == layer["__tilesetDefUid"])
        with Image.open(root / source["relPath"]) as image:
            tile = image.convert("RGBA").crop((*FILL, FILL[0] + GRID, FILL[1] + GRID))
            if tile.getcolors() != [(GRID * GRID, (69, 40, 60, 255))]:
                raise ValueError("O preenchimento escolhido não é mais sólido #45283c.")
        for x, y in sorted(added, key=lambda point: (point[1], point[0])):
            layer["gridTiles"].append({"px": [x, y], "src": list(FILL), "f": 0,
                "t": FILL[1] // GRID * source["__cWid"] + FILL[0] // GRID,
                "d": [y // GRID * layer["__cWid"] + x // GRID], "a": 1})
        candidates = terminals(before_network)
        for owner in room["layerInstances"]:
            for entity in owner["entityInstances"]:
                if entity["__identifier"] != "HordePedestal" or not candidates:
                    continue
                old = tuple(entity["px"])
                nearest = min(candidates, key=lambda point: math.dist(old, point))
                distance = math.dist(old, nearest)
                # Normal authored centre offsets of 8–12 px stay untouched. A
                # central junction is deliberately not treated as an end cap.
                if not 24 < distance <= 256:
                    continue
                target = (nearest[0] + GRID // 2, nearest[1] + GRID // 2)
                footprint = {(x, y)
                    for y in range((target[1] - 32) // GRID * GRID, target[1] + 32, GRID)
                    for x in range((target[0] - 32) // GRID * GRID, target[0] + 32, GRID)}
                if footprint - floor or footprint & solid:
                    raise ValueError("O novo centro de um altar saiu do terreno livre.")
                key = encounter_id(entity)
                paired = [(other, other_owner) for other_owner in room["layerInstances"]
                          for other in other_owner["entityInstances"]
                          if other["__identifier"] == "PedestalArena" and encounter_id(other) == key]
                if len(paired) != 1:
                    raise ValueError("O altar precisa ter exatamente uma arena correspondente: " + key)
                move_entity(entity, target, room, owner["__gridSize"])
                arena, arena_owner = paired[0]
                move_entity(arena, target, room, arena_owner["__gridSize"])
                movements.append({"encounter": key, "before": list(old), "after": list(target),
                    "authored_terminal": list(nearest), "previous_distance_px": round(distance, 3),
                    "pedestal_size_preserved": [entity["width"], entity["height"]],
                    "arena_size_preserved": [arena["width"], arena["height"]],
                    "footprint_on_land": True})
    final = cells(layer)
    final_network = final | protected
    if components(final_network) != original_components:
        raise AssertionError("A ampliação mudou a conectividade da rede original.")
    if original - final or (final - original) - floor:
        raise AssertionError("Uma célula autoral sumiu ou novo caminho invadiu o rio.")
    after_histogram = section_histogram(final)
    if after_histogram.most_common(1)[0][0] != 4:
        raise AssertionError("A seção predominante final precisa medir quatro tiles.")
    report = {"changed": bool(added or movements), "width_tiles": 4, "width_px": 64,
        "border_cells": 2, "inner_cells": 2, "alignment": "preserve_top_left_extend_right_bottom",
        "old_path_tiles": len(original), "new_path_tiles": len(final), "added_path_tiles": len(added),
        "original_paths_preserved": True, "floor_unchanged": True,
        "existing_paths_without_floor_preserved": len(original - floor),
        "new_paths_without_floor": len((final - original) - floor),
        "bridges_and_stairs_unchanged": True, "network_components": original_components,
        "section_histogram_before": dict(sorted(histogram.items())),
        "section_histogram_after": dict(sorted(after_histogram.items())),
        "pedestals_moved": movements, "other_entities_preserved": True}
    if rebuild_borders:
        report["grass_borders"] = rebuild_grass_borders(data, root)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=ROOT / "monster_booster.ldtk")
    parser.add_argument("--without-borders", action="store_true")
    args = parser.parse_args()
    project = json.loads(args.input.read_text(encoding="utf-8-sig"))
    before = deepcopy(project)
    result = convert(project, args.input.parent, rebuild_borders=not args.without_borders)
    checked = deepcopy(project)
    repeated = convert(checked, args.input.parent, rebuild_borders=not args.without_borders)
    if checked != project:
        raise AssertionError("A conversão precisa ser idempotente.")
    result.update(changed=project != before, idempotent=True, project_saved=False)
    print(json.dumps(result, ensure_ascii=False, indent=2))
