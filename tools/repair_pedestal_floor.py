"""Repair the three audited legacy Floor holes beside the southern pedestals.

``repair(data)`` changes only the supplied LDtk dictionary in memory. It never
reads or writes the project file; the caller owns the backup and atomic save.
The solid-colour GroundBase remains visual-only, preserving the river boundary.
"""
from __future__ import annotations

from collections.abc import Iterator
from copy import deepcopy


GRID = 16
EXPECTED_SIZE = (3696, 3248)


def _levels(data: dict) -> Iterator[dict]:
    yield from data.get("levels", [])
    for world in data.get("worlds", []):
        yield from world.get("levels", [])


def _legacy_components() -> dict[str, set[tuple[int, int]]]:
    west_strip = {(x, y) for x in range(16, 21) for y in range(155, 188)}
    west_strip.update((15, y) for y in range(184, 189))
    west_strip.update((21, y) for y in range(184, 188))
    west_strip.add((16, 188))
    return {
        "forest_west_old_west_approach": west_strip,
        "forest_west_old_east_approach": {
            (x, y) for x in range(28, 31) for y in range(154, 185)
        },
        "forest_east_old_platform": {
            (x, y) for x in range(105, 110) for y in range(181, 184)
        },
    }


def _offset(layer: dict) -> tuple[int, int]:
    return int(layer.get("__pxTotalOffsetX", 0)), int(layer.get("__pxTotalOffsetY", 0))


def _entity_bounds(entity: dict, layer: dict) -> tuple[float, float, float, float]:
    ox, oy = _offset(layer)
    width, height = entity["width"], entity["height"]
    pivot_x, pivot_y = entity.get("__pivot", [0, 0])
    x, y = entity["px"]
    left, top = x + ox - width * pivot_x, y + oy - height * pivot_y
    return left, top, left + width, top + height


def _intersects(cell: tuple[int, int], bounds: tuple[float, float, float, float]) -> bool:
    left, top, right, bottom = bounds
    x, y = cell[0] * GRID, cell[1] * GRID
    return x < right and x + GRID > left and y < bottom and y + GRID > top


def repair(data: dict) -> dict:
    """Fill at most 283 audited cells, preserving all existing paint and rules.

    Coordinates identify this specific repair rather than a general hole-fill:
    large unsupported regions are the authored river and must remain empty.
    All guards run before the first mutation. Repeated calls are idempotent.
    """
    by_name = {level["identifier"]: level for level in _levels(data)}
    if not {"Room_2", "Room_2_Cenario"} <= by_name.keys():
        raise ValueError("Room_2 and Room_2_Cenario are required for the audited Floor repair")
    pair = [by_name["Room_2"], by_name["Room_2_Cenario"]]
    if any((level["pxWid"], level["pxHei"]) != EXPECTED_SIZE for level in pair):
        raise ValueError("Legacy Floor coordinates require the current 3696 x 3248 paired map")
    layers = [layer for level in pair for layer in level.get("layerInstances", [])]
    floor = next(
        layer for layer in by_name["Room_2_Cenario"]["layerInstances"]
        if layer["__identifier"] == "Floor"
    )
    if not floor.get("visible", True) or floor["__gridSize"] != GRID or _offset(floor) != (0, 0):
        raise ValueError("Floor repair requires a visible, unshifted 16 px Floor layer")
    tileset = next(
        definition for definition in data["defs"]["tilesets"]
        if definition["uid"] == floor["__tilesetDefUid"]
    )
    if not str(tileset.get("relPath", "")).replace("\\", "/").endswith("/ground_base.png"):
        raise ValueError("Floor no longer uses the audited #533048 solid-colour atlas")
    if tileset["tileGridSize"] != GRID:
        raise ValueError("Solid Floor atlas grid changed")
    prototype = next(
        (tile for tile in floor.get("gridTiles", [])
         if tile.get("src") == [0, 0] and tile.get("t") == 0 and tile.get("f", 0) == 0
         and tile.get("a", 1) == 1), None
    )
    if prototype is None:
        raise ValueError("No opaque, unflipped solid-colour Floor prototype is available")

    supported: set[tuple[int, int]] = set()
    protected: set[tuple[int, int]] = set()
    water_or_gaps: list[tuple[float, float, float, float]] = []
    for layer in layers:
        # Gameplay IntGrid is read even when its editor visibility is disabled.
        if not layer.get("visible", True) and layer["__identifier"] != "Gameplay":
            continue
        name = layer["__identifier"]
        ox, oy = _offset(layer)
        if layer.get("visible", True) and (name == "Floor" or name.startswith("Floor_")):
            if layer["__gridSize"] != GRID or ox % GRID or oy % GRID:
                raise ValueError("Floor support layers require aligned 16 px cells")
            for key in ("gridTiles", "autoLayerTiles"):
                supported.update(
                    ((tile["px"][0] + ox) // GRID, (tile["px"][1] + oy) // GRID)
                    for tile in layer.get(key, [])
                )
        if name == "Gameplay":
            if layer["__gridSize"] != GRID or ox % GRID or oy % GRID:
                raise ValueError("Gameplay protection requires aligned 16 px cells")
            width = layer["__cWid"]
            protected.update(
                (index % width + ox // GRID, index // width + oy // GRID)
                for index, value in enumerate(layer.get("intGridCsv", [])) if value != 0
            )
        for entity in layer.get("entityInstances", []):
            if entity["__identifier"] in {"WaterArea", "DashGapArea", "DoorDash"}:
                water_or_gaps.append(_entity_bounds(entity, layer))

    additions: list[tuple[int, int]] = []
    component_reports: list[dict] = []
    for name, cells in _legacy_components().items():
        remaining = cells - supported
        unsafe = remaining & protected
        unsafe.update(cell for cell in remaining if any(_intersects(cell, bounds) for bounds in water_or_gaps))
        if unsafe:
            raise ValueError(f"Refusing to fill protected gameplay/water cells in {name}: {sorted(unsafe)}")
        additions.extend(sorted(remaining, key=lambda cell: (cell[1], cell[0])))
        left = min(x for x, _ in cells) * GRID
        top = min(y for _, y in cells) * GRID
        right = (max(x for x, _ in cells) + 1) * GRID
        bottom = (max(y for _, y in cells) + 1) * GRID
        component_reports.append({
            "id": name,
            "bounds_px": [left, top, right - left, bottom - top],
            "audited_cells": len(cells),
            "added_cells": len(remaining),
            "already_supported_cells": len(cells & supported),
        })

    for x, y in additions:
        tile = deepcopy(prototype)
        tile["px"] = [x * GRID, y * GRID]
        if tile.get("d"):
            tile["d"][0] = x + y * floor["__cWid"]
        floor["gridTiles"].append(tile)
    return {
        "changed": bool(additions),
        "layer": "Room_2_Cenario/Floor",
        "tileset_uid": floor["__tilesetDefUid"],
        "added_cells": len(additions),
        "cells": [list(cell) for cell in additions],
        "affected_components": component_reports,
    }
