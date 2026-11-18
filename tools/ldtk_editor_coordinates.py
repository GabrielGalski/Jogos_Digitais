"""LDtk 1.5.3 editor coordinates, including instance-offset grid dimensions.

LayerInstance.hx computes cWid=ceil((level.pxWid-pxOffsetX)/gridSize).
The editor imports manual tiles from d[0], not the convenience px export.
Source: https://github.com/deepnight/ldtk/blob/master/src/electron.renderer/data/inst/LayerInstance.hx
"""
from __future__ import annotations

import math


def grid_dimensions(level: dict, instance: dict) -> tuple[int, int]:
    grid = instance["__gridSize"]
    return (math.ceil((level["pxWid"] - instance["pxOffsetX"]) / grid),
            math.ceil((level["pxHei"] - instance["pxOffsetY"]) / grid))


def synchronize(level: dict, instance: dict) -> dict:
    width, height = grid_dimensions(level, instance)
    dimensions_changed = (instance["__cWid"], instance["__cHei"]) != (width, height)
    if dimensions_changed and (instance["autoLayerTiles"] or instance["intGridCsv"]):
        raise ValueError("Review automatic or IntGrid data before resizing the internal grid: " + instance["__identifier"])
    instance["__cWid"], instance["__cHei"] = width, height
    changed_tiles = 0
    for stamp in instance["gridTiles"]:
        x, y = stamp["px"]
        grid = instance["__gridSize"]
        if x % grid or y % grid or x < 0 or y < 0:
            raise ValueError("Manual tile outside the native layer grid: " + instance["__identifier"])
        editor_index = x // grid + y // grid * width
        if stamp.get("d") != [editor_index]:
            stamp["d"] = [editor_index]
            changed_tiles += 1
    return {"layer": instance["__identifier"], "grid": [width, height],
            "dimensions_changed": dimensions_changed, "reindexed_tiles": changed_tiles}


def synchronize_level(level: dict) -> list[dict]:
    return [synchronize(level, layer) for layer in level["layerInstances"]
            if layer["__type"] in ["Tiles", "AutoLayer"]]
