"""Extend only the sides of the paired open world, without stretching its layout.

``convert(data)`` mutates the supplied LDtk dictionary in memory and returns its
manifest. This module deliberately never writes the project or its reference PNG;
the caller can compose the change with vegetation and commit them atomically.
Running this file directly is a read-only preview of the conversion.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
import json
from pathlib import Path

from configure_ldtk_water import all_levels

ROOT = Path(__file__).resolve().parents[1]
PAIR = ("Room_2", "Room_2_Cenario")
OLD_SIZE = (3536, 3248)
NEW_SIZE = (3696, 3248)
SIDE_EXTRA_PX = 80
MAP_LIMIT = 1


def _point(value: object, cells: int) -> object:
    """Translate one exported LDtk Point; null points stay unset."""
    if value is None:
        return None
    if not isinstance(value, dict) or not {"cx", "cy"} <= value.keys():
        raise ValueError(f"Unsupported LDtk Point value: {value!r}")
    result = deepcopy(value)
    result["cx"] += cells
    return result


def _translate_point_fields(owner: dict, grid: int) -> int:
    count = 0
    for field in owner.get("fieldInstances", []):
        kind = field.get("__type")
        if kind not in ("Point", "Array<Point>"):
            continue
        cells = SIDE_EXTRA_PX // grid
        old_value = deepcopy(field.get("__value"))
        if kind == "Point":
            field["__value"] = _point(old_value, cells)
        else:
            field["__value"] = [_point(value, cells) for value in old_value]
        for editor in field.get("realEditorValues", []):
            if editor.get("id") not in ("V_Point", "V_Null"):
                raise ValueError("Unsupported editor representation for Point field")
            params = editor.get("params", [])
            if not params or editor.get("id") == "V_Null":
                continue
            if len(params) == 2 and all(isinstance(v, (int, float)) for v in params):
                params[0] += cells
            elif len(params) == 1 and (params[0] is None or isinstance(params[0], dict)):
                params[0] = _point(params[0], cells)
            else:
                raise ValueError("Unrecognized Point editor parameters; refusing stale editor data")
        count += 1
    return count


def _translate_tiles(layer: dict, new_width: int) -> None:
    grid = layer["__gridSize"]
    for key in ("gridTiles", "autoLayerTiles"):
        for tile in layer.get(key, []):
            tile["px"][0] += SIDE_EXTRA_PX
            if tile.get("d"):
                tile["d"][0] = tile["px"][0] // grid + tile["px"][1] // grid * new_width


def _extend_ground(layer: dict) -> int:
    """Only the visual base grows; Floor and all support cells remain translated."""
    tiles = layer["gridTiles"]
    if not tiles:
        return 0
    grid = layer["__gridSize"]
    width, height = layer["__cWid"], layer["__cHei"]
    extra = SIDE_EXTRA_PX // grid
    expected = {(x * grid, y * grid) for y in range(height) for x in range(extra, width - extra)}
    if len(tiles) != len(expected) or {tuple(t["px"]) for t in tiles} != expected:
        raise ValueError("GroundBase must cover the original rectangle exactly")
    prototype = tiles[0]
    for y in range(height):
        for x in (*range(extra), *range(width - extra, width)):
            tile = deepcopy(prototype)
            tile["px"] = [x * grid, y * grid]
            if tile.get("d"):
                tile["d"][0] = x + y * width
            tiles.append(tile)
    return 2 * extra * height


def _validate_pair(levels: list[dict], size: tuple[int, int]) -> None:
    for level in levels:
        if (level["pxWid"], level["pxHei"]) != size:
            raise ValueError("Paired rooms must have matching expected dimensions")
        for layer in level.get("layerInstances") or []:
            grid = layer["__gridSize"]
            if size[0] % grid or size[1] % grid or SIDE_EXTRA_PX % grid:
                raise ValueError("Room dimensions/translation must match every layer grid")
            if (layer["__cWid"], layer["__cHei"]) != (size[0] // grid, size[1] // grid):
                raise ValueError("Layer dimensions do not match the level")
            if layer.get("__pxTotalOffsetX", 0) or layer.get("__pxTotalOffsetY", 0):
                raise ValueError("Offset layers need explicit mapping")
            values = layer.get("intGridCsv", [])
            if values and len(values) != layer["__cWid"] * layer["__cHei"]:
                raise ValueError("Malformed IntGrid CSV")


def _assert_preserved(before: list[dict], after: list[dict]) -> None:
    for old_level, new_level in zip(before, after, strict=True):
        assert new_level["worldX"] == old_level["worldX"]
        assert new_level["worldY"] == old_level["worldY"]
        for old, new in zip(old_level["layerInstances"], new_level["layerInstances"], strict=True):
            grid = old["__gridSize"]
            for key in ("gridTiles", "autoLayerTiles"):
                tiles = new.get(key, [])
                if old["__identifier"] == "GroundBase" and key == "gridTiles" and tiles:
                    assert len(tiles) == new["__cWid"] * new["__cHei"]
                else:
                    assert len(tiles) == len(old.get(key, []))
                for original, shifted in zip(old.get(key, []), tiles):
                    restored = deepcopy(shifted)
                    restored["px"][0] -= SIDE_EXTRA_PX
                    if restored.get("d"):
                        restored["d"][0] = original["d"][0]
                    assert restored == original, "Existing tile art changed"
            values = old.get("intGridCsv", [])
            if values:
                pad = SIDE_EXTRA_PX // grid
                for y in range(old["__cHei"]):
                    offset = y * new["__cWid"] + pad
                    assert new["intGridCsv"][offset:offset + old["__cWid"]] == values[y * old["__cWid"]:(y + 1) * old["__cWid"]]
            for original, shifted in zip(old.get("entityInstances", []), new.get("entityInstances", []), strict=True):
                assert shifted["px"] == [original["px"][0] + SIDE_EXTRA_PX, original["px"][1]]
                assert (shifted["width"], shifted["height"]) == (original["width"], original["height"])
                assert shifted["__worldX"] == new_level["worldX"] + shifted["px"][0]
                assert shifted["__worldY"] == new_level["worldY"] + shifted["px"][1]
                for field_before, field_after in zip(original["fieldInstances"], shifted["fieldInstances"], strict=True):
                    if field_before["__type"] not in ("Point", "Array<Point>"):
                        assert field_before == field_after, "Gameplay properties changed"
    gameplay = next(l for l in after[0]["layerInstances"] if l["__identifier"] == "Gameplay")
    width, height = gameplay["__cWid"], gameplay["__cHei"]
    cells = gameplay["intGridCsv"]
    assert all(cells[y * width + x] == MAP_LIMIT for y in range(height) for x in (*range(10), *range(width - 10, width)))
    assert all(cells[y * width + x] == MAP_LIMIT for y in range(height - 10, height) for x in range(width))


def convert(data: dict) -> dict:
    """Translate the authored rooms 80 px right and add 80 px at both sides."""
    by_name = {level["identifier"]: level for level in all_levels(data)}
    if not all(name in by_name for name in PAIR):
        raise ValueError("Both Room_2 and Room_2_Cenario are required")
    levels = [by_name[name] for name in PAIR]
    current_sizes = {(level["pxWid"], level["pxHei"]) for level in levels}
    if current_sizes == {NEW_SIZE}:
        _validate_pair(levels, NEW_SIZE)
        return {"changed": False, "size": list(NEW_SIZE), "reason": "Side extension already applied"}
    _validate_pair(levels, OLD_SIZE)
    before = deepcopy(levels)
    point_fields = 0
    added_ground = 0
    for level in levels:
        level["pxWid"], level["pxHei"] = NEW_SIZE
        background = level.get("__bgPos")
        if background:
            background["cropRect"] = [0, 0, *NEW_SIZE]
        point_fields += _translate_point_fields(level, data.get("defaultGridSize", 16))
        for layer in level["layerInstances"]:
            grid = layer["__gridSize"]
            old_width = layer["__cWid"]
            extra = SIDE_EXTRA_PX // grid
            layer["__cWid"] = NEW_SIZE[0] // grid
            _translate_tiles(layer, layer["__cWid"])
            values = layer.get("intGridCsv", [])
            if values:
                fill = MAP_LIMIT if level["identifier"] == "Room_2" and layer["__identifier"] == "Gameplay" else 0
                new_values = []
                for y in range(layer["__cHei"]):
                    new_values.extend([fill] * extra)
                    new_values.extend(values[y * old_width:(y + 1) * old_width])
                    new_values.extend([fill] * extra)
                layer["intGridCsv"] = new_values
            for entity in layer.get("entityInstances", []):
                entity["px"][0] += SIDE_EXTRA_PX
                entity["__grid"] = [value // grid for value in entity["px"]]
                entity["__worldX"] = level["worldX"] + entity["px"][0]
                entity["__worldY"] = level["worldY"] + entity["px"][1]
                point_fields += _translate_point_fields(entity, grid)
            if layer["__identifier"] == "GroundBase":
                added_ground += _extend_ground(layer)
    _validate_pair(levels, NEW_SIZE)
    _assert_preserved(before, levels)
    return {"changed": True, "before_size": list(OLD_SIZE), "size": list(NEW_SIZE),
            "translation_px": [SIDE_EXTRA_PX, 0], "extra_per_side_px": SIDE_EXTRA_PX,
            "side_limit_tiles": 10, "bottom_limit_tiles": 10,
            "added_ground_tiles": added_ground, "translated_point_fields": point_fields,
            "structures_resized": False, "world_origins_preserved": True}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=ROOT / "monster_booster.ldtk")
    args = parser.parse_args()
    print(json.dumps(convert(json.loads(args.input.read_text(encoding="utf-8-sig"))), ensure_ascii=False, indent=2))
